import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  String _formatDateTime(DateTime dt) {
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return "$month/$day/${dt.year}, $hour:$min $amPm";
  }

  Future<void> _exportPDF() async {
    HapticFeedback.mediumImpact();
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('${widget.bookName} Ledger', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 16),
              pw.Table.fromTextArray(
                headers: ['Date', 'Name', 'Category', 'Mode', 'Type', 'Amount'],
                data: _transactions.map((tx) => [
                  "${tx.date.month.toString().padLeft(2, '0')}/${tx.date.day.toString().padLeft(2, '0')}/${tx.date.year}",
                  tx.name,
                  tx.category.isEmpty ? '-' : tx.category,
                  tx.paymentMode,
                  tx.type,
                  tx.amount.toStringAsFixed(0),
                ]).toList(),
              ),
            ],
          );
        },
      ),
    );
    await Printing.sharePdf(bytes: await pdf.save(), filename: '${widget.bookName}_ledger.pdf');
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

  double _calculateTotal(String type) {
    return _transactions.where((t) => t.type == type).fold(0.0, (sum, item) => sum + item.amount);
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
            tooltip: 'Export PDF',
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
                                          tx.paymentMode,
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isDark ? Colors.grey[300] : Colors.grey[800]),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(_formatDateTime(tx.date), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
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
