// features/bug_report/presentation/ntripi_feedback.dart
//
// The bug reporter's layer over the whole app: the one BetterFeedback
// configuration. main.dart mounts it and so do the bug reporter's tests, so the
// reporter a test opens is the reporter a user opens —
// test/feedback_mount_guard_test.dart keeps any other BetterFeedback out of lib/.

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/bug_report/presentation/bug_report_localizations.dart';
import 'package:ntripi/features/bug_report/presentation/bug_report_sheet.dart';
import 'package:ntripi/features/bug_report/presentation/bug_report_theme.dart';
import 'package:ntripi/l10n/app_localizations.dart';

/// Shake-to-report's screenshot, draw and compose layer around [child], the
/// app's MaterialApp.
///
/// It must sit ABOVE MaterialApp: its bottom sheet builds a bare Navigator, and
/// inside MaterialApp that Navigator would inherit the app's HeroController —
/// which asserts, because a HeroController cannot be shared by two Navigators.
class NtripiFeedback extends StatelessWidget {
  const NtripiFeedback({
    super.key,
    required this.themeMode,
    required this.locale,
    required this.child,
  });

  /// The app's theme mode — the reporter follows it as MaterialApp does.
  final ThemeMode themeMode;

  /// The app's language, from the in-app picker.
  final Locale locale;

  /// The app.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BetterFeedback(
      // Above MaterialApp there is no Theme to read, so both brightnesses are
      // supplied and BetterFeedback picks one from themeMode, exactly as
      // MaterialApp does below.
      theme: ntripiFeedbackTheme(NtripiColors.light),
      darkTheme: ntripiFeedbackTheme(NtripiColors.dark),
      themeMode: themeMode,
      // FeedbackApp builds its own Localizations scope from exactly these
      // delegates. The app's own are listed so the compose sheet — which
      // renders in that scope, not MaterialApp's — can still use l10n.
      localizationsDelegates: [
        const NtripiFeedbackLocalizationsDelegate(),
        ...AppLocalizations.localizationsDelegates,
      ],
      // That scope otherwise resolves the *platform* locale, ignoring the
      // in-app language picker. It also drives Directionality, so this is
      // what makes the sheet lay out RTL in Arabic.
      localeOverride: locale,
      feedbackBuilder: (ctx, onSubmit, scrollController) => Theme(
        // The sheet is outside MaterialApp, so the app theme has to be handed
        // to it explicitly — see ntripiFeedbackAppTheme.
        data: ntripiFeedbackAppTheme(ctx, themeMode),
        child: BugReportSheet(
          onSubmit: onSubmit,
          scrollController: scrollController,
        ),
      ),
      // The 3.0 default yields a ~1290×2796 PNG on a modern phone, against a
      // 10 MB request cap and a mobile uplink. The backend downscales to a
      // 1600 px long side anyway.
      pixelRatio: 2.0,
      child: child,
    );
  }
}
