import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeChoice { system, light, dark }

class ThemeProvider extends ChangeNotifier {
  AppThemeChoice _themeChoice = AppThemeChoice.system;
  bool _useMaterialYou = false;
  bool _smsAutoTrack = false;
  bool _appLockEnabled = false;

  // Google Drive Backup State
  String _driveAccount = '';
  String _lastBackupIso = '';
  String _lastAutoBackupDay = '';

  // Daily Notification Reminder State (Default 10:00 PM -> 22:00)
  bool _dailyReminderEnabled = true;
  int _reminderHour = 22;
  int _reminderMinute = 0;

  bool _isInitialized = false;

  AppThemeChoice get themeChoice => _themeChoice;
  bool get useMaterialYou => _useMaterialYou;
  bool get smsAutoTrack => _smsAutoTrack;
  bool get appLockEnabled => _appLockEnabled;
  String get driveAccount => _driveAccount;
  String get lastBackupIso => _lastBackupIso;
  String get lastAutoBackupDay => _lastAutoBackupDay;
  bool get dailyReminderEnabled => _dailyReminderEnabled;
  int get reminderHour => _reminderHour;
  int get reminderMinute => _reminderMinute;
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
    _driveAccount = prefs.getString('drive_account') ?? '';
    _lastBackupIso = prefs.getString('last_backup_iso') ?? '';
    _lastAutoBackupDay = prefs.getString('last_auto_backup_day') ?? '';
    _dailyReminderEnabled = prefs.getBool('daily_reminder_enabled') ?? true;
    _reminderHour = prefs.getInt('reminder_hour') ?? 22;
    _reminderMinute = prefs.getInt('reminder_minute') ?? 0;
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

  Future<void> setAppLock(bool enabled) async {
    _appLockEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_lock_enabled', enabled);
  }

  Future<void> setDriveAccount(String email) async {
    _driveAccount = email.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('drive_account', _driveAccount);
  }

  Future<void> recordBackupSuccess({required String isoTimestamp, required String dayKey}) async {
    _lastBackupIso = isoTimestamp;
    _lastAutoBackupDay = dayKey;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_backup_iso', isoTimestamp);
    await prefs.setString('last_auto_backup_day', dayKey);
  }

  Future<void> setDailyReminder({required bool enabled, int? hour, int? minute}) async {
    _dailyReminderEnabled = enabled;
    if (hour != null) _reminderHour = hour;
    if (minute != null) _reminderMinute = minute;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('daily_reminder_enabled', _dailyReminderEnabled);
    await prefs.setInt('reminder_hour', _reminderHour);
    await prefs.setInt('reminder_minute', _reminderMinute);
  }
}
