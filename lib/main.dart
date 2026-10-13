import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

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
      builder: (context, themeProvider, child) {
        final isModern = themeProvider.themeMode == AppThemeMode.glassmorphic;

        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          
          // Toggle off: Standard Material You
          theme: isModern 
            ? _buildSignatureTheme(Brightness.light)
            : ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: AppConstants.primaryColor), useMaterial3: true, textTheme: GoogleFonts.interTextTheme()),
          
          // Toggle off (Dark): Standard Material You Dark
          darkTheme: isModern
            ? _buildSignatureTheme(Brightness.dark)
            : ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: AppConstants.primaryColor, brightness: Brightness.dark), useMaterial3: true, textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme)),
          
          themeMode: ThemeMode.system, 
          home: const BooksScreen(), 
        );
      }
    );
  }

  // Toggle on: The Custom Premium AMOLED Vibe
  ThemeData _buildSignatureTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: isDark ? AppConstants.backgroundDark : const Color(0xFFF2F2F7),
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppConstants.primaryColor,
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
