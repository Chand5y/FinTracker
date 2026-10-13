import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';
import '../data/database_helper.dart';
import '../data/transaction_model.dart';

class AddTransactionScreen extends StatefulWidget {
  final int bookId;
  final String type; 
  final TransactionModel? existingTransaction; // If provided, we are editing

  const AddTransactionScreen({Key? key, required this.bookId, required this.type, this.existingTransaction}) : super(key: key);

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late String _selectedType;
  String? _selectedCategory; // Null by default (Optional)
  String _paymentMode = 'Cash';

  late TextEditingController _amountController;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.type;
    
    // Pre-fill if editing
    _amountController = TextEditingController(text: widget.existingTransaction?.amount.toString() ?? '');
    _nameController = TextEditingController(text: widget.existingTransaction?.name ?? '');
    _selectedCategory = widget.existingTransaction?.category.isEmpty == false ? widget.existingTransaction?.category : null;
    _paymentMode = widget.existingTransaction?.paymentMode ?? 'Cash';
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();

    final transaction = TransactionModel(
      id: widget.existingTransaction?.id, // Keep ID if editing
      bookId: widget.bookId,
      type: _selectedType,
      amount: double.parse(_amountController.text),
      name: _nameController.text.isEmpty ? 'Untitled Entry' : _nameController.text,
      category: _selectedCategory ?? '', // Optional category saves as empty string
      date: widget.existingTransaction?.date ?? DateTime.now(),
      currency: AppConstants.defaultCurrency,
      paymentMode: _paymentMode,
    );

    if (widget.existingTransaction == null) {
      await DatabaseHelper.instance.insertTransaction(transaction);
    } else {
      await DatabaseHelper.instance.updateTransaction(transaction);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppConstants.backgroundDark : Colors.white,
      appBar: AppBar(title: Text(widget.existingTransaction == null ? 'Add $_selectedType' : 'Edit $_selectedType')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: _selectedType == 'Income' ? const Color(0xFF328D4D) : const Color(0xFFD33636)),
              decoration: const InputDecoration(labelText: 'Amount', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name (e.g., Electricity Bill)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(labelText: 'Category (Optional)', border: OutlineInputBorder()),
              items: AppConstants.categories.map((c) => DropdownMenuItem(value: c['name'], child: Text('${c['emoji']}  ${c['name']}'))).toList(),
              onChanged: (val) => setState(() => _selectedCategory = val),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppConstants.primaryColor, padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _saveTransaction,
              child: const Text('Save', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
