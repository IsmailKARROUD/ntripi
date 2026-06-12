// test/widgets/locked_profile_card_test.dart
//
// Isolated widget tests for LockedProfileCard.
// Covers the two states (private-not-following vs request-pending) and
// confirms the {handle} placeholder is interpolated.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/profile/presentation/widgets/locked_profile_card.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

Widget _host({required bool isPending, required String handle}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: LockedProfileCard(isPending: isPending, handle: handle),
    ),
  );
}

void main() {
  group('LockedProfileCard', () {
    testWidgets(
        'Given isPending=false and handle=@aminad, When widget builds, '
        'Then shows lock icon, private title and follow-to-see body',
        (tester) async {
      await tester.pumpWidget(_host(isPending: false, handle: '@aminad'));
      await tester.pump();

      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.text('This account is private'), findsOneWidget);
      expect(
        find.textContaining('Follow @aminad to see'),
        findsOneWidget,
      );
    });

    testWidgets(
        'Given isPending=true, When widget builds, '
        'Then shows hourglass icon, "Request sent" and pending body',
        (tester) async {
      await tester.pumpWidget(_host(isPending: true, handle: '@aminad'));
      await tester.pump();

      expect(find.byIcon(Icons.hourglass_empty_rounded), findsOneWidget);
      expect(find.text('Request sent'), findsOneWidget);
      expect(
        find.textContaining('Once they accept'),
        findsOneWidget,
      );
    });

    testWidgets(
        'Given isPending=true, When widget builds, '
        'Then handle text is not present (pending copy is handle-agnostic)',
        (tester) async {
      await tester.pumpWidget(_host(isPending: true, handle: '@aminad'));
      await tester.pump();

      // Pending message uses generic "they" — never interpolates the handle.
      expect(find.textContaining('@aminad'), findsNothing);
    });
  });
}
