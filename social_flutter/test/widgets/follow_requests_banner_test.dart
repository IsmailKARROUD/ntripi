// test/widgets/follow_requests_banner_test.dart
//
// Isolated widget tests for FollowRequestsBanner.
// Asserts the count is interpolated, the subtitle copy is shown, and the
// tap callback fires.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/profile/presentation/widgets/follow_requests_banner.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

Widget _host({required int count, required VoidCallback onTap}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: FollowRequestsBanner(count: count, onTap: onTap),
    ),
  );
}

void main() {
  group('FollowRequestsBanner', () {
    testWidgets(
        'Given count=3, When widget builds, '
        'Then title shows "Follow Requests (3)" and "Tap to review"',
        (tester) async {
      await tester.pumpWidget(_host(count: 3, onTap: () {}));
      await tester.pump();

      expect(find.text('Follow Requests (3)'), findsOneWidget);
      expect(find.text('Tap to review'), findsOneWidget);
    });

    testWidgets(
        'Given count=1, When widget builds, '
        'Then title interpolates singular count', (tester) async {
      await tester.pumpWidget(_host(count: 1, onTap: () {}));
      await tester.pump();

      expect(find.text('Follow Requests (1)'), findsOneWidget);
    });

    testWidgets(
        'Given banner rendered, When tapped, '
        'Then onTap fires exactly once', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(count: 2, onTap: () => taps++));
      await tester.pump();

      await tester.tap(find.byType(FollowRequestsBanner));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets(
        'Given banner rendered, When widget builds, '
        'Then person-add icon and chevron are present', (tester) async {
      await tester.pumpWidget(_host(count: 1, onTap: () {}));
      await tester.pump();

      expect(find.byIcon(Icons.person_add_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });
  });
}
