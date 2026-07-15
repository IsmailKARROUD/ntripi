import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// This file is the single source of truth for EVERY color in the app.
// Rule: no Color literal may exist outside this file (Colors.transparent
// excepted). Theme-dependent colors live on [NtripiColors] (light + dark);
// brightness-independent brand artwork colors live on [NtripiBrand].
// ─────────────────────────────────────────────────────────────────────────────

// ── Brand constants (brightness-INDEPENDENT) ─────────────────────────────────
// Colors of the brand artwork itself — logo mark, splash art, chrome drawn
// over photos. These must NOT flip with the theme: the logo is the logo.
abstract final class NtripiBrand {
  static const forest = Color(0xFF1F5E3A); // deep brand green (splash bg, logo tile)
  static const canopy = Color(0xFF2D7D52); // logo tile variant on dark grounds
  static const amber = Color(0xFFC89030);  // logo sun dot
  static const mint = Color(0xFF94D4A8);   // wordmark tint on dark grounds
  static const chrome = Colors.white;      // marks/text over brand fills & photos
  static const chrome66 = Color(0xA8FFFFFF); // 66% chrome — splash tagline
  static const chrome40 = Color(0x66FFFFFF); // 40% chrome — splash motto
  static const scrimInk = Color(0xFF1A2A1E); // gradient scrim base over photos
  static const backdrop = Colors.black;      // fullscreen photo-viewer bg, over-tile shadows
}

/// Theme-dependent design tokens. Resolve via `context.nt`.
///
/// Every field has a light and a dark value; fields that must not vary with
/// brightness (overlayChrome, buttonTransparent) carry the same value in both
/// instances so call sites stay literal-free.
class NtripiColors extends ThemeExtension<NtripiColors> {
  final Brightness brightness;

  // Core palette
  final Color forest;  // primary green — accent/text in dark, deep fill in light
  final Color canopy;  // mid green
  final Color mist;    // soft green tint (chips, icon pills)
  final Color amber;   // accent gold
  final Color sand;    // warm elevated bg (sheets, section cards)
  final Color bark;    // primary text
  final Color surface; // page/card background
  final Color border;
  final Color text2;   // secondary text
  final Color text3;   // tertiary text / hints

  // Inverse of the page surface — a dark chip in light mode, light in dark.
  // Used to make an element stand out against the plain surface.
  final Color inverseSurface;
  final Color onInverseSurface;

  // Danger — destructive-action affordances
  final Color danger;
  final Color dangerTint;

  // Transit / amber palette — transit segment rows
  final Color transitBg;
  final Color transitBorder;
  final Color transitIcon;
  final Color transitText;

  // Action blue — RESERVED for itinerary structure-editing affordances only
  // (edit pencils, move/reorder/add controls); do not reuse elsewhere.
  final Color editBlue;
  final Color editBlueTint;

  // Rating score scale (1=red … 5=green); see [rating].
  final Color ratingRed;
  final Color ratingOrange;
  final Color ratingLimeGreen;

  // Annotation editorial pairs (advice / caution / avoid / info)
  final Color adviceBg;
  final Color adviceFg;
  final Color cautionBg;
  final Color cautionFg;
  final Color avoidBg;
  final Color avoidFg;
  final Color infoBg;
  final Color infoFg;

  // Place-type categorical accents (PlaceType.color)
  final Color placeEatDrink;
  final Color placeSleep;
  final Color placePray;
  final Color placeLearnSee;
  final Color placeBuy;
  final Color placePlayWatch;
  final Color placeNature;
  final Color placeTransport;
  final Color placeHealBathe;
  final Color placeEntertainment;
  final Color placeSight;

  // Stylized map artwork (ItineraryCoverPlaceholder)
  final Color mapLandStart;
  final Color mapLandEnd;
  final Color mapWater;
  final Color mapPark;
  final Color mapBuilding;
  final Color mapStreetThin;
  final Color mapAvenue;
  final Color mapRoute;
  final Color mapInk;
  final Color mapPinEnds;
  final Color mapPinLabel;
  final Color mapLabelBg;
  final Color mapMark;

