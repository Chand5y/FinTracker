import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'theme/theme_provider.dart';
import 'screens/books_screen.dart';
import 'core/constants.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const FintrackApp(),
    ),
  );
}

class FintrackApp extends StatelessWidget {
  const FintrackApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            final bool useDynamic = themeProvider.useMaterialYou;

            final ColorScheme lightScheme = (useDynamic && lightDynamic != null)
                ? lightDynamic
                : ColorScheme.fromSeed(
                    seedColor: AppConstants.goldAccent,
                    primary: AppConstants.goldDarkText,
                    secondary: AppConstants.goldAccent,
                    brightness: Brightness.light,
                    surface: AppConstants.cardLight,
                  );

            final ColorScheme darkScheme = (useDynamic && darkDynamic != null)
                ? darkDynamic
                : ColorScheme.fromSeed(
                    seedColor: AppConstants.goldAccent,
                    primary: AppConstants.goldAccent,
                    secondary: AppConstants.goldAccent,
                    brightness: Brightness.dark,
                    surface: AppConstants.cardDark,
                  );

            return MaterialApp(
              title: AppConstants.appName,
              debugShowCheckedModeBanner: false,
              themeMode: themeProvider.flutterThemeMode,
              theme: _buildTheme(lightScheme, Brightness.light, useDynamic),
              darkTheme: _buildTheme(darkScheme, Brightness.dark, useDynamic),
              home: const AppLockGate(child: BooksScreen()),
            );
          },
        );
      },
    );
  }

  ThemeData _buildTheme(ColorScheme scheme, Brightness brightness, bool useDynamic) {
    final bool isDark = brightness == Brightness.dark;
    final Color scaffoldBg = useDynamic
        ? scheme.surface
        : (isDark ? AppConstants.bgDark : AppConstants.bgLight);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: isDark ? Colors.white : const Color(0xFF0F172A)),
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF0F172A),
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: useDynamic
            ? scheme.secondaryContainer
            : AppConstants.goldAccent.withOpacity(isDark ? 0.22 : 0.18),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: useDynamic ? scheme.onSecondaryContainer : (isDark ? AppConstants.goldAccent : AppConstants.goldDarkText));
          }
          return IconThemeData(color: isDark ? Colors.grey[400] : Colors.grey[600]);
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: useDynamic ? scheme.primaryContainer : AppConstants.goldAccent,
        foregroundColor: useDynamic ? scheme.onPrimaryContainer : AppConstants.iconNavy,
      ),
    );
  }
}

class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({Key? key, required this.child}) : super(key: key);

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  static const MethodChannel _channel = MethodChannel('com.chandankumar.fintrack/sms');

  bool _unlocked = false;
  bool _promptTriggered = false;
  String _enteredPin = '';
  String _errorMessage = '';

  Future<void> _triggerBiometricUnlock() async {
    try {
      final bool isSecure = await _channel.invokeMethod('isDeviceSecure') ?? false;
      if (!isSecure) return;
      final bool ok = await _channel.invokeMethod('authenticateDevice') ?? false;
      if (ok && mounted) {
        HapticFeedback.mediumImpact();
        setState(() => _unlocked = true);
      }
    } catch (_) {}
  }

  void _onDigitPress(String digit, String savedPin) {
    HapticFeedback.selectionClick();
    if (_enteredPin.length >= 4) return;
    setState(() {
      _errorMessage = '';
      _enteredPin += digit;
    });
    if (_enteredPin.length == 4) {
      if (_enteredPin == savedPin) {
        HapticFeedback.mediumImpact();
        setState(() => _unlocked = true);
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _enteredPin = '';
          _errorMessage = 'Incorrect PIN. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    if (!themeProvider.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!themeProvider.appLockEnabled || _unlocked) {
      return widget.child;
    }

    if (!_promptTriggered) {
      _promptTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _triggerBiometricUnlock());
    }

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color gold = isDark ? AppConstants.goldAccent : AppConstants.goldDarkText;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppConstants.iconNavy,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppConstants.goldAccent.withOpacity(0.5), width: 1.5),
                ),
                child: const Icon(Icons.lock_outline_rounded, color: AppConstants.goldAccent, size: 32),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Fin', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF0E1726))),
                  Text('Trax', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w300, color: gold)),
                ],
              ),
              const SizedBox(height: 8),
              Text('Enter your 4-digit PIN or use Fingerprint', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final bool filled = index < _enteredPin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? gold : Colors.transparent,
                      border: Border.all(color: filled ? gold : Colors.grey.withOpacity(0.5), width: 2),
                    ),
                  );
                }),
              ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(_errorMessage, style: const TextStyle(color: AppConstants.expenseRed, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
              const Spacer(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Column(
                  children: [
                    for (final row in [
                      ['1', '2', '3'],
                      ['4', '5', '6'],
                      ['7', '8', '9'],
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: row.map((digit) {
                            return _buildPinKey(
                              label: digit,
                              isDark: isDark,
                              onTap: () => _onDigitPress(digit, themeProvider.appPin),
                            );
                          }).toList(),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          iconSize: 28,
                          tooltip: 'Unlock with Fingerprint / Screen Lock',
                          onPressed: _triggerBiometricUnlock,
                          icon: Icon(Icons.fingerprint_rounded, color: gold),
                        ),
                        _buildPinKey(
                          label: '0',
                          isDark: isDark,
                          onTap: () => _onDigitPress('0', themeProvider.appPin),
                        ),
                        IconButton(
                          iconSize: 24,
                          onPressed: () {
                            if (_enteredPin.isNotEmpty) {
                              HapticFeedback.selectionClick();
                              setState(() => _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1));
                            }
                          },
                          icon: Icon(Icons.backspace_outlined, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinKey({required String label, required bool isDark, required VoidCallback onTap}) {
    return Material(
      color: isDark ? AppConstants.cardDark : AppConstants.cardLight,
      shape: CircleBorder(side: BorderSide(color: isDark ? AppConstants.borderDark : AppConstants.borderLight)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 68,
          height: 68,
          child: Center(
            child: Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}
