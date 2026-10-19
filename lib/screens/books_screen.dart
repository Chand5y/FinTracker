import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../data/database_helper.dart';
import '../data/book_model.dart';
import '../data/transaction_model.dart';
import '../core/constants.dart';
import '../theme/theme_provider.dart';
import 'dashboard_screen.dart';
import 'add_transaction_screen.dart';

enum BookSort { updated, created, aToZ, zToA }

// ===========================================================================
// BUILT-IN BACKEND DIAGNOSTIC LOGGER
// ===========================================================================
class AppLogger {
  static final AppLogger instance = AppLogger._internal();
  AppLogger._internal();

  static const MethodChannel _nativeChannel = MethodChannel('com.chandankumar.fintrack/sms');
  final List<String> _logs = <String>[];
  final ValueNotifier<int> logNotifier = ValueNotifier<int>(0);

  void log(String message, {String tag = 'INFO'}) {
    final now = DateTime.now();
    final ts = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final entry = '[$ts][$tag] $message';
    _logs.add(entry);
    debugPrint(entry);
    logNotifier.value = _logs.length;
  }

  List<String> get logs => List<String>.unmodifiable(_logs);

  String dumpAllText() {
    final header = StringBuffer()
      ..writeln('====================================================')
      ..writeln('FINTRAX BACKEND DIAGNOSTIC LOG DUMP')
      ..writeln('Generated At: ${DateTime.now().toIso8601String()}')
      ..writeln('Platform: ${Platform.operatingSystem} (${Platform.operatingSystemVersion})')
      ..writeln('Dart Version: ${Platform.version}')
      ..writeln('Total Entries: ${_logs.length}')
      ..writeln('====================================================\n');
    return '$header${_logs.join('\n')}\n';
  }

  void clear() {
    _logs.clear();
    logNotifier.value = 0;
    log('Diagnostic logs cleared by user.', tag: 'SYSTEM');
  }

  Future<Map<String, String>> logRuntimeEnvironment(GoogleSignIn googleAuth, ThemeProvider prefs) async {
    String pkg = 'unknown';
    String sha1 = 'unknown';
    try {
      final info = await _nativeChannel.invokeMethod<Map<dynamic, dynamic>>('getApkSignatureInfo');
      if (info != null) {
        pkg = info['packageName']?.toString() ?? 'unknown';
        sha1 = info['sha1']?.toString() ?? 'unknown';
      }
    } catch (_) {}
    log('Live APK Package: "$pkg" | Live APK SHA-1: "$sha1"', tag: 'APK_CERT');
    log('GoogleSignIn Scopes: ${googleAuth.scopes.join(", ")}', tag: 'OAUTH_CFG');
    log('Saved Drive Account: "${prefs.driveAccount.isEmpty ? "NONE" : prefs.driveAccount}"', tag: 'PREFS');
    return {'packageName': pkg, 'sha1': sha1};
  }

  Future<String?> saveLogsToDownloads() async {
    final fileName = 'FinTrax_Debug_Log_${DateTime.now().millisecondsSinceEpoch}.txt';
    final bytes = Uint8List.fromList(utf8.encode(dumpAllText()));

    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        final outFile = File('${downloadDir.path}/$fileName');
        await outFile.writeAsBytes(bytes, flush: true);
        return outFile.path;
      }
    } catch (_) {}

    try {
      final saved = await _nativeChannel.invokeMethod<bool>('savePdfToDownloads', {
            'bytes': bytes,
            'fileName': fileName,
          }) ??
          false;
      if (saved) return 'Downloads/$fileName';
    } catch (_) {}
    return null;
  }
}

