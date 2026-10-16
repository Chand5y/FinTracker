import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
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
  static const String _driveScope = 'https://www.googleapis.com/auth/drive.appdata';
  static const String _cloudFileName = 'fintrax_cloud_backup.json';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>[_driveScope],
  );

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

    final books = await DatabaseHelper.instance.getBooksWithBalances();
    if (books.isEmpty) return;

    final now = DateTime.now();
    final String todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (themeProvider.lastAutoBackupDay == todayKey) return;

    try {
      final GoogleSignInAccount? account = await _googleSignIn.signInSilently();
      if (account == null) return;
      final Map<String, String> authHeaders = await account.authHeaders;
      final String jsonPayload = await DatabaseHelper.instance.exportDatabaseJson();
      final String? fileId = await _uploadJsonToGoogleDrive(authHeaders, jsonPayload);
      if (fileId != null && fileId.isNotEmpty) {
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
The error **`UnimplementedError: canAccessScopes() has not been implemented`** happened because in Flutter's `google_sign_in` package, the `canAccessScopes()` check is only built for Web browsers and throws an error when called on Android. 

On Android, because `_driveScope` is already passed into `GoogleSignIn(scopes: [_driveScope])`, Google Play Services automatically requests the Google Drive permission right inside `signIn()` when you tap **Continue**.

---

### How to Fix It (Quick Edit in `lib/screens/books_screen.dart`)

Open **`lib/screens/books_screen.dart`** in your GitHub repository, press **Edit**, and scroll down to the **`_authenticateGoogleDrive`** function (around line 545).

**1. Find and delete this `canAccessScopes` block inside `_authenticateGoogleDrive`:**
```dart
      final bool hasDrivePermission = await _googleSignIn.canAccessScopes([_driveScope]);
      if (!hasDrivePermission) {
        final bool granted = await _googleSignIn.requestScopes([_driveScope]);
        if (!granted) {
          if (mounted) {
            _showCloudErrorDialog(
              'Drive Permission Required',
              'Please allow FinTrax to access its private Google Drive folder so your books can be backed up to the cloud.',
            );
          }
          return null;
        }
      }
