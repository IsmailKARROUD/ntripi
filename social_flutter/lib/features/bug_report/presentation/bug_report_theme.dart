// features/bug_report/presentation/bug_report_theme.dart
//
// Maps the app's design tokens onto the `feedback` package's own theme object,
// so the screenshot/draw layer it renders looks like Ntripi rather than the
// package's grey-and-blue default.
//
// Every value comes from NtripiColors — no Color literal appears here, which
// keeps app_theme.dart the single source of truth for colour (see its header).

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';

/// The app [ThemeData] for the compose sheet.
///
/// The sheet renders above MaterialApp, so nothing hands it a Theme —
/// without this, `context.nt` would fall back to light and every button would
/// use Material defaults. ThemeMode.system is resolved exactly the way the
/// package's own FeedbackApp resolves it, so the sheet and the chrome around it
/// can never disagree about brightness.
ThemeData ntripiFeedbackAppTheme(BuildContext context, ThemeMode mode) {
  final isDark = mode == ThemeMode.dark ||
      (mode == ThemeMode.system &&
          MediaQuery.platformBrightnessOf(context) == Brightness.dark);
  return isDark ? buildNtripiDarkTheme() : buildNtripiTheme();
}

FeedbackThemeData ntripiFeedbackTheme(NtripiColors nt) {
  return FeedbackThemeData(
    brightness: nt.brightness,
    // The backdrop the scaled-down app floats on.
    background: nt.sand,
    feedbackSheetColor: nt.surface,
    dragHandleColor: nt.text3,
    // Tints the active Navigate/Draw toggle and the package's own submit label.
    activeFeedbackModeColor: nt.forest,
    // Marker colours offered in the draw palette. editBlue is deliberately
    // absent — it is reserved for itinerary structure-editing affordances.
    drawColors: [nt.danger, nt.amber, nt.forest, nt.bark],
    bottomSheetDescriptionStyle: TextStyle(
      fontSize: 13.5,
      height: 1.5,
      color: nt.text2,
    ),
    bottomSheetTextInputStyle: TextStyle(fontSize: 15, color: nt.bark),
    // Draggable so the sheet can be pulled up over the keyboard while typing a
    // long report. This is what hands our builder its ScrollController.
    sheetIsDraggable: true,
    // Roomier than the 0.25 default: the sheet carries a category list and a
    // multi-line field, not just one text box.
    feedbackSheetHeight: 0.45,
  );
}
