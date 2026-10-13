import 'package:flutter/material.dart';
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
  String _selectedCurrency = AppConstants.defaultCurrency;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshTransactions();
  }

  Future<void> _refreshTransactions() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.readTransactionsForBook(widget.bookId);
    setState(() {
      _transactions = data;
      _isLoading = false;
    });
  }

  double _calculateTotal(String type) {
    return _transactions
        .where((t) => t.type == type && t.currency == _selectedCurrency)
        .fold(0.0, (sum, item) => sum + item.amount);
  }

  String _formatDateStrict(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return "$month/$day/${date.year}";
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final totalIncome = _calculateTotal('Income');
    final totalExpenses = _calculateTotal('Expense');
    final totalBalance = totalIncome - totalExpenses;

    Map<String, List<TransactionModel>> groupedTransactions = {};
    for (var tx in _transactions.where((t) => t.currency == _selectedCurrency)) {
      String dateStr = _formatDateStrict(tx.date);
      if (!groupedTransactions.containsKey(dateStr)) {
        groupedTransactions[dateStr] = [];
      }
      groupedTransactions[dateStr]!.add(tx);
    }

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.bookName, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 20, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Header Stats Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Net Balance', style: TextStyle(color: isDark ? Colors.grey[300] : Colors.grey[800], fontSize: 16)),
                    Text(
                      '${totalBalance < 0 ? '-' : ''}$_selectedCurrency${totalBalance.abs().toStringAsFixed(0)}',
                      style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total In (+)', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14)),
                    Text('$_selectedCurrency${totalIncome.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF328D4D), fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Out (-)', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14)),
                    Text('$_selectedCurrency${totalExpenses.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFFD33636), fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ],
            ),
          ),
          
          // Ledger List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: groupedTransactions.length,
                    itemBuilder: (context, index) {
                      String dateKey = groupedTransactions.keys.elementAt(index);
                      List<TransactionModel> dayTransactions = groupedTransactions[dateKey]!;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 24, top: 8, bottom: 4),
                            child: Text(dateKey, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: dayTransactions.map((tx) => _buildTransactionRow(tx, isDark, tx == dayTransactions.last)).toList(),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          
          // Fixed Bottom Buttons
          Container(
            color: isDark ? const Color(0xFF121212) : Colors.white,
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

  Widget _buildTransactionRow(TransactionModel tx, bool isDark, bool isLast) {
    final isIncome = tx.type == 'Income';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[200]!, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                const SizedBox(height: 6),
                Text(tx.paymentMode, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[500], fontSize: 13)),
              ],
            ),
          ),
          Text(
            '${tx.currency}${tx.amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isIncome ? const Color(0xFF328D4D) : const Color(0xFFD33636),
            ),
          ),
        ],
      ),
    );
  }
}
