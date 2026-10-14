import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'FinTrack';
  static const String defaultCurrency = '₹';
  
  // New Signature Navy & Gold Vibe
  static const Color primaryColor = Color(0xFFC5A059); // Champagne Gold
  static const Color backgroundDark = Color(0xFF0B101E); // Deep Navy Blue
  static const Color surfaceDark = Color(0xFF161D2F); // Elevated Navy Card

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
