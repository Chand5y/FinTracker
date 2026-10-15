import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

enum AppThemeChoice { system, light, dark }

class ThemeProvider extends ChangeNotifier {
  AppThemeChoice _themeChoice = AppThemeChoice.system;
  bool _useMaterialYou = false;
  bool _smsAutoTrack = false;
  bool _appLockEnabled = false;
  String _appPin = '';
  String _devEmail = AppConstants.defaultDeveloperEmail;
  String _devGithub = AppConstants.defaultGithubId;
  bool _isInitialized = false;

  AppThemeChoice get themeChoice => _themeChoice;
  bool get useMaterialYou => _useMaterialYou;
  bool get smsAutoTrack => _smsAutoTrack;
  bool get appLockEnabled => _appLockEnabled;
  String get appPin => _appPin;
  String get devEmail => _devEmail;
  String get devGithub => _devGithub;
  bool get isInitialized => _isInitialized;

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
    _appLockEnabled = prefs.getBool('app_lock_enabled') ?? false;
    _appPin = prefs.getString('app_pin') ?? '';
    _devEmail = prefs.getString('dev_email') ?? AppConstants.defaultDeveloperEmail;
    _devGithub = prefs.getString('dev_github') ?? AppConstants.defaultGithubId;
    _isInitialized = true;
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

  Future<void> setAppLock(bool enabled, {String? pin}) async {
    _appLockEnabled = enabled;
    if (pin != null) {
      _appPin = pin;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_lock_enabled', enabled);
    if (pin != null) {
      await prefs.setString('app_pin', pin);
    }
  }

  Future<void> updateDeveloperCredits({required String email, required String github}) async {
    _devEmail = email.trim().isEmpty ? AppConstants.defaultDeveloperEmail : email.trim();
    _devGithub = github.trim().replaceAll('@', '');
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dev_email', _devEmail);
    await prefs.setString('dev_github', _devGithub);
  }
}
