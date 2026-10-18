import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants.dart';
import '../data/database_helper.dart';
import '../data/transaction_model.dart';

// ===========================================================================
// SHARED BANK ICON, MERCHANT ICON & AUTO-CATEGORIZATION HELPER
// ===========================================================================
class FinTraxBrandHelper {
  static const List<Map<String, String>> paymentMethods = [
    {'name': 'Cash', 'emoji': '💵', 'asset': ''},
    {'name': 'UPI', 'emoji': '📱', 'asset': ''},
    {'name': 'Airtel', 'emoji': '🏦', 'asset': 'assets/Icons/airtel.png'},
    {'name': 'Utkarsh SFBL', 'emoji': '💳', 'asset': 'assets/Icons/Utkarsh.png'},
    {'name': 'Kotak Bank', 'emoji': '🏦', 'asset': 'assets/Icons/kotak.png'},
    {'name': 'SBI', 'emoji': '🏦', 'asset': 'assets/Icons/sbi.png'},
    {'name': 'ICICI Bank', 'emoji': '🏦', 'asset': 'assets/Icons/icici.png'},
    {'name': 'Bank of Baroda', 'emoji': '🏦', 'asset': 'assets/Icons/Baroda.png'},
    {'name': 'IPPB', 'emoji': '🏦', 'asset': 'assets/Icons/ippb.png'},
    {'name': 'Google Pay', 'emoji': '📱', 'asset': 'assets/Icons/Gpay.png'},
    {'name': 'PhonePe', 'emoji': '📱', 'asset': 'assets/Icons/PhonePe.png'},
    {'name': 'Paytm', 'emoji': '📱', 'asset': 'assets/Icons/paytm.png'},
    {'name': 'SuperMoney', 'emoji': '⚡', 'asset': 'assets/Icons/SuperMoney.png'},
    {'name': 'Slice', 'emoji': '💳', 'asset': 'assets/Icons/slice.png'},
    {'name': 'Navi', 'emoji': '📱', 'asset': 'assets/Icons/navi.png'},
    {'name': 'PayPal', 'emoji': '🌐', 'asset': 'assets/Icons/paypal.png'},
    {'name': 'JioPay', 'emoji': '📱', 'asset': 'assets/Icons/jio.png'},
    {'name': 'Card', 'emoji': '💳', 'asset': ''},
    {'name': 'Bank Transfer', 'emoji': '🏦', 'asset': ''},
    {'name': 'Online', 'emoji': '🌐', 'asset': ''},
  ];

  static String detectPaymentMethod({
    String currentMode = '',
    String smsBody = '',
    String sender = '',
  }) {
    final combined = '$sender $smsBody $currentMode'.toLowerCase();

    if (combined.contains('airbnk') || combined.contains('airtel payments bank') || combined.contains('airtel')) {
      return 'Airtel';
    }
    if (combined.contains('utkspr') || combined.contains('utkarsh') || combined.contains('supercard')) {
      return 'Utkarsh SFBL';
    }
    if (combined.contains('kotak') || combined.contains('kbankt')) {
      return 'Kotak Bank';
    }
    if (combined.contains('state bank') || RegExp(r'\bsbi\b').hasMatch(combined) || combined.contains('sbipsg')) {
      return 'SBI';
    }
    if (combined.contains('icici')) {
      return 'ICICI Bank';
    }
    if (combined.contains('baroda') || RegExp(r'\bbob\b').hasMatch(combined)) {
      return 'Bank of Baroda';
    }
    if (combined.contains('ippb') || combined.contains('india post')) {
      return 'IPPB';
    }
    if (combined.contains('supermoney') || combined.contains('super.money')) {
      return 'SuperMoney';
    }
    if (combined.contains('slice')) {
      return 'Slice';
    }
    if (combined.contains('navi')) {
      return 'Navi';
    }
    if (combined.contains('phonepe')) {
      return 'PhonePe';
    }
    if (combined.contains('gpay') || combined.contains('google pay')) {
      return 'Google Pay';
    }
    if (combined.contains('paytm')) {
      return 'Paytm';
    }
    if (combined.contains('paypal')) {
      return 'PayPal';
    }
    if (combined.contains('jiopay')) {
      return 'JioPay';
    }

    if (currentMode.trim().isNotEmpty) {
      return currentMode.trim();
    }
    return 'Cash';
  }

