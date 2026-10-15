import 'package:flutter/material.dart';
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
              home: const BooksScreen(),
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
