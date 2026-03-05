import 'package:flutter/material.dart';

// ========== APP THEME ==========
// Pixel-perfect replication of the React Native color scheme and typography

class NinaadaColors {
  NinaadaColors._();

  // Base backgrounds
  static const Color background = Color(0xFF0B0F1A);
  static const Color surface = Color(0xFF10141F);
  static const Color surfaceLight = Color(0xFF141824);
  static const Color border = Color(0xFF1C2030);

  // Primary accent (purple) — velvet, not LED
  static const Color primary = Color(0xFF7C4DFF);
  static const Color primaryLight = Color(0xFF9B7AFF);
  static const Color primaryDark = Color(0xFF5C2ED6);
  static const Color primarySubtle = Color(0xFF3D1A8F);

  // Text
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF888888);
  static const Color textTertiary = Color(0xFF666666);
  static const Color textSubtle = Color(0xFF555555);

  // Functional
  static const Color liked = Color(0xFFFF4D6D);
  static const Color likedDark = Color(0xFFFF1744);
  static const Color download = Color(0xFF8B5CF6);
  static const Color error = Color(0xFFFF5252);
  static const Color success = Color(0xFF2A9D8F);

  // Nav
  static const Color navBackground = Color(0xFF101528); // Elevated surface
  static const Color navBorder = Color(0x1A7C4DFF);     // ~0.10 opacity
  static const Color navInactive = Color(0xFF666666);

  // Gradient presets matching RN
  static const List<Color> headerGradientHome = [
    Color(0xFF1C1336),
    Color(0xFF0B0F1A),
  ];
  static const List<Color> headerGradientExplore = [
    Color(0xFF1C1336),
    Color(0xFF0B0F1A),
  ];
  static const List<Color> headerGradientLibrary = [
    Color(0xFF1A1333),
    Color(0xFF0B0F1A),
  ];
  static const List<Color> headerGradientRadio = [
    Color(0xFF1C1336),
    Color(0xFF1A1333),
    Color(0xFF0B0F1A),
  ];
  static const List<Color> miniPlayerGradient = [
    Color(0xEB7C4DFF), // ~0.92 opacity
    Color(0xF25C2ED6), // ~0.95 opacity
  ];
  static const List<Color> artistGradient = [
    Color(0xFF5C2ED6),
    Color(0xFF0B0F1A),
  ];
  static const List<Color> playerOverlay = [
    Color(0x80000000),
    Color(0xB3000000),
    Color(0xF20B0F1A),
  ];
}

class NinaadaTheme {
  NinaadaTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: NinaadaColors.background,
      primaryColor: NinaadaColors.primary,
      colorScheme: const ColorScheme.dark(
        primary: NinaadaColors.primary,
        secondary: NinaadaColors.primaryLight,
        surface: NinaadaColors.surface,
        error: NinaadaColors.error,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        // headerTitle: 22px, 800 weight
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: -0.5,
        ),
        // secTitle: 18px, 700 weight
        headlineMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        // songRowName: 14px, 600 weight
        bodyLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        // songRowArtist: 12px, 400 weight
        bodyMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: NinaadaColors.textSecondary,
        ),
        // miniName: 14px, 700 weight
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        // greeting: 13px, 400 weight
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: Color(0xB3FFFFFF),
        ),
        // headerSub: 12px, 400 weight
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: Color(0x80FFFFFF),
        ),
        // navLabel: 9px, 400 weight
        labelSmall: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w400,
          color: NinaadaColors.navInactive,
        ),
      ),
    );
  }
}
