import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../data/database_helper.dart';
import '../data/book_model.dart';
import '../data/transaction_model.dart';
import '../core/constants.dart';
import '../theme/theme_provider.dart';
import 'dashboard_screen.dart';
import 'add_transaction_screen.dart';
import 'welcome_and_logs_screen.dart';
import 'cloud_and_insights_helper.dart';

export 'welcome_and_logs_screen.dart';
export 'cloud_and_insights_helper.dart';

enum BookSort { updated, created, aToZ, zToA }

// ===========================================================================
// BOOKS & HOME SCREEN (MODULARIZED)
// ===========================================================================
class BooksScreen extends StatefulWidget {
  const BooksScreen({Key? key}) : super(key: key);

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  static const MethodChannel _nativeBridge = MethodChannel('com.chandankumar.fintrack/sms');

  static const List<String> _monthNames = FinTraxCloudAndInsightsHelper.monthNames;

  int _tabIndex = 0;
  late final PageController _tabPageController = PageController(initialPage: 0);
  List<Map<String, dynamic>> _books = [];
  Map<int, Map<String, String>> _bookContacts = {};
  List<ParsedSmsTransaction> _pendingSms = [];
  bool _loading = false;
  bool _showOnboarding = false;
  bool _isSearchingBooks = false;
  String _bookSearchQuery = '';
  final TextEditingController _bookSearchController = TextEditingController();
  BookSort _sortOrder = BookSort.updated;
  Timer? _autoBackupTimer;

  @override
  void initState() {
    super.initState();
    AppLogger.instance.log('BooksScreen.initState() called.', tag: 'LIFECYCLE');
    FinTraxBrandHelper.dataRefreshNotifier.addListener(_loadBooks);
    _startupSequence();
  }

  @override
  void dispose() {
    FinTraxBrandHelper.dataRefreshNotifier.removeListener(_loadBooks);
    _autoBackupTimer?.cancel();
    _tabPageController.dispose();
    _bookSearchController.dispose();
    super.dispose();
  }

  Future<void> _startupSequence() async {
    Set<String> handledSet = <String>{};
    List<Map<String, dynamic>> existingBooks = <Map<String, dynamic>>[];
    try {
      handledSet = await DatabaseHelper.instance
          .getHandledSmsIds()
          .timeout(const Duration(seconds: 2), onTimeout: () => <String>{});
      existingBooks = await DatabaseHelper.instance
          .getBooksWithBalances()
          .timeout(const Duration(seconds: 2), onTimeout: () => <Map<String, dynamic>>[]);
    } catch (_) {}

    if (existingBooks.isNotEmpty && !handledSet.contains('__onboarding_v1_done__')) {
      try {
        await DatabaseHelper.instance.markSmsHandled('__onboarding_v1_done__', 'done');
        handledSet.add('__onboarding_v1_done__');
      } catch (_) {}
    }

    if (!handledSet.contains('__onboarding_v1_done__')) {
      if (mounted) {
        setState(() => _showOnboarding = true);
      }
      return;
    }

    await _loadBooks();
    if (mounted) {
      unawaited(_initBackgroundTasks(handledSet));
    }
  }

