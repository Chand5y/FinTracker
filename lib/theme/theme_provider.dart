import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeChoice { system, light, dark }

class ThemeProvider extends ChangeNotifier {
  AppThemeChoice _themeChoice = AppThemeChoice.system;
  bool _useMaterialYou = false;
  bool _smsAutoTrack = false;

  AppThemeChoice get themeChoice => _themeChoice;
  bool get useMaterialYou => _useMaterialYou;
  bool get smsAutoTrack => _smsAutoTrack;

  ThemeMode get flutterThemeMode {
    switch (_themeChoice) {
      case AppThemeChoice.light:
        return ThemeMode.light;
      case AppThemeChoice.dark:
        return ThemeMode.dark;
      case AppThemeChoice.system:
        return ThemeMode.system;
    }
  }

  ThemeProvider() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIdx = prefs.getInt('theme_choice') ?? 0;
    if (modeIdx >= 0 && modeIdx < AppThemeChoice.values.length) {
      _themeChoice = AppThemeChoice.values[modeIdx];
    }
    _useMaterialYou = prefs.getBool('use_material_you') ?? false;
    _smsAutoTrack = prefs.getBool('sms_auto_track') ?? false;
    notifyListeners();
  }

  Future<void> setThemeChoice(AppThemeChoice choice) async {
    _themeChoice = choice;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_choice', choice.index);
  }

  Future<void> toggleMaterialYou(bool value) async {
    _useMaterialYou = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_material_you', value);
  }

  Future<void> setSmsAutoTrack(bool value) async {
    _smsAutoTrack = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sms_auto_track', value);
  }
}
