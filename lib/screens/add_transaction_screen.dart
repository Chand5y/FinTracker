import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../data/database_helper.dart';
import '../data/transaction_model.dart';
import '../theme/theme_provider.dart';

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

  void _openImageFullScreen() {
    HapticFeedback.lightImpact();
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.file(File(_imagePath)),
          ),
        ),
      )
    ));
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
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isSignature = themeProvider.themeMode == AppThemeMode.glassmorphic;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isSignature || isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: isSignature ? AppConstants.backgroundDark : (isDark ? Colors.black : Colors.white),
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
              decoration: InputDecoration(
                labelText: 'Amount',
                labelStyle: TextStyle(color: isSignature || isDark ? Colors.grey[400] : Colors.grey[700]),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isSignature || isDark ? Colors.grey[700]! : Colors.grey[400]!)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isSignature ? AppConstants.primaryColor : Colors.blue)),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameController,
              style: TextStyle(color: textColor),
              decoration: InputDecoration(
                labelText: 'Name (e.g., Electricity Bill)', 
                labelStyle: TextStyle(color: isSignature || isDark ? Colors.grey[400] : Colors.grey[700]),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isSignature || isDark ? Colors.grey[700]! : Colors.grey[400]!)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isSignature ? AppConstants.primaryColor : Colors.blue)),
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              dropdownColor: isSignature ? AppConstants.surfaceDark : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
              decoration: InputDecoration(
                labelText: 'Category (Optional)', 
                labelStyle: TextStyle(color: isSignature || isDark ? Colors.grey[400] : Colors.grey[700]),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isSignature || isDark ? Colors.grey[700]! : Colors.grey[400]!)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isSignature ? AppConstants.primaryColor : Colors.blue)),
              ),
              items: AppConstants.categories.map((c) => DropdownMenuItem(value: c['name'], child: Text('${c['emoji']}  ${c['name']}', style: TextStyle(color: textColor)))).toList(),
              onChanged: (val) => setState(() => _selectedCategory = val),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _paymentMode,
              dropdownColor: isSignature ? AppConstants.surfaceDark : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
              decoration: InputDecoration(
                labelText: 'Payment Method', 
                labelStyle: TextStyle(color: isSignature || isDark ? Colors.grey[400] : Colors.grey[700]),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isSignature || isDark ? Colors.grey[700]! : Colors.grey[400]!)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isSignature ? AppConstants.primaryColor : Colors.blue)),
              ),
              items: AppConstants.paymentModes.map((mode) => DropdownMenuItem(value: mode, child: Text(mode, style: TextStyle(color: textColor)))).toList(),
              onChanged: (val) => setState(() => _paymentMode = val!),
            ),
            const SizedBox(height: 20),
            
            InkWell(
              onTap: _pickImage,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSignature ? AppConstants.surfaceDark : Colors.transparent,
                  border: Border.all(color: isSignature || isDark ? Colors.grey[700]! : Colors.grey[400]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.image, color: isSignature ? AppConstants.primaryColor : Colors.blue),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_imagePath.isEmpty ? 'Attach Receipt or Image' : 'Change Image', style: TextStyle(color: textColor))),
                  ],
                ),
              ),
            ),
            
            if (_imagePath.isNotEmpty) ...[
              const SizedBox(height: 16),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  GestureDetector(
                    onTap: _openImageFullScreen,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(_imagePath), height: 150, width: double.infinity, fit: BoxFit.cover),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.white, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                    onPressed: () => setState(() => _imagePath = ''),
                  ),
                ],
              ),
            ],
            
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: isSignature ? AppConstants.primaryColor : Colors.blue, padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _saveTransaction,
              child: Text('Save', style: TextStyle(fontSize: 18, color: isSignature ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