  // Overlays / effects
  final Color overlayChrome;     // white chrome over photos/scrims — same in both modes
  final Color buttonTransparent; // frosted dark overlay buttons — same in both modes
  final Color scrim;             // modal barrier (alpha baked in)
  final Color shadow;            // soft shadow base — use .withValues(alpha:)
  final Color shimmerHighlight;  // skeleton shimmer peak over mist

  // Avatar initial pairs (bg, fg) — index by name-hash, see editorial_widgets
  final List<(Color, Color)> avatarPairs;

  const NtripiColors({
    required this.brightness,
    required this.forest,
    required this.canopy,
    required this.mist,
    required this.amber,
    required this.sand,
    required this.bark,
    required this.surface,
    required this.border,
    required this.text2,
    required this.text3,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.danger,
    required this.dangerTint,
    required this.transitBg,
    required this.transitBorder,
    required this.transitIcon,
    required this.transitText,
    required this.editBlue,
    required this.editBlueTint,
    required this.ratingRed,
    required this.ratingOrange,
    required this.ratingLimeGreen,
    required this.adviceBg,
    required this.adviceFg,
    required this.cautionBg,
    required this.cautionFg,
    required this.avoidBg,
    required this.avoidFg,
    required this.infoBg,
    required this.infoFg,
    required this.placeEatDrink,
    required this.placeSleep,
    required this.placePray,
    required this.placeLearnSee,
    required this.placeBuy,
    required this.placePlayWatch,
    required this.placeNature,
    required this.placeTransport,
    required this.placeHealBathe,
    required this.placeEntertainment,
    required this.placeSight,
    required this.mapLandStart,
    required this.mapLandEnd,
    required this.mapWater,
    required this.mapPark,
    required this.mapBuilding,
    required this.mapStreetThin,
    required this.mapAvenue,
    required this.mapRoute,
    required this.mapInk,
    required this.mapPinEnds,
    required this.mapPinLabel,
    required this.mapLabelBg,
    required this.mapMark,
    required this.overlayChrome,
    required this.buttonTransparent,
    required this.scrim,
    required this.shadow,
    required this.shimmerHighlight,
    required this.avatarPairs,
  });

