import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AppThemeChoice { system, light, dark }

class ThemeProvider extends ChangeNotifier {
  static const MethodChannel _nativeChannel = MethodChannel('com.chandankumar.fintrack/sms');

  AppThemeChoice _themeChoice = AppThemeChoice.system;
  bool _useMaterialYou = false;
  bool _appLockEnabled = false;
  bool _smsAutoTrack = false;
  bool _dailyReminderEnabled = true;
  int _reminderHour = 21;
  int _reminderMinute = 0;
  String _driveAccount = '';
  String _lastBackupIso = '';
  String _lastAutoBackupDay = '';
  bool _isInitialized = false;

  AppThemeChoice get themeChoice => _themeChoice;
  bool get useMaterialYou => _useMaterialYou;
  bool get appLockEnabled => _appLockEnabled;
  bool get smsAutoTrack => _smsAutoTrack;
  bool get dailyReminderEnabled => _dailyReminderEnabled;
  int get reminderHour => _reminderHour;
  int get reminderMinute => _reminderMinute;
  String get driveAccount => _driveAccount;
  String get lastBackupIso => _lastBackupIso;
  String get lastAutoBackupDay => _lastAutoBackupDay;
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

  Future<void> _writePref(String key, dynamic value) async {
    try {
      await _nativeChannel.invokeMethod('writeAppPref', {'key': key, 'value': value});
    } catch (_) {}
  }

  Future<void> _loadPreferences() async {
    try {
      final raw = await _nativeChannel.invokeMethod<Map<dynamic, dynamic>>('readAppPrefs');
      if (raw != null) {
        final int idx = (raw['themeChoice'] as num?)?.toInt() ?? 0;
        if (idx >= 0 && idx < AppThemeChoice.values.length) {
          _themeChoice = AppThemeChoice.values[idx];
        }
        _useMaterialYou = (raw['useMaterialYou'] as bool?) ?? false;
        _appLockEnabled = (raw['appLockEnabled'] as bool?) ?? false;
        _smsAutoTrack = (raw['smsAutoTrack'] as bool?) ?? false;
        _dailyReminderEnabled = (raw['dailyReminderEnabled'] as bool?) ?? true;
        _reminderHour = (raw['reminderHour'] as num?)?.toInt() ?? 21;
        _reminderMinute = (raw['reminderMinute'] as num?)?.toInt() ?? 0;
        _driveAccount = raw['driveAccount']?.toString() ?? '';
        _lastBackupIso = raw['lastBackupIso']?.toString() ?? '';
        _lastAutoBackupDay = raw['lastAutoBackupDay']?.toString() ?? '';
      }
    } catch (_) {
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> setThemeChoice(AppThemeChoice choice) async {
    _themeChoice = choice;
    notifyListeners();
    await _writePref('themeChoice', choice.index);
  }

  Future<void> toggleMaterialYou(bool value) async {
    _useMaterialYou = value;
    notifyListeners();
    await _writePref('useMaterialYou', value);
  }

  Future<void> setAppLock(bool enabled) async {
    _appLockEnabled = enabled;
    notifyListeners();
    await _writePref('appLockEnabled', enabled);
  }

  Future<void> setSmsAutoTrack(bool enabled) async {
    _smsAutoTrack = enabled;
    notifyListeners();
    await _writePref('smsAutoTrack', enabled);
  }

  Future<void> setDailyReminder({required bool enabled, int? hour, int? minute}) async {
    _dailyReminderEnabled = enabled;
    if (hour != null) _reminderHour = hour;
    if (minute != null) _reminderMinute = minute;
    notifyListeners();
    await _writePref('dailyReminderEnabled', _dailyReminderEnabled);
    await _writePref('reminderHour', _reminderHour);
    await _writePref('reminderMinute', _reminderMinute);
  }

  Future<void> setDriveAccount(String email) async {
    _driveAccount = email;
    notifyListeners();
    await _writePref('driveAccount', email);
  }

  Future<void> recordBackupSuccess({required String isoTimestamp, required String dayKey}) async {
    _lastBackupIso = isoTimestamp;
    _lastAutoBackupDay = dayKey;
    notifyListeners();
    await _writePref('lastBackupIso', isoTimestamp);
    await _writePref('lastAutoBackupDay', dayKey);
  }
}
