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

  const AddTransactionScreen({
    Key? key,
    required this.bookId,
    required this.type,
    this.existingTransaction,
  }) : super(key: key);

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
    _amountController = TextEditingController(
      text: widget.existingTransaction != null ? widget.existingTransaction!.amount.toStringAsFixed(0) : '',
    );
    _nameController = TextEditingController(text: widget.existingTransaction?.name ?? '');
    final existingCat = widget.existingTransaction?.category ?? '';
    _selectedCategory = existingCat.isNotEmpty ? existingCat : null;
    _paymentMode = widget.existingTransaction?.paymentMode ?? 'Cash';
    if (!AppConstants.paymentModes.contains(_paymentMode)) {
      _paymentMode = 'Cash';
    }
    _imagePath = widget.existingTransaction?.imagePath ?? '';
  }

  Future<void> _pickImage() async {
    HapticFeedback.selectionClick();
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      setState(() => _imagePath = image.path);
    }
  }

  void _openImageFullScreen() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text('Receipt Attachment', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(File(_imagePath)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    final double? parsedAmount = double.tryParse(_amountController.text.trim());
    if (parsedAmount == null || parsedAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid amount.')));
      return;
    }

    HapticFeedback.mediumImpact();

    final transaction = TransactionModel(
      id: widget.existingTransaction?.id,
      bookId: widget.bookId,
      type: _selectedType,
      amount: parsedAmount,
      name: _nameController.text.trim().isEmpty ? 'Untitled Entry' : _nameController.text.trim(),
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
    final bool isIncome = _selectedType == 'Income';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingTransaction == null ? 'Add $_selectedType' : 'Edit $_selectedType'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _amountController,
              autofocus: widget.existingTransaction == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: isIncome ? AppConstants.incomeGreen : AppConstants.expenseRed,
              ),
              decoration: InputDecoration(
                labelText: 'Amount (${AppConstants.defaultCurrency})',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter an amount' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Remark / Title (e.g., Electricity Bill)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: InputDecoration(
                labelText: 'Category (Optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('None')),
                ...AppConstants.categories.map(
                  (c) => DropdownMenuItem<String>(
                    value: c['name'],
                    child: Text('${c['emoji']}  ${c['name']}'),
                  ),
                ),
              ],
              onChanged: (val) => setState(() => _selectedCategory = val),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _paymentMode,
              decoration: InputDecoration(
                labelText: 'Payment Method',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              items: AppConstants.paymentModes.map((mode) => DropdownMenuItem(value: mode, child: Text(mode))).toList(),
              onChanged: (val) => setState(() => _paymentMode = val!),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickImage,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.add_photo_alternate_outlined, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _imagePath.isEmpty ? 'Attach Receipt or Screenshot' : 'Change Attached Image',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_imagePath.isNotEmpty) ...[
              const SizedBox(height: 12),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  GestureDetector(
                    onTap: _openImageFullScreen,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(File(_imagePath), height: 170, width: double.infinity, fit: BoxFit.cover),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.close, size: 18, color: Colors.white),
                        onPressed: () => setState(() => _imagePath = ''),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Tap image to view full screen', style: TextStyle(fontSize: 11, color: Colors.grey[500]), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 32),
            FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _saveTransaction,
              child: const Text('Save Entry', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
