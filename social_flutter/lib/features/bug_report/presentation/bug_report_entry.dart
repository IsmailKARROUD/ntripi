// features/bug_report/presentation/bug_report_entry.dart
//
// The one way into the bug reporter, shared by the shake gesture and the
// Settings ▸ Support row. Two call sites, one flow — a second entry point that
// drifted would mean reports arriving without diagnostics.

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/features/bug_report/data/bug_report_repository.dart';
import 'package:social_flutter/features/bug_report/data/diagnostics_service.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

/// Opens the screenshot + draw + compose flow.
///
/// [context] must sit below the BetterFeedback mounted in MaterialApp.builder.
void startBugReport(BuildContext context, WidgetRef ref) {
  final controller = BetterFeedback.of(context);
  // Guard the caller as well as the shake handler: the settings row and a
  // shake could otherwise both fire during the same frame.
  if (controller.isVisible) return;

  // Captured before any await — the feedback UI covers the screen, so this
  // messenger is the only one that can show the confirmation once it closes.
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context)!;

  controller.show((feedback) async {
    final diagnostics = await collectDiagnostics(ref);
    // Deliberately unguarded: BugReportSheet awaits this callback and keeps
    // itself open (with the user's text intact) when it throws.
    await ref.read(bugReportRepositoryProvider).submit(
          message: feedback.text,
          category: feedback.extra?['category'] as String?,
          diagnostics: diagnostics,
          screenshot: feedback.screenshot,
        );
    controller.hide();
    messenger.showSnackBar(SnackBar(content: Text(l10n.bugReportThanks)));
  });
}
