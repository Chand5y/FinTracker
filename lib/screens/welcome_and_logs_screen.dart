import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import '../data/database_helper.dart';
import '../core/constants.dart';
import '../theme/theme_provider.dart';
import 'add_transaction_screen.dart';

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
                FinTraxBrandHelper.showModernSnackBar(
                  context: context,
                  message: 'Logs copied to clipboard!',
                  icon: Icons.copy_all_rounded,
                  color: AppConstants.incomeGreen,
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
                FinTraxBrandHelper.showModernSnackBar(
                  context: context,
                  message: savedPath != null ? 'Saved to: $savedPath' : 'Save failed. Use Copy instead.',
                  icon: savedPath != null ? Icons.download_done_rounded : Icons.error_outline_rounded,
                  color: savedPath != null ? AppConstants.incomeGreen : AppConstants.expenseRed,
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
