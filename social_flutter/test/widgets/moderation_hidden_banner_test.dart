// test/widgets/moderation_hidden_banner_test.dart
//
// The banner is the only place an author is told their content was taken down,
// and the only in-context route to an appeal. These tests pin the two things
// that would silently break that: the optional reason line, and the appeal
// action disappearing when there is nothing to appeal against.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/moderation_hidden_banner.dart';

void main() {
  const appealButton = Key('moderationAppealButton');

  Future<void> pumpBanner(
    WidgetTester tester, {
    String message = 'Only you can see this.',
    String? reason,
    VoidCallback? onAppeal,
  }) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ModerationHiddenBanner(
            message: message,
            reason: reason,
            onAppeal: onAppeal,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Given no reason, When rendered, Then only the message shows',
      (tester) async {
    await pumpBanner(tester);

    expect(find.text('Only you can see this.'), findsOneWidget);
    expect(find.textContaining('Reason:'), findsNothing);
  });

  testWidgets('Given a reason, When rendered, Then the reason line shows',
      (tester) async {
    await pumpBanner(tester, reason: 'Hate speech');

    expect(find.textContaining('Hate speech'), findsOneWidget);
  });

  testWidgets(
      'Given a blank reason, When rendered, Then no empty reason line shows',
      (tester) async {
    await pumpBanner(tester, reason: '   ');

    expect(find.textContaining('Reason:'), findsNothing);
  });

  testWidgets('Given no onAppeal, When rendered, Then no appeal action shows',
      (tester) async {
    await pumpBanner(tester);

    expect(find.byKey(appealButton), findsNothing);
  });

  testWidgets('Given onAppeal, When tapped, Then the callback fires',
      (tester) async {
    var taps = 0;
    await pumpBanner(tester, onAppeal: () => taps++);

    await tester.tap(find.byKey(appealButton));
    await tester.pump();

    expect(taps, 1);
  });
}
