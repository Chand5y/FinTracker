import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'FinTrax';
  static const String appTagline = 'YOUR PERSONAL FINANCIAL TRACKER';
  static const String defaultCurrency = '₹';

  // Default Developer Credits
  static const String developerName = 'Chandan Kumar';
  static const String defaultGithubId = 'Chand5y';
  static const String defaultDeveloperEmail = 'chandankumar@example.com';

  // Signature Champagne Gold & Midnight Navy (Matches App Icon)
  static const Color goldAccent = Color(0xFFC5A059);
  static const Color goldDarkText = Color(0xFF9E7B36);
  static const Color iconNavy = Color(0xFF111C30);
  static const Color accentIndigo = Color(0xFFC5A059);

  // Clean Light Palette
  static const Color bgLight = Color(0xFFF8FAFC);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFE2E8F0);

  // True AMOLED Dark Palette
  static const Color bgDark = Color(0xFF000000);
  static const Color cardDark = Color(0xFF121316);
  static const Color borderDark = Color(0xFF22242A);

  // Semantic Colors
  static const Color incomeGreen = Color(0xFF16A34A);
  static const Color expenseRed = Color(0xFFDC2626);

  static const List<Map<String, String>> categories = [
    {'name': 'Food & Dining', 'emoji': '🍔'},
    {'name': 'Transportation & Fuel', 'emoji': '🚗'},
    {'name': 'Housing & Rent', 'emoji': '🏠'},
    {'name': 'Utilities & Bills', 'emoji': '⚡'},
    {'name': 'Groceries', 'emoji': '🛒'},
    {'name': 'Entertainment', 'emoji': '🎬'},
    {'name': 'Shopping', 'emoji': '🛍️'},
    {'name': 'Healthcare & Medical', 'emoji': '🏥'},
    {'name': 'Salary / Income', 'emoji': '💰'},
    {'name': 'Lent to Someone', 'emoji': '🤝'},
    {'name': 'Repayment Received', 'emoji': '✅'},
    {'name': 'Miscellaneous', 'emoji': '📦'},
  ];

  static const List<String> paymentModes = [
    'Cash', 'Online', 'GPay', 'Paytm', 'SuperMoney',
    'WhatsApp', 'Bhim', 'Credit Card', 'Debit Card'
  ];

  static const Map<String, String> paymentModeEmojis = {
    'Cash': '💵',
    'Online': '🌐',
    'GPay': '📱',
    'Paytm': '💙',
    'SuperMoney': '⚡',
    'WhatsApp': '💬',
    'Bhim': '🇮🇳',
    'Credit Card': '💳',
    'Debit Card': '🏦',
  };

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static String _ordinalSuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  /// Formats as: "1st Jan 2026" or "15th Oct 2026"
  static String formatOrdinalDate(DateTime date) {
    final int d = date.day;
    final String month = _months[date.month - 1];
    return '$d${_ordinalSuffix(d)} $month ${date.year}';
  }

  /// Formats as: "15th Oct 2026, 7:39 AM"
  static String formatOrdinalDateTime(DateTime date) {
    final String datePart = formatOrdinalDate(date);
    final int hour = date.hour == 0 ? 12 : (date.hour > 12 ? date.hour - 12 : date.hour);
    final String amPm = date.hour >= 12 ? 'PM' : 'AM';
    final String min = date.minute.toString().padLeft(2, '0');
    return '$datePart, $hour:$min $amPm';
  }
}

class ParsedSmsTransaction {
  final String smsId;
  final String sender;
  final String body;
  final double amount;
  final String type;
  final String merchant;
  final String paymentMode;
  final DateTime date;

  ParsedSmsTransaction({
    required this.smsId,
    required this.sender,
    required this.body,
    required this.amount,
    required this.type,
    required this.merchant,
    required this.paymentMode,
    required this.date,
  });

  static ParsedSmsTransaction? tryParse(Map<dynamic, dynamic> raw) {
    final String id = (raw['id'] ?? '').toString();
    final String sender = (raw['address'] ?? '').toString();
    final String body = (raw['body'] ?? '').toString();
    final int timestamp = int.tryParse((raw['date'] ?? '0').toString()) ?? 0;

    if (id.isEmpty || body.isEmpty) return null;
    final lower = body.toLowerCase();

    const ignoreWords = [
      'otp', 'one time password', 'verification code', 'secret code',
      'pre-approved', 'offer', 'discount', 'cashback up to', 'win ',
      'apply now', 'bill is due', 'minimum amount due', 'statement for',
      'auto-debit will', 'mandate', 'loan up to', 'limit increase'
    ];
    for (final w in ignoreWords) {
      if (lower.contains(w)) return null;
    }

    final hasBankContext = RegExp(r'(a/c|acct|account|bank|upi|vpa|card|debited|credited|spent|paid)', caseSensitive: false).hasMatch(body);
    if (!hasBankContext) return null;

    final isDebit = RegExp(r'(debited|spent|paid|sent\s+rs|withdrawn|purchase|charged)', caseSensitive: false).hasMatch(body);
    final isCredit = RegExp(r'(credited|received|deposited|refund)', caseSensitive: false).hasMatch(body);
    if (!isDebit && !isCredit) return null;

    String type = 'Expense';
    if (isCredit && !lower.contains('debited from') && !lower.contains('sent rs')) {
      type = 'Income';
    }

    final amtMatch = RegExp(r'(?:rs\.?|inr|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)', caseSensitive: false).firstMatch(body);
    if (amtMatch == null) return null;
    final cleanAmt = amtMatch.group(1)!.replaceAll(',', '');
    final double? amount = double.tryParse(cleanAmt);
    if (amount == null || amount <= 0) return null;

    String mode = 'Online';
    if (lower.contains('gpay') || lower.contains('google pay')) mode = 'GPay';
    else if (lower.contains('paytm')) mode = 'Paytm';
    else if (lower.contains('bhim')) mode = 'Bhim';
    else if (lower.contains('credit card')) mode = 'Credit Card';
    else if (lower.contains('debit card') || lower.contains('pos')) mode = 'Debit Card';
    else if (lower.contains('atm')) mode = 'Cash';

    String merchant = sender.replaceAll(RegExp(r'^[A-Z]{2}-'), '');
    final toMatch = RegExp(r'(?:to|at|towards|from)\s+([A-Za-z0-9\s&\-\.@]{2,22}?)(?:\s+on|\s+ref|\s+upi|\s+avl|\.|$)', caseSensitive: false).firstMatch(body);
    if (toMatch != null && toMatch.group(1) != null) {
      final candidate = toMatch.group(1)!.trim();
      if (candidate.length >= 2 && !candidate.toLowerCase().startsWith('a/c')) {
        merchant = candidate;
      }
    }

    return ParsedSmsTransaction(
      smsId: id,
      sender: sender,
      body: body,
      amount: amount,
      type: type,
      merchant: merchant,
      paymentMode: mode,
      date: timestamp > 0 ? DateTime.fromMillisecondsSinceEpoch(timestamp) : DateTime.now(),
    );
  }
}
