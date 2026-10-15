import 'dart:async';
import 'dart:convert';
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

enum BookSort { updated, created, aToZ, zToA }

class BooksScreen extends StatefulWidget {
  const BooksScreen({Key? key}) : super(key: key);

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  static const MethodChannel _smsChannel = MethodChannel('com.chandankumar.fintrack/sms');

  int _selectedIndex = 0;
  List<Map<String, dynamic>> _booksData = [];
  List<ParsedSmsTransaction> _smsSuggestions = [];
  bool _isLoading = true;
  BookSort _currentSort = BookSort.updated;
  Timer? _midnightBackupTimer;

  @override
  void initState() {
    super.initState();
    _refreshBooks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSchedulesAndAutoBackup();
    });
  }

  @override
  void dispose() {
    _midnightBackupTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeSchedulesAndAutoBackup() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    if (!themeProvider.isInitialized) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    if (!mounted) return;

    try {
      await _smsChannel.invokeMethod('scheduleDailyReminder', {
        'enabled': themeProvider.dailyReminderEnabled,
        'hour': themeProvider.reminderHour,
        'minute': themeProvider.reminderMinute,
      });
    } catch (_) {}

    await _checkAndRunDailyAutoBackup();

    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 5);
    _midnightBackupTimer?.cancel();
    _midnightBackupTimer = Timer(nextMidnight.difference(now), () {
      _checkAndRunDailyAutoBackup();
    });
  }

  Future<void> _checkAndRunDailyAutoBackup() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    if (themeProvider.driveAccount.isEmpty) return;

    // Never overwrite an existing cloud backup with an empty database!
    final books = await DatabaseHelper.instance.getBooksWithBalances();
    if (books.isEmpty) return;

    final now = DateTime.now();
    final String todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (themeProvider.lastAutoBackupDay == todayKey) return;

    try {
      final String jsonPayload = await DatabaseHelper.instance.exportDatabaseJson();
      final bool ok = await _smsChannel.invokeMethod('performDriveBackup', {
        'account': themeProvider.driveAccount,
        'data': jsonPayload,
      }) ?? false;
      if (ok) {
        await themeProvider.recordBackupSuccess(
          isoTimestamp: now.toIso8601String(),
          dayKey: todayKey,
        );
      }
    } catch (_) {}
  }

  Future<void> _refreshBooks() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final List<Map<String, dynamic>> data = await DatabaseHelper.instance.getBooksWithBalances();

      data.sort((a, b) {
        final int pinA = (a['isPinned'] ?? 0) as int;
        final int pinB = (b['isPinned'] ?? 0) as int;
        if (pinA == 1 && pinB == 0) return -1;
        if (pinA == 0 && pinB == 1) return 1;

        final DateTime upA = DateTime.tryParse(a['updatedAt']?.toString() ?? '') ?? DateTime.now();
        final DateTime upB = DateTime.tryParse(b['updatedAt']?.toString() ?? '') ?? DateTime.now();
        final DateTime crA = DateTime.tryParse(a['createdAt']?.toString() ?? '') ?? upA;
        final DateTime crB = DateTime.tryParse(b['createdAt']?.toString() ?? '') ?? upB;

        switch (_currentSort) {
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

      if (mounted) {
        setState(() => _booksData = data);
      }
      await _scanSmsIfEnabled();
    } catch (e) {
      debugPrint('Error loading books: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _scanSmsIfEnabled() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    if (!themeProvider.smsAutoTrack) {
      if (mounted) setState(() => _smsSuggestions = []);
      return;
    }
    try {
      final bool hasPerm = await _smsChannel.invokeMethod('checkSmsPermission') ?? false;
      if (!hasPerm) return;

      final List<dynamic> rawSms = await _smsChannel.invokeMethod('getBankSms') ?? [];
      final Set<String> handledIds = await DatabaseHelper.instance.getHandledSmsIds();

      final List<ParsedSmsTransaction> parsed = [];
      for (final item in rawSms) {
        if (item is Map) {
          final tx = ParsedSmsTransaction.tryParse(item);
          if (tx != null && !handledIds.contains(tx.smsId)) {
            parsed.add(tx);
          }
        }
      }
      if (mounted) {
        setState(() => _smsSuggestions = parsed);
      }
    } catch (e) {
      debugPrint('SMS Scan skipped: $e');
    }
  }

  String _formatCreatedDate(String? isoString) {
    final DateTime date = DateTime.tryParse(isoString ?? '') ?? DateTime.now();
    return AppConstants.formatOrdinalDate(date);
  }

  String _formatUpdatedDateTime(String? isoString) {
    final DateTime date = DateTime.tryParse(isoString ?? '') ?? DateTime.now();
    return AppConstants.formatOrdinalDateTime(date);
  }

  /// Opens the Create New Book dialog and returns the newly created book's ID (or null if cancelled)
  Future<int?> _showAddBookDialog() async {
    HapticFeedback.lightImpact();
    final TextEditingController nameController = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Create New Book', style: TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'e.g., Monthly Expenses',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final text = nameController.text.trim();
              if (text.isEmpty) return;
              final now = DateTime.now();
              final int result = await DatabaseHelper.instance.insertBook(
                BookModel(name: text, createdAt: now, updatedAt: now),
              );
              if (result == -1) {
                HapticFeedback.heavyImpact();
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('A book with this name already exists.'), backgroundColor: AppConstants.expenseRed),
                  );
                }
              } else {
                HapticFeedback.mediumImpact();
                await _refreshBooks();
                if (dialogContext.mounted) Navigator.pop(dialogContext, result);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showEditBookDialog(int bookId, String currentName) {
    final TextEditingController nameController = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Rename Book', style: TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final text = nameController.text.trim();
              if (text.isNotEmpty && text != currentName) {
                final res = await DatabaseHelper.instance.updateBookName(bookId, text);
                if (res == -1) {
                  HapticFeedback.heavyImpact();
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('A book with this name already exists.'), backgroundColor: AppConstants.expenseRed),
                    );
                  }
                  return;
                }
                HapticFeedback.mediumImpact();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _refreshBooks();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showBookOptions(int bookId, String currentName, int isPinned) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
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
                child: Text(currentName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const Divider(),
              ListTile(
                leading: Icon(isPinned == 1 ? Icons.push_pin_outlined : Icons.push_pin),
                title: Text(isPinned == 1 ? 'Unpin from Top' : 'Pin to Top'),
                onTap: () async {
                  HapticFeedback.lightImpact();
                  await DatabaseHelper.instance.togglePinBook(bookId, isPinned == 0);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  _refreshBooks();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename Book'),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(sheetContext);
                  _showEditBookDialog(bookId, currentName);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share as PDF'),
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(sheetContext);
                  final bytes = await DashboardScreen.generateBookPdfBytes(bookId, currentName);
                  await Printing.sharePdf(bytes: bytes, filename: '${currentName}_FinTrax_Statement.pdf');
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Export & Save as PDF'),
                subtitle: const Text('Save PDF statement to Downloads folder', style: TextStyle(fontSize: 11.5)),
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(sheetContext);
                  final bytes = await DashboardScreen.generateBookPdfBytes(bookId, currentName);
                  final bool saved = await _smsChannel.invokeMethod('savePdfToDownloads', {
                    'bytes': bytes,
                    'fileName': '${currentName}_FinTrax_Statement.pdf',
                  }) ?? false;
                  if (mounted && saved) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('PDF saved to Downloads successfully!'), backgroundColor: AppConstants.incomeGreen),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppConstants.expenseRed),
                title: const Text('Delete Book', style: TextStyle(color: AppConstants.expenseRed)),
                onTap: () async {
                  HapticFeedback.heavyImpact();
                  await DatabaseHelper.instance.deleteBook(bookId);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  _refreshBooks();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDismissAllSms(int count) async {
    HapticFeedback.mediumImpact();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppConstants.expenseRed),
            SizedBox(width: 10),
            Expanded(child: Text('Dismiss All SMS?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
          ],
        ),
        content: Text(
          'Are you sure you want to dismiss all $count pending SMS transactions?\n\nOnce dismissed, these messages will be permanently removed from suggestions and cannot be added from this tab again. Only new future bank SMS messages will appear.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConstants.expenseRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Dismiss All'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _showSmsSuggestionsSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (_smsSuggestions.isEmpty) {
              return const SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: Text('All detected SMS transactions have been reviewed!')),
                ),
              );
            }
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2))),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Detected Bank SMS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                Text('${_smsSuggestions.length} pending', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final bool proceed = await _confirmDismissAllSms(_smsSuggestions.length);
                              if (!proceed) return;
                              HapticFeedback.heavyImpact();
                              final ids = _smsSuggestions.map((s) => s.smsId).toList();
                              await DatabaseHelper.instance.markMultipleSmsHandled(ids, 'dismissed');
                              setSheetState(() => _smsSuggestions.clear());
                              if (mounted) setState(() {});
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                            },
                            icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: AppConstants.expenseRed),
                            label: const Text('Dismiss All', style: TextStyle(color: AppConstants.expenseRed, fontWeight: FontWeight.w700, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _smsSuggestions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final sms = _smsSuggestions[idx];
                          final isIncome = sms.type == 'Income';
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text(sms.merchant, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                                Text(
                                  '${isIncome ? '+' : '-'}${AppConstants.defaultCurrency}${sms.amount.toStringAsFixed(0)}',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: isIncome ? AppConstants.incomeGreen : AppConstants.expenseRed),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(sms.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text('${sms.paymentMode} • ${AppConstants.formatOrdinalDateTime(sms.date)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () async {
                                        HapticFeedback.selectionClick();
                                        await DatabaseHelper.instance.markSmsHandled(sms.smsId, 'dismissed');
                                        setSheetState(() => _smsSuggestions.removeAt(idx));
                                        setState(() {});
                                      },
                                      child: const Text('Dismiss', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                    ),
                                    FilledButton.tonal(
                                      onPressed: () => _promptBookAndEditSms(sms, () {
                                        setSheetState(() => _smsSuggestions.removeAt(idx));
                                      }),
                                      child: const Text('Review & Add', style: TextStyle(fontSize: 12)),
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
        );
      },
    );
  }

  // If no books exist yet, immediately opens the Create New Book dialog and proceeds straight to adding the SMS entry
  Future<void> _promptBookAndEditSms(ParsedSmsTransaction sms, VoidCallback onAdded) async {
    int? chosenBookId;

    if (_booksData.isEmpty) {
      chosenBookId = await _showAddBookDialog();
      if (chosenBookId == null) return;
    } else if (_booksData.length == 1) {
      chosenBookId = _booksData.first['id'] as int;
    } else {
      chosenBookId = await showDialog<int>(
        context: context,
        builder: (dCtx) => SimpleDialog(
          title: const Text('Select Book', style: TextStyle(fontWeight: FontWeight.w700)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          children: [
            ..._booksData.map((b) {
              return SimpleDialogOption(
                onPressed: () => Navigator.pop(dCtx, b['id'] as int),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.book_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(child: Text(b['name'].toString(), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
              );
            }),
            const Divider(),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dCtx, -999),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Text('Create New Book', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

      if (chosenBookId == -999) {
        chosenBookId = await _showAddBookDialog();
      }
    }

    if (chosenBookId != null && chosenBookId > 0 && mounted) {
      HapticFeedback.lightImpact();
      final prefilledDraft = TransactionModel(
        id: null,
        bookId: chosenBookId,
        type: sms.type,
        amount: sms.amount,
        name: sms.merchant,
        category: '',
        notes: sms.body,
        date: sms.date,
        currency: AppConstants.defaultCurrency,
        paymentMode: sms.paymentMode,
      );

      final bool? saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => AddTransactionScreen(
            bookId: chosenBookId!,
            type: sms.type,
            existingTransaction: prefilledDraft,
            isSmsDraft: true,
          ),
        ),
      );

      if (saved == true) {
        await DatabaseHelper.instance.markSmsHandled(sms.smsId, 'added');
        onAdded();
        _refreshBooks();
      }
    }
  }

  Future<String?> _ensureGoogleDriveAccount(ThemeProvider themeProvider, {bool forceChoose = false}) async {
    if (themeProvider.driveAccount.isNotEmpty && !forceChoose) {
      return themeProvider.driveAccount;
    }

    final String? selectedEmail = await _smsChannel.invokeMethod('pickGoogleAccount');
    if (selectedEmail == null || selectedEmail.isEmpty || !mounted) return null;

    final bool? granted = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.add_to_drive_rounded, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            const Expanded(child: Text('Allow Google Drive Access?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          ],
        ),
        content: Text(
          'FinTrax wants permission to store and restore your ledger backups in Google Drive for:\n\n$selectedEmail\n\n• Automatic daily backup after 12:00 AM\n• Private app-only Drive sync',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Deny')),
          FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Allow')),
        ],
      ),
    );

    if (granted == true) {
      await themeProvider.setDriveAccount(selectedEmail);
      // Check if an existing backup is already stored for this Google account and sync its timestamp
      try {
        final String? existingJson = await _smsChannel.invokeMethod('checkDriveBackup', {'account': selectedEmail});
        if (existingJson != null && existingJson.isNotEmpty) {
          final Map<String, dynamic> decoded = jsonDecode(existingJson) as Map<String, dynamic>;
          final String expIso = decoded['exportedAt']?.toString() ?? '';
          if (expIso.isNotEmpty) {
            await themeProvider.recordBackupSuccess(isoTimestamp: expIso, dayKey: themeProvider.lastAutoBackupDay);
          }
        }
      } catch (_) {}
      return selectedEmail;
    }
    return null;
  }

  Future<void> _handleDriveBackup(ThemeProvider themeProvider) async {
    HapticFeedback.mediumImpact();
    final String? account = await _ensureGoogleDriveAccount(themeProvider);
    if (account == null) return;

    try {
      final String jsonPayload = await DatabaseHelper.instance.exportDatabaseJson();
      final bool success = await _smsChannel.invokeMethod('performDriveBackup', {
        'account': account,
        'data': jsonPayload,
      }) ?? false;

      if (success) {
        final now = DateTime.now();
        final String todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        await themeProvider.recordBackupSuccess(
          isoTimestamp: now.toIso8601String(),
          dayKey: todayKey,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Backed up to Google Drive ($account)'),
              backgroundColor: AppConstants.incomeGreen,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google Drive backup failed.'), backgroundColor: AppConstants.expenseRed),
        );
      }
    }
  }

  Future<void> _handleDriveRestore(ThemeProvider themeProvider) async {
    HapticFeedback.mediumImpact();
    final String? account = await _ensureGoogleDriveAccount(themeProvider);
    if (account == null || !mounted) return;

    final String? jsonContent = await _smsChannel.invokeMethod('checkDriveBackup', {'account': account});
    if (!mounted) return;

    if (jsonContent == null || jsonContent.isEmpty) {
      showDialog(
        context: context,
        builder: (dCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('No Backup Found', style: TextStyle(fontWeight: FontWeight.w700)),
          content: Text('No FinTrax backup was found on Google Drive for $account.'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(dCtx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    String backupTimeFormatted = 'Unknown date';
    String exportedIso = '';
    int bookCount = 0;
    int txCount = 0;
    try {
      final Map<String, dynamic> decoded = jsonDecode(jsonContent) as Map<String, dynamic>;
      exportedIso = decoded['exportedAt']?.toString() ?? '';
      final DateTime? expDate = DateTime.tryParse(exportedIso);
      if (expDate != null) {
        backupTimeFormatted = AppConstants.formatOrdinalDateTime(expDate);
      }
      bookCount = ((decoded['books'] as List<dynamic>?) ?? []).length;
      txCount = ((decoded['transactions'] as List<dynamic>?) ?? []).length;
    } catch (_) {}

    final bool? confirmRestore = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Google Drive Backup Found', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text(
          'Account: $account\nLast Backup: $backupTimeFormatted\nContents: $bookCount Book(s), $txCount Entries\n\nDo you want to restore this backup into FinTrax?',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Restore Now')),
        ],
      ),
    );

    if (confirmRestore == true) {
      final int restored = await DatabaseHelper.instance.importDatabaseJson(jsonContent);
      if (exportedIso.isNotEmpty) {
        final now = DateTime.now();
        final String todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        await themeProvider.recordBackupSuccess(isoTimestamp: exportedIso, dayKey: todayKey);
      }
      await _refreshBooks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restored $restored book(s) from Google Drive ($account)!'),
            backgroundColor: AppConstants.incomeGreen,
          ),
        );
      }
    }
  }

  Future<void> _handleAppLockToggle(ThemeProvider themeProvider, bool enable) async {
    if (!enable) {
      await themeProvider.setAppLock(false);
      return;
    }
    final bool isSecure = await _smsChannel.invokeMethod('isDeviceSecure') ?? false;
    if (!isSecure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please set up a Fingerprint or Screen Lock in your phone settings first.')),
        );
      }
      return;
    }
    final bool verified = await _smsChannel.invokeMethod('authenticateDevice') ?? false;
    if (verified) {
      HapticFeedback.mediumImpact();
      await themeProvider.setAppLock(true);
    }
  }

  Future<void> _pickReminderTime(ThemeProvider themeProvider) async {
    HapticFeedback.selectionClick();
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: themeProvider.reminderHour, minute: themeProvider.reminderMinute),
    );
    if (picked != null) {
      await themeProvider.setDailyReminder(
        enabled: true,
        hour: picked.hour,
        minute: picked.minute,
      );
      await _smsChannel.invokeMethod('scheduleDailyReminder', {
        'enabled': true,
        'hour': picked.hour,
        'minute': picked.minute,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Daily reminder set for ${AppConstants.formatTimeOfDay(picked.hour, picked.minute)}')),
        );
      }
    }
  }

  Widget _buildBrandHeader(bool isDark, bool useMaterialYou) {
    final Color finColor = isDark ? Colors.white : const Color(0xFF0E1726);
    final Color traxColor = useMaterialYou
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
              Text(
                'Fin',
                style: TextStyle(
                  color: finColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 27,
                  letterSpacing: 0.2,
                  height: 1.0,
                ),
              ),
              Text(
                'Trax',
                style: TextStyle(
                  color: traxColor,
                  fontWeight: FontWeight.w300,
                  fontSize: 27,
                  letterSpacing: 0.5,
                  height: 1.0,
                ),
              ),
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

  Widget _buildBooksView(bool isDark, bool useMaterialYou) {
    final scheme = Theme.of(context).colorScheme;
    final Color goldOrDynamic = useMaterialYou ? scheme.primary : AppConstants.goldAccent;

    return Scaffold(
      appBar: AppBar(
        title: _buildBrandHeader(isDark, useMaterialYou),
        actions: [
          PopupMenuButton<BookSort>(
            icon: const Icon(Icons.sort_rounded),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (sort) {
              HapticFeedback.selectionClick();
              setState(() => _currentSort = sort);
              _refreshBooks();
            },
            itemBuilder: (context) => const [
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
          if (_smsSuggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Material(
                color: goldOrDynamic.withOpacity(isDark ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _showSmsSuggestionsSheet,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.sms_outlined, size: 20, color: goldOrDynamic),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${_smsSuggestions.length} Bank SMS transaction${_smsSuggestions.length == 1 ? '' : 's'} found',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                        Text('Review', style: TextStyle(color: goldOrDynamic, fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios_rounded, size: 12, color: goldOrDynamic),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _booksData.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.menu_book_rounded, size: 56, color: goldOrDynamic.withOpacity(0.45)),
                            const SizedBox(height: 12),
                            Text('No books yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[500])),
                            const SizedBox(height: 4),
                            Text('Tap "+ New Book" below to get started', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 96, top: 8),
                        itemCount: _booksData.length,
                        itemBuilder: (context, index) {
                          final book = _booksData[index];
                          final bool isPinned = (book['isPinned'] ?? 0) == 1;
                          final double netBalance = ((book['totalIn'] ?? 0) as num).toDouble() - ((book['totalOut'] ?? 0) as num).toDouble();
                          final bool isNegative = netBalance < 0;

                          final Color cardColor = isDark
                              ? (isPinned ? const Color(0xFF171A24) : AppConstants.cardDark)
                              : (isPinned ? const Color(0xFFFAF6EE) : AppConstants.cardLight);

                          final Color borderColor = isDark
                              ? (isPinned ? goldOrDynamic.withOpacity(0.45) : AppConstants.borderDark)
                              : (isPinned ? goldOrDynamic.withOpacity(0.40) : AppConstants.borderLight);

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: Material(
                              color: cardColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                                side: BorderSide(color: borderColor, width: 1),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DashboardScreen(bookId: book['id'] as int, bookName: book['name'].toString()),
                                    ),
                                  ).then((_) => _refreshBooks());
                                },
                                onLongPress: () => _showBookOptions(book['id'] as int, book['name'].toString(), (book['isPinned'] ?? 0) as int),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(11),
                                        decoration: BoxDecoration(
                                          color: useMaterialYou
                                              ? scheme.primary.withOpacity(0.12)
                                              : (isDark ? AppConstants.iconNavy : const Color(0xFFF5EFE2)),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: goldOrDynamic.withOpacity(0.35),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Icon(
                                          isPinned ? Icons.push_pin_rounded : Icons.book_rounded,
                                          color: useMaterialYou ? scheme.primary : (isDark ? AppConstants.goldAccent : AppConstants.goldDarkText),
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
                                                    book['name'].toString(),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                // Compact "Created on :" badge without extending pill width
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                                  decoration: BoxDecoration(
                                                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    'Created on : ${_formatCreatedDate(book['createdAt']?.toString())}',
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
                                            const SizedBox(height: 6),
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.schedule_rounded,
                                                  size: 12,
                                                  color: isDark ? Colors.grey[500] : Colors.grey[500],
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    _formatUpdatedDateTime(book['updatedAt']?.toString()),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w500,
                                                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  '${isNegative ? '-' : ''}${AppConstants.defaultCurrency}${netBalance.abs().toStringAsFixed(0)}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 16,
                                                    color: isNegative ? AppConstants.expenseRed : AppConstants.incomeGreen,
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
        onPressed: () => _showAddBookDialog(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Book', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children, required bool isDark}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
      child: Text(
        title,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Colors.grey[500]),
      ),
    );
  }

  // Clean, spacious, executive Settings view
  Widget _buildSettingsView(BuildContext context, bool isDark) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final scheme = Theme.of(context).colorScheme;

    final String lastBackupText = themeProvider.lastBackupIso.isEmpty
        ? 'Not backed up yet'
        : AppConstants.formatOrdinalDateTime(DateTime.tryParse(themeProvider.lastBackupIso) ?? DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        children: [
          _buildSectionHeader('APPEARANCE'),
          _buildSettingsCard(
            isDark: isDark,
            children: [
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
                        style: SegmentedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        ),
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
                        selected: {themeProvider.themeChoice},
                        onSelectionChanged: (selection) {
                          HapticFeedback.selectionClick();
                          themeProvider.setThemeChoice(selection.first);
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
                subtitle: const Text('Use wallpaper colors instead of Gold', style: TextStyle(fontSize: 11.5)),
                value: themeProvider.useMaterialYou,
                onChanged: (val) {
                  HapticFeedback.lightImpact();
                  themeProvider.toggleMaterialYou(val);
                },
              ),
            ],
          ),

          _buildSectionHeader('PREFERENCES & SECURITY'),
          _buildSettingsCard(
            isDark: isDark,
            children: [
              SwitchListTile(
                dense: true,
                secondary: Icon(Icons.fingerprint_rounded, color: scheme.primary, size: 22),
                title: const Text('Biometric App Lock', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                subtitle: const Text('Unlock with Fingerprint or screen lock', style: TextStyle(fontSize: 11.5)),
                value: themeProvider.appLockEnabled,
                onChanged: (val) {
                  HapticFeedback.lightImpact();
                  _handleAppLockToggle(themeProvider, val);
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                dense: true,
                secondary: Icon(Icons.sms_outlined, color: scheme.primary, size: 21),
                title: const Text('Smart SMS Auto-Track', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                subtitle: const Text('Auto-detect bank & UPI SMS offline', style: TextStyle(fontSize: 11.5)),
                value: themeProvider.smsAutoTrack,
                onChanged: (val) async {
                  HapticFeedback.lightImpact();
                  if (val) {
                    final bool granted = await _smsChannel.invokeMethod('requestSmsPermission') ?? false;
                    if (!granted) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('SMS permission is required to suggest bank transactions.')),
                        );
                      }
                      return;
                    }
                  }
                  await themeProvider.setSmsAutoTrack(val);
                  await _scanSmsIfEnabled();
                },
              ),
              const Divider(height: 1),
              // Merged Daily Reminder Switch + Inline Tappable Time Chip
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.notifications_active_outlined, color: scheme.primary, size: 21),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Daily Expense Reminder', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                          const SizedBox(height: 2),
                          Text(
                            themeProvider.dailyReminderEnabled ? 'Includes daily SMS summary' : 'Reminders paused',
                            style: TextStyle(fontSize: 11.5, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    if (themeProvider.dailyReminderEnabled)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _pickReminderTime(themeProvider),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              color: scheme.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: scheme.primary.withOpacity(0.3)),
                            ),
                            child: Text(
                              AppConstants.formatTimeOfDay(themeProvider.reminderHour, themeProvider.reminderMinute),
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: scheme.primary),
                            ),
                          ),
                        ),
                      ),
                    Switch(
                      value: themeProvider.dailyReminderEnabled,
                      onChanged: (val) async {
                        HapticFeedback.lightImpact();
                        await themeProvider.setDailyReminder(enabled: val);
                        await _smsChannel.invokeMethod('scheduleDailyReminder', {
                          'enabled': val,
                          'hour': themeProvider.reminderHour,
                          'minute': themeProvider.reminderMinute,
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          _buildSectionHeader('GOOGLE DRIVE SYNC'),
          _buildSettingsCard(
            isDark: isDark,
            children: [
              ListTile(
                dense: true,
                leading: Icon(Icons.add_to_drive_rounded, color: scheme.primary, size: 22),
                title: Text(
                  themeProvider.driveAccount.isEmpty ? 'Connect Google Account' : themeProvider.driveAccount,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                subtitle: Text(
                  themeProvider.driveAccount.isEmpty
                      ? 'Auto-backups daily after 12:00 AM'
                      : 'Last: $lastBackupText  •  Auto: 12:00 AM',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: TextButton(
                  onPressed: () => _ensureGoogleDriveAccount(themeProvider, forceChoose: true),
                  child: Text(themeProvider.driveAccount.isEmpty ? 'Connect' : 'Switch', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
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
                        onPressed: () => _handleDriveBackup(themeProvider),
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
                        onPressed: () => _handleDriveRestore(themeProvider),
                        icon: const Icon(Icons.cloud_download_outlined, size: 18),
                        label: const Text('Restore', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Clean, Structured Privacy & Zero-Ads Card
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '100% Free • Offline • Zero Ads',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppConstants.incomeGreen),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'FinTrax never shows ads and never collects or shares your data. SMS detection runs locally on your phone, and backups stay in your personal Google Drive.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.38,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          _buildSectionHeader('ABOUT & CREDITS'),
          _buildSettingsCard(
            isDark: isDark,
            children: [
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
                  _smsChannel.invokeMethod('openUrl', {'url': 'https://github.com/${AppConstants.defaultGithubId}'});
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
                  _smsChannel.invokeMethod('openUrl', {'url': 'mailto:${AppConstants.defaultDeveloperEmail}?subject=FinTrax%20Feedback'});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeProvider = Provider.of<ThemeProvider>(context);
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: _selectedIndex == 0
            ? KeyedSubtree(key: const ValueKey('books'), child: _buildBooksView(isDark, themeProvider.useMaterialYou))
            : KeyedSubtree(key: const ValueKey('settings'), child: _buildSettingsView(context, isDark)),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        backgroundColor: isDark ? AppConstants.cardDark : AppConstants.cardLight,
        elevation: 0,
        onDestinationSelected: (index) {
          HapticFeedback.selectionClick();
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.book_outlined), selectedIcon: Icon(Icons.book_rounded), label: 'Books'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}
