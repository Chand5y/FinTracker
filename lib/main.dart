import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme/theme_provider.dart';
import 'screens/books_screen.dart';

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
    // We listen to the theme provider here so the whole app rebuilds when toggled
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        final isModern = themeProvider.themeMode == AppThemeMode.glassmorphic;

        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            ColorScheme lightScheme = lightDynamic ?? ColorScheme.fromSeed(seedColor: const Color(0xFF4C44D4));
            ColorScheme darkScheme = darkDynamic ?? ColorScheme.fromSeed(seedColor: const Color(0xFF4C44D4), brightness: Brightness.dark);

            return MaterialApp(
              title: 'Fintrack',
              debugShowCheckedModeBanner: false,
              theme: isModern 
                ? _buildModernTheme(Brightness.light)
                : ThemeData(colorScheme: lightScheme, useMaterial3: true, textTheme: GoogleFonts.interTextTheme()),
              darkTheme: isModern
                ? _buildModernTheme(Brightness.dark)
                : ThemeData(colorScheme: darkScheme, useMaterial3: true, textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme)),
              themeMode: ThemeMode.system, 
              home: const BooksScreen(), 
            );
          },
        );
      }
    );
  }

  ThemeData _buildModernTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4C44D4),
        brightness: brightness,
      ),
      textTheme: GoogleFonts.interTextTheme(
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
        titleTextStyle: GoogleFonts.inter(
          color: isDark ? Colors.white : Colors.black,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
