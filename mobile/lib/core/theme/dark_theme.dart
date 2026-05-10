import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.darkBg,
  colorScheme: const ColorScheme.dark(
    surface: AppColors.darkSurface,
    primary: AppColors.darkPrimary,
    secondary: AppColors.darkAccent,
    error: AppColors.darkError,
    onPrimary: AppColors.darkTextPrimary,
    onSurface: AppColors.darkTextPrimary,
    outline: AppColors.darkBorder,
    surfaceContainerHighest: AppColors.darkSurfaceVariant,
  ),
  textTheme: GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme).copyWith(
    displayLarge:  GoogleFonts.syne(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w800),
    displayMedium: GoogleFonts.syne(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w700),
    displaySmall:  GoogleFonts.syne(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w700),
    headlineLarge:  GoogleFonts.syne(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w700),
    headlineMedium: GoogleFonts.syne(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w600),
    headlineSmall:  GoogleFonts.syne(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w600),
    titleLarge:  GoogleFonts.syne(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w600),
    titleMedium: GoogleFonts.syne(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w600),
    bodyLarge:   GoogleFonts.dmSans(color: AppColors.darkTextPrimary),
    bodyMedium:  GoogleFonts.dmSans(color: AppColors.darkTextPrimary),
    bodySmall:   GoogleFonts.dmSans(color: AppColors.darkTextSecondary),
    labelLarge:  GoogleFonts.dmSans(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w500),
    labelSmall:  GoogleFonts.dmSans(color: AppColors.darkTextSecondary),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: AppColors.darkBg,
    elevation: 0,
    scrolledUnderElevation: 0,
    iconTheme: const IconThemeData(color: AppColors.darkTextPrimary),
    titleTextStyle: GoogleFonts.syne(
      color: AppColors.darkTextPrimary,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
  ),
  cardTheme: CardThemeData(
    color: AppColors.darkSurface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: AppColors.darkBorder),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.darkSurface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.darkBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.darkBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.darkPrimary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.darkError),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.darkError, width: 1.5),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: AppColors.darkBorder.withOpacity(0.5)),
    ),
    labelStyle: GoogleFonts.dmSans(
      color: AppColors.darkTextSecondary,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    ),
    hintStyle: GoogleFonts.dmSans(color: const Color(0xFF4B6280), fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.darkPrimary,
      foregroundColor: AppColors.darkTextPrimary,
      disabledBackgroundColor: AppColors.darkPrimary.withOpacity(0.5),
      elevation: 0,
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w500),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.darkTextPrimary,
      side: const BorderSide(color: AppColors.darkBorder, width: 1.5),
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w500),
    ),
  ),
  dividerColor: AppColors.darkBorder,
  iconTheme: const IconThemeData(color: AppColors.darkTextSecondary),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: AppColors.darkPrimary,
    foregroundColor: AppColors.darkTextPrimary,
  ),
);
