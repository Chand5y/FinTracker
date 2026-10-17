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
  final bool isSmsDraft;

  const AddTransactionScreen({
    Key? key,
    required this.bookId,
    required this.type,
    this.existingTransaction,
    this.isSmsDraft = false,
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
  String _smsText = '';

  late TextEditingController _amountController;
  late TextEditingController _nameController;

  List<Map<String, dynamic>> _otherBooks = [];
  final Set<int> _selectedExtraBookIds = <int>{};

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
    _smsText = widget.existingTransaction?.effectiveSmsText ?? '';
    _loadOtherBooks();
  }

  Future<void> _loadOtherBooks() async {
    try {
      final allBooks = await DatabaseHelper.instance.getBooksWithBalances();
      final filtered = allBooks.where((b) => (b['id'] as int) != widget.bookId).toList();
      if (mounted) {
        setState(() => _otherBooks = filtered);
      }
    } catch (_) {}
  }

  String _getEmojiForCategory(String? catName) {
    if (catName == null || catName.isEmpty) return '🏷️';
    for (final c in AppConstants.categories) {
      if (c['name'] == catName) return c['emoji'] ?? '🏷️';
    }
    return '🏷️';
  }

  void _openCategoryPicker(bool isDark) {
    HapticFeedback.lightImpact();
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.68),
          decoration: BoxDecoration(
            color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Select Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    shrinkWrap: true,
                    children: [
                      _buildPickerOptionCard(
                        isDark: isDark,
                        emoji: '🚫',
                        title: 'None (No Category)',
                        isSelected: _selectedCategory == null,
                        accentColor: scheme.primary,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedCategory = null);
                          Navigator.pop(sheetCtx);
                        },
                      ),
                      ...AppConstants.categories.map((c) {
                        final String name = c['name']!;
                        final String emoji = c['emoji']!;
                        final bool isSelected = _selectedCategory == name;
                        return _buildPickerOptionCard(
                          isDark: isDark,
                          emoji: emoji,
                          title: name,
                          isSelected: isSelected,
                          accentColor: scheme.primary,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedCategory = name);
                            Navigator.pop(sheetCtx);
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openPaymentModePicker(bool isDark) {
    HapticFeedback.lightImpact();
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
          decoration: BoxDecoration(
            color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Payment Method', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    shrinkWrap: true,
                    children: AppConstants.paymentModes.map((mode) {
                      final String emoji = AppConstants.paymentModeEmojis[mode] ?? '💳';
                      final bool isSelected = _paymentMode == mode;
                      return _buildPickerOptionCard(
                        isDark: isDark,
                        emoji: emoji,
                        title: mode,
                        isSelected: isSelected,
                        accentColor: scheme.primary,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _paymentMode = mode);
                          Navigator.pop(sheetCtx);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPickerOptionCard({
    required bool isDark,
    required String emoji,
    required String title,
    required bool isSelected,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    final Color cardBg = isSelected
        ? accentColor.withOpacity(isDark ? 0.18 : 0.12)
        : (isDark ? const Color(0xFF1A1C22) : const Color(0xFFF8FAFC));

    final Color borderColor = isSelected
        ? accentColor
        : (isDark ? AppConstants.borderDark : AppConstants.borderLight);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: borderColor, width: isSelected ? 1.4 : 1.0),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black.withOpacity(0.35) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle_rounded, color: accentColor, size: 22)
                else
                  Icon(Icons.circle_outlined, color: Colors.grey.withOpacity(0.35), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
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

    final bool isNewInsert = widget.existingTransaction == null || widget.existingTransaction?.id == null;

    final transaction = TransactionModel(
      id: widget.existingTransaction?.id,
      bookId: widget.bookId,
      type: _selectedType,
      amount: parsedAmount,
      name: _nameController.text.trim().isEmpty ? 'Untitled Entry' : _nameController.text.trim(),
      category: _selectedCategory ?? '',
      notes: _smsText,
      smsBody: _smsText,
      date: widget.existingTransaction?.date ?? DateTime.now(),
      currency: AppConstants.defaultCurrency,
      paymentMode: _paymentMode,
      imagePath: _imagePath,
    );

    if (isNewInsert) {
      final targetBooks = <int>[widget.bookId, ..._selectedExtraBookIds];
      await DatabaseHelper.instance.insertTransactionToMultipleBooks(transaction, targetBooks);
    } else {
      await DatabaseHelper.instance.updateTransaction(transaction);
      if (_selectedExtraBookIds.isNotEmpty) {
        await DatabaseHelper.instance.copyTransactionToBooks(transaction, _selectedExtraBookIds.toList());
      }
    }

    if (mounted) Navigator.pop(context, true);
  }

  Widget _buildSelectorCard({
    required bool isDark,
    required String label,
    required String valueText,
    required String emoji,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 19)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      valueText,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey[500]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermanentSmsCard(bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    final txDate = widget.existingTransaction?.date;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppConstants.cardDark : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.primary.withOpacity(isDark ? 0.35 : 0.28),
          width: 1.1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.sms_rounded, size: 16, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Text(
                'Transaction SMS Record',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              if (txDate != null)
                Text(
                  AppConstants.formatOrdinalDateTime(txDate),
                  style: TextStyle(fontSize: 10.5, color: Colors.grey[500], fontWeight: FontWeight.w500),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            _smsText,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: isDark ? Colors.grey[300] : Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiBookSelectorCard(bool isDark) {
    if (_otherBooks.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final isEditing = widget.existingTransaction != null && widget.existingTransaction?.id != null;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.library_add_check_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isEditing ? 'Also Copy Entry to Other Books' : 'Also Add to Other Books (Optional)',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap to save this same entry into additional books at once:',
            style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _otherBooks.map((book) {
              final int id = book['id'] as int;
              final String name = book['name'].toString();
              final bool isLending = (book['bookType']?.toString() ?? 'standard') == 'lending';
              final bool selected = _selectedExtraBookIds.contains(id);

              return FilterChip(
                selected: selected,
                showCheckmark: true,
                avatar: Icon(
                  isLending ? Icons.handshake_rounded : Icons.book_rounded,
                  size: 15,
                  color: selected ? scheme.primary : Colors.grey[500],
                ),
                label: Text(
                  name,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                onSelected: (val) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (val) {
                      _selectedExtraBookIds.add(id);
                    } else {
                      _selectedExtraBookIds.remove(id);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isIncome = _selectedType == 'Income';
    final String screenTitle = widget.isSmsDraft
        ? 'Review SMS $_selectedType'
        : (widget.existingTransaction == null ? 'Add $_selectedType' : 'Edit $_selectedType');

    return Scaffold(
      appBar: AppBar(title: Text(screenTitle)),
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
                filled: true,
                fillColor: isDark ? AppConstants.cardDark : AppConstants.cardLight,
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
                filled: true,
                fillColor: isDark ? AppConstants.cardDark : AppConstants.cardLight,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 16),
            _buildSelectorCard(
              isDark: isDark,
              label: 'Category (Optional)',
              valueText: _selectedCategory ?? 'None',
              emoji: _getEmojiForCategory(_selectedCategory),
              onTap: () => _openCategoryPicker(isDark),
            ),
            const SizedBox(height: 16),
            _buildSelectorCard(
              isDark: isDark,
              label: 'Payment Method',
              valueText: _paymentMode,
              emoji: AppConstants.paymentModeEmojis[_paymentMode] ?? '💳',
              onTap: () => _openPaymentModePicker(isDark),
            ),
            if (_smsText.isNotEmpty) _buildPermanentSmsCard(isDark),
            _buildMultiBookSelectorCard(isDark),
            const SizedBox(height: 16),
            Material(
              color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _pickImage,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _imagePath.isEmpty ? 'Attach Receipt or Screenshot' : 'Change Attached Image',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_imagePath.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF181A20) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? const Color(0xFF323642) : const Color(0xFFCBD5E1),
                    width: 1.5,
                  ),
                  boxShadow: [
                    if (!isDark)
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    GestureDetector(
                      onTap: _openImageFullScreen,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
                            width: 0.8,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(_imagePath),
                            height: 170,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
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
              child: Text(
                _selectedExtraBookIds.isEmpty
                    ? 'Save Entry'
                    : 'Save in ${1 + _selectedExtraBookIds.length} Books',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
