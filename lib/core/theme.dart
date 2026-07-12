import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette calquée sur le thème sombre déjà utilisé sur la version web
/// (écran Produit/lst) afin de garder une identité visuelle cohérente
/// entre le back-office web et l'application mobile ShopCell.
class AppColors {
  AppColors._();

  static const bgDeep = Color(0xFF080A0E);
  static const bgCard = Color(0xFF0E1117);
  static const bgHover = Color(0xFF12161E);
  static const bgElevated = Color(0xFF161B26);

  static const accent = Color(0xFF12B76A);
  static const accentLight = Color(0xFF6EE7B7);
  static const accentGlow = Color(0x3812B76A);

  static const green = Color(0xFF00E5A0);
  static const yellow = Color(0xFFF5C842);
  static const blue = Color(0xFF3AB5FF);
  static const red = Color(0xFFFF4D6D);
  static const orange = Color(0xFFFF8C42);

  static const textPrimary = Color(0xFFF0F2F8);
  static const textSecondary = Color(0xFF8B92A8);
  static const textMuted = Color(0xFF4A5068);

  static const border = Color(0x0FFFFFFF);
  static const borderAccent = Color(0x4D12B76A);

  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, Color(0xFF0C8F52)],
  );

  static const backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0A0C14), bgDeep],
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bgDeep,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accent,
        secondary: AppColors.green,
        surface: AppColors.bgCard,
        error: AppColors.red,
      ),
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      dividerColor: AppColors.border,
      inputDecorationTheme: InputDecorationTheme(
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.accent, width: 1.4),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.red),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: AppColors.accentLight),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.bgElevated,
        contentTextStyle: GoogleFonts.inter(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