  static const light = NtripiColors(
    brightness: Brightness.light,
    forest: Color(0xFF1F5E3A),
    canopy: Color(0xFF2D7D52),
    mist: Color(0xFFD0EBDA),
    amber: Color(0xFFC89030),
    sand: Color(0xFFF5F2EC),
    bark: Color(0xFF1A2A1E),
    surface: Colors.white,
    border: Color(0xFFE4EDE6),
    text2: Color(0xFF5A7562),
    text3: Color(0xFF93A898),
    inverseSurface: Color(0xFF1A2A1E),
    onInverseSurface: Color(0xFFEFF1EB),
    danger: Color(0xFFBA1A1A),
    dangerTint: Color(0xFFFCECEC),
    transitBg: Color(0xFFFFF8EC),
    transitBorder: Color(0xFFF0E2C2),
    transitIcon: Color(0xFFA06D1F),
    transitText: Color(0xFF8A5A18),
    editBlue: Color(0xFA2563C9),
    editBlueTint: Color(0xFFE8F0FC),
    ratingRed: Color(0xFFF01A1A),
    ratingOrange: Color(0xFFD4611A),
    ratingLimeGreen: Color(0xFF7AAE35),
    adviceBg: Color(0xFFE0EBE4),
    adviceFg: Color(0xFF1F5E3A),
    cautionBg: Color(0xFFFFE3CC),
    cautionFg: Color(0xFFA05D1F),
    avoidBg: Color(0xFFFFD6D2),
    avoidFg: Color(0xFFA02828),
    infoBg: Color(0xFFDCEAF6),
    infoFg: Color(0xFF3B6EA5),
    placeEatDrink: Color(0xFFE65100),
    placeSleep: Color(0xFF5E35B1),
    placePray: Color(0xFF00897B),
    placeLearnSee: Color(0xFF1E88E5),
    placeBuy: Color(0xFFD81B60),
    placePlayWatch: Color(0xFF43A047),
    placeNature: Color(0xFF2E7D32),
    placeTransport: Color(0xFF546E7A),
    placeHealBathe: Color(0xFF0097A7),
    placeEntertainment: Color(0xFF6A1B9A),
    placeSight: Color(0xFFF57F17),
    mapLandStart: Color(0xFFEAEBEC),
    mapLandEnd: Color(0xFFD9DBDE),
    mapWater: Color(0xE6C7D0D4),
    mapPark: Color(0xD9CDD6CD),
    mapBuilding: Color(0x2E6E7B74),
    mapStreetThin: Color(0xB3FFFFFF),
    mapAvenue: Colors.white,
    mapRoute: Color(0xFF5E6B64),
    mapInk: Color(0xFF4B554F),
    mapPinEnds: Color(0xFF6E7B74),
    mapPinLabel: Colors.white,
    mapLabelBg: Color(0xD1FFFFFF),
    mapMark: Color(0xFF8C9891),
    overlayChrome: Colors.white,
    buttonTransparent: Color(0x55000000),
    scrim: Color(0x75142018), // ≈ rgba(20,32,24,0.46)
    shadow: Color(0xFF002814),
    shimmerHighlight: Colors.white,
    avatarPairs: [
      (Color(0xFFD0EBDA), Color(0xFF1F5E3A)),
      (Color(0xFFFFE3CC), Color(0xFFA05D1F)),
      (Color(0xFFE0DAF0), Color(0xFF5A3F8F)),
      (Color(0xFFF4D4A8), Color(0xFF8A3A1F)),
      (Color(0xFFCDE0D6), Color(0xFF3B6EA5)),
    ],
  );

  // Warm green-tinted dark neutrals — no pure black; the sand/surface
  // luminance relationship inverts (elevated layers get lighter).
  static const dark = NtripiColors(
    brightness: Brightness.dark,
    forest: Color(0xFF74D098),
    canopy: Color(0xFF57BB83),
    mist: Color(0xFF1F3A2A),
    amber: Color(0xFFDFAE55),
    sand: Color(0xFF1C231D),
    bark: Color(0xFFE2E9E2),
    surface: Color(0xFF121813),
    border: Color(0xFF2A342C),
    text2: Color(0xFFA8BCAE),
    text3: Color(0xFF75897B),
    inverseSurface: Color(0xFFE2E9E2),
    onInverseSurface: Color(0xFF2B322C),
    danger: Color(0xFFFFB4AB), // M3 dark-error convention
    dangerTint: Color(0xFF3B211F),
    transitBg: Color(0xFF262014),
    transitBorder: Color(0xFF463B24),
    transitIcon: Color(0xFFDBAE60),
    transitText: Color(0xFFD3A85C),
    editBlue: Color(0xFF9DC0F5),
    editBlueTint: Color(0xFF1C2938),
    ratingRed: Color(0xFFFF7A6E),
    ratingOrange: Color(0xFFEF8E50),
    ratingLimeGreen: Color(0xFF9DCC57),
    adviceBg: Color(0xFF203226),
    adviceFg: Color(0xFF74D098),
    cautionBg: Color(0xFF33261A),
    cautionFg: Color(0xFFE0A468),
    avoidBg: Color(0xFF39211F),
    avoidFg: Color(0xFFEC9B93),
    infoBg: Color(0xFF1C2A38),
    infoFg: Color(0xFF96BEE8),
    placeEatDrink: Color(0xFFFFB074),
    placeSleep: Color(0xFFB39DDB),
    placePray: Color(0xFF4DB6AC),
    placeLearnSee: Color(0xFF90CAF9),
    placeBuy: Color(0xFFF48FB1),
    placePlayWatch: Color(0xFF81C784),
    placeNature: Color(0xFF9CCC65),
    placeTransport: Color(0xFFB0BEC5),
    placeHealBathe: Color(0xFF80DEEA),
    placeEntertainment: Color(0xFFCE93D8),
    placeSight: Color(0xFFFFD54F),
    mapLandStart: Color(0xFF23282A),
    mapLandEnd: Color(0xFF1B2022),
    mapWater: Color(0xE62E3A40),
    mapPark: Color(0xD9263129),
    mapBuilding: Color(0x2EA9B8AE),
    mapStreetThin: Color(0x38FFFFFF),
    mapAvenue: Color(0xFF3A4346),
    mapRoute: Color(0xFF9DB2A5),
    mapInk: Color(0xFFD6DED8),
    mapPinEnds: Color(0xFF97A79B),
    mapPinLabel: Color(0xFF1B2022),
    mapLabelBg: Color(0xD1242B28),
    mapMark: Color(0xFF5C6862),
    overlayChrome: Colors.white,
    buttonTransparent: Color(0x55000000),
    scrim: Color(0xA6000000),
    shadow: Colors.black,
    shimmerHighlight: Color(0xFF2B4A38),
    avatarPairs: [
      (Color(0xFF1F3A2A), Color(0xFF8FD4AA)),
      (Color(0xFF33261A), Color(0xFFE0A468)),
      (Color(0xFF2A2338), Color(0xFFC3B2E8)),
      (Color(0xFF362A1A), Color(0xFFE3B583)),
      (Color(0xFF20302A), Color(0xFF96BEE8)),
    ],
  );

