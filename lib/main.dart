import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme/theme_provider.dart';
import 'screens/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const FintrackerApp(),
    ),
  );
}

class FintrackerApp extends StatelessWidget {
  const FintrackerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isGlass = themeProvider.themeMode == AppThemeMode.glassmorphic;

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // Dynamic Material Expressive Theme based on OS colors
        ColorScheme lightScheme = lightDynamic ?? ColorScheme.fromSeed(seedColor: Colors.grey);
        ColorScheme darkScheme = darkDynamic ?? ColorScheme.fromSeed(seedColor: Colors.grey, brightness: Brightness.dark);

        return MaterialApp(
          title: 'Fintracker',
          debugShowCheckedModeBanner: false,
          theme: isGlass 
            ? _buildGlassTheme(Brightness.light)
            : ThemeData(
                colorScheme: lightScheme, 
                useMaterial3: true, 
                textTheme: GoogleFonts.interTextTheme()
              ),
          darkTheme: isGlass
            ? _buildGlassTheme(Brightness.dark)
            : ThemeData(
                colorScheme: darkScheme, 
                useMaterial3: true, 
                textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme)
              ),
          themeMode: ThemeMode.system, // Respects your phone's dark/light mode
          home: const DashboardScreen(), // Connects directly to your new dashboard
        );
      },
    );
  }

  // Apple-inspired minimalist aesthetic
  ThemeData _buildGlassTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.grey, // Neutral monochromatic base
        brightness: brightness,
      ),
      textTheme: GoogleFonts.interTextTheme(
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
        titleTextStyle: GoogleFonts.inter(
          color: isDark ? Colors.white : Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
