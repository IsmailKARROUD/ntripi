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

// Rating score colors: 1=red · 2=orange · 3=amber · 4=lime · 5=green
const kRatingRed = Color(0xFFF01A1A);
const kRatingOrange = Color(0xFFD4611A);
const kRatingLimeGreen = Color(0xFF7AAE35);

/// Maps a 1–5 rating score to a semantic color (decimals supported).
Color ratingColor(double score) {
  if (score >= 4.5) return kCanopy;
  if (score >= 3.5) return kRatingLimeGreen;
  if (score >= 2.5) return kAmber;
  if (score >= 1.5) return kRatingOrange;
  return kRatingRed;
}

// Surface / border / secondary-text shades derived from the palette
const kSurface = Colors.white;
const kBorder = Color(0xFFE4EDE6);
const kText2 = Color(0xFF5A7562);
const kText3 = Color(0xFF93A898);
ThemeData buildNtripiTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: kForest,
    onPrimary: Colors.white,
    primaryContainer: kMist,
    onPrimaryContainer: kBark,
    secondary: kAmber,
    onSecondary: Colors.white,
    secondaryContainer:  Color(0xFFFFF0CC),
    onSecondaryContainer:  Color(0xFF3B2000),
    tertiary: kCanopy,
    onTertiary: Colors.white,
    tertiaryContainer:  Color(0xFFD0EDD8),
    onTertiaryContainer: kBark,
    error:  Color(0xFFBA1A1A),
    onError: Colors.white,
    errorContainer:  Color(0xFFFFDAD6),
    onErrorContainer:  Color(0xFF410002),
    surface: kSurface,
    onSurface: kBark,
    surfaceContainerHighest:  Color(0xFFEFF2EC),
    onSurfaceVariant:  Color(0xFF44483E),
    outline: kBorder,
    outlineVariant:  Color(0xFFC4CAC0),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: kBark,
    onInverseSurface:  Color(0xFFEFF1EB),
    inversePrimary:  Color(0xFF74D098),
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
      color: kSurface,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: kBorder),
      ),
      margin: EdgeInsets.zero,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kBorder),
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
      labelStyle: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: kText2),
      hintStyle: GoogleFonts.dmSans(color: kText3),
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
        side: const BorderSide(color: kBorder),
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
      backgroundColor: kSurface,
      selectedItemColor: kForest,
      unselectedItemColor: kText3,
      selectedLabelStyle: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w600),
      unselectedLabelStyle: GoogleFonts.dmSans(fontSize: 10),
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),

    dividerTheme: const DividerThemeData(color: kBorder, space: 1, thickness: 1),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return kForest;
        return Colors.transparent;
      }),
      side: const BorderSide(color: kBorder, width: 1.5),
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
