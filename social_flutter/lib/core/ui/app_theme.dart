import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Design tokens ────────────────────────────────────────────────────────────
// Converted from the NTripi design's oklch palette to sRGB approximations.
const kForest = Color(0xFF1F5E3A); // oklch(34% 0.11 150) — primary green
const kCanopy = Color(0xFF2D7D52); // oklch(48% 0.13 150) — mid green
const kMist = Color(0xFFD0EBDA);   // oklch(90% 0.06 150) — light green tint
const kAmber = Color(0xFFC89030);  // oklch(66% 0.17 75)  — accent gold
const kSand = Color(0xFFF5F2EC);   // oklch(97% 0.008 80) — warm cream bg
const kBark = Color(0xFF1A2A1E);   // oklch(18% 0.03 150) — near-black text

// Surface / border shades derived from the palette
const _surface = Colors.white;
const _border = Color(0xFFE4EDE6);
const _text2 = Color(0xFF5A7562);
const _text3 = Color(0xFF93A898);
ThemeData buildNtripiTheme() {
  final scheme = ColorScheme(
    brightness: Brightness.light,
    primary: kForest,
    onPrimary: Colors.white,
    primaryContainer: kMist,
    onPrimaryContainer: kBark,
    secondary: kAmber,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFFFF0CC),
    onSecondaryContainer: const Color(0xFF3B2000),
    tertiary: kCanopy,
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFD0EDD8),
    onTertiaryContainer: kBark,
    error: const Color(0xFFBA1A1A),
    onError: Colors.white,
    errorContainer: const Color(0xFFFFDAD6),
    onErrorContainer: const Color(0xFF410002),
    surface: _surface,
    onSurface: kBark,
    surfaceContainerHighest: const Color(0xFFEFF2EC),
    onSurfaceVariant: const Color(0xFF44483E),
    outline: _border,
    outlineVariant: const Color(0xFFC4CAC0),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: kBark,
    onInverseSurface: const Color(0xFFEFF1EB),
    inversePrimary: const Color(0xFF74D098),
    surfaceTint: kForest,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final dmSans = GoogleFonts.dmSansTextTheme(base.textTheme);

  return base.copyWith(
    scaffoldBackgroundColor: kSand,
    textTheme: dmSans,
    primaryTextTheme: GoogleFonts.dmSansTextTheme(base.primaryTextTheme),

    appBarTheme: AppBarTheme(
      backgroundColor: kSand,
      foregroundColor: kBark,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.dmSans(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: kBark,
      ),
      iconTheme: const IconThemeData(color: kBark),
    ),

    cardTheme: CardThemeData(
      color: _surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _border),
      ),
      margin: EdgeInsets.zero,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kForest, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFBA1A1A)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFBA1A1A), width: 1.5),
      ),
      labelStyle: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: _text2),
      hintStyle: GoogleFonts.dmSans(color: _text3),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kForest,
        foregroundColor: Colors.white,
        disabledBackgroundColor: kForest.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white70,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(vertical: 15),
        elevation: 0,
        shadowColor: Colors.transparent,
        textStyle: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kForest,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(vertical: 15),
        textStyle: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kForest,
        side: const BorderSide(color: _border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kForest,
        textStyle: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kForest,
      foregroundColor: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),

    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: _surface,
      selectedItemColor: kForest,
      unselectedItemColor: _text3,
      selectedLabelStyle: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w600),
      unselectedLabelStyle: GoogleFonts.dmSans(fontSize: 10),
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),

    dividerTheme: const DividerThemeData(color: _border, space: 1, thickness: 1),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return kForest;
        return Colors.transparent;
      }),
      side: const BorderSide(color: _border, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kBark,
      contentTextStyle: GoogleFonts.dmSans(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: kMist,
      labelStyle: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w500, color: kForest),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(color: kForest),
  );
}