  /// Maps a 1–5 rating score to a semantic color (decimals supported).
  Color rating(double score) {
    if (score >= 4.5) return canopy;
    if (score >= 3.5) return ratingLimeGreen;
    if (score >= 2.5) return amber;
    if (score >= 1.5) return ratingOrange;
    return ratingRed;
  }

  // Nothing ever mutates a single field of the palette — identity is enough.
  @override
  NtripiColors copyWith() => this;

  @override
  NtripiColors lerp(NtripiColors? other, double t) {
    if (other is! NtripiColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return NtripiColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      forest: c(forest, other.forest),
      canopy: c(canopy, other.canopy),
      mist: c(mist, other.mist),
      amber: c(amber, other.amber),
      sand: c(sand, other.sand),
      bark: c(bark, other.bark),
      surface: c(surface, other.surface),
      border: c(border, other.border),
      inverseSurface: c(inverseSurface, other.inverseSurface),
      onInverseSurface: c(onInverseSurface, other.onInverseSurface),
      text2: c(text2, other.text2),
      text3: c(text3, other.text3),
      danger: c(danger, other.danger),
      dangerTint: c(dangerTint, other.dangerTint),
      transitBg: c(transitBg, other.transitBg),
      transitBorder: c(transitBorder, other.transitBorder),
      transitIcon: c(transitIcon, other.transitIcon),
      transitText: c(transitText, other.transitText),
      editBlue: c(editBlue, other.editBlue),
      editBlueTint: c(editBlueTint, other.editBlueTint),
      ratingRed: c(ratingRed, other.ratingRed),
      ratingOrange: c(ratingOrange, other.ratingOrange),
      ratingLimeGreen: c(ratingLimeGreen, other.ratingLimeGreen),
      adviceBg: c(adviceBg, other.adviceBg),
      adviceFg: c(adviceFg, other.adviceFg),
      cautionBg: c(cautionBg, other.cautionBg),
      cautionFg: c(cautionFg, other.cautionFg),
      avoidBg: c(avoidBg, other.avoidBg),
      avoidFg: c(avoidFg, other.avoidFg),
      infoBg: c(infoBg, other.infoBg),
      infoFg: c(infoFg, other.infoFg),
      placeEatDrink: c(placeEatDrink, other.placeEatDrink),
      placeSleep: c(placeSleep, other.placeSleep),
      placePray: c(placePray, other.placePray),
      placeLearnSee: c(placeLearnSee, other.placeLearnSee),
      placeBuy: c(placeBuy, other.placeBuy),
      placePlayWatch: c(placePlayWatch, other.placePlayWatch),
      placeNature: c(placeNature, other.placeNature),
      placeTransport: c(placeTransport, other.placeTransport),
      placeHealBathe: c(placeHealBathe, other.placeHealBathe),
      placeEntertainment: c(placeEntertainment, other.placeEntertainment),
      placeSight: c(placeSight, other.placeSight),
      mapLandStart: c(mapLandStart, other.mapLandStart),
      mapLandEnd: c(mapLandEnd, other.mapLandEnd),
      mapWater: c(mapWater, other.mapWater),
      mapPark: c(mapPark, other.mapPark),
      mapBuilding: c(mapBuilding, other.mapBuilding),
      mapStreetThin: c(mapStreetThin, other.mapStreetThin),
      mapAvenue: c(mapAvenue, other.mapAvenue),
      mapRoute: c(mapRoute, other.mapRoute),
      mapInk: c(mapInk, other.mapInk),
      mapPinEnds: c(mapPinEnds, other.mapPinEnds),
      mapPinLabel: c(mapPinLabel, other.mapPinLabel),
      mapLabelBg: c(mapLabelBg, other.mapLabelBg),
      mapMark: c(mapMark, other.mapMark),
      overlayChrome: c(overlayChrome, other.overlayChrome),
      buttonTransparent: c(buttonTransparent, other.buttonTransparent),
      scrim: c(scrim, other.scrim),
      shadow: c(shadow, other.shadow),
      shimmerHighlight: c(shimmerHighlight, other.shimmerHighlight),
      avatarPairs: [
        for (var i = 0; i < avatarPairs.length; i++)
          (
            c(avatarPairs[i].$1, other.avatarPairs[i].$1),
            c(avatarPairs[i].$2, other.avatarPairs[i].$2),
          ),
      ],
    );
  }
}

