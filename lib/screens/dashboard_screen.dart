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
  const DashboardScreen({Key? key, required this.bookId, required this.bookName}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<TransactionModel> _transactions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshTransactions();
  }

  Future<void> _refreshTransactions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await DatabaseHelper.instance.readTransactionsForBook(widget.bookId);
      if (mounted) {
        setState(() => _transactions = data);
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
    final pdf = pw.Document();

    final double totalIncome = _calculateTotal('Income');
    final double totalExpenses = _calculateTotal('Expense');
    final double netBalance = totalIncome - totalExpenses;
    final bool isNetNegative = netBalance < 0;

    // Signature PDF Palette
    const PdfColor navyBg = PdfColor.fromInt(0xFF111C30);
    const PdfColor goldColor = PdfColor.fromInt(0xFFC5A059);
    const PdfColor greenText = PdfColor.fromInt(0xFF16A34A);
    const PdfColor greenBg = PdfColor.fromInt(0xFFECFDF5);
    const PdfColor redText = PdfColor.fromInt(0xFFDC2626);
    const PdfColor redBg = PdfColor.fromInt(0xFFFEF2F2);
    const PdfColor slateBorder = PdfColor.fromInt(0xFFE2E8F0);
    const PdfColor rowAltBg = PdfColor.fromInt(0xFFF8FAFC);
    const PdfColor mutedText = PdfColor.fromInt(0xFF64748B);

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
                          'Track',
                          style: const pw.TextStyle(color: goldColor, fontSize: 24),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'FINANCE TRACKER',
                      style: pw.TextStyle(color: goldColor, fontSize: 7, fontWeight: pw.FontWeight.bold, letterSpacing: 2),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      widget.bookName,
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
                pw.Text('FinTrack • Personal Finance Statement', style: const pw.TextStyle(color: mutedText, fontSize: 9)),
                pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(color: mutedText, fontSize: 9)),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return [
            // 3 Executive Summary Cards (Total In, Total Out, Net Balance)
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
              'Transaction History (${_transactions.length} ${_transactions.length == 1 ? 'Entry' : 'Entries'})',
              style: pw.TextStyle(color: navyBg, fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),

            // Color-Coded Ledger Table
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
                // Table Header
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
                // Table Data Rows
                ...List.generate(_transactions.length, (idx) {
                  final tx = _transactions[idx];
                  final bool isIncome = tx.type == 'Income';
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: idx.isEven ? PdfColors.white : rowAltBg),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(AppConstants.formatOrdinalDateTime(tx.date), style: const pw.TextStyle(fontSize: 8.5, color: mutedText)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(tx.name, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: navyBg)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(tx.category.isEmpty ? '-' : tx.category, style: const pw.TextStyle(fontSize: 8.5, color: mutedText)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(tx.paymentMode, style: const pw.TextStyle(fontSize: 8.5, color: navyBg)),
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

    await Printing.sharePdf(bytes: await pdf.save(), filename: '${widget.bookName}_Statement.pdf');
  }

  void _showTransactionOptions(TransactionModel tx) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Entry'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddTransactionScreen(bookId: widget.bookId, type: tx.type, existingTransaction: tx)),
                ).then((_) => _refreshTransactions());
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppConstants.expenseRed),
              title: const Text('Delete Entry', style: TextStyle(color: AppConstants.expenseRed)),
              onTap: () async {
                HapticFeedback.heavyImpact();
                await DatabaseHelper.instance.deleteTransaction(tx.id!, widget.bookId);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
                _refreshTransactions();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalIncome = _calculateTotal('Income');
    final totalExpenses = _calculateTotal('Expense');
    final totalBalance = totalIncome - totalExpenses;
    final bool isNegative = totalBalance < 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookName),
        actions: [
          IconButton(
            tooltip: 'Export PDF Statement',
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
              border: Border.all(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Net Balance', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[700], fontSize: 15, fontWeight: FontWeight.w500)),
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
                    Text('Total In (+)', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 13)),
                    Text('${AppConstants.defaultCurrency}${totalIncome.toStringAsFixed(0)}', style: const TextStyle(color: AppConstants.incomeGreen, fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Out (-)', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 13)),
                    Text('${AppConstants.defaultCurrency}${totalExpenses.toStringAsFixed(0)}', style: const TextStyle(color: AppConstants.expenseRed, fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Showing ${_transactions.length} ${_transactions.length == 1 ? 'entry' : 'entries'}',
              style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w500),
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

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                        child: Material(
                          color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
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
                                        child: Text(tx.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                      ),
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
                                  if (tx.category.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(tx.category, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${AppConstants.paymentModeEmojis[tx.paymentMode] ?? '💳'} ${tx.paymentMode}',
                                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: isDark ? Colors.grey[300] : Colors.grey[800]),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(AppConstants.formatOrdinalDateTime(tx.date), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                      const Spacer(),
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
                      label: const Text('Cash In', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
                      label: const Text('Cash Out', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