  Future<void> _initBackgroundTasks(Set<String> handledSet) async {
    if (!mounted) return;
    final prefs = Provider.of<ThemeProvider>(context, listen: false);

    for (int i = 0; i < 10 && !prefs.isInitialized; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (!mounted) return;

    try {
      final hasOsSmsPerm = await _nativeBridge.invokeMethod<bool>('checkSmsPermission') ?? false;
      final manuallyTurnedOff = handledSet.contains('__sms_manually_off__');
      if (hasOsSmsPerm && !manuallyTurnedOff && !prefs.smsAutoTrack) {
        await prefs.setSmsAutoTrack(true);
      }
    } catch (_) {}

    await _refreshSmsInbox();

    if (!handledSet.contains('__default_9pm_migrated__')) {
      if (prefs.reminderHour == 22 && prefs.reminderMinute == 0) {
        await prefs.setDailyReminder(
          enabled: prefs.dailyReminderEnabled,
          hour: 21,
          minute: 0,
        );
      }
      try {
        await DatabaseHelper.instance.markSmsHandled('__default_9pm_migrated__', 'done');
      } catch (_) {}
    }

    await AppLogger.instance.logRuntimeEnvironment(
      FinTraxCloudAndInsightsHelper.googleAuthPrimary,
      prefs,
    );

    try {
      await _nativeBridge.invokeMethod('scheduleDailyReminder', {
        'enabled': prefs.dailyReminderEnabled,
        'hour': prefs.reminderHour,
        'minute': prefs.reminderMinute,
      }).timeout(const Duration(seconds: 2));
    } catch (_) {}

    await _checkAndShowFirstOfMonthInsights(handledSet);
    unawaited(FinTraxCloudAndInsightsHelper.runSilentDailyBackup(prefs));

    final now = DateTime.now();
    final nextRun = DateTime(now.year, now.month, now.day + 1, 0, 5);
    _autoBackupTimer?.cancel();
    _autoBackupTimer = Timer(
      nextRun.difference(now),
      () => FinTraxCloudAndInsightsHelper.runSilentDailyBackup(prefs),
    );
  }

  Future<void> _checkAndShowFirstOfMonthInsights(Set<String> handledSet) async {
    try {
      bool launchedFromInsightNotif = false;
      try {
        launchedFromInsightNotif = await _nativeBridge
                .invokeMethod<bool>('consumeMonthlyInsightIntent')
                .timeout(const Duration(seconds: 1)) ??
            false;
      } catch (_) {}

      final now = DateTime.now();
      final markerKey = '__monthly_insight_shown_${now.year}_${now.month}__';

      if (launchedFromInsightNotif) {
        await DatabaseHelper.instance.markSmsHandled(markerKey, 'shown');
        if (mounted) {
          FinTraxCloudAndInsightsHelper.openMonthlyInsightsSheet(
            context: context,
            initialPreviousMonth: true,
            onBooksReload: _loadBooks,
          );
        }
        return;
      }

      if (!handledSet.contains(markerKey)) {
        final prevMonthDate = DateTime(now.year, now.month - 1, 1);
        final insights = await DatabaseHelper.instance.getMonthlyInsights(prevMonthDate.year, prevMonthDate.month);
        final int txCount = (insights['txCount'] as int?) ?? 0;
        final double lendingGiven = (insights['lendingGiven'] as num?)?.toDouble() ?? 0.0;
        await DatabaseHelper.instance.markSmsHandled(markerKey, 'shown');
        if ((txCount > 0 || lendingGiven > 0) && mounted) {
          FinTraxCloudAndInsightsHelper.openMonthlyInsightsSheet(
            context: context,
            initialPreviousMonth: true,
            onBooksReload: _loadBooks,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _loadBooks() async {
    if (!mounted) return;
    try {
      final rows = await DatabaseHelper.instance
          .getBooksWithBalances()
          .timeout(const Duration(seconds: 2), onTimeout: () => <Map<String, dynamic>>[]);

      rows.sort((a, b) {
        final pinA = (a['isPinned'] ?? 0) as int;
        final pinB = (b['isPinned'] ?? 0) as int;
        if (pinA != pinB) return pinB.compareTo(pinA);

        final upA = DateTime.tryParse(a['updatedAt']?.toString() ?? '') ?? DateTime.now();
        final upB = DateTime.tryParse(b['updatedAt']?.toString() ?? '') ?? DateTime.now();
        final crA = DateTime.tryParse(a['createdAt']?.toString() ?? '') ?? upA;
        final crB = DateTime.tryParse(b['createdAt']?.toString() ?? '') ?? upB;

        switch (_sortOrder) {
          case BookSort.updated:
            return upB.compareTo(upA);
          case BookSort.created:
            return crB.compareTo(crA);
          case BookSort.aToZ:
            return a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase());
          case BookSort.zToA:
            return b['name'].toString().toLowerCase().compareTo(a['name'].toString().toLowerCase());
        }
      });

      final contactsMap = await FinTraxBrandHelper.getAllBookContacts();
      if (mounted) {
        setState(() {
          _books = rows;
          _bookContacts = contactsMap;
          _loading = false;
        });
      }
      unawaited(_refreshSmsInbox());
    } catch (e) {
      AppLogger.instance.log('Book load error: $e', tag: 'ERROR');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Scans SMS inbox and automatically filters out any SMS that is already present
  /// in any local or restored book so duplicate suggestions never appear.
  Future<void> _refreshSmsInbox() async {
    if (!mounted) return;
    final prefs = Provider.of<ThemeProvider>(context, listen: false);
    try {
      final permitted = await _nativeBridge
              .invokeMethod<bool>('checkSmsPermission')
              .timeout(const Duration(seconds: 2), onTimeout: () => false) ??
          false;
      if (!permitted) {
        if (mounted) setState(() => _pendingSms = []);
        return;
      }

      // First reconcile any restored book transactions with the SMS inbox
      await FinTraxCloudAndInsightsHelper.syncRestoredTransactionsWithSmsInbox();

      final ignoredIds = await DatabaseHelper.instance.getHandledSmsIds();
      final manuallyOff = ignoredIds.contains('__sms_manually_off__');

      if (manuallyOff && !prefs.smsAutoTrack) {
        if (mounted) setState(() => _pendingSms = []);
        return;
      }

      if (!prefs.smsAutoTrack && !manuallyOff) {
        await prefs.setSmsAutoTrack(true);
      }

      final rawList = await _nativeBridge
              .invokeMethod<List<dynamic>>('getBankSms')
              .timeout(const Duration(seconds: 4), onTimeout: () => <dynamic>[]) ??
          [];

      final detected = <ParsedSmsTransaction>[];
      for (final item in rawList) {
        if (item is Map) {
          final parsed = ParsedSmsTransaction.tryParse(item);
          if (parsed != null && !ignoredIds.contains(parsed.smsId)) {
            detected.add(parsed);
          }
        }
      }
      if (mounted) setState(() => _pendingSms = detected);
    } catch (_) {}
  }

  // ===========================================================================
  // SMART CREATE & EDIT BOOK DIALOGS (WITH LENDING CONTACT PICKER)
  // ===========================================================================
  Future<Map<String, String>?> _pickContactFromPhone() async {
    try {
      final res = await _nativeBridge.invokeMethod<Map<dynamic, dynamic>>('pickContact');
      if (res == null) return null;
      return {
        'name': res['name']?.toString() ?? '',
        'phone': res['phone']?.toString() ?? '',
        'photoBase64': res['photoBase64']?.toString() ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  Future<int?> _promptCreateBook() async {
    HapticFeedback.lightImpact();
    final ctrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String pickedPhotoBase64 = '';
    String selectedBookType = 'standard';
    final currentMonthName = _monthNames[DateTime.now().month - 1];

    final suggestions = <Map<String, String>>[
      {'label': '$currentMonthName Expenses', 'type': 'standard', 'icon': '📅'},
      {'label': 'Grocery Expenses', 'type': 'standard', 'icon': '🛒'},
      {'label': 'Shopping Expenses', 'type': 'standard', 'icon': '🛍️'},
      {'label': 'Personal Expenses', 'type': 'standard', 'icon': '👤'},
      {'label': 'Money Lent', 'type': 'lending', 'icon': '🤝'},
      {'label': 'Home & Bills', 'type': 'standard', 'icon': '🏠'},
      {'label': 'Travel & Trips', 'type': 'standard', 'icon': '✈️'},
      {'label': 'Investments', 'type': 'standard', 'icon': '📈'},
    ];

    Widget buildCompactSuggestionChip({
      required Map<String, String> item,
      required bool isDark,
      required ColorScheme scheme,
      required StateSetter setDialogState,
    }) {
      final String label = item['label']!;
      final String type = item['type']!;
      final String icon = item['icon']!;
      final bool isSelected = ctrl.text.trim().toLowerCase() == label.toLowerCase();

      return Material(
        color: isSelected
            ? scheme.primary.withOpacity(isDark ? 0.25 : 0.14)
            : (isDark ? const Color(0xFF1A1D26) : const Color(0xFFF1F5F9)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected
                ? scheme.primary
                : (isDark ? AppConstants.borderDark : AppConstants.borderLight),
            width: isSelected ? 1.3 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            HapticFeedback.selectionClick();
            setDialogState(() {
              ctrl.text = label;
              ctrl.selection = TextSelection.fromPosition(TextPosition(offset: ctrl.text.length));
              selectedBookType = type;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final scheme = Theme.of(ctx).colorScheme;

          final List<Widget> suggestionRows = [];
          for (int i = 0; i < suggestions.length; i += 2) {
            final first = suggestions[i];
            final second = (i + 1 < suggestions.length) ? suggestions[i + 1] : null;
            suggestionRows.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: buildCompactSuggestionChip(
                        item: first,
                        isDark: isDark,
                        scheme: scheme,
                        setDialogState: setDialogState,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: second != null
                          ? buildCompactSuggestionChip(
                              item: second,
                              isDark: isDark,
                              scheme: scheme,
                              setDialogState: setDialogState,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            );
          }

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: const Text('Create New Book', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
            content: SizedBox(
              width: MediaQuery.of(ctx).size.width,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'e.g., $currentMonthName Expenses',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'BOOK TYPE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setDialogState(() => selectedBookType = 'standard');
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                              decoration: BoxDecoration(
                                color: selectedBookType == 'standard'
                                    ? scheme.primary.withOpacity(isDark ? 0.22 : 0.12)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selectedBookType == 'standard'
                                      ? scheme.primary
                                      : (isDark ? AppConstants.borderDark : AppConstants.borderLight),
                                  width: selectedBookType == 'standard' ? 1.4 : 1.0,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.book_rounded, size: 15, color: selectedBookType == 'standard' ? scheme.primary : Colors.grey),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      'Expense Book',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: selectedBookType == 'standard' ? FontWeight.w800 : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setDialogState(() => selectedBookType = 'lending');
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                              decoration: BoxDecoration(
                                color: selectedBookType == 'lending'
                                    ? AppConstants.goldAccent.withOpacity(isDark ? 0.22 : 0.14)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selectedBookType == 'lending'
                                      ? AppConstants.goldAccent
                                      : (isDark ? AppConstants.borderDark : AppConstants.borderLight),
                                  width: selectedBookType == 'lending' ? 1.4 : 1.0,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.handshake_rounded,
                                    size: 15,
                                    color: selectedBookType == 'lending' ? AppConstants.goldAccent : Colors.grey,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      'Lending Ledger',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: selectedBookType == 'lending' ? FontWeight.w800 : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (selectedBookType == 'lending') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Contact Number (Optional)',
                          hintText: 'Enter or import from contacts',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          suffixIcon: IconButton(
                            tooltip: 'Import from Contacts',
                            icon: Icon(Icons.contacts_rounded, color: scheme.primary),
                            onPressed: () async {
                              HapticFeedback.selectionClick();
                              final picked = await _pickContactFromPhone();
                              if (picked != null) {
                                setDialogState(() {
                                  phoneCtrl.text = picked['phone'] ?? '';
                                  pickedPhotoBase64 = picked['photoBase64'] ?? '';
                                  if (ctrl.text.trim().isEmpty && (picked['name'] ?? '').isNotEmpty) {
                                    ctrl.text = picked['name']!;
                                  }
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'QUICK SUGGESTIONS',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 6),
                    ...suggestionRows,
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  final title = ctrl.text.trim();
                  if (title.isEmpty) return;
                  final now = DateTime.now();
                  final id = await DatabaseHelper.instance.insertBook(
                    BookModel(
                      name: title,
                      createdAt: now,
                      updatedAt: now,
                      bookType: selectedBookType,
                    ),
                  );
                  if (id == -1) {
                    HapticFeedback.heavyImpact();
                    if (ctx.mounted) {
                      FinTraxBrandHelper.showModernSnackBar(
                        context: ctx,
                        message: 'A book with this name already exists.',
                        icon: Icons.warning_amber_rounded,
                        color: AppConstants.expenseRed,
                      );
                    }
                  } else {
                    if (selectedBookType == 'lending') {
                      await FinTraxBrandHelper.saveBookContact(id, phoneCtrl.text, pickedPhotoBase64);
                    }
                    HapticFeedback.mediumImpact();
                    await _loadBooks();
                    if (ctx.mounted) Navigator.pop(ctx, id);
                  }
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _promptRenameBook(int id, String oldName, String currentType) async {
    final existingContact = await FinTraxBrandHelper.getBookContact(id);
    if (!mounted) return;
    final ctrl = TextEditingController(text: oldName);
    final phoneCtrl = TextEditingController(text: existingContact['phone'] ?? '');
    String pickedPhotoBase64 = existingContact['photoBase64'] ?? '';
    String selectedType = currentType;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Rename / Edit Book', style: TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Lending Ledger', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  subtitle: const Text('Mark this book for money lent/borrowed', style: TextStyle(fontSize: 11)),
                  value: selectedType == 'lending',
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    setDialogState(() => selectedType = v ? 'lending' : 'standard');
                  },
                ),
                if (selectedType == 'lending') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Contact Number (Optional)',
                      hintText: 'Enter or import from contacts',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: IconButton(
                        tooltip: 'Import from Contacts',
                        icon: Icon(Icons.contacts_rounded, color: Theme.of(ctx).colorScheme.primary),
                        onPressed: () async {
                          HapticFeedback.selectionClick();
                          final picked = await _pickContactFromPhone();
                          if (picked != null) {
                            setDialogState(() {
                              phoneCtrl.text = picked['phone'] ?? '';
                              pickedPhotoBase64 = picked['photoBase64'] ?? '';
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final updated = ctrl.text.trim();
                if (updated.isNotEmpty) {
                  final res = await DatabaseHelper.instance.updateBookName(id, updated, bookType: selectedType);
                  if (res == -1) {
                    HapticFeedback.heavyImpact();
                    if (ctx.mounted) {
                      FinTraxBrandHelper.showModernSnackBar(
                        context: ctx,
                        message: 'A book with this name already exists.',
                        icon: Icons.warning_amber_rounded,
                        color: AppConstants.expenseRed,
                      );
                    }
                    return;
                  }
                  if (selectedType == 'lending') {
                    await FinTraxBrandHelper.saveBookContact(id, phoneCtrl.text, pickedPhotoBase64);
                  }
                  HapticFeedback.mediumImpact();
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadBooks();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndDeleteBookWithUndo(int bookId, String bookName) async {
    HapticFeedback.mediumImpact();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Do you want to delete?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: Text(
          'Delete "$bookName" and all its entries?',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConstants.expenseRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      HapticFeedback.heavyImpact();
      final db = await DatabaseHelper.instance.database;
      final bookRows = await db.query('books', where: 'id = ?', whereArgs: [bookId]);
      final txRows = await db.query('transactions', where: 'bookId = ?', whereArgs: [bookId]);
      final contactBackup = await FinTraxBrandHelper.getBookContact(bookId);

      await DatabaseHelper.instance.deleteBook(bookId);
      await FinTraxBrandHelper.saveBookContact(bookId, '', '');
      await _loadBooks();
      if (!mounted) return;

      FinTraxBrandHelper.showModernUndoBar(
        messenger: ScaffoldMessenger.of(context),
        message: 'Deleted "$bookName"',
        onUndo: () async {
          final restoreDb = await DatabaseHelper.instance.database;
          if (bookRows.isNotEmpty) {
            await restoreDb.insert('books', Map<String, Object?>.from(bookRows.first));
          }
          for (final tx in txRows) {
            await restoreDb.insert('transactions', Map<String, Object?>.from(tx));
          }
          if ((contactBackup['phone'] ?? '').isNotEmpty || (contactBackup['photoBase64'] ?? '').isNotEmpty) {
            await FinTraxBrandHelper.saveBookContact(
              bookId,
              contactBackup['phone'] ?? '',
              contactBackup['photoBase64'] ?? '',
            );
          }
          await _loadBooks();
        },
      );
    }
  }

  void _openBookMenu(int bookId, String bookName, int pinned, String bookType) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(bookName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const Divider(),
              ListTile(
                leading: Icon(pinned == 1 ? Icons.push_pin_outlined : Icons.push_pin),
                title: Text(pinned == 1 ? 'Unpin from Top' : 'Pin to Top'),
                onTap: () async {
                  HapticFeedback.lightImpact();
                  await DatabaseHelper.instance.togglePinBook(bookId, pinned == 0);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadBooks();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename / Change Book Type'),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx);
                  _promptRenameBook(bookId, bookName, bookType);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share as PDF'),
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(ctx);
                  final pdfBytes = await DashboardScreen.generateBookPdfBytes(bookId, bookName);
                  await Printing.sharePdf(bytes: pdfBytes, filename: '${bookName}_FinTrax_Statement.pdf');
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Export & Save as PDF'),
                subtitle: const Text('Save PDF statement to Downloads folder', style: TextStyle(fontSize: 11.5)),
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(ctx);
                  final pdfBytes = await DashboardScreen.generateBookPdfBytes(bookId, bookName);
                  final ok = await _nativeBridge.invokeMethod<bool>('savePdfToDownloads', {
                        'bytes': pdfBytes,
                        'fileName': '${bookName}_FinTrax_Statement.pdf',
                      }) ??
                      false;
                  if (mounted && ok) {
                    FinTraxBrandHelper.showModernSnackBar(
                      context: context,
                      message: 'PDF saved to Downloads successfully!',
                      icon: Icons.picture_as_pdf_rounded,
                      color: AppConstants.incomeGreen,
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppConstants.expenseRed),
                title: const Text('Delete Book', style: TextStyle(color: AppConstants.expenseRed)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmAndDeleteBookWithUndo(bookId, bookName);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _askDismissAllConfirmation(int total) async {
    HapticFeedback.mediumImpact();
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppConstants.expenseRed),
            SizedBox(width: 10),
            Expanded(child: Text('Dismiss All SMS?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
          ],
        ),
        content: Text(
          'Dismiss all $total detected SMS transactions?\n\nOnce dismissed, they will not appear in suggestions again. Only new future bank messages will be shown.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConstants.expenseRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dismiss All'),
          ),
        ],
      ),
    );
    return res == true;
  }

  void _openSmsReviewSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, updateSheet) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          if (_pendingSms.isEmpty) {
            return const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('All detected SMS transactions have been reviewed!')),
              ),
            );
          }
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.78),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Detected Bank SMS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              Text('${_pendingSms.length} pending', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            if (!await _askDismissAllConfirmation(_pendingSms.length)) return;
                            HapticFeedback.heavyImpact();
                            final ids = _pendingSms.map((e) => e.smsId).toList();
                            await DatabaseHelper.instance.markMultipleSmsHandled(ids, 'dismissed');
                            updateSheet(() => _pendingSms.clear());
                            if (mounted) setState(() {});
                            if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                          },
                          icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: AppConstants.expenseRed),
                          label: const Text(
                            'Dismiss All',
                            style: TextStyle(color: AppConstants.expenseRed, fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _pendingSms.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final item = _pendingSms[i];
                        final isCredit = item.type == 'Income';

                        final String resolvedTitle = FinTraxBrandHelper.resolveMerchantTitle(item.merchant, item.body);
                        final String resolvedMode = FinTraxBrandHelper.detectPaymentMethod(
                          currentMode: item.paymentMode,
                          smsBody: item.body,
                          sender: item.merchant,
                        );
                        final String? bankIconAsset = FinTraxBrandHelper.getPaymentIconAsset(
                          resolvedMode,
                          smsBody: item.body,
                          sender: item.merchant,
                        );
                        final String? autoCat = FinTraxBrandHelper.detectCategory(
                          resolvedTitle,
                          smsBody: item.body,
                        );

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  resolvedTitle,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${isCredit ? '+' : '-'}${AppConstants.defaultCurrency}${item.amount.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isCredit ? AppConstants.incomeGreen : AppConstants.expenseRed,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(item.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: bankIconAsset != null ? 5 : 7,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: bankIconAsset != null
                                        ? FinTraxBrandHelper.buildIconBadge(
                                            assetPath: bankIconAsset,
                                            fallbackEmoji: FinTraxBrandHelper.getPaymentEmoji(resolvedMode),
                                            size: 16,
                                            borderRadius: 3,
                                          )
                                        : Text(
                                            resolvedMode,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: isDark ? Colors.grey[300] : Colors.grey[800],
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${autoCat != null ? '$autoCat • ' : ''}${AppConstants.formatOrdinalDateTime(item.date)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppConstants.expenseRed,
                                      backgroundColor: AppConstants.expenseRed.withOpacity(0.08),
                                      side: BorderSide(color: AppConstants.expenseRed.withOpacity(0.45), width: 1),
                                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                                      minimumSize: const Size(0, 33),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                    ),
                                    onPressed: () async {
                                      HapticFeedback.selectionClick();
                                      await DatabaseHelper.instance.markSmsHandled(item.smsId, 'dismissed');
                                      updateSheet(() => _pendingSms.removeAt(i));
                                      setState(() {});
                                    },
                                    child: const Text(
                                      'Dismiss',
                                      style: TextStyle(
                                        color: AppConstants.expenseRed,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  FilledButton.tonal(
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      minimumSize: const Size(0, 33),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                    ),
                                    onPressed: () => _assignSmsToBook(item, () => updateSheet(() => _pendingSms.removeAt(i))),
                                    child: const Text('Review & Add', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _assignSmsToBook(ParsedSmsTransaction sms, VoidCallback onComplete) async {
    int? targetBookId;
    if (_books.isEmpty) {
      targetBookId = await _promptCreateBook();
      if (targetBookId == null) return;
    } else if (_books.length == 1) {
      targetBookId = _books.first['id'] as int;
    } else {
      targetBookId = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Select Book', style: TextStyle(fontWeight: FontWeight.w700)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          children: [
            ..._books.map(
              (b) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, b['id'] as int),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        (b['bookType']?.toString() ?? 'standard') == 'lending'
                            ? Icons.handshake_rounded
                            : Icons.book_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(b['name'].toString(), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, -999),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      'Create New Book',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
      if (targetBookId == -999) {
        targetBookId = await _promptCreateBook();
      }
    }

    if (targetBookId != null && targetBookId > 0 && mounted) {
      HapticFeedback.lightImpact();
      final String resolvedTitle = FinTraxBrandHelper.resolveMerchantTitle(sms.merchant, sms.body);
      final String resolvedMode = FinTraxBrandHelper.detectPaymentMethod(
        currentMode: sms.paymentMode,
        smsBody: sms.body,
        sender: sms.merchant,
      );
      final String autoCategory = FinTraxBrandHelper.detectCategory(
            resolvedTitle,
            smsBody: sms.body,
          ) ??
          '';

      final draft = TransactionModel(
        id: null,
        bookId: targetBookId,
        type: sms.type,
        amount: sms.amount,
        name: resolvedTitle,
        category: autoCategory,
        notes: '',
        smsBody: sms.body,
        date: sms.date,
        currency: AppConstants.defaultCurrency,
        paymentMode: resolvedMode,
      );

      final added = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => AddTransactionScreen(
            bookId: targetBookId!,
            type: sms.type,
            existingTransaction: draft,
            isSmsDraft: true,
          ),
        ),
      );

      if (added == true) {
        await DatabaseHelper.instance.markSmsHandled(sms.smsId, 'added');
        onComplete();
        _loadBooks();
      }
    }
  }

  Future<void> _toggleBiometricLock(ThemeProvider prefs, bool enabled) async {
    if (!enabled) {
      await prefs.setAppLock(false);
      return;
    }
    final secure = await _nativeBridge.invokeMethod<bool>('isDeviceSecure') ?? false;
    if (!secure) {
      if (mounted) {
        FinTraxBrandHelper.showModernSnackBar(
          context: context,
          message: 'Please set up a Fingerprint or Screen Lock in phone settings first.',
          icon: Icons.fingerprint_rounded,
          color: AppConstants.goldAccent,
        );
      }
      return;
    }
    final authenticated = await _nativeBridge.invokeMethod<bool>('authenticateDevice') ?? false;
    if (authenticated) {
      HapticFeedback.mediumImpact();
      await prefs.setAppLock(true);
    }
  }

  Future<void> _selectReminderTime(ThemeProvider prefs) async {
    HapticFeedback.selectionClick();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: prefs.reminderHour, minute: prefs.reminderMinute),
    );
    if (picked != null) {
      await prefs.setDailyReminder(enabled: true, hour: picked.hour, minute: picked.minute);
      await _nativeBridge.invokeMethod('scheduleDailyReminder', {
        'enabled': true,
        'hour': picked.hour,
        'minute': picked.minute,
      });
      if (mounted) {
        FinTraxBrandHelper.showModernSnackBar(
          context: context,
          message: 'Daily reminder set for ${AppConstants.formatTimeOfDay(picked.hour, picked.minute)}',
          icon: Icons.notifications_active_rounded,
          color: AppConstants.incomeGreen,
        );
      }
    }
  }

  Widget _buildHeaderLogo(bool isDark, bool dynamicColors) {
    final finColor = isDark ? Colors.white : const Color(0xFF0E1726);
    final traxColor = dynamicColors
        ? Theme.of(context).colorScheme.primary
        : (isDark ? AppConstants.goldAccent : AppConstants.goldDarkText);

    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Fin', style: TextStyle(color: finColor, fontWeight: FontWeight.w800, fontSize: 27, letterSpacing: 0.2, height: 1.0)),
              Text('Trax', style: TextStyle(color: traxColor, fontWeight: FontWeight.w300, fontSize: 27, letterSpacing: 0.5, height: 1.0)),
            ],
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: 0,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              child: Text(
                AppConstants.appTagline,
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBooksTab(bool isDark, bool dynamicColors) {
    final scheme = Theme.of(context).colorScheme;
    final accent = dynamicColors ? scheme.primary : AppConstants.goldAccent;
    final now = DateTime.now();
    final prevMonthName = _monthNames[DateTime(now.year, now.month - 1, 1).month - 1];

    final query = _bookSearchQuery.trim().toLowerCase();
    final digitsQuery = query.replaceAll(RegExp(r'[^0-9]'), '');
    final filteredBooks = query.isEmpty
        ? _books
        : _books.where((b) {
            final nameMatch = b['name'].toString().toLowerCase().contains(query);
            final bookId = b['id'] as int;
            final savedPhone = (_bookContacts[bookId]?['phone'] ?? '').toLowerCase();
            final savedDigits = savedPhone.replaceAll(RegExp(r'[^0-9]'), '');
            final phoneMatch = savedPhone.contains(query) ||
                (digitsQuery.isNotEmpty && savedDigits.contains(digitsQuery));
            return nameMatch || phoneMatch;
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: _isSearchingBooks
            ? TextField(
                controller: _bookSearchController,
                autofocus: true,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  hintText: 'Search books or phone number...',
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _bookSearchQuery = val),
              )
            : _buildHeaderLogo(isDark, dynamicColors),
        actions: [
          IconButton(
            tooltip: _isSearchingBooks ? 'Close Search' : 'Search Books',
            icon: Icon(_isSearchingBooks ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (_isSearchingBooks) {
                  _isSearchingBooks = false;
                  _bookSearchQuery = '';
                  _bookSearchController.clear();
                } else {
                  _isSearchingBooks = true;
                }
              });
            },
          ),
          IconButton(
            tooltip: 'Monthly Financial Insights',
            icon: const Icon(Icons.insights_rounded),
            onPressed: () => FinTraxCloudAndInsightsHelper.openMonthlyInsightsSheet(
              context: context,
              initialPreviousMonth: true,
              onBooksReload: _loadBooks,
            ),
          ),
          PopupMenuButton<BookSort>(
            icon: const Icon(Icons.sort_rounded),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (choice) {
              HapticFeedback.selectionClick();
              setState(() => _sortOrder = choice);
              _loadBooks();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: BookSort.updated, child: Text('Recently Updated')),
              PopupMenuItem(value: BookSort.created, child: Text('Recently Created')),
              PopupMenuItem(value: BookSort.aToZ, child: Text('Name (A to Z)')),
              PopupMenuItem(value: BookSort.zToA, child: Text('Name (Z to A)')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (now.day <= 5 && _books.isNotEmpty && !_isSearchingBooks)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Material(
                color: scheme.primary.withOpacity(isDark ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => FinTraxCloudAndInsightsHelper.openMonthlyInsightsSheet(
                    context: context,
                    initialPreviousMonth: true,
                    onBooksReload: _loadBooks,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(
                      children: [
                        Icon(Icons.insights_rounded, size: 20, color: scheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your $prevMonthName Expense Insights are ready!',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                          ),
                        ),
                        Text('View', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 12.5)),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios_rounded, size: 11, color: scheme.primary),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_pendingSms.isNotEmpty && !_isSearchingBooks)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Material(
                color: accent.withOpacity(isDark ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _openSmsReviewSheet,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.sms_outlined, size: 20, color: accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${_pendingSms.length} Bank SMS transaction${_pendingSms.length == 1 ? '' : 's'} found',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                        Text('Review', style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios_rounded, size: 12, color: accent),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _books.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.menu_book_rounded, size: 56, color: accent.withOpacity(0.45)),
                            const SizedBox(height: 12),
                            Text('No books yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[500])),
                            const SizedBox(height: 4),
                            Text('Tap "+ New Book" below to see smart suggestions', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : filteredBooks.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[500]),
                                const SizedBox(height: 10),
                                Text(
                                  'No books matching "$_bookSearchQuery"',
                                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 96, top: 8),
                            itemCount: filteredBooks.length,
                            itemBuilder: (ctx, idx) {
                              final item = filteredBooks[idx];
                              final pinned = (item['isPinned'] ?? 0) == 1;
                              final String bookType = item['bookType']?.toString() ?? 'standard';
                              final bool isLending = bookType == 'lending';
                              final balance = ((item['totalIn'] ?? 0) as num).toDouble() - ((item['totalOut'] ?? 0) as num).toDouble();
                              final isNeg = balance < 0;

                              final bg = isDark
                                  ? (pinned ? const Color(0xFF171A24) : AppConstants.cardDark)
                                  : (pinned ? const Color(0xFFFAF6EE) : AppConstants.cardLight);
                              final border = isLending
                                  ? AppConstants.goldAccent.withOpacity(0.55)
                                  : (isDark
                                      ? (pinned ? accent.withOpacity(0.45) : AppConstants.borderDark)
                                      : (pinned ? accent.withOpacity(0.40) : AppConstants.borderLight));

                              final createdDate = DateTime.tryParse(item['createdAt']?.toString() ?? '') ?? DateTime.now();
                              final updatedDate = DateTime.tryParse(item['updatedAt']?.toString() ?? '') ?? DateTime.now();

                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                child: Material(
                                  color: bg,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    side: BorderSide(color: border, width: isLending ? 1.2 : 1.0),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => DashboardScreen(
                                            bookId: item['id'] as int,
                                            bookName: item['name'].toString(),
                                            bookType: bookType,
                                          ),
                                        ),
                                      ).then((_) => _loadBooks());
                                    },
                                    onLongPress: () => _openBookMenu(
                                      item['id'] as int,
                                      item['name'].toString(),
                                      (item['isPinned'] ?? 0) as int,
                                      bookType,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(11),
                                            decoration: BoxDecoration(
                                              color: isLending
                                                  ? AppConstants.goldAccent.withOpacity(0.15)
                                                  : (dynamicColors
                                                      ? scheme.primary.withOpacity(0.12)
                                                      : (isDark ? AppConstants.iconNavy : const Color(0xFFF5EFE2))),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: accent.withOpacity(0.35), width: 0.8),
                                            ),
                                            child: Icon(
                                              isLending
                                                  ? Icons.handshake_rounded
                                                  : (pinned ? Icons.push_pin_rounded : Icons.book_rounded),
                                              color: isLending
                                                  ? AppConstants.goldAccent
                                                  : (dynamicColors ? scheme.primary : (isDark ? AppConstants.goldAccent : AppConstants.goldDarkText)),
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Row(
                                                  crossAxisAlignment: CrossAxisAlignment.center,
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        item['name'].toString(),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16.5),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Text(
                                                      '${isNeg ? '-' : ''}${AppConstants.defaultCurrency}${balance.abs().toStringAsFixed(0)}',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w800,
                                                        fontSize: 16.5,
                                                        color: isNeg ? AppConstants.expenseRed : AppConstants.incomeGreen,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    Icon(Icons.schedule_rounded, size: 11.5, color: Colors.grey[500]),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        AppConstants.formatOrdinalDateTime(updatedDate),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w500,
                                                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                                                        borderRadius: BorderRadius.circular(5),
                                                      ),
                                                      child: Text(
                                                        'Created on: ${AppConstants.formatOrdinalDate(createdDate)}',
                                                        style: TextStyle(
                                                          fontSize: 8.5,
                                                          letterSpacing: -0.2,
                                                          fontWeight: FontWeight.w500,
                                                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _promptCreateBook,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Book', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _settingsGroupCard(bool isDark, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Colors.grey[500]),
      ),
    );
  }

  Widget _buildSettingsTab(BuildContext context, bool isDark) {
    final prefs = Provider.of<ThemeProvider>(context);
    final scheme = Theme.of(context).colorScheme;

    final lastSyncLabel = prefs.lastBackupIso.isEmpty
        ? 'Not backed up yet'
        : AppConstants.formatOrdinalDateTime(DateTime.tryParse(prefs.lastBackupIso) ?? DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        children: [
          _sectionLabel('APPEARANCE'),
          _settingsGroupCard(isDark, [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Theme Mode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<AppThemeChoice>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
                      segments: const [
                        ButtonSegment(
                          value: AppThemeChoice.system,
                          icon: Icon(Icons.brightness_auto_outlined, size: 17),
                          label: Text('Auto', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 13)),
                        ),
                        ButtonSegment(
                          value: AppThemeChoice.light,
                          icon: Icon(Icons.light_mode_outlined, size: 17),
                          label: Text('Light', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 13)),
                        ),
                        ButtonSegment(
                          value: AppThemeChoice.dark,
                          icon: Icon(Icons.dark_mode_outlined, size: 17),
                          label: Text('AMOLED', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 13)),
                        ),
                      ],
                      selected: {prefs.themeChoice},
                      onSelectionChanged: (sel) {
                        HapticFeedback.selectionClick();
                        prefs.setThemeChoice(sel.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              dense: true,
              secondary: Icon(Icons.palette_outlined, color: scheme.primary, size: 21),
              title: const Text('Material You Colors', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: const Text('Use wallpaper colors instead of the default color', style: TextStyle(fontSize: 11.5)),
              value: prefs.useMaterialYou,
              onChanged: (v) {
                HapticFeedback.lightImpact();
                prefs.toggleMaterialYou(v);
              },
            ),
          ]),
          _sectionLabel('PREFERENCES & SECURITY'),
          _settingsGroupCard(isDark, [
            SwitchListTile(
              dense: true,
              secondary: Icon(Icons.fingerprint_rounded, color: scheme.primary, size: 22),
              title: const Text('Biometric App Lock', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: const Text('Unlock with Fingerprint or screen lock', style: TextStyle(fontSize: 11.5)),
              value: prefs.appLockEnabled,
              onChanged: (v) {
                HapticFeedback.lightImpact();
                _toggleBiometricLock(prefs, v);
              },
            ),
            const Divider(height: 1),
            SwitchListTile(
              dense: true,
              secondary: Icon(Icons.sms_outlined, color: scheme.primary, size: 21),
              title: const Text('Smart SMS Auto-Track', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: const Text('Auto-detect bank & UPI SMS offline', style: TextStyle(fontSize: 11.5)),
              value: prefs.smsAutoTrack,
              onChanged: (v) async {
                HapticFeedback.lightImpact();
                if (v) {
                  final ok = await _nativeBridge.invokeMethod<bool>('requestSmsPermission') ?? false;
                  if (!ok) {
                    if (context.mounted) {
                      FinTraxBrandHelper.showModernSnackBar(
                        context: context,
                        message: 'SMS permission is required to suggest bank transactions.',
                        icon: Icons.sms_failed_outlined,
                        color: AppConstants.expenseRed,
                      );
                    }
                    return;
                  }
                  final db = await DatabaseHelper.instance.database;
                  await db.delete('handled_sms', where: 'smsId = ?', whereArgs: ['__sms_manually_off__']);
                } else {
                  await DatabaseHelper.instance.markSmsHandled('__sms_manually_off__', 'true');
                }
                await prefs.setSmsAutoTrack(v);
                await _refreshSmsInbox();
              },
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.notifications_active_outlined, color: scheme.primary, size: 21),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _selectReminderTime(prefs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Daily Expense Reminder', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                          const SizedBox(height: 2),
                          Text(
                            prefs.dailyReminderEnabled
                                ? 'Tap time to change (${AppConstants.formatTimeOfDay(prefs.reminderHour, prefs.reminderMinute)})'
                                : 'Reminders paused • Tap switch to enable',
                            style: TextStyle(fontSize: 11.5, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _selectReminderTime(prefs),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: scheme.primary.withOpacity(prefs.dailyReminderEnabled ? 0.14 : 0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: scheme.primary.withOpacity(prefs.dailyReminderEnabled ? 0.35 : 0.15)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule_rounded, size: 13, color: prefs.dailyReminderEnabled ? scheme.primary : Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              AppConstants.formatTimeOfDay(prefs.reminderHour, prefs.reminderMinute),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                                color: prefs.dailyReminderEnabled ? scheme.primary : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Switch(
                    value: prefs.dailyReminderEnabled,
                    onChanged: (v) async {
                      HapticFeedback.lightImpact();
                      await prefs.setDailyReminder(enabled: v);
                      await _nativeBridge.invokeMethod('scheduleDailyReminder', {
                        'enabled': v,
                        'hour': prefs.reminderHour,
                        'minute': prefs.reminderMinute,
                      });
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(Icons.insights_rounded, color: scheme.primary, size: 21),
              title: const Text('Monthly Expense Insights', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: const Text('Tap categories or books to inspect detailed entries', style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
              onTap: () => FinTraxCloudAndInsightsHelper.openMonthlyInsightsSheet(
                context: context,
                initialPreviousMonth: true,
                onBooksReload: _loadBooks,
              ),
            ),
          ]),
          _sectionLabel('GOOGLE DRIVE SYNC'),
          _settingsGroupCard(isDark, [
            ListTile(
              dense: true,
              leading: Icon(Icons.add_to_drive_rounded, color: scheme.primary, size: 22),
              title: Text(
                prefs.driveAccount.isEmpty ? 'Connect Google Account' : prefs.driveAccount,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              subtitle: Text(
                prefs.driveAccount.isEmpty ? 'Auto-backups daily after 12:00 AM' : 'Last: $lastSyncLabel  •  Auto: 12:00 AM',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: TextButton(
                onPressed: () => FinTraxCloudAndInsightsHelper.onSwitchDriveAccount(
                  context: context,
                  prefs: prefs,
                  onBooksReload: _loadBooks,
                ),
                child: Text(
                  prefs.driveAccount.isEmpty ? 'Connect' : 'Switch',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => FinTraxCloudAndInsightsHelper.onBackupNow(
                        context: context,
                        prefs: prefs,
                        onBooksReload: _loadBooks,
                      ),
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text('Backup Now', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => FinTraxCloudAndInsightsHelper.onRestoreNow(
                        context: context,
                        prefs: prefs,
                        onBooksReload: _loadBooks,
                      ),
                      icon: const Icon(Icons.cloud_download_outlined, size: 18),
                      label: const Text('Restore', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(Icons.cloud_sync_rounded, color: scheme.primary, size: 21),
              title: const Text('Manage Cloud Data', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: const Text('Inspect backed-up books or delete specific cloud books', style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
              onTap: () => FinTraxCloudAndInsightsHelper.openManageCloudDataModal(
                context: context,
                prefs: prefs,
                onBooksReload: _loadBooks,
              ),
            ),
          ]),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppConstants.incomeGreen.withOpacity(isDark ? 0.10 : 0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppConstants.incomeGreen.withOpacity(0.28)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.verified_user_outlined, color: AppConstants.incomeGreen, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Offline • Zero Data Collection • Zero Ads',
                        maxLines: 1,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppConstants.incomeGreen),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'FinTrax never shows ads and never collects or shares your data. SMS detection runs locally on your phone, and backups stay in your personal Google Drive.',
                        style: TextStyle(fontSize: 11, height: 1.38, color: isDark ? Colors.grey[300] : Colors.grey[800]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _sectionLabel('ABOUT & CREDITS'),
          _settingsGroupCard(isDark, [
            const ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: AppConstants.iconNavy,
                child: Text('CK', style: TextStyle(color: AppConstants.goldAccent, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
              title: Text(AppConstants.developerRole, style: TextStyle(fontSize: 11, color: Colors.grey)),
              subtitle: Text(AppConstants.developerName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(Icons.code_rounded, color: scheme.primary, size: 20),
              title: const Text('GitHub', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              subtitle: const Text('github.com/${AppConstants.defaultGithubId}', style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.open_in_new_rounded, size: 16, color: Colors.grey),
              onTap: () {
                HapticFeedback.lightImpact();
                _nativeBridge.invokeMethod('openUrl', {'url': 'https://github.com/${AppConstants.defaultGithubId}'});
              },
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(Icons.alternate_email_rounded, color: scheme.primary, size: 20),
              title: const Text('Contact Email', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              subtitle: const Text(AppConstants.defaultDeveloperEmail, style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.mail_outline_rounded, size: 16, color: Colors.grey),
              onTap: () {
                HapticFeedback.lightImpact();
                _nativeBridge.invokeMethod('openUrl', {'url': 'mailto:${AppConstants.defaultDeveloperEmail}?subject=FinTrax%20Feedback'});
              },
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(Icons.send_rounded, color: scheme.primary, size: 20),
              title: const Text('Telegram', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              subtitle: const Text('@chandsy', style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.open_in_new_rounded, size: 16, color: Colors.grey),
              onTap: () {
                HapticFeedback.lightImpact();
                _nativeBridge.invokeMethod('openUrl', {'url': 'https://t.me/chandsy'});
              },
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(Icons.bug_report_rounded, color: scheme.primary, size: 20),
              title: const Text('Diagnostic Logs', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              subtitle: const Text('View, clear, or save backend logs to Downloads', style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DebugLogsScreen()));
              },
            ),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding) {
      return WelcomeSetupScreen(
        onFinished: () async {
          setState(() => _showOnboarding = false);
          await _loadBooks();
          final handled = await DatabaseHelper.instance.getHandledSmsIds();
          unawaited(_initBackgroundTasks(handled));
        },
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prefs = Provider.of<ThemeProvider>(context);
    return Scaffold(
      body: PageView(
        controller: _tabPageController,
        onPageChanged: (idx) {
          if (_tabIndex != idx) {
            HapticFeedback.selectionClick();
            setState(() => _tabIndex = idx);
          }
        },
        children: [
          KeyedSubtree(key: const ValueKey('books_tab'), child: _buildBooksTab(isDark, prefs.useMaterialYou)),
          KeyedSubtree(key: const ValueKey('settings_tab'), child: _buildSettingsTab(context, isDark)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        backgroundColor: isDark ? AppConstants.cardDark : AppConstants.cardLight,
        elevation: 0,
        onDestinationSelected: (idx) {
          HapticFeedback.selectionClick();
          setState(() => _tabIndex = idx);
          _tabPageController.animateToPage(
            idx,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.book_outlined), selectedIcon: Icon(Icons.book_rounded), label: 'Books'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}