extension NtripiThemeX on BuildContext {
  /// Falls back to light so bare-MaterialApp widget tests keep working.
  NtripiColors get nt =>
      Theme.of(this).extension<NtripiColors>() ?? NtripiColors.light;
}

const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF1F5E3A),
  onPrimary: Colors.white,
  primaryContainer: Color(0xFFD0EBDA),
  onPrimaryContainer: Color(0xFF1A2A1E),
  secondary: Color(0xFFC89030),
  onSecondary: Colors.white,
  secondaryContainer: Color(0xFFFFF0CC),
  onSecondaryContainer: Color(0xFF3B2000),
  tertiary: Color(0xFF2D7D52),
  onTertiary: Colors.white,
  tertiaryContainer: Color(0xFFD0EDD8),
  onTertiaryContainer: Color(0xFF1A2A1E),
  error: Color(0xFFBA1A1A),
  onError: Colors.white,
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),
  surface: Colors.white,
  onSurface: Color(0xFF1A2A1E),
  surfaceContainerHighest: Color(0xFFEFF2EC),
  onSurfaceVariant: Color(0xFF44483E),
  outline: Color(0xFFE4EDE6),
  outlineVariant: Color(0xFFC4CAC0),
  shadow: Colors.black,
  scrim: Colors.black,
  inverseSurface: Color(0xFF1A2A1E),
  onInverseSurface: Color(0xFFEFF1EB),
  inversePrimary: Color(0xFF74D098),
  surfaceTint: Color(0xFF1F5E3A),
);

