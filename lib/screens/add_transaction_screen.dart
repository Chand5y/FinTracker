import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants.dart';
import '../data/database_helper.dart';
import '../data/transaction_model.dart';

class AddTransactionScreen extends StatefulWidget {
  final int bookId;
  final String type; 
  final TransactionModel? existingTransaction; 

  const AddTransactionScreen({Key? key, required this.bookId, required this.type, this.existingTransaction}) : super(key: key);

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  
  late String _selectedType;
  String? _selectedCategory; 
  late String _paymentMode;
  String _imagePath = '';

  late TextEditingController _amountController;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.type;
    _amountController = TextEditingController(text: widget.existingTransaction?.amount.toString() ?? '');
    _nameController = TextEditingController(text: widget.existingTransaction?.name ?? '');
    _selectedCategory = widget.existingTransaction?.category.isEmpty == false ? widget.existingTransaction?.category : null;
    _paymentMode = widget.existingTransaction?.paymentMode ?? 'Cash';
    _imagePath = widget.existingTransaction?.imagePath ?? '';
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _imagePath = image.path);
    }
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();

    final transaction = TransactionModel(
      id: widget.existingTransaction?.id, 
      bookId: widget.bookId,
      type: _selectedType,
      amount: double.parse(_amountController.text),
      name: _nameController.text.isEmpty ? 'Untitled Entry' : _nameController.text,
      category: _selectedCategory ?? '', 
      date: widget.existingTransaction?.date ?? DateTime.now(),
      currency: AppConstants.defaultCurrency,
      paymentMode: _paymentMode,
      imagePath: _imagePath,
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
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _paymentMode,
              decoration: const InputDecoration(labelText: 'Payment Method', border: OutlineInputBorder()),
              items: AppConstants.paymentModes.map((mode) => DropdownMenuItem(value: mode, child: Text(mode))).toList(),
              onChanged: (val) => setState(() => _paymentMode = val!),
            ),
            const SizedBox(height: 20),
            
            // Attachment Section
            InkWell(
              onTap: _pickImage,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.image, color: AppConstants.primaryColor),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_imagePath.isEmpty ? 'Attach Receipt or Image' : 'Change Image', style: TextStyle(color: isDark ? Colors.white : Colors.black))),
                  ],
                ),
              ),
            ),
            
            if (_imagePath.isNotEmpty) ...[
              const SizedBox(height: 16),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(_imagePath), height: 150, width: double.infinity, fit: BoxFit.cover),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.white),
                    onPressed: () => setState(() => _imagePath = ''),
                  ),
                ],
              ),
            ],
            
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
