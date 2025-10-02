import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppThemes {
  static final List<ThemeData> themes = [
    _buildTheme(
        name: 'DineFlow Dark',
        brightness: Brightness.dark,
        background: const Color(0xFF0A0A0A),
        accent: const Color(0xFFF25C05),
        textPrimary: const Color(0xFFFFFFFF),
        textSecondary: const Color(0xFFa3a3a3),
        surface: const Color(0xFF1F1F1F),
        border: const Color.fromARGB(30, 255, 255, 255)),
    _buildTheme(
        name: 'DineFlow Light',
        brightness: Brightness.light,
        background: const Color(0xFFF5F5F7),
        accent: const Color(0xFFE55302),
        textPrimary: const Color(0xFF1d1d1f),
        textSecondary: const Color(0xFF6e6e73),
        surface: const Color(0xFFFFFFFF),
        border: const Color(0xFFd2d2d7)),
    _buildTheme(
        name: 'Oceanic',
        brightness: Brightness.dark,
        background: const Color(0xFF0B132B),
        accent: const Color(0xFF6FFFE9),
        textPrimary: const Color(0xFFFFFFFF),
        textSecondary: const Color(0xFF8B94A3),
        surface: const Color(0xFF1C2541),
        border: const Color(0xFF3A506B)),
    _buildTheme(
        name: 'Sunset',
        brightness: Brightness.light,
        background: const Color(0xFFFFEEDB),
        accent: const Color(0xFFF65E54),
        textPrimary: const Color(0xFF3D2C24),
        textSecondary: const Color(0xFF856352),
        surface: const Color(0xFFFFFFFF),
        border: const Color(0xFFD3B8AE)),
    _buildTheme(
        name: 'Forest',
        brightness: Brightness.dark,
        background: const Color(0xFF1A2A27),
        accent: const Color(0xFF5F939A),
        textPrimary: const Color(0xFFE8E8E8),
        textSecondary: const Color(0xFFAFBDBD),
        surface: const Color(0xFF2E4642),
        border: const Color(0xFF4C6A65)),
    _buildTheme(
        name: 'Rose',
        brightness: Brightness.light,
        background: const Color(0xFFF9E6E2),
        accent: const Color(0xFFD9667B),
        textPrimary: const Color(0xFF593339),
        textSecondary: const Color(0xFF9F6B73),
        surface: const Color(0xFFFFFFFF),
        border: const Color(0xFFEAC9C3)),
    _buildTheme(
        name: 'Midnight',
        brightness: Brightness.dark,
        background: const Color(0xFF000000),
        accent: const Color(0xFFBB86FC),
        textPrimary: const Color(0xFFFFFFFF),
        textSecondary: const Color(0xFFB3B3B3),
        surface: const Color(0xFF121212),
        border: const Color(0xFF272727)),
    _buildTheme(
        name: 'Classic',
        brightness: Brightness.light,
        background: const Color(0xFFF0F0F0),
        accent: const Color(0xFF007AFF),
        textPrimary: const Color(0xFF000000),
        textSecondary: const Color(0xFF8A8A8E),
        surface: const Color(0xFFFFFFFF),
        border: const Color(0xFFC7C7CC)),
    _buildTheme(
        name: 'Emerald',
        brightness: Brightness.dark,
        background: const Color(0xFF013220),
        accent: const Color(0xFF00C58A),
        textPrimary: const Color(0xFFFFFFFF),
        textSecondary: const Color(0xFFB2D8B2),
        surface: const Color(0xFF025133),
        border: const Color(0xFF037E4A)),
    _buildTheme(
        name: 'Lemonade',
        brightness: Brightness.light,
        background: const Color(0xFFFFF9C4),
        accent: const Color(0xFFF44336),
        textPrimary: const Color(0xFF3E2723),
        textSecondary: const Color(0xFF795548),
        surface: const Color(0xFFFFFFFF),
        border: const Color(0xFFFFECB3)),
    _buildTheme(
        name: 'Grape',
        brightness: Brightness.dark,
        background: const Color(0xFF1E1B3A),
        accent: const Color(0xFF9C27B0),
        textPrimary: const Color(0xFFFFFFFF),
        textSecondary: const Color(0xFFE1BEE7),
        surface: const Color(0xFF312D5B),
        border: const Color(0xFF4A4488)),
    _buildTheme(
        name: 'Mint',
        brightness: Brightness.light,
        background: const Color(0xFFE0F2F1),
        accent: const Color(0xFF009688),
        textPrimary: const Color(0xFF004D40),
        textSecondary: const Color(0xFF00796B),
        surface: const Color(0xFFFFFFFF),
        border: const Color(0xFFB2DFDB)),
    _buildTheme(
        name: 'Chocolate',
        brightness: Brightness.dark,
        background: const Color(0xFF120E0D),
        accent: const Color(0xFFD2691E),
        textPrimary: const Color(0xFFFFFFFF),
        textSecondary: const Color(0xFF8B4513),
        surface: const Color(0xFF2D1B13),
        border: const Color(0xFF4A2D1F)),
    _buildTheme(
        name: 'Sky',
        brightness: Brightness.light,
        background: const Color(0xFFE3F2FD),
        accent: const Color(0xFF2196F3),
        textPrimary: const Color(0xFF0D47A1),
        textSecondary: const Color(0xFF1976D2),
        surface: const Color(0xFFFFFFFF),
        border: const Color(0xFFBBDEFB)),
    _buildTheme(
        name: 'Ruby',
        brightness: Brightness.dark,
        background: const Color(0xFF2C0000),
        accent: const Color(0xFFE53935),
        textPrimary: const Color(0xFFFFFFFF),
        textSecondary: const Color(0xFFFFCDD2),
        surface: const Color(0xFF4B0000),
        border: const Color(0xFF6E0000)),
    _buildTheme(
        name: 'Sandstone',
        brightness: Brightness.light,
        background: const Color(0xFFFDF6E3),
        accent: const Color(0xFFCB4B16),
        textPrimary: const Color(0xFF586E75),
        textSecondary: const Color(0xFF839496),
        surface: const Color(0xFFEEE8D5),
        border: const Color(0xFF93A1A1)),
    _buildTheme(
        name: 'Slate',
        brightness: Brightness.dark,
        background: const Color(0xFF263238),
        accent: const Color(0xFF26A69A),
        textPrimary: const Color(0xFFECEFF1),
        textSecondary: const Color(0xFFB0BEC5),
        surface: const Color(0xFF37474F),
        border: const Color(0xFF546E7A)),
    _buildTheme(
        name: 'Paper',
        brightness: Brightness.light,
        background: const Color(0xFFFFFFFF),
        accent: const Color(0xFFD4B483),
        textPrimary: const Color(0xFF484848),
        textSecondary: const Color(0xFF888888),
        surface: const Color(0xFFF8F8F8),
        border: const Color(0xFFE8E8E8)),
    _buildTheme(
        name: 'Cyberpunk',
        brightness: Brightness.dark,
        background: const Color(0xFF000000),
        accent: const Color(0xFF00FFFF),
        textPrimary: const Color(0xFFF8F8F2),
        textSecondary: const Color(0xFF8BE9FD),
        surface: const Color(0xFF282A36),
        border: const Color(0xFF44475A)),
    _buildTheme(
        name: 'Sakura',
        brightness: Brightness.light,
        background: const Color(0xFFFEDFE1),
        accent: const Color(0xFFE8368F),
        textPrimary: const Color(0xFF333333),
        textSecondary: const Color(0xFF896473),
        surface: const Color(0xFFFFFFFF),
        border: const Color(0xFFF7C5CC)),
  ];

  static ThemeData _buildTheme({
    required String name,
    required Color background,
    required Color accent,
    required Color textPrimary,
    required Color textSecondary,
    required Color surface,
    required Color border,
    required Brightness brightness,
  }) {
    // Base text theme using Google Fonts for consistency
    final baseTextTheme = GoogleFonts.poppinsTextTheme(
      TextTheme(
        // Default styles for different text types
        displayLarge: TextStyle(fontWeight: FontWeight.bold, color: textPrimary),
        headlineMedium: TextStyle(fontWeight: FontWeight.bold, color: textPrimary),
        titleLarge: TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
        titleMedium: TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: TextStyle(color: textSecondary),
        bodyMedium: TextStyle(color: textSecondary),
        bodySmall: TextStyle(color: textSecondary.withOpacity(0.8)),
        labelLarge: TextStyle(fontWeight: FontWeight.bold, color: brightness == Brightness.dark ? textPrimary : Colors.white),
      ),
    );

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: background,
      primaryColor: accent,
      // Assign the complete and safe text theme
      textTheme: baseTextTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
        background: background,
        surface: surface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: accent, width: 2)),
        labelStyle: baseTextTheme.bodyLarge,
        prefixIconColor: textSecondary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
          backgroundColor: accent,
          foregroundColor: brightness == Brightness.dark ? textPrimary : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: baseTextTheme.labelLarge,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        titleTextStyle: baseTextTheme.headlineMedium,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: brightness == Brightness.dark ? textPrimary : background,
        elevation: 4,
        shape: const CircleBorder(),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      extensions: <ThemeExtension<dynamic>>[
        ThemeName(name),
      ],
    );
  }

}

// A custom ThemeExtension to hold the theme name
@immutable
class ThemeName extends ThemeExtension<ThemeName> {
  const ThemeName(this.name);

  final String name;

  @override
  ThemeName copyWith({String? name}) {
    return ThemeName(name ?? this.name);
  }

  @override
  ThemeName lerp(ThemeExtension<ThemeName>? other, double t) {
    if (other is! ThemeName) {
      return this;
    }
    return t < 0.5 ? this : other;
  }

  @override
  String toString() => 'ThemeName(name: $name)';
}