const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF74D098),
  onPrimary: Color(0xFF00391D),
  primaryContainer: Color(0xFF1F5E3A),
  onPrimaryContainer: Color(0xFFD0EBDA),
  secondary: Color(0xFFDFAE55),
  onSecondary: Color(0xFF402D00),
  secondaryContainer: Color(0xFF5C4200),
  onSecondaryContainer: Color(0xFFFFDEA8),
  tertiary: Color(0xFF57BB83),
  onTertiary: Color(0xFF00391D),
  tertiaryContainer: Color(0xFF1F5E3A),
  onTertiaryContainer: Color(0xFFD0EDD8),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF121813),
  onSurface: Color(0xFFE2E9E2),
  surfaceContainerHighest: Color(0xFF232B24),
  onSurfaceVariant: Color(0xFFBFC9BC),
  outline: Color(0xFF2A342C),
  outlineVariant: Color(0xFF3F4A41),
  shadow: Colors.black,
  scrim: Colors.black,
  inverseSurface: Color(0xFFE2E9E2),
  onInverseSurface: Color(0xFF2B322C),
  inversePrimary: Color(0xFF1F5E3A),
  surfaceTint: Color(0xFF74D098),
);

ThemeData buildNtripiTheme() => _buildTheme(NtripiColors.light, _lightScheme);
ThemeData buildNtripiDarkTheme() => _buildTheme(NtripiColors.dark, _darkScheme);

ThemeData _buildTheme(NtripiColors nt, ColorScheme scheme) {
  final isDark = nt.brightness == Brightness.dark;
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final dmSans = GoogleFonts.dmSansTextTheme(base.textTheme);

  return base.copyWith(
    extensions: [nt],
    scaffoldBackgroundColor: nt.surface,
    textTheme: dmSans,
    primaryTextTheme: GoogleFonts.dmSansTextTheme(base.primaryTextTheme),

    appBarTheme: AppBarTheme(
      backgroundColor: nt.surface,
      foregroundColor: nt.bark,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.dmSans(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: nt.bark,
      ),
      iconTheme: IconThemeData(color: nt.bark),
      // Status/nav bar icons must flip with the theme (AppBar-less screens
      // get the same style via the AnnotatedRegion in main.dart).
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: nt.brightness,
        systemNavigationBarColor: nt.surface,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    ),

    cardTheme: CardThemeData(
      color: nt.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: nt.border),
      ),
      margin: EdgeInsets.zero,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: nt.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: nt.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: nt.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: nt.forest, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: nt.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: nt.danger, width: 1.5),
      ),
      labelStyle: GoogleFonts.dmSans(
          fontSize: 12, fontWeight: FontWeight.w600, color: nt.text2),
      hintStyle: GoogleFonts.dmSans(color: nt.text3),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: nt.forest,
        // onPrimary, not white — dark mode's light-green fill needs deep-green text
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: nt.forest.withValues(alpha: 0.4),
        disabledForegroundColor: scheme.onPrimary.withValues(alpha: 0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(vertical: 15),
        elevation: 0,
        shadowColor: Colors.transparent,
        textStyle: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: nt.forest,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(vertical: 15),
        textStyle: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: nt.forest,
        side: BorderSide(color: nt.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: nt.forest,
        textStyle: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: nt.forest,
      foregroundColor: scheme.onPrimary,
      elevation: 4,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),

    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: nt.surface,
      selectedItemColor: nt.forest,
      unselectedItemColor: nt.text3,
      selectedLabelStyle:
          GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w600),
      unselectedLabelStyle: GoogleFonts.dmSans(fontSize: 10),
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: nt.surface,
      modalBackgroundColor: nt.sand,
      surfaceTintColor: Colors.transparent,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: nt.surface,
      surfaceTintColor: Colors.transparent,
    ),

    dividerTheme: DividerThemeData(color: nt.border, space: 1, thickness: 1),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return nt.forest;
        return Colors.transparent;
      }),
      side: BorderSide(color: nt.border, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      // inverseSurface flips per mode — dark snackbar on light, light on dark
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: GoogleFonts.dmSans(color: scheme.onInverseSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: nt.mist,
      labelStyle: GoogleFonts.dmSans(
          fontSize: 11, fontWeight: FontWeight.w500, color: nt.forest),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(color: nt.forest),
  );
}
