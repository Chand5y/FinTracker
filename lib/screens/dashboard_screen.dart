import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../data/database_helper.dart';
import '../data/transaction_model.dart';
import '../core/constants.dart';
import 'add_transaction_screen.dart';

class DashboardScreen extends StatefulWidget {
  final int bookId;
  final String bookName;
  final String bookType;

  const DashboardScreen({
    Key? key,
    required this.bookId,
    required this.bookName,
    this.bookType = 'standard',
  }) : super(key: key);

  /// Generates branded FinTrax PDF bytes for any book (used for both Share & Export to Downloads)
  static Future<Uint8List> generateBookPdfBytes(int bookId, String bookName) async {
    final List<TransactionModel> transactions = await DatabaseHelper.instance.readTransactionsForBook(bookId);
    final double totalIncome = transactions.where((t) => t.type == 'Income').fold(0.0, (s, i) => s + i.amount);
    final double totalExpenses = transactions.where((t) => t.type == 'Expense').fold(0.0, (s, i) => s + i.amount);
    final double netBalance = totalIncome - totalExpenses;
    final bool isNetNegative = netBalance < 0;

    const PdfColor navyBg = PdfColor.fromInt(0xFF111C30);
    const PdfColor goldColor = PdfColor.fromInt(0xFFC5A059);
    const PdfColor greenText = PdfColor.fromInt(0xFF16A34A);
    const PdfColor greenBg = PdfColor.fromInt(0xFFECFDF5);
    const PdfColor redText = PdfColor.fromInt(0xFFDC2626);
    const PdfColor redBg = PdfColor.fromInt(0xFFFEF2F2);
    const PdfColor slateBorder = PdfColor.fromInt(0xFFE2E8F0);
    const PdfColor rowAltBg = PdfColor.fromInt(0xFFF8FAFC);
    const PdfColor mutedText = PdfColor.fromInt(0xFF64748B);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context ctx) {
          return pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            margin: const pw.EdgeInsets.only(bottom: 20),
            decoration: pw.BoxDecoration(
              color: navyBg,
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Text(
                          'Fin',
                          style: pw.TextStyle(color: PdfColors.white, fontSize: 24, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          'Trax',
                          style: const pw.TextStyle(color: goldColor, fontSize: 24),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      AppConstants.appTagline,
                      style: pw.TextStyle(color: goldColor, fontSize: 6.2, fontWeight: pw.FontWeight.bold, letterSpacing: 1.1),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      bookName,
                      style: pw.TextStyle(color: PdfColors.white, fontSize: 16, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Generated: ${AppConstants.formatOrdinalDateTime(DateTime.now())}',
                      style: const pw.TextStyle(color: PdfColor.fromInt(0xFFCBD5E1), fontSize: 9),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
        footer: (pw.Context ctx) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 12),
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: slateBorder, width: 0.8)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('FinTrax • Personal Financial Statement', style: const pw.TextStyle(color: mutedText, fontSize: 9)),
                pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(color: mutedText, fontSize: 9)),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return [
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: greenBg,
                      borderRadius: pw.BorderRadius.circular(10),
                      border: pw.Border.all(color: greenText, width: 0.8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('TOTAL CASH IN (+)', style: pw.TextStyle(color: greenText, fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 6),
                        pw.Text('+ Rs. ${totalIncome.toStringAsFixed(0)}', style: pw.TextStyle(color: greenText, fontSize: 15, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: redBg,
                      borderRadius: pw.BorderRadius.circular(10),
                      border: pw.Border.all(color: redText, width: 0.8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('TOTAL CASH OUT (-)', style: pw.TextStyle(color: redText, fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 6),
                        pw.Text('- Rs. ${totalExpenses.toStringAsFixed(0)}', style: pw.TextStyle(color: redText, fontSize: 15, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: isNetNegative ? redBg : greenBg,
                      borderRadius: pw.BorderRadius.circular(10),
                      border: pw.Border.all(color: isNetNegative ? redText : greenText, width: 1.2),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('NET BALANCE', style: pw.TextStyle(color: navyBg, fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          '${isNetNegative ? '-' : '+'} Rs. ${netBalance.abs().toStringAsFixed(0)}',
                          style: pw.TextStyle(
                            color: isNetNegative ? redText : greenText,
                            fontSize: 15,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Transaction History (${transactions.length} ${transactions.length == 1 ? 'Entry' : 'Entries'})',
              style: pw.TextStyle(color: navyBg, fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: slateBorder, width: 0.6),
              columnWidths: {
                0: const pw.FlexColumnWidth(2.3),
                1: const pw.FlexColumnWidth(2.6),
                2: const pw.FlexColumnWidth(1.8),
                3: const pw.FlexColumnWidth(1.4),
                4: const pw.FlexColumnWidth(1.8),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: navyBg),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Date & Time', style: pw.TextStyle(color: goldColor, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Remark / Particulars', style: pw.TextStyle(color: goldColor, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Category', style: pw.TextStyle(color: goldColor, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Method', style: pw.TextStyle(color: goldColor, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Amount', textAlign: pw.TextAlign.right, style: pw.TextStyle(color: goldColor, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    ),
                  ],
                ),
                ...List.generate(transactions.length, (idx) {
                  final tx = transactions[idx];
                  final bool isIncome = tx.type == 'Income';
                  final String resolvedTitle = FinTraxBrandHelper.resolveMerchantTitle(tx.name, tx.effectiveSmsText);
                  final String resolvedMode = FinTraxBrandHelper.detectPaymentMethod(
                    currentMode: tx.paymentMode,
                    smsBody: tx.effectiveSmsText,
                    sender: tx.name,
                  );
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: idx.isEven ? PdfColors.white : rowAltBg),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(AppConstants.formatOrdinalDateTime(tx.date), style: const pw.TextStyle(fontSize: 8.5, color: mutedText)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(resolvedTitle, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: navyBg)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(tx.category.isEmpty ? '-' : tx.category, style: const pw.TextStyle(fontSize: 8.5, color: mutedText)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(resolvedMode, style: const pw.TextStyle(fontSize: 8.5, color: navyBg)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          '${isIncome ? '+' : '-'} Rs. ${tx.amount.toStringAsFixed(0)}',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                            fontSize: 9.5,
                            fontWeight: pw.FontWeight.bold,
                            color: isIncome ? greenText : redText,
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<TransactionModel> _transactions = [];
  bool _isLoading = true;
  late String _bookType;
  String _contactPhone = '';
  Uint8List? _contactPhotoBytes;

  @override
  void initState() {
    super.initState();
    _bookType = widget.bookType;
    FinTraxBrandHelper.dataRefreshNotifier.addListener(_refreshTransactions);
    _refreshTransactions();
  }

  @override
  void dispose() {
    FinTraxBrandHelper.dataRefreshNotifier.removeListener(_refreshTransactions);
    super.dispose();
  }

  Future<void> _refreshTransactions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await DatabaseHelper.instance.readTransactionsForBook(widget.bookId);
      final books = await DatabaseHelper.instance.getBooksWithBalances();
      final match = books.where((b) => (b['id'] as int) == widget.bookId).toList();
      final contactInfo = await FinTraxBrandHelper.getBookContact(widget.bookId);
      final String photoB64 = contactInfo['photoBase64'] ?? '';
      Uint8List? decodedPhoto;
      if (photoB64.isNotEmpty) {
        try {
          decodedPhoto = base64Decode(photoB64);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _transactions = data;
          if (match.isNotEmpty) {
            _bookType = match.first['bookType']?.toString() ?? widget.bookType;
          }
          _contactPhone = contactInfo['phone'] ?? '';
          _contactPhotoBytes = decodedPhoto;
        });
      }
    } catch (e) {
      debugPrint('Error loading transactions: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  double _calculateTotal(String type) {
    return _transactions.where((t) => t.type == type).fold(0.0, (sum, item) => sum + item.amount);
  }

  Future<void> _exportPDF() async {
    HapticFeedback.mediumImpact();
    final bytes = await DashboardScreen.generateBookPdfBytes(widget.bookId, widget.bookName);
    await Printing.sharePdf(bytes: bytes, filename: '${widget.bookName}_FinTrax_Statement.pdf');
  }

  Future<void> _confirmAndDeleteTransactionWithUndo(TransactionModel tx) async {
    HapticFeedback.mediumImpact();
    final displayTitle = FinTraxBrandHelper.resolveMerchantTitle(tx.name, tx.effectiveSmsText);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Do you want to delete?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: Text(
          'Delete "$displayTitle" from this book?',
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
      final backupMap = tx.toMap();
      await DatabaseHelper.instance.deleteTransaction(tx.id!, widget.bookId);
      await _refreshTransactions();
      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('Deleted "$displayTitle"'),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: AppConstants.goldAccent,
            onPressed: () async {
              final db = await DatabaseHelper.instance.database;
              await db.insert('transactions', backupMap);
              FinTraxBrandHelper.dataRefreshNotifier.value++;
            },
          ),
        ),
      );
    }
  }

  Future<void> _openCopyOrMoveBookSelector(TransactionModel tx, {required bool isMove}) async {
    final allBooks = await DatabaseHelper.instance.getBooksWithBalances();
    final otherBooks = allBooks.where((b) => (b['id'] as int) != widget.bookId).toList();

    if (!mounted) return;
    if (otherBooks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other books found. Create another book first!')),
      );
      return;
    }

    if (isMove) {
      final int? targetBookId = await showModalBottomSheet<int>(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Text('Move Entry To Book', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Select the book where "${tx.name}" should be moved:',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[500]),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: otherBooks.length,
                    itemBuilder: (_, i) {
                      final b = otherBooks[i];
                      final bool isLending = (b['bookType']?.toString() ?? 'standard') == 'lending';
                      return ListTile(
                        leading: Icon(
                          isLending ? Icons.handshake_rounded : Icons.book_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(b['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                        onTap: () => Navigator.pop(ctx, b['id'] as int),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (targetBookId != null && mounted) {
        HapticFeedback.mediumImpact();
        await DatabaseHelper.instance.moveTransactionToBook(tx, targetBookId);
        final targetName = otherBooks.firstWhere((b) => (b['id'] as int) == targetBookId)['name'].toString();
        await _refreshTransactions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Moved "${tx.name}" to $targetName'),
              backgroundColor: AppConstants.incomeGreen,
            ),
          );
        }
      }
    } else {
      final selectedIds = <int>{};
      final bool? confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheetState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    child: Text('Copy Entry To Book(s)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Select one or more books to copy "${tx.name}" into:',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey[500]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: otherBooks.length,
                      itemBuilder: (_, i) {
                        final b = otherBooks[i];
                        final int bId = b['id'] as int;
                        final bool isLending = (b['bookType']?.toString() ?? 'standard') == 'lending';
                        final bool isChecked = selectedIds.contains(bId);
                        return CheckboxListTile(
                          secondary: Icon(
                            isLending ? Icons.handshake_rounded : Icons.book_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(b['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                          value: isChecked,
                          onChanged: (v) {
                            HapticFeedback.selectionClick();
                            setSheetState(() {
                              if (v == true) {
                                selectedIds.add(bId);
                              } else {
                                selectedIds.remove(bId);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: selectedIds.isEmpty ? null : () => Navigator.pop(ctx, true),
                        child: Text(
                          selectedIds.isEmpty
                              ? 'Select Book(s)'
                              : 'Copy to ${selectedIds.length} Book${selectedIds.length == 1 ? '' : 's'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      if (confirmed == true && selectedIds.isNotEmpty && mounted) {
        HapticFeedback.mediumImpact();
        final count = await DatabaseHelper.instance.copyTransactionToBooks(tx, selectedIds.toList());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Copied "${tx.name}" to $count book${count == 1 ? '' : 's'}!'),
              backgroundColor: AppConstants.incomeGreen,
            ),
          );
        }
      }
    }
  }

  void _showTransactionOptions(TransactionModel tx) {
    HapticFeedback.mediumImpact();
    final displayTitle = FinTraxBrandHelper.resolveMerchantTitle(tx.name, tx.effectiveSmsText);

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
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Text(
                  displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit Entry'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddTransactionScreen(bookId: widget.bookId, type: tx.type, existingTransaction: tx),
                    ),
                  ).then((_) => _refreshTransactions());
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy to Book...'),
                subtitle: const Text('Duplicate this entry into another book', style: TextStyle(fontSize: 11.5)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openCopyOrMoveBookSelector(tx, isMove: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outlined),
                title: const Text('Move to Book...'),
                subtitle: const Text('Transfer this entry out of this book to another book', style: TextStyle(fontSize: 11.5)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openCopyOrMoveBookSelector(tx, isMove: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppConstants.expenseRed),
                title: const Text('Delete Entry', style: TextStyle(color: AppConstants.expenseRed)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmAndDeleteTransactionWithUndo(tx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isLending = _bookType == 'lending';
    final totalIncome = _calculateTotal('Income');
    final totalExpenses = _calculateTotal('Expense');
    final totalBalance = totalIncome - totalExpenses;
    final bool isNegative = totalBalance < 0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.bookName),
            if (isLending)
              const Text(
                'LENDING LEDGER',
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppConstants.goldAccent, letterSpacing: 1.0),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Share PDF Statement',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _exportPDF,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isLending
                    ? AppConstants.goldAccent.withOpacity(0.45)
                    : (isDark ? AppConstants.borderDark : AppConstants.borderLight),
              ),
            ),
              child: Column(
              children: [
                if (isLending && (_contactPhone.isNotEmpty || _contactPhotoBytes != null)) ...[
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 21,
                        backgroundColor: AppConstants.goldAccent.withOpacity(0.18),
                        backgroundImage: _contactPhotoBytes != null ? MemoryImage(_contactPhotoBytes!) : null,
                        child: _contactPhotoBytes == null
                            ? const Icon(Icons.person_rounded, color: AppConstants.goldAccent, size: 22)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.bookName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                            ),
                            if (_contactPhone.isNotEmpty)
                              Text(
                                _contactPhone,
                                style: TextStyle(fontSize: 12.5, color: Colors.grey[500], fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isLending ? 'Net Pending / Balance' : 'Net Balance',

                      style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[700], fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      '${isNegative ? '-' : ''}${AppConstants.defaultCurrency}${totalBalance.abs().toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isLending ? 'Total Returned / Received (+)' : 'Total In (+)',
                      style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 13),
                    ),
                    Text(
                      '${AppConstants.defaultCurrency}${totalIncome.toStringAsFixed(0)}',
                      style: const TextStyle(color: AppConstants.incomeGreen, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isLending ? 'Total Given / Lent (-)' : 'Total Out (-)',
                      style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 13),
                    ),
                    Text(
                      '${AppConstants.defaultCurrency}${totalExpenses.toStringAsFixed(0)}',
                      style: const TextStyle(color: AppConstants.expenseRed, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Showing ${_transactions.length} ${_transactions.length == 1 ? 'entry' : 'entries'} • Long-press for options',
              style: TextStyle(color: Colors.grey[500], fontSize: 11.5, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: _transactions.length,
                    itemBuilder: (context, index) {
                      final tx = _transactions[index];
                      final bool hasImage = tx.imagePath.isNotEmpty;
                      final bool hasSms = tx.effectiveSmsText.isNotEmpty;
                      final bool hasNote = tx.hasUserNote;

                      final String displayTitle = FinTraxBrandHelper.resolveMerchantTitle(tx.name, tx.effectiveSmsText);
                      final String effectiveCategory = FinTraxBrandHelper.detectCategory(
                            displayTitle,
                            smsBody: tx.effectiveSmsText,
                            currentCategory: tx.category,
                          ) ??
                          tx.category;
                      final bool isInvestment = effectiveCategory.toLowerCase() == 'investment';

                      final String displayPaymentMode = FinTraxBrandHelper.detectPaymentMethod(
                        currentMode: tx.paymentMode,
                        smsBody: tx.effectiveSmsText,
                        sender: tx.name,
                      );
                      final String? bankIconAsset = FinTraxBrandHelper.getPaymentIconAsset(
                        displayPaymentMode,
                        smsBody: tx.effectiveSmsText,
                        sender: tx.name,
                      );
                      final String? merchantIconAsset = FinTraxBrandHelper.getMerchantIconAsset(
                        displayTitle,
                        smsBody: tx.effectiveSmsText,
                      );

                      final Color borderColor = isInvestment
                          ? AppConstants.incomeGreen.withOpacity(isDark ? 0.65 : 0.55)
                          : (isDark ? AppConstants.borderDark : AppConstants.borderLight);

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                        child: Material(
                          color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: borderColor, width: isInvestment ? 1.35 : 1.0),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AddTransactionScreen(bookId: widget.bookId, type: tx.type, existingTransaction: tx),
                                ),
                              ).then((_) => _refreshTransactions());
                            },
                            onLongPress: () => _showTransactionOptions(tx),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                                                   Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          displayTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${tx.type == 'Income' ? '+' : '-'}${AppConstants.defaultCurrency}${tx.amount.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                          color: tx.type == 'Income' ? AppConstants.incomeGreen : AppConstants.expenseRed,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (effectiveCategory.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      isInvestment ? '📈 Investment' : effectiveCategory,
                                      style: TextStyle(
                                        color: isInvestment ? AppConstants.incomeGreen : Colors.grey[500],
                                        fontWeight: isInvestment ? FontWeight.w700 : FontWeight.w500,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: bankIconAsset != null ? 5 : 8,
                                          vertical: 3.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: bankIconAsset != null
                                            ? FinTraxBrandHelper.buildIconBadge(
                                                assetPath: bankIconAsset,
                                                fallbackEmoji: FinTraxBrandHelper.getPaymentEmoji(displayPaymentMode),
                                                size: 18,
                                                borderRadius: 4,
                                              )
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    FinTraxBrandHelper.getPaymentEmoji(displayPaymentMode),
                                                    style: const TextStyle(fontSize: 11),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    displayPaymentMode,
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.w700,
                                                      color: isDark ? Colors.grey[300] : Colors.grey[800],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                      const SizedBox(width: 8),
                                      Text(AppConstants.formatOrdinalDateTime(tx.date), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                      const Spacer(),
                                      if (hasNote)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: Tooltip(
                                            message: 'Has Note',
                                            child: Icon(
                                              Icons.sticky_note_2_outlined,
                                              size: 15,
                                              color: Theme.of(context).colorScheme.primary.withOpacity(0.85),
                                            ),
                                          ),
                                        ),
                                      if (hasSms)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: Tooltip(
                                            message: 'Bank SMS Attached',
                                            child: Icon(
                                              Icons.sms_outlined,
                                              size: 15,
                                              color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                                            ),
                                          ),
                                        ),
                                      if (hasImage) Icon(Icons.attachment_rounded, size: 16, color: Colors.grey[500]),
                                    ],
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
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: isDark ? AppConstants.bgDark : AppConstants.cardLight,
                border: Border(top: BorderSide(color: isDark ? AppConstants.borderDark : AppConstants.borderLight)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppConstants.incomeGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => AddTransactionScreen(bookId: widget.bookId, type: 'Income')),
                        ).then((_) => _refreshTransactions());
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: Text(
                        isLending ? 'Received (+)' : 'Cash In',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppConstants.expenseRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => AddTransactionScreen(bookId: widget.bookId, type: 'Expense')),
                        ).then((_) => _refreshTransactions());
                      },
                      icon: const Icon(Icons.remove_rounded),
                      label: Text(
                        isLending ? 'Lent / Given (-)' : 'Cash Out',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
