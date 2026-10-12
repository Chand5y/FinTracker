import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { glassmorphic, materialExpressive }

class ThemeProvider extends ChangeNotifier {
  AppThemeMode _themeMode = AppThemeMode.glassmorphic;
  
  AppThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _loadTheme();
  }

  void toggleTheme() async {
    _themeMode = _themeMode == AppThemeMode.glassmorphic 
        ? AppThemeMode.materialExpressive 
        : AppThemeMode.glassmorphic;
    notifyListeners();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setInt('themeMode', _themeMode.index);
  }

  void _loadTheme() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int? savedTheme = prefs.getInt('themeMode');
    if (savedTheme != null) {
      _themeMode = AppThemeMode.values[savedTheme];
      notifyListeners();
    }
  }
}
