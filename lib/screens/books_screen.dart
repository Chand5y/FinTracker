import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data/database_helper.dart';
import '../data/book_model.dart';
import '../data/transaction_model.dart';
import '../core/constants.dart';
import '../theme/theme_provider.dart';
import 'dashboard_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _refreshBooks();
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

  String _formatDateStrict(String? isoString) {
    final DateTime date = DateTime.tryParse(isoString ?? '') ?? DateTime.now();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return "$month/$day/${date.year}";
  }

  void _showAddBookDialog() {
    HapticFeedback.lightImpact();
    final TextEditingController nameController = TextEditingController();
    showDialog(
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
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final text = nameController.text.trim();
              if (text.isEmpty) return;
              final now = DateTime.now();
              final result = await DatabaseHelper.instance.insertBook(
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
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _refreshBooks();
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
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2))),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Detected Bank SMS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('${_smsSuggestions.length} pending', style: const TextStyle(color: Colors.grey, fontSize: 13)),
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
                                    Text('${sms.paymentMode} • ${_formatDateStrict(sms.date.toIso8601String())}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
                                      onPressed: () => _promptBookForSms(sms, () {
                                        setSheetState(() => _smsSuggestions.removeAt(idx));
                                      }),
                                      child: const Text('Add to Book', style: TextStyle(fontSize: 12)),
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

  Future<void> _promptBookForSms(ParsedSmsTransaction sms, VoidCallback onAdded) async {
    if (_booksData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please create a Book first before adding SMS entries.')));
      return;
    }
    int? chosenBookId = _booksData.length == 1 ? _booksData.first['id'] as int : null;

    if (chosenBookId == null) {
      chosenBookId = await showDialog<int>(
        context: context,
        builder: (dCtx) => SimpleDialog(
          title: const Text('Select Book'),
          children: _booksData.map((b) {
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(dCtx, b['id'] as int),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(b['name'].toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ),
            );
          }).toList(),
        ),
      );
    }

    if (chosenBookId != null) {
      HapticFeedback.mediumImpact();
      await DatabaseHelper.instance.insertTransaction(
        TransactionModel(
          bookId: chosenBookId,
          type: sms.type,
          amount: sms.amount,
          name: sms.merchant,
          category: '',
          notes: sms.body,
          date: sms.date,
          currency: AppConstants.defaultCurrency,
          paymentMode: sms.paymentMode,
        ),
      );
      await DatabaseHelper.instance.markSmsHandled(sms.smsId, 'added');
      onAdded();
      _refreshBooks();
    }
  }

  // Matches the exact logo lockup: Bold "Fin" + Thin Gold "Track", with tiny tagline matching the exact width
  Widget _buildBrandHeader(bool isDark, bool useMaterialYou) {
    final Color finColor = isDark ? Colors.white : const Color(0xFF0E1726);
    final Color trackColor = useMaterialYou
        ? Theme.of(context).colorScheme.primary
        : (isDark ? AppConstants.goldAccent : AppConstants.goldDarkText);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
                fontWeight: FontWeight.w700,
                fontSize: 26,
                letterSpacing: 0.2,
                height: 1.0,
              ),
            ),
            Text(
              'Track',
              style: TextStyle(
                color: trackColor,
                fontWeight: FontWeight.w300,
                fontSize: 26,
                letterSpacing: 0.5,
                height: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          'YOUR PERSONAL FINANCE TRACKER',
          style: TextStyle(
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            fontSize: 5.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.65,
            height: 1.0,
          ),
        ),
      ],
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
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: borderColor, width: 1),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
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
                                      // Icon styled with Midnight Navy & Champagne Gold like the App Icon
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
                                      // Fixed 3-line structure: Created at top, Book Name in middle, Updated at bottom
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Created ${_formatDateStrict(book['createdAt']?.toString())}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w500,
                                                color: isDark ? Colors.grey[500] : Colors.grey[600],
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              book['name'].toString(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              'Updated ${_formatDateStrict(book['updatedAt']?.toString())}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w500,
                                                color: isDark ? Colors.grey[500] : Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        '${isNegative ? '-' : ''}${AppConstants.defaultCurrency}${netBalance.abs().toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                          color: isNegative ? AppConstants.expenseRed : AppConstants.incomeGreen,
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
        onPressed: _showAddBookDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Book', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children, required bool isDark}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _buildSettingsView(BuildContext context, bool isDark) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
            child: Text('APPEARANCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: Colors.grey[500])),
          ),
          _buildSettingsCard(
            isDark: isDark,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Theme Mode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 12),
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
                secondary: Icon(Icons.color_lens_outlined, color: scheme.primary),
                title: const Text('Material You Colors', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                subtitle: const Text('Override signature Gold theme with wallpaper colors', style: TextStyle(fontSize: 12)),
                value: themeProvider.useMaterialYou,
                onChanged: (val) {
                  HapticFeedback.lightImpact();
                  themeProvider.toggleMaterialYou(val);
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            child: Text('AUTOMATION & PRIVACY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: Colors.grey[500])),
          ),
          _buildSettingsCard(
            isDark: isDark,
            children: [
              SwitchListTile(
                secondary: Icon(Icons.sms_outlined, color: scheme.primary),
                title: const Text('Smart SMS Auto-Track', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                subtitle: const Text('Detect bank & UPI SMS locally on device to suggest entries (100% offline)', style: TextStyle(fontSize: 12)),
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
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            child: Text('CLOUD BACKUP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: Colors.grey[500])),
          ),
          _buildSettingsCard(
            isDark: isDark,
            children: [
              ListTile(
                leading: Icon(Icons.cloud_upload_outlined, color: scheme.primary),
                title: const Text('Google Drive Backup', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                onTap: () {
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Google Drive OAuth setup ready for configuration.')));
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.cloud_download_outlined, color: scheme.primary),
                title: const Text('Restore from Drive', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                onTap: () {
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Google Drive OAuth setup ready for configuration.')));
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
