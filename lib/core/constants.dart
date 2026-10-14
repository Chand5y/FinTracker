import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'FinTrack';
  static const String defaultCurrency = '₹';

  // Classy Minimalist Palette
  static const Color accentIndigo = Color(0xFF4F46E5);
  static const Color bgLight = Color(0xFFF8FAFC);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFE2E8F0);

  // True AMOLED Dark Palette
  static const Color bgDark = Color(0xFF000000);
  static const Color cardDark = Color(0xFF121214);
  static const Color borderDark = Color(0xFF222226);

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
}

class ParsedSmsTransaction {
  final String smsId;
  final String sender;
  final String body;
  final double amount;
  final String type; // 'Income' or 'Expense'
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

    // 1. Ignore OTPs, Promos, Statements, and Due Reminders
    const ignoreWords = [
      'otp', 'one time password', 'verification code', 'secret code',
      'pre-approved', 'offer', 'discount', 'cashback up to', 'win ',
      'apply now', 'bill is due', 'minimum amount due', 'statement for',
      'auto-debit will', 'mandate', 'loan up to', 'limit increase'
    ];
    for (final w in ignoreWords) {
      if (lower.contains(w)) return null;
    }

    // Must look like a financial message
    final hasBankContext = RegExp(r'(a/c|acct|account|bank|upi|vpa|card|debited|credited|spent|paid)', caseSensitive: false).hasMatch(body);
    if (!hasBankContext) return null;

    // 2. Determine Transaction Type
    final isDebit = RegExp(r'(debited|spent|paid|sent\s+rs|withdrawn|purchase|charged)', caseSensitive: false).hasMatch(body);
    final isCredit = RegExp(r'(credited|received|deposited|refund)', caseSensitive: false).hasMatch(body);
    if (!isDebit && !isCredit) return null;

    // In UPI SMS, "debited from A/c ... and credited to VPA" is an Expense
    String type = 'Expense';
    if (isCredit && !lower.contains('debited from') && !lower.contains('sent rs')) {
      type = 'Income';
    }

    // 3. Extract Amount (Rs. / INR / ₹)
    final amtMatch = RegExp(r'(?:rs\.?|inr|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)', caseSensitive: false).firstMatch(body);
    if (amtMatch == null) return null;
    final cleanAmt = amtMatch.group(1)!.replaceAll(',', '');
    final double? amount = double.tryParse(cleanAmt);
    if (amount == null || amount <= 0) return null;

    // 4. Detect Payment Mode
    String mode = 'Online';
    if (lower.contains('gpay') || lower.contains('google pay')) mode = 'GPay';
    else if (lower.contains('paytm')) mode = 'Paytm';
    else if (lower.contains('bhim')) mode = 'Bhim';
    else if (lower.contains('credit card')) mode = 'Credit Card';
    else if (lower.contains('debit card') || lower.contains('pos')) mode = 'Debit Card';
    else if (lower.contains('atm')) mode = 'Cash';

    // 5. Extract Merchant / Counterparty Name
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
