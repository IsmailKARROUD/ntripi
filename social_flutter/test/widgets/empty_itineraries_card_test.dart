// test/widgets/empty_itineraries_card_test.dart
//
// Isolated widget tests for EmptyItinerariesCard.
// Covers the primary "Create itinerary" CTA, the secondary "Browse for ideas"
// row, and the callback wiring.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/profile/presentation/widgets/empty_itineraries_card.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

Widget _host({
  required VoidCallback onCreateTap,
  required VoidCallback onExploreTap,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: EmptyItinerariesCard(
          onCreateTap: onCreateTap,
          onExploreTap: onExploreTap,
        ),
      ),
    ),
  );
}

void main() {
  group('EmptyItinerariesCard', () {
    testWidgets(
        'Given widget builds, '
        'Then primary card shows headline, hint and Create CTA',
        (tester) async {
      await tester.pumpWidget(_host(onCreateTap: () {}, onExploreTap: () {}));
      await tester.pump();

      expect(find.text('Plan your first journey'), findsOneWidget);
      expect(
        find.textContaining('Add stops, transit segments'),
        findsOneWidget,
      );
      expect(find.text('Create itinerary'), findsOneWidget);
    });

    testWidgets(
        'Given widget builds, '
        'Then secondary card shows "Need inspiration?" and explore copy',
        (tester) async {
      await tester.pumpWidget(_host(onCreateTap: () {}, onExploreTap: () {}));
      await tester.pump();

      expect(find.text('Need inspiration?'), findsOneWidget);
      expect(
        find.textContaining('Browse your itineraries'),
        findsOneWidget,
      );
    });

    testWidgets(
        'Given widget rendered, When Create itinerary tapped, '
        'Then onCreateTap fires and onExploreTap does not', (tester) async {
      var creates = 0;
      var explores = 0;
      await tester.pumpWidget(_host(
        onCreateTap: () => creates++,
        onExploreTap: () => explores++,
      ));
      await tester.pump();

      await tester.tap(find.text('Create itinerary'));
      await tester.pump();

      expect(creates, 1);
      expect(explores, 0);
    });

    testWidgets(
        'Given widget rendered, When explore row tapped, '
        'Then onExploreTap fires and onCreateTap does not', (tester) async {
      var creates = 0;
      var explores = 0;
      await tester.pumpWidget(_host(
        onCreateTap: () => creates++,
        onExploreTap: () => explores++,
      ));
      await tester.pump();

      await tester.tap(find.text('Need inspiration?'));
      await tester.pump();

      expect(explores, 1);
      expect(creates, 0);
    });
  });
}