  static String? getPaymentIconAsset(String paymentMode, {String smsBody = '', String sender = ''}) {
    final resolved = detectPaymentMethod(currentMode: paymentMode, smsBody: smsBody, sender: sender);
    for (final item in paymentMethods) {
      if (item['name']!.toLowerCase() == resolved.toLowerCase()) {
        final asset = item['asset'] ?? '';
        return asset.isNotEmpty ? asset : null;
      }
    }
    return null;
  }

  static String getPaymentEmoji(String paymentMode) {
    for (final item in paymentMethods) {
      if (item['name']!.toLowerCase() == paymentMode.toLowerCase()) {
        return item['emoji'] ?? '💳';
      }
    }
    return AppConstants.paymentModeEmojis[paymentMode] ?? '💳';
  }

  static String? getMerchantIconAsset(String name, {String smsBody = ''}) {
    final text = '$name $smsBody'.toLowerCase();
    if (text.contains('flipkart')) return 'assets/Icons/Flipkart.png';
    if (text.contains('amazon') || text.contains('amzn')) return 'assets/Icons/amazon.png';
    if (text.contains('myntra')) return 'assets/Icons/Myntra.png';
    if (text.contains('meesho')) return 'assets/Icons/meesho.png';
    if (text.contains('swiggy') || text.contains('instamart')) return 'assets/Icons/swiggy.png';
    if (text.contains('zomato') || text.contains('blinkit')) return 'assets/Icons/zomato.png';
    if (text.contains('jio')) return 'assets/Icons/jio.png';
    if (text.contains('airtel')) return 'assets/Icons/airtel.png';
    return null;
  }

  static String? detectCategory(String name, {String smsBody = '', String currentCategory = ''}) {
    if (currentCategory.trim().isNotEmpty) return currentCategory.trim();
    final text = '$name $smsBody'.toLowerCase();

    // Check Swiggy Instamart & E-commerce first so Instamart maps to Shopping
    if (text.contains('instamart') ||
        text.contains('flipkart') ||
        text.contains('amazon') ||
        text.contains('amzn') ||
        text.contains('meesho') ||
        text.contains('myntra') ||
        text.contains('ajio') ||
        text.contains('nykaa')) {
      return 'Shopping';
    }

    // Food delivery & dining apps
    if (text.contains('zomato') ||
        text.contains('swiggy') ||
        text.contains('dominos') ||
        text.contains("domino's") ||
        text.contains('kfc') ||
        text.contains('mcdonald') ||
        text.contains('pizza hut') ||
        text.contains('burger king')) {
      return 'Food';
    }

    return null;
  }

  static Widget buildIconBadge({
    required String? assetPath,
    required String fallbackEmoji,
    double size = 20,
    double borderRadius = 6,
  }) {
    if (assetPath != null && assetPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Text(fallbackEmoji, style: TextStyle(fontSize: size * 0.78)),
        ),
      );
    }
    return Text(fallbackEmoji, style: TextStyle(fontSize: size * 0.78));
  }
}

