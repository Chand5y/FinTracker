import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../data/database_helper.dart';
import '../data/transaction_model.dart';
import '../theme/theme_provider.dart';
import '../core/constants.dart';
import 'add_transaction_screen.dart';


class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

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
    final data = await DatabaseHelper.instance.readAllTransactions();
    setState(() {
      _transactions = data;
      _isLoading = false;
    });
  }

  // Calculates totals based on the currently selected currency in the top dropdown
  double _calculateTotal(String type) {
    return _transactions
        .where((t) => t.type == type && t.currency == _selectedCurrency)
        .fold(0.0, (sum, item) => sum + item.amount);
  }

  String _formatDate(DateTime date) {
    // Strictly formatted as MM/DD/YYYY
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return "$month/$day/${date.year}";
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final totalExpenses = _calculateTotal('Expense');
    final totalGiven = _calculateTotal('Given');
    final totalReceived = _calculateTotal('Received');
    final totalBalance = totalReceived - totalExpenses - totalGiven;

    return Scaffold(
      appBar: AppBar(
        title: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedCurrency,
            dropdownColor: Theme.of(context).scaffoldBackgroundColor,
            style: Theme.of(context).appBarTheme.titleTextStyle,
            icon: Icon(Icons.keyboard_arrow_down, color: Theme.of(context).iconTheme.color),
            items: AppConstants.availableCurrencies.map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text('Currency: $value'),
              );
            }).toList(),
            onChanged: (newValue) {
              if (newValue != null) {
                setState(() => _selectedCurrency = newValue);
              }
            },
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: 'Toggle Theme',
            onPressed: () => themeProvider.toggleTheme(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshTransactions,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildGlassCard(
                    context: context,
                    title: 'Total Balance',
                    amount: totalBalance,
                    isDark: isDark,
                    mainColor: Colors.blueAccent,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildGlassCard(
                          context: context,
                          title: 'Expenses',
                          amount: totalExpenses,
                          isDark: isDark,
                          mainColor: Colors.redAccent,
                          height: 120,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildGlassCard(
                          context: context,
                          title: 'Money Given',
                          amount: totalGiven,
                          isDark: isDark,
                          mainColor: Colors.orangeAccent,
                          height: 120,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Recent Transactions',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ..._transactions
                      .where((t) => t.currency == _selectedCurrency)
                      .map((tx) => _buildTransactionTile(tx, isDark))
                      .toList(),
                  if (_transactions.where((t) => t.currency == _selectedCurrency).isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(child: Text('No transactions for this currency yet.')),
                    )
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: isDark ? Colors.white : Colors.black,
        foregroundColor: isDark ? Colors.black : Colors.white,
        elevation: 4,
        onPressed: () async {
  await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddTransactionScreen()));
  _refreshTransactions();
},
        
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildGlassCard({
    required BuildContext context,
    required String title,
    required double amount,
    required bool isDark,
    required Color mainColor,
    double height = 150,
  }) {
    return GlassmorphicContainer(
      width: double.infinity,
      height: height,
      borderRadius: 24,
      blur: 20,
      alignment: Alignment.center,
      border: 1.5,
      linearGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          mainColor.withOpacity(isDark ? 0.2 : 0.1),
          mainColor.withOpacity(isDark ? 0.05 : 0.01),
        ],
      ),
      borderGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(isDark ? 0.5 : 0.8),
          Colors.white.withOpacity(isDark ? 0.1 : 0.2),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '$_selectedCurrency${amount.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTile(TransactionModel tx, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: tx.type == 'Expense' || tx.type == 'Given'
              ? Colors.redAccent.withOpacity(0.1)
              : Colors.greenAccent.withOpacity(0.1),
          child: Icon(
            tx.type == 'Expense' ? Icons.shopping_bag_outlined
                : tx.type == 'Given' ? Icons.arrow_outward
                : Icons.account_balance_wallet_outlined,
            color: tx.type == 'Expense' || tx.type == 'Given' ? Colors.redAccent : Colors.green,
          ),
        ),
        title: Text(tx.category, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(_formatDate(tx.date)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${tx.type == 'Expense' || tx.type == 'Given' ? '-' : '+'}${tx.currency}${tx.amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: tx.type == 'Expense' || tx.type == 'Given' ? Colors.redAccent : Colors.green,
              ),
            ),
            if (tx.imagePath != null)
              const Icon(Icons.image_outlined, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
