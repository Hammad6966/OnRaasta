import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

ThemeData lightTheme = ThemeData(
  brightness: Brightness.light,
  scaffoldBackgroundColor: AppColors.lightBg,
  colorScheme: const ColorScheme.light(
    surface: AppColors.lightSurface,
    primary: AppColors.lightPrimary,
    secondary: AppColors.lightAccent,
    error: AppColors.lightError,
    onPrimary: Colors.white,
    onSurface: AppColors.lightTextPrimary,
    outline: AppColors.lightBorder,
    surfaceContainerHighest: AppColors.lightSurfaceVariant,
  ),
  textTheme: GoogleFonts.dmSansTextTheme(ThemeData.light().textTheme).copyWith(
    displayLarge:  GoogleFonts.syne(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w800),
    displayMedium: GoogleFonts.syne(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w700),
    displaySmall:  GoogleFonts.syne(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w700),
    headlineLarge:  GoogleFonts.syne(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w700),
    headlineMedium: GoogleFonts.syne(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w600),
    headlineSmall:  GoogleFonts.syne(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w600),
    titleLarge:  GoogleFonts.syne(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w600),
    titleMedium: GoogleFonts.syne(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w600),
    bodyLarge:   GoogleFonts.dmSans(color: AppColors.lightTextPrimary),
    bodyMedium:  GoogleFonts.dmSans(color: AppColors.lightTextPrimary),
    bodySmall:   GoogleFonts.dmSans(color: AppColors.lightTextSecondary),
    labelLarge:  GoogleFonts.dmSans(color: AppColors.lightTextPrimary, fontWeight: FontWeight.w500),
    labelSmall:  GoogleFonts.dmSans(color: AppColors.lightTextSecondary),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: AppColors.lightBg,
    elevation: 0,
    scrolledUnderElevation: 0,
    iconTheme: const IconThemeData(color: AppColors.lightTextPrimary),
    titleTextStyle: GoogleFonts.syne(
      color: AppColors.lightTextPrimary,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
  ),
  cardTheme: CardThemeData(
    color: AppColors.lightSurface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: AppColors.lightBorder),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.lightSurface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.lightBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.lightBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.lightPrimary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.lightError),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.lightError, width: 1.5),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: AppColors.lightBorder.withOpacity(0.5)),
    ),
    labelStyle: GoogleFonts.dmSans(
      color: AppColors.lightTextSecondary,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    ),
    hintStyle: GoogleFonts.dmSans(color: AppColors.lightTextSecondary, fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.lightPrimary,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.lightPrimary.withOpacity(0.5),
      elevation: 0,
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w500),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.lightTextPrimary,
      side: const BorderSide(color: AppColors.lightBorder, width: 1.5),
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w500),
    ),
  ),
  dividerColor: AppColors.lightBorder,
  iconTheme: const IconThemeData(color: AppColors.lightTextSecondary),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: AppColors.lightPrimary,
    foregroundColor: Colors.white,
  ),
);
