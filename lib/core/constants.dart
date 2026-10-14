import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'Fintrack';
  static const String defaultCurrency = '₹';
  
  static const Color primaryColor = Color(0xFF6366F1); 
  static const Color surfaceDark = Color(0xFF121212); 
  static const Color backgroundDark = Colors.black; 

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
    'Cash', 'Online', 'Credit Card', 'Debit Card', 
    'GPay', 'Paytm', 'SuperMoney', 'WhatsApp', 'Bhim'
  ];

  static const List<String> availableCurrencies = ['₹', '\$', '€', '£', '¥', 'A\$', 'C\$'];
}
