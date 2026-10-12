import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../core/constants.dart';
import '../data/database_helper.dart';
import '../data/transaction_model.dart';
import 'dashboard_screen.dart';

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({Key? key}) : super(key: key);

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  
  String _selectedType = 'Expense'; // Default
  final List<String> _types = ['Expense', 'Income', 'Given', 'Received'];
  
  String _selectedCategory = AppConstants.defaultCategories.first;
  String _selectedCurrency = AppConstants.defaultCurrency;

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _partyController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  File? _selectedImage;
  bool _isSaving = false;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, imageQuality: 70);

    if (pickedFile != null) {
      // Copy image to persistent app directory so it isn't cleared by OS cache
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
      type: _selectedType,
      amount: double.parse(_amountController.text),
      partyName: (_selectedType == 'Given' || _selectedType == 'Received') 
          ? _partyController.text 
          : null,
      category: _selectedCategory,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
      imagePath: _selectedImage?.path,
      date: DateTime.now(),
      currency: _selectedCurrency,
    );

    await DatabaseHelper.instance.insertTransaction(transaction);

    if (mounted) {
      // Return to Dashboard and trigger a refresh
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Entry'),
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
                    // --- TYPE SELECTOR ---
                    SegmentedButton<String>(
                      segments: _types.map((t) => ButtonSegment(value: t, label: Text(t))).toList(),
                      selected: {_selectedType},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() {
                          _selectedType = newSelection.first;
                        });
                      },
                    ),
                    const SizedBox(height: 24),

                    // --- AMOUNT & CURRENCY ---
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 1,
                          child: DropdownButtonFormField<String>(
                            value: _selectedCurrency,
                            decoration: const InputDecoration(
                              labelText: 'Cur',
                              border: OutlineInputBorder(),
                            ),
                            items: AppConstants.availableCurrencies.map((c) {
                              return DropdownMenuItem(value: c, child: Text(c));
                            }).toList(),
                            onChanged: (val) => setState(() => _selectedCurrency = val!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Amount',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Enter amount';
                              if (double.tryParse(value) == null) return 'Enter valid number';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // --- CONDITIONAL PARTY NAME (If tracking Lent/Repaid money) ---
                    if (_selectedType == 'Given' || _selectedType == 'Received') ...[
                      TextFormField(
                        controller: _partyController,
                        decoration: InputDecoration(
                          labelText: _selectedType == 'Given' ? 'Who did you give it to?' : 'Who repaid you?',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        validator: (value) => value!.isEmpty ? 'Name required' : null,
                      ),
                      const SizedBox(height: 20),
                    ],

                    // --- CATEGORY ---
                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      items: AppConstants.defaultCategories.map((c) {
                        return DropdownMenuItem(value: c, child: Text(c));
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedCategory = val!),
                    ),
                    const SizedBox(height: 20),

                    // --- NOTES ---
                    TextFormField(
                      controller: _notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Notes / Comments (Optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- IMAGE PICKER ---
                    Text(
                      'Receipt / Screenshot',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    if (_selectedImage != null)
                      Stack(
                        alignment: Alignment.topRight,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(_selectedImage!, height: 150, width: double.infinity, fit: BoxFit.cover),
                          ),
                          IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.white),
                            onPressed: () => setState(() => _selectedImage = null),
                          )
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _pickImage(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('Camera'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _pickImage(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('Gallery'),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 40),
                    
                    // --- SAVE BUTTON ---
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? Colors.white : Colors.black,
                          foregroundColor: isDark ? Colors.black : Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _saveTransaction,
                        child: const Text('Save Entry', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }
}
