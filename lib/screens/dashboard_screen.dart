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
    // Now correctly fetches transactions only for THIS specific book
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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.bookName, style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Add Member, Book Activity etc', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ],
        ),
        actions: const [
          Icon(Icons.person_add_alt_1_outlined, color: Color(0xFF4C44D4)),
          SizedBox(width: 16),
          Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF4C44D4)),
          SizedBox(width: 12),
          Icon(Icons.more_vert, color: Colors.black),
          SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Header Stats (Net Balance, Total In, Total Out)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Net Balance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                      '${totalBalance < 0 ? '-' : ''}$_selectedCurrency${totalBalance.abs().toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total In (+)', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text('$_selectedCurrency${totalIncome.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF328D4D), fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Out (-)', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text('$_selectedCurrency${totalExpenses.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFFD33636), fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('View Reports >', style: TextStyle(color: Color(0xFF4C44D4), fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text('Showing ${_transactions.length} entries', style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
                          Container(
                            width: double.infinity,
                            color: Colors.grey[100],
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text(dateKey, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                          ),
                          ...dayTransactions.map((tx) => _buildTransactionRow(tx)).toList(),
                        ],
                      );
                    },
                  ),
          ),
          
          // Fixed Bottom Buttons
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E7B44),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  Widget _buildTransactionRow(TransactionModel tx) {
    final isIncome = tx.type == 'Income';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.black12, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(tx.paymentMode, style: const TextStyle(color: Color(0xFF4C44D4), fontSize: 12)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${tx.currency}${tx.amount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isIncome ? const Color(0xFF328D4D) : const Color(0xFFD33636),
                ),
              ),
              const SizedBox(height: 4),
              if (tx.imagePath != null)
                Row(
                  children: const [
                    Icon(Icons.attachment, size: 12, color: Colors.grey),
                    SizedBox(width: 4),
                    Text('1 Attachment', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
