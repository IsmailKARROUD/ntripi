// The bug reporter is configured once, in NtripiFeedback
// (lib/features/bug_report/presentation/ntripi_feedback.dart): main.dart mounts
// it and so do the bug reporter's tests. Before it, the tests mounted a hand
// copy of main.dart's BetterFeedback, fixed to the light theme, and stayed
// green while a phone in dark mode with the app set to Light opened the
// reporter onto a failed assertion (2026-11-09).
//
// This holds it for code nobody has written yet: no other file in lib/ may
// build a BetterFeedback.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _home = 'lib/features/bug_report/presentation/ntripi_feedback.dart';

void main() {
  test('only $_home builds a BetterFeedback', () {
    // `BetterFeedback(` builds one; `BetterFeedback.of(` only looks it up.
    final builds = RegExp(r'\bBetterFeedback\s*\(');
    final builders = {
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        if (file.readAsLinesSync().any((line) =>
            !line.trimLeft().startsWith('//') && builds.hasMatch(line)))
          file.path,
    };
    expect(builders, {_home},
        reason: 'mount NtripiFeedback, never a BetterFeedback of your own: '
            'it is the reporter the tests open.');
  });
}