// ===========================================================================
// DIAGNOSTIC LOG VIEWER SCREEN
// ===========================================================================
class DebugLogsScreen extends StatelessWidget {
  const DebugLogsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostic Logs', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: () async {
              HapticFeedback.lightImpact();
              await Clipboard.setData(ClipboardData(text: AppLogger.instance.dumpAllText()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logs copied to clipboard!'), backgroundColor: AppConstants.incomeGreen),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () {
              HapticFeedback.mediumImpact();
              AppLogger.instance.clear();
            },
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded),
            onPressed: () async {
              HapticFeedback.mediumImpact();
              final savedPath = await AppLogger.instance.saveLogsToDownloads();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(savedPath != null ? 'Saved to: $savedPath' : 'Save failed. Use Copy instead.'),
                    backgroundColor: savedPath != null ? AppConstants.incomeGreen : AppConstants.expenseRed,
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: AppLogger.instance.logNotifier,
        builder: (context, _, __) {
          final logs = AppLogger.instance.logs;
          if (logs.isEmpty) {
            return const Center(child: Text('No logs recorded yet.', style: TextStyle(color: Colors.grey)));
          }
          return SelectionArea(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final line = logs[index];
                final isErr = line.contains('[ERROR]') || line.contains('[DIAGNOSIS]') || line.contains('failed');
                final isWarn = line.contains('[WARN]');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      color: isErr
                          ? AppConstants.expenseRed
                          : isWarn
                              ? const Color(0xFFE5A93B)
                              : (isDark ? Colors.grey[300] : Colors.grey[850]),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ===========================================================================
// FIRST-INSTALL WELCOME & FRIENDLY PERMISSION SETUP FLOW
// ===========================================================================
class WelcomeSetupScreen extends StatefulWidget {
  final VoidCallback onFinished;
  const WelcomeSetupScreen({Key? key, required this.onFinished}) : super(key: key);

  @override
  State<WelcomeSetupScreen> createState() => _WelcomeSetupScreenState();
}

class _WelcomeSetupScreenState extends State<WelcomeSetupScreen> with WidgetsBindingObserver {
  static const MethodChannel _nativeBridge = MethodChannel('com.chandankumar.fintrack/sms');
  int _step = 0;
  bool _waitingForNotifDialog = false;
  bool _waitingForSmsDialog = false;
  bool _dialogPausedApp = false;
  bool _completedOnboarding = false;
  Timer? _noDialogFallbackTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noDialogFallbackTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_waitingForNotifDialog && !_waitingForSmsDialog) return;

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _dialogPausedApp = true;
      _noDialogFallbackTimer?.cancel();
    } else if (state == AppLifecycleState.resumed && _dialogPausedApp) {
      _dialogPausedApp = false;
      if (_waitingForNotifDialog) {
        _advanceFromNotifToStep3();
      } else if (_waitingForSmsDialog) {
        _finishOnboardingAndGoHome();
      }
    }
  }

  void _advanceFromNotifToStep3() {
    _noDialogFallbackTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _waitingForNotifDialog = false;
      _step = 2;
    });
  }

  Future<void> _handleNotificationStep(bool enable) async {
    if (_waitingForNotifDialog) return;
    HapticFeedback.mediumImpact();
    final prefs = Provider.of<ThemeProvider>(context, listen: false);

    if (!enable) {
      unawaited(prefs.setDailyReminder(enabled: false, hour: 21, minute: 0));
      setState(() => _step = 2);
      return;
    }

    setState(() {
      _waitingForNotifDialog = true;
      _dialogPausedApp = false;
    });

    unawaited(prefs.setDailyReminder(enabled: true, hour: 21, minute: 0));
    unawaited(_nativeBridge.invokeMethod('requestNotificationPermission').catchError((_) => null));
    unawaited(_nativeBridge.invokeMethod('scheduleDailyReminder', {
      'enabled': true,
      'hour': 21,
      'minute': 0,
    }).catchError((_) => null));

    _noDialogFallbackTimer?.cancel();
    _noDialogFallbackTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted && _waitingForNotifDialog && !_dialogPausedApp) {
        _advanceFromNotifToStep3();
      }
    });
  }

  Future<void> _finishOnboardingAndGoHome() async {
    if (_completedOnboarding) return;
    _completedOnboarding = true;
    _noDialogFallbackTimer?.cancel();
    _waitingForSmsDialog = false;

    final prefs = Provider.of<ThemeProvider>(context, listen: false);
    try {
      await DatabaseHelper.instance.markSmsHandled('__onboarding_v1_done__', 'done');
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 250));
    try {
      final granted = await _nativeBridge.invokeMethod<bool>('checkSmsPermission') ?? false;
      await prefs.setSmsAutoTrack(granted);
    } catch (_) {}

    widget.onFinished();
  }

  Future<void> _handleSmsStep(bool enable) async {
    if (_waitingForSmsDialog || _completedOnboarding) return;
    HapticFeedback.mediumImpact();
    final prefs = Provider.of<ThemeProvider>(context, listen: false);

    if (!enable) {
      _completedOnboarding = true;
      await prefs.setSmsAutoTrack(false);
      try {
        await DatabaseHelper.instance.markSmsHandled('__onboarding_v1_done__', 'done');
        await DatabaseHelper.instance.markSmsHandled('__sms_manually_off__', 'true');
      } catch (_) {}
      widget.onFinished();
      return;
    }

    bool alreadyGranted = false;
    try {
      alreadyGranted = await _nativeBridge
              .invokeMethod<bool>('checkSmsPermission')
              .timeout(const Duration(milliseconds: 400), onTimeout: () => false) ??
          false;
    } catch (_) {}

    if (alreadyGranted) {
      await prefs.setSmsAutoTrack(true);
      await _finishOnboardingAndGoHome();
      return;
    }

    setState(() {
      _waitingForSmsDialog = true;
      _dialogPausedApp = false;
    });

    _nativeBridge.invokeMethod<bool>('requestSmsPermission').then((granted) async {
      if (granted == true) {
        await prefs.setSmsAutoTrack(true);
      }
      if (mounted && _waitingForSmsDialog) {
        await _finishOnboardingAndGoHome();
      }
    }).catchError((_) {});

    _noDialogFallbackTimer?.cancel();
    _noDialogFallbackTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && _waitingForSmsDialog && !_dialogPausedApp) {
        _finishOnboardingAndGoHome();
      }
    });
  }

  Widget _featureTile(bool isDark, IconData icon, String title, String subtitle, {double bottomSpacing = 16}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 21, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: isDark ? Colors.grey[400] : Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) {
          setState(() {
            _waitingForNotifDialog = false;
            _waitingForSmsDialog = false;
            _step -= 1;
          });
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Fin',
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0E1726),
                            fontWeight: FontWeight.w800,
                            fontSize: 26,
                          ),
                        ),
                        Text(
                          'Trax',
                          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w300, fontSize: 26),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4.5),
                      decoration: BoxDecoration(
                        color: scheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Step ${_step + 1} of 3',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: SingleChildScrollView(
                    child: _step == 0
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Container(
                                  width: 72,
                                  height: 72,
                                  margin: const EdgeInsets.only(top: 4),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.18),
                                        blurRadius: 12,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: Image.asset('logo.png', width: 72, height: 72, fit: BoxFit.cover),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Center(
                                child: Text(
                                  'Know Where Your Money Goes',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.25),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  'Tracking expenses shouldn\'t feel like homework. FinTrax keeps your daily money habits simple, private, and effortless.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 13, height: 1.45, color: isDark ? Colors.grey[300] : Colors.grey[800]),
                                ),
                              ),
                              const SizedBox(height: 20),
                              _featureTile(
                                isDark,
                                Icons.menu_book_rounded,
                                'Separate Books for Everything',
                                'Keep monthly bills, groceries, shopping, or money lent to friends neatly organized.',
                                bottomSpacing: 15,
                              ),
                              _featureTile(
                                isDark,
                                Icons.sms_outlined,
                                '1-Tap Bank & UPI Entries',
                                'Spots your bank and UPI alerts automatically so you don\'t have to type them out.',
                                bottomSpacing: 15,
                              ),
                              _featureTile(
                                isDark,
                                Icons.library_add_check_rounded,
                                'Multi-Book Logging & Monthly Insights',
                                'Save one expense into multiple books at once, export PDFs, and see a clear summary every month.',
                                bottomSpacing: 15,
                              ),
                              _featureTile(
                                isDark,
                                Icons.cloud_done_outlined,
                                'Biometric Lock & Google Drive Backup',
                                'Lock the app with your fingerprint and back up to your own Google Drive so your data stays safe even when switching phones.',
                                bottomSpacing: 18,
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppConstants.incomeGreen.withOpacity(isDark ? 0.12 : 0.08),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppConstants.incomeGreen.withOpacity(0.35)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.verified_user_rounded, color: AppConstants.incomeGreen, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Offline • Zero Data Collection • Zero Ads',
                                            maxLines: 1,
                                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppConstants.incomeGreen),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            'Everything stays on your phone. No servers, no tracking, and no ads.',
                                            style: TextStyle(fontSize: 11.8, height: 1.38, color: isDark ? Colors.grey[300] : Colors.grey[800]),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : _step == 1
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 10),
                                  Center(
                                    child: Container(
                                      width: 74,
                                      height: 74,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: scheme.primary.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(22),
                                      ),
                                      child: Icon(Icons.notifications_active_rounded, size: 36, color: scheme.primary),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Center(
                                    child: Text(
                                      'A Friendly 9:00 PM Check-In',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.25),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Text(
                                      'The easiest way to stay aware of your spending is taking 30 seconds at night to log today\'s expenses while you still remember them.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 13, height: 1.45, color: isDark ? Colors.grey[300] : Colors.grey[800]),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  _featureTile(
                                    isDark,
                                    Icons.schedule_rounded,
                                    'Daily Evening Reminder',
                                    'A quick nudge at 9:00 PM so small cash or UPI spends don\'t slip your mind. Change the time or turn it off anytime.',
                                    bottomSpacing: 20,
                                  ),
                                  _featureTile(
                                    isDark,
                                    Icons.insights_rounded,
                                    '1st-of-the-Month Recap',
                                    'Wake up on the 1st to a ready-made summary of last month\'s shopping, groceries, investments, and savings.',
                                    bottomSpacing: 20,
                                  ),
                                  _featureTile(
                                    isDark,
                                    Icons.do_not_disturb_on_outlined,
                                    'No Spam, Ever',
                                    'We never send promotional messages or unnecessary alerts—only the reminders you actually choose to enable.',
                                    bottomSpacing: 24,
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF161922) : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.tune_rounded, size: 20, color: scheme.primary),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'You are always in full control: change the check-in time or pause notifications anytime with one tap in Settings.',
                                            style: TextStyle(fontSize: 12, height: 1.4, color: isDark ? Colors.grey[300] : Colors.grey[700]),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 8),
                                  Center(
                                    child: Container(
                                      width: 74,
                                      height: 74,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: AppConstants.incomeGreen.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(22),
                                      ),
                                      child: const Icon(Icons.lock_outline_rounded, size: 36, color: AppConstants.incomeGreen),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Center(
                                    child: Text(
                                      'Save Time with Offline SMS Detection',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.25),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Text(
                                      'It\'s completely normal to be cautious about SMS permission. Here is how FinTrax uses it while keeping your messages 100% private:',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 13, height: 1.45, color: isDark ? Colors.grey[300] : Colors.grey[800]),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  _featureTile(
                                    isDark,
                                    Icons.bolt_rounded,
                                    'No More Manual Typing',
                                    'Spots bank debit and credit alerts to pre-fill the amount and merchant for you in one tap.',
                                    bottomSpacing: 16,
                                  ),
                                  _featureTile(
                                    isDark,
                                    Icons.receipt_long_rounded,
                                    'Original SMS Saved for Reference',
                                    'Automatically attaches the transaction SMS to your entry so you always have the payment reference.',
                                    bottomSpacing: 16,
                                  ),
                                  _featureTile(
                                    isDark,
                                    Icons.phonelink_lock_rounded,
                                    'Never Leaves Your Phone',
                                    'All scanning happens locally offline. FinTrax has no servers, so nobody can ever read your messages.',
                                    bottomSpacing: 16,
                                  ),
                                  _featureTile(
                                    isDark,
                                    Icons.shield_outlined,
                                    'OTPs & Personal Texts Ignored',
                                    'Personal chats and OTP codes are completely skipped—only bank transaction alerts are picked up.',
                                    bottomSpacing: 18,
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF161922) : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.offline_bolt_outlined, size: 20, color: AppConstants.incomeGreen),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'FinTrax operates 100% on-device. SMS detection works even in airplane mode with no internet connection.',
                                            style: TextStyle(fontSize: 12, height: 1.4, color: isDark ? Colors.grey[300] : Colors.grey[700]),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_step == 0)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() => _step = 1);
                    },
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Continue to Set Up', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                  )
                else if (_step == 1) ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    onPressed: () => _handleNotificationStep(true),
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Enable Reminders & Continue', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => _handleNotificationStep(false),
                    child: const Text('Skip for now', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                  ),
                ] else ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    onPressed: () => _handleSmsStep(true),
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('Allow SMS Auto-Track & Start', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => _handleSmsStep(false),
                    child: const Text('I\'ll enter expenses manually (Skip)', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// BOOKS & HOME SCREEN
// ===========================================================================
class BooksScreen extends StatefulWidget {
  const BooksScreen({Key? key}) : super(key: key);

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  static const MethodChannel _nativeBridge = MethodChannel('com.chandankumar.fintrack/sms');
  static const String _driveAppDataScope = 'https://www.googleapis.com/auth/drive.appdata';
  static const String _backupFileName = 'fintrax_cloud_backup.json';

  final GoogleSignIn _googleAuth = GoogleSignIn(
    scopes: <String>[_driveAppDataScope],
  );

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  int _tabIndex = 0;
  late final PageController _tabPageController = PageController(initialPage: 0);
  List<Map<String, dynamic>> _books = [];
  Map<int, Map<String, String>> _bookContacts = {};
  List<ParsedSmsTransaction> _pendingSms = [];
  bool _loading = false;
  bool _showOnboarding = false;
  bool _isSearchingBooks = false;
  String _bookSearchQuery = '';
  final TextEditingController _bookSearchController = TextEditingController();
  BookSort _sortOrder = BookSort.updated;
  Timer? _autoBackupTimer;

  @override
  void initState() {
    super.initState();
    AppLogger.instance.log('BooksScreen.initState() called.', tag: 'LIFECYCLE');
    FinTraxBrandHelper.dataRefreshNotifier.addListener(_loadBooks);
    _startupSequence();
  }

  @override
  void dispose() {
    FinTraxBrandHelper.dataRefreshNotifier.removeListener(_loadBooks);
    _autoBackupTimer?.cancel();
    _tabPageController.dispose();
    _bookSearchController.dispose();
    super.dispose();
  }

  Future<void> _startupSequence() async {
    Set<String> handledSet = <String>{};
    try {
      handledSet = await DatabaseHelper.instance
          .getHandledSmsIds()
          .timeout(const Duration(seconds: 2), onTimeout: () => <String>{});
    } catch (_) {}

    if (!handledSet.contains('__onboarding_v1_done__')) {
      if (mounted) {
        setState(() => _showOnboarding = true);
      }
      return;
    }

    await _loadBooks();
    if (mounted) {
      unawaited(_initBackgroundTasks(handledSet));
    }
  }

  Future<void> _initBackgroundTasks(Set<String> handledSet) async {
    if (!mounted) return;
    final prefs = Provider.of<ThemeProvider>(context, listen: false);

    for (int i = 0; i < 10 && !prefs.isInitialized; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (!mounted) return;

    try {
      final hasOsSmsPerm = await _nativeBridge.invokeMethod<bool>('checkSmsPermission') ?? false;
      final manuallyTurnedOff = handledSet.contains('__sms_manually_off__');
      if (hasOsSmsPerm && !manuallyTurnedOff && !prefs.smsAutoTrack) {
        await prefs.setSmsAutoTrack(true);
      }
    } catch (_) {}

    await _refreshSmsInbox();

    if (!handledSet.contains('__default_9pm_migrated__')) {
      if (prefs.reminderHour == 22 && prefs.reminderMinute == 0) {
        await prefs.setDailyReminder(
          enabled: prefs.dailyReminderEnabled,
          hour: 21,
          minute: 0,
        );
      }
      try {
        await DatabaseHelper.instance.markSmsHandled('__default_9pm_migrated__', 'done');
      } catch (_) {}
    }

    await AppLogger.instance.logRuntimeEnvironment(_googleAuth, prefs);

    try {
      await _nativeBridge.invokeMethod('scheduleDailyReminder', {
        'enabled': prefs.dailyReminderEnabled,
        'hour': prefs.reminderHour,
        'minute': prefs.reminderMinute,
      }).timeout(const Duration(seconds: 2));
    } catch (_) {}

    await _checkAndShowFirstOfMonthInsights(handledSet);
    unawaited(_runSilentDailyBackup());

    final now = DateTime.now();
    final nextRun = DateTime(now.year, now.month, now.day + 1, 0, 5);
    _autoBackupTimer?.cancel();
    _autoBackupTimer = Timer(nextRun.difference(now), _runSilentDailyBackup);
  }

  Future<void> _checkAndShowFirstOfMonthInsights(Set<String> handledSet) async {
    try {
      bool launchedFromInsightNotif = false;
      try {
        launchedFromInsightNotif = await _nativeBridge
                .invokeMethod<bool>('consumeMonthlyInsightIntent')
                .timeout(const Duration(seconds: 1)) ??
            false;
      } catch (_) {}

      final now = DateTime.now();
      final markerKey = '__monthly_insight_shown_${now.year}_${now.month}__';

      if (launchedFromInsightNotif) {
        await DatabaseHelper.instance.markSmsHandled(markerKey, 'shown');
        if (mounted) _openMonthlyInsightsSheet(initialPreviousMonth: true);
        return;
      }

      if (!handledSet.contains(markerKey)) {
        final prevMonthDate = DateTime(now.year, now.month - 1, 1);
        final insights = await DatabaseHelper.instance.getMonthlyInsights(prevMonthDate.year, prevMonthDate.month);
        final int txCount = (insights['txCount'] as int?) ?? 0;
        final double lendingGiven = (insights['lendingGiven'] as num?)?.toDouble() ?? 0.0;
        await DatabaseHelper.instance.markSmsHandled(markerKey, 'shown');
        if ((txCount > 0 || lendingGiven > 0) && mounted) {
          _openMonthlyInsightsSheet(initialPreviousMonth: true);
        }
      }
    } catch (_) {}
  }

  String _todayStamp() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _runSilentDailyBackup() async {
    final prefs = Provider.of<ThemeProvider>(context, listen: false);
    if (prefs.driveAccount.isEmpty) return;

    final currentBooks = await DatabaseHelper.instance.getBooksWithBalances();
    if (currentBooks.isEmpty) return;

    final today = _todayStamp();
    if (prefs.lastAutoBackupDay == today) return;

    try {
      final account = await _googleAuth.signInSilently();
      if (account == null) return;
      final headers = await account.authHeaders;
      final payload = await DatabaseHelper.instance.exportDatabaseJson();
      final uploadedId = await _pushBackupToDrive(headers, payload);
      if (uploadedId != null && uploadedId.isNotEmpty) {
        await prefs.recordBackupSuccess(
          isoTimestamp: DateTime.now().toIso8601String(),
          dayKey: today,
        );
      }
    } catch (_) {}
  }

  Future<void> _loadBooks() async {
    if (!mounted) return;
    try {
      final rows = await DatabaseHelper.instance
          .getBooksWithBalances()
          .timeout(const Duration(seconds: 2), onTimeout: () => <Map<String, dynamic>>[]);

      rows.sort((a, b) {
        final pinA = (a['isPinned'] ?? 0) as int;
        final pinB = (b['isPinned'] ?? 0) as int;
        if (pinA != pinB) return pinB.compareTo(pinA);

        final upA = DateTime.tryParse(a['updatedAt']?.toString() ?? '') ?? DateTime.now();
        final upB = DateTime.tryParse(b['updatedAt']?.toString() ?? '') ?? DateTime.now();
        final crA = DateTime.tryParse(a['createdAt']?.toString() ?? '') ?? upA;
        final crB = DateTime.tryParse(b['createdAt']?.toString() ?? '') ?? upB;

        switch (_sortOrder) {
          case BookSort.updated:
            return upB.compareTo(upA);
          case BookSort.created:
            return crB.compareTo(crA);
          case BookSort.aToZ:
            return a['name'].toString().toLowerCase().compareTo(b['name'].toString().toLowerCase());
          case BookSort.zToA:
            return b['name'].toString().toLowerCase().compareTo(a['name'].toString().toLowerCase());
        }
      });

      final contactsMap = await FinTraxBrandHelper.getAllBookContacts();
      if (mounted) {
        setState(() {
          _books = rows;
          _bookContacts = contactsMap;
          _loading = false;
        });
      }
      unawaited(_refreshSmsInbox());
    } catch (e) {
      AppLogger.instance.log('Book load error: $e', tag: 'ERROR');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshSmsInbox() async {
    if (!mounted) return;
    final prefs = Provider.of<ThemeProvider>(context, listen: false);
    try {
      final permitted = await _nativeBridge
              .invokeMethod<bool>('checkSmsPermission')
              .timeout(const Duration(seconds: 2), onTimeout: () => false) ??
          false;
      if (!permitted) {
        if (mounted) setState(() => _pendingSms = []);
        return;
      }

      final ignoredIds = await DatabaseHelper.instance.getHandledSmsIds();
      final manuallyOff = ignoredIds.contains('__sms_manually_off__');

      if (manuallyOff && !prefs.smsAutoTrack) {
        if (mounted) setState(() => _pendingSms = []);
        return;
      }

      if (!prefs.smsAutoTrack && !manuallyOff) {
        await prefs.setSmsAutoTrack(true);
      }

      final rawList = await _nativeBridge
              .invokeMethod<List<dynamic>>('getBankSms')
              .timeout(const Duration(seconds: 3), onTimeout: () => <dynamic>[]) ??
          [];

      final detected = <ParsedSmsTransaction>[];
      for (final item in rawList) {
        if (item is Map) {
          final parsed = ParsedSmsTransaction.tryParse(item);
          if (parsed != null && !ignoredIds.contains(parsed.smsId)) {
            detected.add(parsed);
          }
        }
      }
      if (mounted) setState(() => _pendingSms = detected);
    } catch (_) {}
  }

  // ===========================================================================
  // SMART CREATE & EDIT BOOK DIALOGS (WITH LENDING CONTACT PICKER)
  // ===========================================================================
  Future<Map<String, String>?> _pickContactFromPhone() async {
    try {
      final res = await _nativeBridge.invokeMethod<Map<dynamic, dynamic>>('pickContact');
      if (res == null) return null;
      return {
        'name': res['name']?.toString() ?? '',
        'phone': res['phone']?.toString() ?? '',
        'photoBase64': res['photoBase64']?.toString() ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  Future<int?> _promptCreateBook() async {
    HapticFeedback.lightImpact();
    final ctrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String pickedPhotoBase64 = '';
    String selectedBookType = 'standard';
    final currentMonthName = _monthNames[DateTime.now().month - 1];

    final suggestions = <Map<String, String>>[
      {'label': '$currentMonthName Expenses', 'type': 'standard', 'icon': '📅'},
      {'label': 'Grocery Expenses', 'type': 'standard', 'icon': '🛒'},
      {'label': 'Shopping Expenses', 'type': 'standard', 'icon': '🛍️'},
      {'label': 'Personal Expenses', 'type': 'standard', 'icon': '👤'},
      {'label': 'Money Lent', 'type': 'lending', 'icon': '🤝'},
      {'label': 'Home & Bills', 'type': 'standard', 'icon': '🏠'},
      {'label': 'Travel & Trips', 'type': 'standard', 'icon': '✈️'},
      {'label': 'Investments', 'type': 'standard', 'icon': '📈'},
    ];

    Widget buildCompactSuggestionChip({
      required Map<String, String> item,
      required bool isDark,
      required ColorScheme scheme,
      required StateSetter setDialogState,
    }) {
      final String label = item['label']!;
      final String type = item['type']!;
      final String icon = item['icon']!;
      final bool isSelected = ctrl.text.trim().toLowerCase() == label.toLowerCase();

      return Material(
        color: isSelected
            ? scheme.primary.withOpacity(isDark ? 0.25 : 0.14)
            : (isDark ? const Color(0xFF1A1D26) : const Color(0xFFF1F5F9)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected
                ? scheme.primary
                : (isDark ? AppConstants.borderDark : AppConstants.borderLight),
            width: isSelected ? 1.3 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            HapticFeedback.selectionClick();
            setDialogState(() {
              ctrl.text = label;
              ctrl.selection = TextSelection.fromPosition(TextPosition(offset: ctrl.text.length));
              selectedBookType = type;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final scheme = Theme.of(ctx).colorScheme;

          final List<Widget> suggestionRows = [];
          for (int i = 0; i < suggestions.length; i += 2) {
            final first = suggestions[i];
            final second = (i + 1 < suggestions.length) ? suggestions[i + 1] : null;
            suggestionRows.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: buildCompactSuggestionChip(
                        item: first,
                        isDark: isDark,
                        scheme: scheme,
                        setDialogState: setDialogState,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: second != null
                          ? buildCompactSuggestionChip(
                              item: second,
                              isDark: isDark,
                              scheme: scheme,
                              setDialogState: setDialogState,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            );
          }

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: const Text('Create New Book', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
            content: SizedBox(
              width: MediaQuery.of(ctx).size.width,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'e.g., $currentMonthName Expenses',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'BOOK TYPE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setDialogState(() => selectedBookType = 'standard');
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                              decoration: BoxDecoration(
                                color: selectedBookType == 'standard'
                                    ? scheme.primary.withOpacity(isDark ? 0.22 : 0.12)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selectedBookType == 'standard'
                                      ? scheme.primary
                                      : (isDark ? AppConstants.borderDark : AppConstants.borderLight),
                                  width: selectedBookType == 'standard' ? 1.4 : 1.0,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.book_rounded, size: 15, color: selectedBookType == 'standard' ? scheme.primary : Colors.grey),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      'Expense Book',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: selectedBookType == 'standard' ? FontWeight.w800 : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setDialogState(() => selectedBookType = 'lending');
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                              decoration: BoxDecoration(
                                color: selectedBookType == 'lending'
                                    ? AppConstants.goldAccent.withOpacity(isDark ? 0.22 : 0.14)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selectedBookType == 'lending'
                                      ? AppConstants.goldAccent
                                      : (isDark ? AppConstants.borderDark : AppConstants.borderLight),
                                  width: selectedBookType == 'lending' ? 1.4 : 1.0,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.handshake_rounded,
                                    size: 15,
                                    color: selectedBookType == 'lending' ? AppConstants.goldAccent : Colors.grey,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      'Lending Ledger',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: selectedBookType == 'lending' ? FontWeight.w800 : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (selectedBookType == 'lending') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Contact Number (Optional)',
                          hintText: 'Enter or import from contacts',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          suffixIcon: IconButton(
                            tooltip: 'Import from Contacts',
                            icon: Icon(Icons.contacts_rounded, color: scheme.primary),
                            onPressed: () async {
                              HapticFeedback.selectionClick();
                              final picked = await _pickContactFromPhone();
                              if (picked != null) {
                                setDialogState(() {
                                  phoneCtrl.text = picked['phone'] ?? '';
                                  pickedPhotoBase64 = picked['photoBase64'] ?? '';
                                  if (ctrl.text.trim().isEmpty && (picked['name'] ?? '').isNotEmpty) {
                                    ctrl.text = picked['name']!;
                                  }
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'QUICK SUGGESTIONS',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.0, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 6),
                    ...suggestionRows,
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  final title = ctrl.text.trim();
                  if (title.isEmpty) return;
                  final now = DateTime.now();
                  final id = await DatabaseHelper.instance.insertBook(
                    BookModel(
                      name: title,
                      createdAt: now,
                      updatedAt: now,
                      bookType: selectedBookType,
                    ),
                  );
                  if (id == -1) {
                    HapticFeedback.heavyImpact();
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('A book with this name already exists.'),
                          backgroundColor: AppConstants.expenseRed,
                        ),
                      );
                    }
                  } else {
                    if (selectedBookType == 'lending') {
                      await FinTraxBrandHelper.saveBookContact(id, phoneCtrl.text, pickedPhotoBase64);
                    }
                    HapticFeedback.mediumImpact();
                    await _loadBooks();
                    if (ctx.mounted) Navigator.pop(ctx, id);
                  }
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _promptRenameBook(int id, String oldName, String currentType) async {
    final existingContact = await FinTraxBrandHelper.getBookContact(id);
    if (!mounted) return;
    final ctrl = TextEditingController(text: oldName);
    final phoneCtrl = TextEditingController(text: existingContact['phone'] ?? '');
    String pickedPhotoBase64 = existingContact['photoBase64'] ?? '';
    String selectedType = currentType;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Rename / Edit Book', style: TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Lending Ledger', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  subtitle: const Text('Mark this book for money lent/borrowed', style: TextStyle(fontSize: 11)),
                  value: selectedType == 'lending',
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    setDialogState(() => selectedType = v ? 'lending' : 'standard');
                  },
                ),
                if (selectedType == 'lending') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Contact Number (Optional)',
                      hintText: 'Enter or import from contacts',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: IconButton(
                        tooltip: 'Import from Contacts',
                        icon: Icon(Icons.contacts_rounded, color: Theme.of(ctx).colorScheme.primary),
                        onPressed: () async {
                          HapticFeedback.selectionClick();
                          final picked = await _pickContactFromPhone();
                          if (picked != null) {
                            setDialogState(() {
                              phoneCtrl.text = picked['phone'] ?? '';
                              pickedPhotoBase64 = picked['photoBase64'] ?? '';
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final updated = ctrl.text.trim();
                if (updated.isNotEmpty) {
                  final res = await DatabaseHelper.instance.updateBookName(id, updated, bookType: selectedType);
                  if (res == -1) {
                    HapticFeedback.heavyImpact();
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('A book with this name already exists.'),
                          backgroundColor: AppConstants.expenseRed,
                        ),
                      );
                    }
                    return;
                  }
                  if (selectedType == 'lending') {
                    await FinTraxBrandHelper.saveBookContact(id, phoneCtrl.text, pickedPhotoBase64);
                  }
                  HapticFeedback.mediumImpact();
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadBooks();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndDeleteBookWithUndo(int bookId, String bookName) async {
    HapticFeedback.mediumImpact();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Do you want to delete?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: Text(
          'Delete "$bookName" and all its entries?',
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
      final db = await DatabaseHelper.instance.database;
      final bookRows = await db.query('books', where: 'id = ?', whereArgs: [bookId]);
      final txRows = await db.query('transactions', where: 'bookId = ?', whereArgs: [bookId]);

      await DatabaseHelper.instance.deleteBook(bookId);
      await _loadBooks();
      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('Deleted "$bookName"'),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: AppConstants.goldAccent,
            onPressed: () async {
              final restoreDb = await DatabaseHelper.instance.database;
              if (bookRows.isNotEmpty) {
                await restoreDb.insert('books', Map<String, Object?>.from(bookRows.first));
              }
              for (final tx in txRows) {
                await restoreDb.insert('transactions', Map<String, Object?>.from(tx));
              }
              await _loadBooks();
            },
          ),
        ),
      );
    }
  }

  // ===========================================================================
  // MONTHLY FINANCIAL INSIGHTS MODAL (WITH INVESTMENT HIGHLIGHT)
  // ===========================================================================
  void _openMonthlyInsightsSheet({bool initialPreviousMonth = true}) {
    HapticFeedback.lightImpact();
    bool showPrevMonth = initialPreviousMonth;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final scheme = Theme.of(ctx).colorScheme;
          final now = DateTime.now();
          final targetDate = showPrevMonth
              ? DateTime(now.year, now.month - 1, 1)
              : DateTime(now.year, now.month, 1);
          final monthTitle = '${_monthNames[targetDate.month - 1]} ${targetDate.year}';

          return Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.86),
            decoration: BoxDecoration(
              color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: scheme.primary.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.insights_rounded, color: scheme.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$monthTitle Insights',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                              ),
                              Text(
                                showPrevMonth ? 'Previous Month Financial Summary' : 'Current Month Live Summary',
                                style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(sheetCtx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: true,
                          label: Text(
                            'Last Month (${_monthNames[DateTime(now.year, now.month - 1, 1).month - 1]})',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text(
                            'This Month (${_monthNames[now.month - 1]})',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                      selected: {showPrevMonth},
                      onSelectionChanged: (sel) {
                        HapticFeedback.selectionClick();
                        setSheetState(() => showPrevMonth = sel.first);
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Divider(height: 1),
                  Flexible(
                    child: FutureBuilder<Map<String, dynamic>>(
                      future: DatabaseHelper.instance.getMonthlyInsights(targetDate.year, targetDate.month),
                      builder: (ctx, snap) {
                        if (!snap.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final data = snap.data!;
                        final double totalIn = (data['totalIncome'] as num?)?.toDouble() ?? 0.0;
                        final double totalOut = (data['totalExpense'] as num?)?.toDouble() ?? 0.0;
                        final double netFlow = (data['netFlow'] as num?)?.toDouble() ?? 0.0;
                        final double shoppingSpend = (data['shoppingSpend'] as num?)?.toDouble() ?? 0.0;
                        final double grocerySpend = (data['grocerySpend'] as num?)?.toDouble() ?? 0.0;
                        final double foodSpend = (data['foodSpend'] as num?)?.toDouble() ?? 0.0;
                        final double lendingGiven = (data['lendingGiven'] as num?)?.toDouble() ?? 0.0;
                        final int txCount = (data['txCount'] as int?) ?? 0;
                        final List<dynamic> cats = (data['categoryBreakdown'] as List<dynamic>?) ?? [];
                        final List<dynamic> booksBreak = (data['bookBreakdown'] as List<dynamic>?) ?? [];

                        double investmentSpend = (data['investmentSpend'] as num?)?.toDouble() ?? 0.0;
                        if (investmentSpend == 0.0) {
                          for (final c in cats) {
                            final String cName = c['name']?.toString().toLowerCase() ?? '';
                            if (cName == 'investment' || cName == 'investments') {
                              investmentSpend += (c['amount'] as num?)?.toDouble() ?? 0.0;
                            }
                          }
                        }

                        if (txCount == 0 && lendingGiven == 0) {
                          return Padding(
                            padding: const EdgeInsets.all(36),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.insert_chart_outlined, size: 48, color: Colors.grey[500]),
                                const SizedBox(height: 12),
                                Text(
                                  'No entries logged for $monthTitle',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Keep logging your daily expenses to unlock rich monthly insights!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12.5, color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView(
                          padding: const EdgeInsets.all(18),
                          shrinkWrap: true,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _insightMetricCard(
                                    isDark: isDark,
                                    title: 'Total Income',
                                    amount: totalIn,
                                    color: AppConstants.incomeGreen,
                                    prefix: '+',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _insightMetricCard(
                                    isDark: isDark,
                                    title: 'Total Spent',
                                    amount: totalOut,
                                    color: AppConstants.expenseRed,
                                    prefix: '-',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF171A24) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Net Monthly Savings / Flow ($txCount unique ${txCount == 1 ? 'entry' : 'entries'})',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[500]),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${netFlow < 0 ? '-' : '+'}${AppConstants.defaultCurrency}${netFlow.abs().toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                      color: netFlow < 0 ? AppConstants.expenseRed : AppConstants.incomeGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'KEY SPENDING & INVESTMENT HIGHLIGHTS',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Colors.grey[500]),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _highlightPill(
                                    isDark: isDark,
                                    emoji: '📈',
                                    label: 'Investment',
                                    amount: investmentSpend,
                                    highlightGreen: true,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _highlightPill(
                                    isDark: isDark,
                                    emoji: '🛍️',
                                    label: 'Shopping',
                                    amount: shoppingSpend,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _highlightPill(
                                    isDark: isDark,
                                    emoji: '🛒',
                                    label: 'Groceries',
                                    amount: grocerySpend,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _highlightPill(
                                    isDark: isDark,
                                    emoji: '🍽️',
                                    label: 'Food & Dining',
                                    amount: foodSpend,
                                  ),
                                ),
                              ],
                            ),
                            if (cats.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Text(
                                'CATEGORY BREAKDOWN',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Colors.grey[500]),
                              ),
                              const SizedBox(height: 8),
                              ...cats.take(6).map((c) {
                                final String cName = c['name'].toString();
                                final bool isInv = cName.toLowerCase() == 'investment';
                                final double cAmt = (c['amount'] as num).toDouble();
                                final double pct = totalOut > 0 ? (cAmt / totalOut).clamp(0.0, 1.0) : 0.0;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            isInv ? '📈 $cName' : cName,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: isInv ? AppConstants.incomeGreen : null,
                                            ),
                                          ),
                                          Text(
                                            '${AppConstants.defaultCurrency}${cAmt.toStringAsFixed(0)} (${(pct * 100).toStringAsFixed(0)}%)',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                              color: isInv ? AppConstants.incomeGreen : null,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: LinearProgressIndicator(
                                          value: pct,
                                          minHeight: 6,
                                          backgroundColor: isDark ? Colors.white10 : Colors.black12,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            isInv ? AppConstants.incomeGreen : scheme.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                            if (booksBreak.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                'SPENDING BY BOOK',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Colors.grey[500]),
                              ),
                              const SizedBox(height: 8),
                              ...booksBreak.map((b) {
                                final String bName = b['name'].toString();
                                final double bAmt = (b['amount'] as num).toDouble();
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.book_outlined, size: 15, color: scheme.primary),
                                          const SizedBox(width: 8),
                                          Text(bName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                      Text(
                                        '${AppConstants.defaultCurrency}${bAmt.toStringAsFixed(0)}',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppConstants.expenseRed),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ],
                        );
                      },
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

  Widget _insightMetricCard({
    required bool isDark,
    required String title,
    required double amount,
    required Color color,
    required String prefix,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 6),
          Text(
            '$prefix${AppConstants.defaultCurrency}${amount.toStringAsFixed(0)}',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  Widget _highlightPill({
    required bool isDark,
    required String emoji,
    required String label,
    required double amount,
    bool highlightGreen = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
      decoration: BoxDecoration(
        color: highlightGreen
            ? AppConstants.incomeGreen.withOpacity(isDark ? 0.14 : 0.08)
            : (isDark ? const Color(0xFF171A24) : const Color(0xFFF8FAFC)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlightGreen
              ? AppConstants.incomeGreen.withOpacity(0.55)
              : (isDark ? AppConstants.borderDark : AppConstants.borderLight),
          width: highlightGreen ? 1.3 : 1.0,
        ),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: highlightGreen ? AppConstants.incomeGreen : Colors.grey[500],
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${AppConstants.defaultCurrency}${amount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: highlightGreen ? AppConstants.incomeGreen : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openBookMenu(int bookId, String bookName, int pinned, String bookType) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(bookName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const Divider(),
              ListTile(
                leading: Icon(pinned == 1 ? Icons.push_pin_outlined : Icons.push_pin),
                title: Text(pinned == 1 ? 'Unpin from Top' : 'Pin to Top'),
                onTap: () async {
                  HapticFeedback.lightImpact();
                  await DatabaseHelper.instance.togglePinBook(bookId, pinned == 0);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadBooks();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename / Change Book Type'),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx);
                  _promptRenameBook(bookId, bookName, bookType);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share as PDF'),
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(ctx);
                  final pdfBytes = await DashboardScreen.generateBookPdfBytes(bookId, bookName);
                  await Printing.sharePdf(bytes: pdfBytes, filename: '${bookName}_FinTrax_Statement.pdf');
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Export & Save as PDF'),
                subtitle: const Text('Save PDF statement to Downloads folder', style: TextStyle(fontSize: 11.5)),
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(ctx);
                  final pdfBytes = await DashboardScreen.generateBookPdfBytes(bookId, bookName);
                  final ok = await _nativeBridge.invokeMethod<bool>('savePdfToDownloads', {
                        'bytes': pdfBytes,
                        'fileName': '${bookName}_FinTrax_Statement.pdf',
                      }) ??
                      false;
                  if (mounted && ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('PDF saved to Downloads successfully!'),
                        backgroundColor: AppConstants.incomeGreen,
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppConstants.expenseRed),
                title: const Text('Delete Book', style: TextStyle(color: AppConstants.expenseRed)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmAndDeleteBookWithUndo(bookId, bookName);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _askDismissAllConfirmation(int total) async {
    HapticFeedback.mediumImpact();
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppConstants.expenseRed),
            SizedBox(width: 10),
            Expanded(child: Text('Dismiss All SMS?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
          ],
        ),
        content: Text(
          'Dismiss all $total detected SMS transactions?\n\nOnce dismissed, they will not appear in suggestions again. Only new future bank messages will be shown.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConstants.expenseRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dismiss All'),
          ),
        ],
      ),
    );
    return res == true;
  }

  void _openSmsReviewSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, updateSheet) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          if (_pendingSms.isEmpty) {
            return const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('All detected SMS transactions have been reviewed!')),
              ),
            );
          }
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.78),
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
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Detected Bank SMS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              Text('${_pendingSms.length} pending', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            if (!await _askDismissAllConfirmation(_pendingSms.length)) return;
                            HapticFeedback.heavyImpact();
                            final ids = _pendingSms.map((e) => e.smsId).toList();
                            await DatabaseHelper.instance.markMultipleSmsHandled(ids, 'dismissed');
                            updateSheet(() => _pendingSms.clear());
                            if (mounted) setState(() {});
                            if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                          },
                          icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: AppConstants.expenseRed),
                          label: const Text(
                            'Dismiss All',
                            style: TextStyle(color: AppConstants.expenseRed, fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _pendingSms.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final item = _pendingSms[i];
                        final isCredit = item.type == 'Income';

                        final String resolvedTitle = FinTraxBrandHelper.resolveMerchantTitle(item.merchant, item.body);
                        final String resolvedMode = FinTraxBrandHelper.detectPaymentMethod(
                          currentMode: item.paymentMode,
                          smsBody: item.body,
                          sender: item.merchant,
                        );
                        final String? bankIconAsset = FinTraxBrandHelper.getPaymentIconAsset(
                          resolvedMode,
                          smsBody: item.body,
                          sender: item.merchant,
                        );
                        final String? autoCat = FinTraxBrandHelper.detectCategory(
                          resolvedTitle,
                          smsBody: item.body,
                        );

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  resolvedTitle,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${isCredit ? '+' : '-'}${AppConstants.defaultCurrency}${item.amount.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isCredit ? AppConstants.incomeGreen : AppConstants.expenseRed,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(item.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: bankIconAsset != null ? 5 : 7,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: bankIconAsset != null
                                        ? FinTraxBrandHelper.buildIconBadge(
                                            assetPath: bankIconAsset,
                                            fallbackEmoji: FinTraxBrandHelper.getPaymentEmoji(resolvedMode),
                                            size: 16,
                                            borderRadius: 3,
                                          )
                                        : Text(
                                            resolvedMode,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: isDark ? Colors.grey[300] : Colors.grey[800],
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${autoCat != null ? '$autoCat • ' : ''}${AppConstants.formatOrdinalDateTime(item.date)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppConstants.expenseRed,
                                      backgroundColor: AppConstants.expenseRed.withOpacity(0.08),
                                      side: BorderSide(color: AppConstants.expenseRed.withOpacity(0.45), width: 1),
                                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                                      minimumSize: const Size(0, 33),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                    ),
                                    onPressed: () async {
                                      HapticFeedback.selectionClick();
                                      await DatabaseHelper.instance.markSmsHandled(item.smsId, 'dismissed');
                                      updateSheet(() => _pendingSms.removeAt(i));
                                      setState(() {});
                                    },
                                    child: const Text(
                                      'Dismiss',
                                      style: TextStyle(
                                        color: AppConstants.expenseRed,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  FilledButton.tonal(
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      minimumSize: const Size(0, 33),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                    ),
                                    onPressed: () => _assignSmsToBook(item, () => updateSheet(() => _pendingSms.removeAt(i))),
                                    child: const Text('Review & Add', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
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

  Future<void> _assignSmsToBook(ParsedSmsTransaction sms, VoidCallback onComplete) async {
    int? targetBookId;
    if (_books.isEmpty) {
      targetBookId = await _promptCreateBook();
      if (targetBookId == null) return;
    } else if (_books.length == 1) {
      targetBookId = _books.first['id'] as int;
    } else {
      targetBookId = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Select Book', style: TextStyle(fontWeight: FontWeight.w700)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          children: [
            ..._books.map(
              (b) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, b['id'] as int),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        (b['bookType']?.toString() ?? 'standard') == 'lending'
                            ? Icons.handshake_rounded
                            : Icons.book_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(b['name'].toString(), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, -999),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      'Create New Book',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
      if (targetBookId == -999) {
        targetBookId = await _promptCreateBook();
      }
    }

    if (targetBookId != null && targetBookId > 0 && mounted) {
      HapticFeedback.lightImpact();
      final String resolvedTitle = FinTraxBrandHelper.resolveMerchantTitle(sms.merchant, sms.body);
      final String resolvedMode = FinTraxBrandHelper.detectPaymentMethod(
        currentMode: sms.paymentMode,
        smsBody: sms.body,
        sender: sms.merchant,
      );
      final String autoCategory = FinTraxBrandHelper.detectCategory(
            resolvedTitle,
            smsBody: sms.body,
          ) ??
          '';

      final draft = TransactionModel(
        id: null,
        bookId: targetBookId,
        type: sms.type,
        amount: sms.amount,
        name: resolvedTitle,
        category: autoCategory,
        notes: '',
        smsBody: sms.body,
        date: sms.date,
        currency: AppConstants.defaultCurrency,
        paymentMode: resolvedMode,
      );

      final added = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => AddTransactionScreen(
            bookId: targetBookId!,
            type: sms.type,
            existingTransaction: draft,
            isSmsDraft: true,
          ),
        ),
      );

      if (added == true) {
        await DatabaseHelper.instance.markSmsHandled(sms.smsId, 'added');
        onComplete();
        _loadBooks();
      }
    }
  }

  // ===========================================================================
  // GOOGLE DRIVE CLOUD SYNC
  // ===========================================================================
  void _showProgressModal(String label) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Row(
          children: [
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.8)),
            const SizedBox(width: 18),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }

  void _showErrorModal(String heading, String body) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppConstants.expenseRed),
            const SizedBox(width: 10),
            Expanded(child: Text(heading, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          ],
        ),
        content: SingleChildScrollView(child: Text(body, style: const TextStyle(fontSize: 13, height: 1.45))),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DebugLogsScreen()));
            },
            icon: const Icon(Icons.bug_report_outlined, size: 18),
            label: const Text('View Logs'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<GoogleSignInAccount?> _signInForDrive(ThemeProvider prefs, {bool switchAccount = false}) async {
    final certInfo = await AppLogger.instance.logRuntimeEnvironment(_googleAuth, prefs);
    final livePkg = certInfo['packageName'] ?? 'com.chandsy.fintrax';
    final liveSha1 = certInfo['sha1'] ?? 'UNKNOWN';

    try {
      if (switchAccount) {
        await _googleAuth.signOut();
      }
      GoogleSignInAccount? user = _googleAuth.currentUser;
      if (user == null && !switchAccount) {
        user = await _googleAuth.signInSilently();
      }
      user ??= await _googleAuth.signIn();

      if (user == null) {
        AppLogger.instance.log('User cancelled account picker.', tag: 'WARN');
        return null;
      }

      await user.authHeaders;
      await prefs.setDriveAccount(user.email);
      AppLogger.instance.log('Google Sign-In succeeded for ${user.email}', tag: 'AUTH');
      return user;
    } on PlatformException catch (e) {
      AppLogger.instance.log('PlatformException (${e.code}): ${e.message}', tag: 'ERROR');
      if (mounted) {
        _showErrorModal(
          'Google Sign-In Blocked (${e.code})',
          'Google Play Services rejected the sign-in: ${e.message ?? e.code}\n\n'
          'Live APK Package: $livePkg\n'
          'Live APK SHA-1:\n$liveSha1\n\n'
          'If this account is not yet added under Google Cloud Console -> Audience -> Test Users, add the email there while the app is in Testing mode.',
        );
      }
      return null;
    } catch (e) {
      AppLogger.instance.log('Sign-in error: $e', tag: 'ERROR');
      if (mounted) _showErrorModal('Google Sign-In Error', e.toString());
      return null;
    }
  }

  Future<String?> _locateBackupFileId(Map<String, String> headers) async {
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'spaces': 'appDataFolder',
      'q': "name = '$_backupFileName' and trashed = false",
      'fields': 'files(id,name,modifiedTime)',
      'pageSize': '1',
    });
    final resp = await http.get(uri, headers: headers);
    if (resp.statusCode != 200) {
      throw Exception('Drive list failed (${resp.statusCode}): ${resp.body}');
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (decoded['files'] as List<dynamic>?) ?? [];
    if (list.isEmpty) return null;
    return (list.first as Map<String, dynamic>)['id']?.toString();
  }

  Future<String?> _pushBackupToDrive(Map<String, String> headers, String jsonPayload) async {
    String? fileId = await _locateBackupFileId(headers);

    if (fileId == null) {
      final createUri = Uri.parse('https://www.googleapis.com/drive/v3/files');
      final createResp = await http.post(
        createUri,
        headers: {...headers, 'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'name': _backupFileName,
          'parents': ['appDataFolder'],
        }),
      );
      if (createResp.statusCode != 200 && createResp.statusCode != 201) {
        throw Exception('Drive create failed (${createResp.statusCode}): ${createResp.body}');
      }
      final created = jsonDecode(createResp.body) as Map<String, dynamic>;
      fileId = created['id']?.toString();
    }

    if (fileId == null || fileId.isEmpty) {
      throw Exception('Could not obtain Google Drive file ID.');
    }

    final uploadUri = Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$fileId?uploadType=media');
    final uploadResp = await http.patch(
      uploadUri,
      headers: {...headers, 'Content-Type': 'application/json; charset=UTF-8'},
      body: utf8.encode(jsonPayload),
    );
    if (uploadResp.statusCode != 200) {
      throw Exception('Drive upload failed (${uploadResp.statusCode}): ${uploadResp.body}');
    }
    return fileId;
  }

  Future<String?> _pullBackupFromDrive(Map<String, String> headers) async {
    final fileId = await _locateBackupFileId(headers);
    if (fileId == null || fileId.isEmpty) return null;

    final downloadUri = Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
    final resp = await http.get(downloadUri, headers: headers);
    if (resp.statusCode != 200) {
      throw Exception('Drive download failed (${resp.statusCode}): ${resp.body}');
    }
    return utf8.decode(resp.bodyBytes);
  }

  Future<void> _onSwitchDriveAccount(ThemeProvider prefs) async {
    HapticFeedback.lightImpact();
    final user = await _signInForDrive(prefs, switchAccount: true);
    if (user == null || !mounted) return;

    _showProgressModal('Checking Google Drive for ${user.email}...');
    try {
      final headers = await user.authHeaders;
      final existing = await _pullBackupFromDrive(headers);
      if (mounted) Navigator.pop(context);

      if (existing != null && existing.isNotEmpty) {
        final decoded = jsonDecode(existing) as Map<String, dynamic>;
        final ts = decoded['exportedAt']?.toString() ?? '';
        if (ts.isNotEmpty) {
          await prefs.recordBackupSuccess(isoTimestamp: ts, dayKey: prefs.lastAutoBackupDay);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connected to ${user.email} • Existing cloud backup found!'),
              backgroundColor: AppConstants.incomeGreen,
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connected to ${user.email}')));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) _showErrorModal('Google Drive Connection Error', e.toString());
    }
  }

  Future<void> _onBackupNow(ThemeProvider prefs) async {
    HapticFeedback.mediumImpact();
    final user = await _signInForDrive(prefs);
    if (user == null || !mounted) return;

    _showProgressModal('Uploading backup to Google Drive...');
    try {
      final headers = await user.authHeaders;
      final payload = await DatabaseHelper.instance.exportDatabaseJson();
      final fileId = await _pushBackupToDrive(headers, payload);
      if (mounted) Navigator.pop(context);

      if (fileId != null && fileId.isNotEmpty) {
        await prefs.recordBackupSuccess(
          isoTimestamp: DateTime.now().toIso8601String(),
          dayKey: _todayStamp(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cloud Backup saved to Google Drive (${user.email})'),
              backgroundColor: AppConstants.incomeGreen,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) _showErrorModal('Google Drive Backup Failed', e.toString());
    }
  }

  Future<void> _onRestoreNow(ThemeProvider prefs) async {
    HapticFeedback.mediumImpact();
    final user = await _signInForDrive(prefs);
    if (user == null || !mounted) return;

    _showProgressModal('Checking Google Drive Cloud...');
    String? rawJson;
    try {
      final headers = await user.authHeaders;
      rawJson = await _pullBackupFromDrive(headers);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) _showErrorModal('Google Drive Restore Error', e.toString());
      return;
    }

    if (!mounted) return;

    if (rawJson == null || rawJson.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('No Backup Found', style: TextStyle(fontWeight: FontWeight.w700)),
          content: Text('No FinTrax backup was found on Google Drive for ${user.email}.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    String backupDateText = 'Unknown date';
    String exportedIso = '';
    int bookTotal = 0;
    int txTotal = 0;
    try {
      final parsed = jsonDecode(rawJson) as Map<String, dynamic>;
      exportedIso = parsed['exportedAt']?.toString() ?? '';
      final dt = DateTime.tryParse(exportedIso);
      if (dt != null) backupDateText = AppConstants.formatOrdinalDateTime(dt);
      bookTotal = ((parsed['books'] as List<dynamic>?) ?? []).length;
      txTotal = ((parsed['transactions'] as List<dynamic>?) ?? []).length;
    } catch (_) {}

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Google Drive Backup Found', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text(
          'Account: ${user.email}\nLast Backup: $backupDateText\nContents: $bookTotal Book(s), $txTotal Entries\n\nRestore this cloud backup into FinTrax?',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore Now')),
        ],
      ),
    );

    if (confirmed == true) {
      final count = await DatabaseHelper.instance.importDatabaseJson(rawJson);
      if (exportedIso.isNotEmpty) {
        await prefs.recordBackupSuccess(isoTimestamp: exportedIso, dayKey: _todayStamp());
      }
      await _loadBooks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restored $count book(s) from Google Drive (${user.email})!'),
            backgroundColor: AppConstants.incomeGreen,
          ),
        );
      }
    }
  }

  Future<void> _toggleBiometricLock(ThemeProvider prefs, bool enabled) async {
    if (!enabled) {
      await prefs.setAppLock(false);
      return;
    }
    final secure = await _nativeBridge.invokeMethod<bool>('isDeviceSecure') ?? false;
    if (!secure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please set up a Fingerprint or Screen Lock in your phone settings first.')),
        );
      }
      return;
    }
    final authenticated = await _nativeBridge.invokeMethod<bool>('authenticateDevice') ?? false;
    if (authenticated) {
      HapticFeedback.mediumImpact();
      await prefs.setAppLock(true);
    }
  }

  Future<void> _selectReminderTime(ThemeProvider prefs) async {
    HapticFeedback.selectionClick();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: prefs.reminderHour, minute: prefs.reminderMinute),
    );
    if (picked != null) {
      await prefs.setDailyReminder(enabled: true, hour: picked.hour, minute: picked.minute);
      await _nativeBridge.invokeMethod('scheduleDailyReminder', {
        'enabled': true,
        'hour': picked.hour,
        'minute': picked.minute,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Daily reminder set for ${AppConstants.formatTimeOfDay(picked.hour, picked.minute)}')),
        );
      }
    }
  }

  Widget _buildHeaderLogo(bool isDark, bool dynamicColors) {
    final finColor = isDark ? Colors.white : const Color(0xFF0E1726);
    final traxColor = dynamicColors
        ? Theme.of(context).colorScheme.primary
        : (isDark ? AppConstants.goldAccent : AppConstants.goldDarkText);

    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Fin', style: TextStyle(color: finColor, fontWeight: FontWeight.w800, fontSize: 27, letterSpacing: 0.2, height: 1.0)),
              Text('Trax', style: TextStyle(color: traxColor, fontWeight: FontWeight.w300, fontSize: 27, letterSpacing: 0.5, height: 1.0)),
            ],
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: 0,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              child: Text(
                AppConstants.appTagline,
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBooksTab(bool isDark, bool dynamicColors) {
    final scheme = Theme.of(context).colorScheme;
    final accent = dynamicColors ? scheme.primary : AppConstants.goldAccent;
    final now = DateTime.now();
    final prevMonthName = _monthNames[DateTime(now.year, now.month - 1, 1).month - 1];

    final query = _bookSearchQuery.trim().toLowerCase();
    final digitsQuery = query.replaceAll(RegExp(r'[^0-9]'), '');
    final filteredBooks = query.isEmpty
        ? _books
        : _books.where((b) {
            final nameMatch = b['name'].toString().toLowerCase().contains(query);
            final bookId = b['id'] as int;
            final savedPhone = (_bookContacts[bookId]?['phone'] ?? '').toLowerCase();
            final savedDigits = savedPhone.replaceAll(RegExp(r'[^0-9]'), '');
            final phoneMatch = savedPhone.contains(query) ||
                (digitsQuery.isNotEmpty && savedDigits.contains(digitsQuery));
            return nameMatch || phoneMatch;
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: _isSearchingBooks
            ? TextField(
                controller: _bookSearchController,
                autofocus: true,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  hintText: 'Search books or phone number...',
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _bookSearchQuery = val),
              )
            : _buildHeaderLogo(isDark, dynamicColors),
        actions: [
          IconButton(
            tooltip: _isSearchingBooks ? 'Close Search' : 'Search Books',
            icon: Icon(_isSearchingBooks ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (_isSearchingBooks) {
                  _isSearchingBooks = false;
                  _bookSearchQuery = '';
                  _bookSearchController.clear();
                } else {
                  _isSearchingBooks = true;
                }
              });
            },
          ),
          IconButton(
            tooltip: 'Monthly Financial Insights',
            icon: const Icon(Icons.insights_rounded),
            onPressed: () => _openMonthlyInsightsSheet(initialPreviousMonth: true),
          ),
          PopupMenuButton<BookSort>(
            icon: const Icon(Icons.sort_rounded),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (choice) {
              HapticFeedback.selectionClick();
              setState(() => _sortOrder = choice);
              _loadBooks();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: BookSort.updated, child: Text('Recently Updated')),
              PopupMenuItem(value: BookSort.created, child: Text('Recently Created')),
              PopupMenuItem(value: BookSort.aToZ, child: Text('Name (A to Z)')),
              PopupMenuItem(value: BookSort.zToA, child: Text('Name (Z to A)')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (now.day <= 5 && _books.isNotEmpty && !_isSearchingBooks)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Material(
                color: scheme.primary.withOpacity(isDark ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _openMonthlyInsightsSheet(initialPreviousMonth: true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(
                      children: [
                        Icon(Icons.insights_rounded, size: 20, color: scheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your $prevMonthName Expense Insights are ready!',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                          ),
                        ),
                        Text('View', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 12.5)),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios_rounded, size: 11, color: scheme.primary),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_pendingSms.isNotEmpty && !_isSearchingBooks)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Material(
                color: accent.withOpacity(isDark ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _openSmsReviewSheet,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.sms_outlined, size: 20, color: accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${_pendingSms.length} Bank SMS transaction${_pendingSms.length == 1 ? '' : 's'} found',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                        Text('Review', style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios_rounded, size: 12, color: accent),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _books.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.menu_book_rounded, size: 56, color: accent.withOpacity(0.45)),
                            const SizedBox(height: 12),
                            Text('No books yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[500])),
                            const SizedBox(height: 4),
                            Text('Tap "+ New Book" below to see smart suggestions', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : filteredBooks.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[500]),
                                const SizedBox(height: 10),
                                Text(
                                  'No books matching "$_bookSearchQuery"',
                                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 96, top: 8),
                            itemCount: filteredBooks.length,
                            itemBuilder: (ctx, idx) {
                              final item = filteredBooks[idx];
                              final pinned = (item['isPinned'] ?? 0) == 1;
                              final String bookType = item['bookType']?.toString() ?? 'standard';
                              final bool isLending = bookType == 'lending';
                              final balance = ((item['totalIn'] ?? 0) as num).toDouble() - ((item['totalOut'] ?? 0) as num).toDouble();
                              final isNeg = balance < 0;

                              final bg = isDark
                                  ? (pinned ? const Color(0xFF171A24) : AppConstants.cardDark)
                                  : (pinned ? const Color(0xFFFAF6EE) : AppConstants.cardLight);
                              final border = isLending
                                  ? AppConstants.goldAccent.withOpacity(0.55)
                                  : (isDark
                                      ? (pinned ? accent.withOpacity(0.45) : AppConstants.borderDark)
                                      : (pinned ? accent.withOpacity(0.40) : AppConstants.borderLight));

                              final createdDate = DateTime.tryParse(item['createdAt']?.toString() ?? '') ?? DateTime.now();
                              final updatedDate = DateTime.tryParse(item['updatedAt']?.toString() ?? '') ?? DateTime.now();

                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                child: Material(
                                  color: bg,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    side: BorderSide(color: border, width: isLending ? 1.2 : 1.0),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => DashboardScreen(
                                            bookId: item['id'] as int,
                                            bookName: item['name'].toString(),
                                            bookType: bookType,
                                          ),
                                        ),
                                      ).then((_) => _loadBooks());
                                    },
                                    onLongPress: () => _openBookMenu(
                                      item['id'] as int,
                                      item['name'].toString(),
                                      (item['isPinned'] ?? 0) as int,
                                      bookType,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(11),
                                            decoration: BoxDecoration(
                                              color: isLending
                                                  ? AppConstants.goldAccent.withOpacity(0.15)
                                                  : (dynamicColors
                                                      ? scheme.primary.withOpacity(0.12)
                                                      : (isDark ? AppConstants.iconNavy : const Color(0xFFF5EFE2))),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: accent.withOpacity(0.35), width: 0.8),
                                            ),
                                            child: Icon(
                                              isLending
                                                  ? Icons.handshake_rounded
                                                  : (pinned ? Icons.push_pin_rounded : Icons.book_rounded),
                                              color: isLending
                                                  ? AppConstants.goldAccent
                                                  : (dynamicColors ? scheme.primary : (isDark ? AppConstants.goldAccent : AppConstants.goldDarkText)),
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Line 1: Full-width Book Title + Balance Amount
                                                Row(
                                                  crossAxisAlignment: CrossAxisAlignment.center,
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        item['name'].toString(),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16.5),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Text(
                                                      '${isNeg ? '-' : ''}${AppConstants.defaultCurrency}${balance.abs().toStringAsFixed(0)}',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w800,
                                                        fontSize: 16.5,
                                                        color: isNeg ? AppConstants.expenseRed : AppConstants.incomeGreen,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                // Line 2: Clean 2-Line Metadata (Updated Time + Created on Date Pill)
                                                Row(
                                                  children: [
                                                    Icon(Icons.schedule_rounded, size: 11.5, color: Colors.grey[500]),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        AppConstants.formatOrdinalDateTime(updatedDate),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w500,
                                                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                                                        borderRadius: BorderRadius.circular(5),
                                                      ),
                                                      child: Text(
                                                        'Created on: ${AppConstants.formatOrdinalDate(createdDate)}',
                                                        style: TextStyle(
                                                          fontSize: 8.5,
                                                          letterSpacing: -0.2,
                                                          fontWeight: FontWeight.w500,
                                                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _promptCreateBook,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Book', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _settingsGroupCard(bool isDark, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: isDark ? AppConstants.borderDark : AppConstants.borderLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Colors.grey[500]),
      ),
    );
  }

  Widget _buildSettingsTab(BuildContext context, bool isDark) {
    final prefs = Provider.of<ThemeProvider>(context);
    final scheme = Theme.of(context).colorScheme;

    final lastSyncLabel = prefs.lastBackupIso.isEmpty
        ? 'Not backed up yet'
        : AppConstants.formatOrdinalDateTime(DateTime.tryParse(prefs.lastBackupIso) ?? DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        children: [
          _sectionLabel('APPEARANCE'),
          _settingsGroupCard(isDark, [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Theme Mode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<AppThemeChoice>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
                      segments: const [
                        ButtonSegment(
                          value: AppThemeChoice.system,
                          icon: Icon(Icons.brightness_auto_outlined, size: 17),
                          label: Text('Auto', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 13)),
                        ),
                        ButtonSegment(
                          value: AppThemeChoice.light,
                          icon: Icon(Icons.light_mode_outlined, size: 17),
                          label: Text('Light', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 13)),
                        ),
                        ButtonSegment(
                          value: AppThemeChoice.dark,
                          icon: Icon(Icons.dark_mode_outlined, size: 17),
                          label: Text('AMOLED', maxLines: 1, softWrap: false, style: TextStyle(fontSize: 13)),
                        ),
                      ],
                      selected: {prefs.themeChoice},
                      onSelectionChanged: (sel) {
                        HapticFeedback.selectionClick();
                        prefs.setThemeChoice(sel.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              dense: true,
              secondary: Icon(Icons.palette_outlined, color: scheme.primary, size: 21),
              title: const Text('Material You Colors', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: const Text('Use wallpaper colors instead of the default color', style: TextStyle(fontSize: 11.5)),
              value: prefs.useMaterialYou,
              onChanged: (v) {
                HapticFeedback.lightImpact();
                prefs.toggleMaterialYou(v);
              },
            ),
          ]),
          _sectionLabel('PREFERENCES & SECURITY'),
          _settingsGroupCard(isDark, [
            SwitchListTile(
              dense: true,
              secondary: Icon(Icons.fingerprint_rounded, color: scheme.primary, size: 22),
              title: const Text('Biometric App Lock', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: const Text('Unlock with Fingerprint or screen lock', style: TextStyle(fontSize: 11.5)),
              value: prefs.appLockEnabled,
              onChanged: (v) {
                HapticFeedback.lightImpact();
                _toggleBiometricLock(prefs, v);
              },
            ),
            const Divider(height: 1),
            SwitchListTile(
              dense: true,
              secondary: Icon(Icons.sms_outlined, color: scheme.primary, size: 21),
              title: const Text('Smart SMS Auto-Track', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: const Text('Auto-detect bank & UPI SMS offline', style: TextStyle(fontSize: 11.5)),
              value: prefs.smsAutoTrack,
              onChanged: (v) async {
                HapticFeedback.lightImpact();
                if (v) {
                  final ok = await _nativeBridge.invokeMethod<bool>('requestSmsPermission') ?? false;
                  if (!ok) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('SMS permission is required to suggest bank transactions.')),
                      );
                    }
                    return;
                  }
                  final db = await DatabaseHelper.instance.database;
                  await db.delete('handled_sms', where: 'smsId = ?', whereArgs: ['__sms_manually_off__']);
                } else {
                  await DatabaseHelper.instance.markSmsHandled('__sms_manually_off__', 'true');
                }
                await prefs.setSmsAutoTrack(v);
                await _refreshSmsInbox();
              },
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.notifications_active_outlined, color: scheme.primary, size: 21),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _selectReminderTime(prefs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Daily Expense Reminder', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                          const SizedBox(height: 2),
                          Text(
                            prefs.dailyReminderEnabled
                                ? 'Tap time to change (${AppConstants.formatTimeOfDay(prefs.reminderHour, prefs.reminderMinute)})'
                                : 'Reminders paused • Tap switch to enable',
                            style: TextStyle(fontSize: 11.5, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _selectReminderTime(prefs),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: scheme.primary.withOpacity(prefs.dailyReminderEnabled ? 0.14 : 0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: scheme.primary.withOpacity(prefs.dailyReminderEnabled ? 0.35 : 0.15)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule_rounded, size: 13, color: prefs.dailyReminderEnabled ? scheme.primary : Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              AppConstants.formatTimeOfDay(prefs.reminderHour, prefs.reminderMinute),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                                color: prefs.dailyReminderEnabled ? scheme.primary : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Switch(
                    value: prefs.dailyReminderEnabled,
                    onChanged: (v) async {
                      HapticFeedback.lightImpact();
                      await prefs.setDailyReminder(enabled: v);
                      await _nativeBridge.invokeMethod('scheduleDailyReminder', {
                        'enabled': v,
                        'hour': prefs.reminderHour,
                        'minute': prefs.reminderMinute,
                      });
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(Icons.insights_rounded, color: scheme.primary, size: 21),
              title: const Text('Monthly Expense Insights', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: const Text('View previous & current month spending breakdown', style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
              onTap: () => _openMonthlyInsightsSheet(initialPreviousMonth: true),
            ),
          ]),
          _sectionLabel('GOOGLE DRIVE SYNC'),
          _settingsGroupCard(isDark, [
            ListTile(
              dense: true,
              leading: Icon(Icons.add_to_drive_rounded, color: scheme.primary, size: 22),
              title: Text(
                prefs.driveAccount.isEmpty ? 'Connect Google Account' : prefs.driveAccount,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              subtitle: Text(
                prefs.driveAccount.isEmpty ? 'Auto-backups daily after 12:00 AM' : 'Last: $lastSyncLabel  •  Auto: 12:00 AM',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: TextButton(
                onPressed: () => _onSwitchDriveAccount(prefs),
                child: Text(
                  prefs.driveAccount.isEmpty ? 'Connect' : 'Switch',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _onBackupNow(prefs),
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text('Backup Now', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _onRestoreNow(prefs),
                      icon: const Icon(Icons.cloud_download_outlined, size: 18),
                      label: const Text('Restore', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ]),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppConstants.incomeGreen.withOpacity(isDark ? 0.10 : 0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppConstants.incomeGreen.withOpacity(0.28)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.verified_user_outlined, color: AppConstants.incomeGreen, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Offline • Zero Data Collection • Zero Ads',
                        maxLines: 1,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppConstants.incomeGreen),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'FinTrax never shows ads and never collects or shares your data. SMS detection runs locally on your phone, and backups stay in your personal Google Drive.',
                        style: TextStyle(fontSize: 11, height: 1.38, color: isDark ? Colors.grey[300] : Colors.grey[800]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _sectionLabel('ABOUT & CREDITS'),
          _settingsGroupCard(isDark, [
            const ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: AppConstants.iconNavy,
                child: Text('CK', style: TextStyle(color: AppConstants.goldAccent, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
              title: Text(AppConstants.developerRole, style: TextStyle(fontSize: 11, color: Colors.grey)),
              subtitle: Text(AppConstants.developerName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(Icons.code_rounded, color: scheme.primary, size: 20),
              title: const Text('GitHub', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              subtitle: const Text('github.com/${AppConstants.defaultGithubId}', style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.open_in_new_rounded, size: 16, color: Colors.grey),
              onTap: () {
                HapticFeedback.lightImpact();
                _nativeBridge.invokeMethod('openUrl', {'url': 'https://github.com/${AppConstants.defaultGithubId}'});
              },
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(Icons.alternate_email_rounded, color: scheme.primary, size: 20),
              title: const Text('Contact Email', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              subtitle: const Text(AppConstants.defaultDeveloperEmail, style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.mail_outline_rounded, size: 16, color: Colors.grey),
              onTap: () {
                HapticFeedback.lightImpact();
                _nativeBridge.invokeMethod('openUrl', {'url': 'mailto:${AppConstants.defaultDeveloperEmail}?subject=FinTrax%20Feedback'});
              },
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(Icons.send_rounded, color: scheme.primary, size: 20),
              title: const Text('Telegram', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              subtitle: const Text('@chandsy', style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.open_in_new_rounded, size: 16, color: Colors.grey),
              onTap: () {
                HapticFeedback.lightImpact();
                _nativeBridge.invokeMethod('openUrl', {'url': 'https://t.me/chandsy'});
              },
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(Icons.bug_report_rounded, color: scheme.primary, size: 20),
              title: const Text('Diagnostic Logs', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              subtitle: const Text('View, clear, or save backend logs to Downloads', style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DebugLogsScreen()));
              },
            ),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding) {
      return WelcomeSetupScreen(
        onFinished: () async {
          setState(() => _showOnboarding = false);
          await _loadBooks();
          final handled = await DatabaseHelper.instance.getHandledSmsIds();
          unawaited(_initBackgroundTasks(handled));
        },
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prefs = Provider.of<ThemeProvider>(context);
    return Scaffold(
      body: PageView(
        controller: _tabPageController,
        onPageChanged: (idx) {
          if (_tabIndex != idx) {
            HapticFeedback.selectionClick();
            setState(() => _tabIndex = idx);
          }
        },
        children: [
          KeyedSubtree(key: const ValueKey('books_tab'), child: _buildBooksTab(isDark, prefs.useMaterialYou)),
          KeyedSubtree(key: const ValueKey('settings_tab'), child: _buildSettingsTab(context, isDark)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        backgroundColor: isDark ? AppConstants.cardDark : AppConstants.cardLight,
        elevation: 0,
        onDestinationSelected: (idx) {
          HapticFeedback.selectionClick();
          setState(() => _tabIndex = idx);
          _tabPageController.animateToPage(
            idx,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.book_outlined), selectedIcon: Icon(Icons.book_rounded), label: 'Books'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}
