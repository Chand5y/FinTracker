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
  void initState() { super.initState(); _refreshTransactions(); }

  Future<void> _refreshTransactions() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.readTransactionsForBook(widget.bookId);
    setState(() { _transactions = data; _isLoading = false; });
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
              pw.Text('${widget.bookName} Ledger', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Table.fromTextArray(
                headers: ['Date', 'Name', 'Category', 'Mode', 'Type', 'Amount'],
                data: _transactions.map((tx) => [
                  "${tx.date.month}/${tx.date.day}/${tx.date.year}", tx.name, tx.category, tx.paymentMode, tx.type, tx.amount.toString()
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
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Transaction'),
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
    
    // Dynamic Header Colors
    Color headerColor = isDark 
        ? (isNegative ? const Color(0xFF311313) : const Color(0xFF132D1A))
        : (isNegative ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9));

    return Scaffold(
      backgroundColor: isDark ? AppConstants.backgroundDark : const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text(widget.bookName),
        actions: [
          IconButton(icon: Icon(Icons.picture_as_pdf, color: isDark ? Colors.white : Colors.black), onPressed: _exportPDF),
        ],
      ),
      body: Column(
        children: [
          // Dynamic Header Stats Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: headerColor, borderRadius: BorderRadius.circular(20)),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Net Balance', style: TextStyle(color: isDark ? Colors.grey[300] : Colors.grey[800], fontSize: 16)),
                    Text(
                      '${isNegative ? '-' : ''}${AppConstants.defaultCurrency}${totalBalance.abs().toStringAsFixed(0)}',
                      style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total In (+)', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14)),
                    Text('${AppConstants.defaultCurrency}${totalIncome.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF328D4D), fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Out (-)', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14)),
                    Text('${AppConstants.defaultCurrency}${totalExpenses.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFFD33636), fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ],
            ),
          ),
          
          Expanded(
            child: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
              itemCount: _transactions.length,
              itemBuilder: (context, index) {
                final tx = _transactions[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Material(
                    color: isDark ? AppConstants.surfaceDark : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(context, MaterialPageRoute(builder: (_) => AddTransactionScreen(bookId: widget.bookId, type: tx.type, existingTransaction: tx))).then((_) => _refreshTransactions());
                      },
                      onLongPress: () => _showTransactionOptions(tx),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tx.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                                Text(tx.category.isEmpty ? 'No Category' : tx.category, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                              ],
                            ),
                            Text('${AppConstants.defaultCurrency}${tx.amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: tx.type == 'Income' ? const Color(0xFF328D4D) : const Color(0xFFD33636))),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Fixed Bottom Buttons
          Container(
            color: isDark ? AppConstants.backgroundDark : Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E7B44),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => AddTransactionScreen(bookId: widget.bookId, type: 'Income'))).then((_) => _refreshTransactions());
                    },
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Cash In', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFCB3C3C),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => AddTransactionScreen(bookId: widget.bookId, type: 'Expense'))).then((_) => _refreshTransactions());
                    },
                    icon: const Icon(Icons.remove, color: Colors.white),
                    label: const Text('Cash Out', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