// ===========================================================================
// ADD / EDIT TRANSACTION SCREEN
// ===========================================================================
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
  late DateTime _selectedDate;
  String _imagePath = '';
  String _smsText = '';

  late TextEditingController _amountController;
  late TextEditingController _nameController;
  late TextEditingController _notesController;

  List<Map<String, dynamic>> _otherBooks = [];
  final Set<int> _selectedExtraBookIds = <int>{};

  bool get _isEditingExisting =>
      widget.existingTransaction != null && widget.existingTransaction?.id != null && !widget.isSmsDraft;

  List<Map<String, String>> get _allCategories {
    final list = List<Map<String, String>>.from(AppConstants.categories);
    if (!list.any((c) => (c['name'] ?? '').toLowerCase() == 'emi')) {
      list.add({'name': 'EMI', 'emoji': '🏦'});
    }
    if (!list.any((c) => (c['name'] ?? '').toLowerCase() == 'food')) {
      list.add({'name': 'Food', 'emoji': '🍔'});
    }
    if (!list.any((c) => (c['name'] ?? '').toLowerCase() == 'shopping')) {
      list.add({'name': 'Shopping', 'emoji': '🛍️'});
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _selectedType = widget.type;
    _selectedDate = widget.existingTransaction?.date ?? DateTime.now();
    _amountController = TextEditingController(
      text: widget.existingTransaction != null ? widget.existingTransaction!.amount.toStringAsFixed(0) : '',
    );
    _nameController = TextEditingController(text: widget.existingTransaction?.name ?? '');
    _notesController = TextEditingController(
      text: widget.isSmsDraft ? '' : (widget.existingTransaction?.notes ?? ''),
    );

    _smsText = widget.existingTransaction?.effectiveSmsText ?? '';
    final existingCat = widget.existingTransaction?.category ?? '';
    _selectedCategory = FinTraxBrandHelper.detectCategory(
      _nameController.text,
      smsBody: _smsText,
      currentCategory: existingCat,
    );

    final initialMode = widget.existingTransaction?.paymentMode ?? 'Cash';
    _paymentMode = FinTraxBrandHelper.detectPaymentMethod(
      currentMode: initialMode,
      smsBody: _smsText,
      sender: _nameController.text,
    );

    _imagePath = widget.existingTransaction?.imagePath ?? '';
    _nameController.addListener(_onMerchantNameChanged);
    _loadOtherBooks();
  }

  void _onMerchantNameChanged() {
    if (_selectedCategory == null || _selectedCategory!.isEmpty) {
      final autoCat = FinTraxBrandHelper.detectCategory(_nameController.text, smsBody: _smsText);
      if (autoCat != null && mounted) {
        setState(() => _selectedCategory = autoCat);
      }
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_onMerchantNameChanged);
    _amountController.dispose();
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
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
    for (final c in _allCategories) {
      if (c['name']!.toLowerCase() == catName.toLowerCase()) return c['emoji'] ?? '🏷️';
    }
    return '🏷️';
  }

  Future<void> _pickTransactionDate() async {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
      firstDate: DateTime(2000),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'SELECT TRANSACTION DATE',
    );

    if (pickedDate != null && mounted) {
      setState(() {
        _selectedDate = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          _selectedDate.hour,
          _selectedDate.minute,
          _selectedDate.second,
        );
      });
    }
  }

  Future<void> _confirmAndDeleteEntry() async {
    if (!_isEditingExisting) return;
    HapticFeedback.mediumImpact();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Entry?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
          'Are you sure you want to delete "${widget.existingTransaction!.name}" from this book?',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConstants.expenseRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      HapticFeedback.heavyImpact();
      await DatabaseHelper.instance.deleteTransaction(widget.existingTransaction!.id!, widget.bookId);
      if (mounted) Navigator.pop(context, true);
    }
  }

  Widget _buildTwoColumnGridTile({
    required bool isDark,
    required Widget leadingIcon,
    required String title,
    required bool isSelected,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    final Color cardBg = isSelected
        ? accentColor.withOpacity(isDark ? 0.20 : 0.12)
        : (isDark ? const Color(0xFF1A1C22) : const Color(0xFFF8FAFC));

    final Color borderColor = isSelected
        ? accentColor
        : (isDark ? AppConstants.borderDark : AppConstants.borderLight);

    return Material(
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: borderColor, width: isSelected ? 1.4 : 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDark ? Colors.black.withOpacity(0.35) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: leadingIcon,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: accentColor, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _openCategoryPicker(bool isDark) {
    HapticFeedback.lightImpact();
    final scheme = Theme.of(context).colorScheme;
    final options = <Map<String, String?>>[
      {'name': null, 'label': 'None', 'emoji': '🚫'},
      ..._allCategories.map((c) => {'name': c['name'], 'label': c['name'], 'emoji': c['emoji']}),
    ];

    final rows = <Widget>[];
    for (int i = 0; i < options.length; i += 2) {
      final first = options[i];
      final second = (i + 1 < options.length) ? options[i + 1] : null;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: _buildTwoColumnGridTile(
                  isDark: isDark,
                  leadingIcon: Text(first['emoji'] ?? '🏷️', style: const TextStyle(fontSize: 15)),
                  title: first['label'] ?? 'None',
                  isSelected: _selectedCategory == first['name'],
                  accentColor: scheme.primary,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedCategory = first['name']);
                    Navigator.pop(context);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: second != null
                    ? _buildTwoColumnGridTile(
                        isDark: isDark,
                        leadingIcon: Text(second['emoji'] ?? '🏷️', style: const TextStyle(fontSize: 15)),
                        title: second['label'] ?? '',
                        isSelected: _selectedCategory == second['name'],
                        accentColor: scheme.primary,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedCategory = second['name']);
                          Navigator.pop(context);
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }

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
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Select Category', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
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
                    children: rows,
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
    const methods = FinTraxBrandHelper.paymentMethods;

    final rows = <Widget>[];
    for (int i = 0; i < methods.length; i += 2) {
      final first = methods[i];
      final second = (i + 1 < methods.length) ? methods[i + 1] : null;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: _buildTwoColumnGridTile(
                  isDark: isDark,
                  leadingIcon: FinTraxBrandHelper.buildIconBadge(
                    assetPath: first['asset'],
                    fallbackEmoji: first['emoji'] ?? '💳',
                    size: 20,
                  ),
                  title: first['name']!,
                  isSelected: _paymentMode.toLowerCase() == first['name']!.toLowerCase(),
                  accentColor: scheme.primary,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _paymentMode = first['name']!);
                    Navigator.pop(context);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: second != null
                    ? _buildTwoColumnGridTile(
                        isDark: isDark,
                        leadingIcon: FinTraxBrandHelper.buildIconBadge(
                          assetPath: second['asset'],
                          fallbackEmoji: second['emoji'] ?? '💳',
                          size: 20,
                        ),
                        title: second['name']!,
                        isSelected: _paymentMode.toLowerCase() == second['name']!.toLowerCase(),
                        accentColor: scheme.primary,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _paymentMode = second['name']!);
                          Navigator.pop(context);
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.72),
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
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Payment Method / Bank', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
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
                    children: rows,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openOtherBooksSheet(bool isDark) {
    HapticFeedback.lightImpact();
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
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
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _isEditingExisting ? 'Also Copy Entry to Books' : 'Also Add to Other Books',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(sheetCtx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _otherBooks.length,
                      itemBuilder: (_, idx) {
                        final book = _otherBooks[idx];
                        final int id = book['id'] as int;
                        final String name = book['name'].toString();
                        final bool isLending = (book['bookType']?.toString() ?? 'standard') == 'lending';
                        final bool isSelected = _selectedExtraBookIds.contains(id);

                        return CheckboxListTile(
                          secondary: Icon(
                            isLending ? Icons.handshake_rounded : Icons.book_rounded,
                            color: isSelected ? scheme.primary : Colors.grey[500],
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                          value: isSelected,
                          onChanged: (val) {
                            HapticFeedback.selectionClick();
                            setSheetState(() {
                              if (val == true) {
                                _selectedExtraBookIds.add(id);
                              } else {
                                _selectedExtraBookIds.remove(id);
                              }
                            });
                            setState(() {});
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: Text(
                          _selectedExtraBookIds.isEmpty
                              ? 'Done'
                              : 'Done (${_selectedExtraBookIds.length} Selected)',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
      notes: _notesController.text.trim(),
      smsBody: _smsText,
      date: _selectedDate,
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

  Widget _buildCompactSelectorCard({
    required bool isDark,
    required String label,
    required String valueText,
    required Widget iconWidget,
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
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: iconWidget,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      valueText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.grey[500]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelectorRow(bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _pickTransactionDate,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(Icons.calendar_month_rounded, size: 19, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Date: ${AppConstants.formatOrdinalDate(_selectedDate)}',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Change Date',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: scheme.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermanentSmsCard(bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 14),
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
              Text(
                AppConstants.formatOrdinalDateTime(_selectedDate),
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

  Widget _buildCompactMultiBookButton(bool isDark) {
    if (_otherBooks.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final int count = _selectedExtraBookIds.length;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: count > 0 ? scheme.primary : (isDark ? AppConstants.borderDark : AppConstants.borderLight),
            width: count > 0 ? 1.3 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openOtherBooksSheet(isDark),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(Icons.library_add_check_rounded, size: 20, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isEditingExisting ? 'Also Copy Entry to Other Books' : 'Also Add to Other Books',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$count selected',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: scheme.primary),
                    ),
                  )
                else
                  Text('Select', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary)),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_right_rounded, size: 18, color: Colors.grey[500]),
              ],
            ),
          ),
        ),
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

    final paymentIconAsset = FinTraxBrandHelper.getPaymentIconAsset(_paymentMode, smsBody: _smsText);

    return Scaffold(
      appBar: AppBar(
        title: Text(screenTitle),
        actions: [
          if (_isEditingExisting)
            IconButton(
              tooltip: 'Delete Entry',
              icon: const Icon(Icons.delete_outline_rounded, color: AppConstants.expenseRed),
              onPressed: _confirmAndDeleteEntry,
            ),
        ],
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
                filled: true,
                fillColor: isDark ? AppConstants.cardDark : AppConstants.cardLight,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter an amount' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Remark / Title (e.g., Flipkart, Zomato, Bill)',
                filled: true,
                fillColor: isDark ? AppConstants.cardDark : AppConstants.cardLight,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildCompactSelectorCard(
                    isDark: isDark,
                    label: 'Category',
                    valueText: _selectedCategory ?? 'None',
                    iconWidget: Text(_getEmojiForCategory(_selectedCategory), style: const TextStyle(fontSize: 16)),
                    onTap: () => _openCategoryPicker(isDark),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildCompactSelectorCard(
                    isDark: isDark,
                    label: 'Payment Mode',
                    valueText: _paymentMode,
                    iconWidget: FinTraxBrandHelper.buildIconBadge(
                      assetPath: paymentIconAsset,
                      fallbackEmoji: FinTraxBrandHelper.getPaymentEmoji(_paymentMode),
                      size: 20,
                    ),
                    onTap: () => _openPaymentModePicker(isDark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildDateSelectorRow(isDark),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notesController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Notes (Optional)',
                hintText: 'Add any extra details about this payment...',
                prefixIcon: const Icon(Icons.sticky_note_2_outlined, size: 20),
                filled: true,
                fillColor: isDark ? AppConstants.cardDark : AppConstants.cardLight,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            if (_smsText.isNotEmpty) _buildPermanentSmsCard(isDark),
            _buildCompactMultiBookButton(isDark),
            const SizedBox(height: 14),
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  child: Row(
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _imagePath.isEmpty ? 'Attach Receipt or Screenshot' : 'Change Attached Image',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
                ),
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    GestureDetector(
                      onTap: _openImageFullScreen,
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
            const SizedBox(height: 26),
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
