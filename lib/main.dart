import 'dart:async';
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

// ===========================================================================
// REUSABLE FINTRAX BRAND LOGO ICON & LAUNCH SPLASH SCREEN
// ===========================================================================
class FinTraxLogoIcon extends StatelessWidget {
  final double size;
  const FinTraxLogoIcon({Key? key, this.size = 84}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16243E), Color(0xFF0B1322)],
        ),
        borderRadius: BorderRadius.circular(size * 0.26),
        border: Border.all(
          color: AppConstants.goldAccent.withOpacity(0.55),
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _FinTraxMonogramPainter(),
      ),
    );
  }
}

class _FinTraxMonogramPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final goldPaint = Paint()
      ..color = AppConstants.goldAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.068
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Stylized 'F' and 'T' monogram matching the FinTrax app icon
    final fPath = Path()
      ..moveTo(w * 0.26, h * 0.72)
      ..lineTo(w * 0.26, h * 0.38)
      ..quadraticBezierTo(w * 0.26, h * 0.27, w * 0.38, h * 0.27)
      ..lineTo(w * 0.50, h * 0.27);
    canvas.drawPath(fPath, goldPaint);

    // Middle crossbar of F
    canvas.drawLine(
      Offset(w * 0.26, h * 0.49),
      Offset(w * 0.45, h * 0.49),
      goldPaint,
    );

    // Stylized 'T' with upward financial arrow tip
    final tPath = Path()
      ..moveTo(w * 0.46, h * 0.27)
      ..lineTo(w * 0.76, h * 0.27);
    canvas.drawPath(tPath, goldPaint);

    canvas.drawLine(
      Offset(w * 0.61, h * 0.27),
      Offset(w * 0.61, h * 0.72),
      goldPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FinTraxSplashScreen extends StatelessWidget {
  const FinTraxSplashScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color finColor = isDark ? Colors.white : const Color(0xFF0E1726);
    final Color traxColor = isDark ? AppConstants.goldAccent : AppConstants.goldDarkText;

    return Scaffold(
      backgroundColor: isDark ? AppConstants.bgDark : AppConstants.bgLight,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FinTraxLogoIcon(size: 88),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'Fin',
                  style: TextStyle(
                    color: finColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 30,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  'Trax',
                  style: TextStyle(
                    color: traxColor,
                    fontWeight: FontWeight.w300,
                    fontSize: 30,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
            return IconThemeData(
              color: useDynamic
                  ? scheme.onSecondaryContainer
                  : (isDark ? AppConstants.goldAccent : AppConstants.goldDarkText),
            );
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
  bool _splashDone = false;
  bool _initialLockStateChecked = false;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    // Show the branded FinTrax logo splash screen briefly on launch
    _splashTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted) {
        setState(() => _splashDone = true);
      }
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  Future<void> _triggerBiometricUnlock() async {
    try {
      final bool isSecure = await _channel.invokeMethod<bool>('isDeviceSecure') ?? false;
      if (!isSecure) {
        if (mounted) setState(() => _unlocked = true);
        return;
      }
      final bool ok = await _channel.invokeMethod<bool>('authenticateDevice') ?? false;
      if (ok && mounted) {
        HapticFeedback.mediumImpact();
        setState(() => _unlocked = true);
      }
    } catch (_) {
      if (mounted) setState(() => _unlocked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    if (!themeProvider.isInitialized || !_splashDone) {
      return const FinTraxSplashScreen();
    }

    if (!_initialLockStateChecked) {
      _initialLockStateChecked = true;
      if (!themeProvider.appLockEnabled) {
        _unlocked = true;
      }
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
                const FinTraxLogoIcon(size: 84),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Fin',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0E1726),
                      ),
                    ),
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
