// shared/widgets/reload_report.dart — how a screen shows that a reload the
// user started failed while the content stayed on screen.

import 'package:flutter/material.dart';
import 'package:ntripi/core/api/api_client.dart';
import 'package:ntripi/core/providers/reload_keeps_content.dart';
import 'package:ntripi/l10n/app_localizations.dart';

/// Awaits [reloads] — `refresh()` calls the user started: a pull-to-refresh, a
/// Retry — and shows the first failure that left content on screen as a
/// SnackBar. With nothing on screen a failure is the error view's to show and
/// comes back null, so the same call serves the error view's Retry as well.
///
/// Full-screen routes only: a SnackBar draws behind a sheet's barrier, where a
/// sheet shows its failure inline instead.
Future<void> reportReloads(
  BuildContext context,
  List<Future<ReloadFailure?>> reloads,
) async {
  final failures = await Future.wait(reloads);
  final failure = failures.nonNulls.firstOrNull;
  if (failure == null) return;
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(
        extractErrorMessage(failure.error, AppLocalizations.of(context)),
      ),
    ),
  );
}
