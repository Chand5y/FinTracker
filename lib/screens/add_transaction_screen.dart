import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../core/constants.dart';
import '../data/database_helper.dart';
import '../data/transaction_model.dart';

class AddTransactionScreen extends StatefulWidget {
  final int bookId;
  final String type; // Pre-selects 'Income' or 'Expense' based on the button tapped

  const AddTransactionScreen({Key? key, required this.bookId, required this.type}) : super(key: key);

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late String _selectedType;
  String _selectedCategory = AppConstants.defaultCategories.first;
  String _selectedCurrency = AppConstants.defaultCurrency;
  String _paymentMode = 'Cash';

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  File? _selectedImage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.type;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);

    if (pickedFile != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = p.basename(pickedFile.path);
      final savedImage = await File(pickedFile.path).copy('${appDir.path}/$fileName');
      
      setState(() {
        _selectedImage = savedImage;
      });
    }
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final transaction = TransactionModel(
      bookId: widget.bookId,
      type: _selectedType,
      amount: double.parse(_amountController.text),
      name: _nameController.text.isEmpty ? 'Untitled Entry' : _nameController.text,
      category: _selectedCategory,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
      imagePath: _selectedImage?.path,
      date: DateTime.now(),
      currency: _selectedCurrency,
      paymentMode: _paymentMode,
    );

    await DatabaseHelper.instance.insertTransaction(transaction);

    if (mounted) {
      Navigator.pop(context); // Returns to the DashboardScreen
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_selectedType, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Amount Field
                    TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _selectedType == 'Income' ? const Color(0xFF328D4D) : const Color(0xFFD33636)),
                      decoration: InputDecoration(
                        labelText: 'Amount ($_selectedCurrency)',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) => (value == null || double.tryParse(value) == null) ? 'Enter valid amount' : null,
                    ),
                    const SizedBox(height: 20),

                    // Name Field
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Name (e.g., Electricity Bill)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Payment Mode Toggle
                    const Text('Payment Mode', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'Cash', label: Text('Cash')),
                        ButtonSegment(value: 'Online', label: Text('Online')),
                        ButtonSegment(value: 'Cheque', label: Text('Cheque')),
                      ],
                      selected: {_paymentMode},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() => _paymentMode = newSelection.first);
                      },
                    ),
                    const SizedBox(height: 20),

                    // Category
                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                      items: AppConstants.defaultCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) => setState(() => _selectedCategory = val!),
                    ),
                    const SizedBox(height: 20),

                    // Notes
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(labelText: 'Remark (Optional)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 20),

                    // Image Picker
                    if (_selectedImage != null)
                      Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Image.file(_selectedImage!, height: 100),
                          IconButton(icon: const Icon(Icons.cancel), onPressed: () => setState(() => _selectedImage = null)),
                        ],
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Attach Receipt'),
                      ),
                    
                    const SizedBox(height: 40),
                    
                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4C44D4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _saveTransaction,
                        child: const Text('Save', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
