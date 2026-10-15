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

  Future<void> _triggerBiometricUnlock() async {
    try {
      final bool isSecure = await _channel.invokeMethod('isDeviceSecure') ?? false;
      if (!isSecure) {
        if (mounted) setState(() => _unlocked = true);
        return;
      }
      final bool ok = await _channel.invokeMethod('authenticateDevice') ?? false;
      if (ok && mounted) {
        HapticFeedback.mediumImpact();
        setState(() => _unlocked = true);
      }
    } catch (_) {}
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
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppConstants.iconNavy,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppConstants.goldAccent.withOpacity(0.5), width: 1.5),
                  ),
                  child: const Icon(Icons.fingerprint_rounded, color: AppConstants.goldAccent, size: 48),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Fin', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF0E1726))),
                    Text('Trax', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w300, color: gold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'FinTrax is locked for your privacy',
                  style: TextStyle(fontSize: 13.5, color: Colors.grey[500]),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _triggerBiometricUnlock,
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text('Unlock with Fingerprint / PIN', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
