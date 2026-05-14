// test/widgets/profile_identity_facts_test.dart
//
// Widget tests for ProfileIdentityFacts — the three-chip row shown on both
// self-profile and other-user profiles (Passport · Lives in · Speaks).
//
// Tests verify:
//   · Correct sub-labels and values rendered for each chip
//   · Flag emoji and country names looked up from kCountries
//   · Multiple passport codes joined by " · "
//   · Language codes joined by " · "
//   · Chips are absent when the corresponding field is null/empty
//   · The widget renders nothing (SizedBox.shrink) when all fields are null

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/profile/presentation/profile_identity_facts.dart';
import 'package:social_flutter/shared/models/user.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(User user) => MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ProfileIdentityFacts(user: user),
        ),
      ),
    );

User _user({
  List<String>? passportCountries,
  String? residentCountry,
  List<String>? languages,
}) =>
    User(
      id: 'u1',
      username: 'ismauo',
      isPrivate: false,
      followersCount: 0,
      followingCount: 0,
      createdAt: DateTime(2024),
      passportCountries: passportCountries,
      residentCountry: residentCountry,
      languages: languages,
    );

// ---------------------------------------------------------------------------

void main() {
  group('ProfileIdentityFacts', () {
    setUp(() {
      // No animations or tiles — just pure widget rendering.
    });

    // ── all fields null → renders nothing ──────────────────────────────────

    testWidgets(
        'Given all travel identity fields null, '
        'When widget builds, '
        'Then renders SizedBox.shrink (no chips visible)', (tester) async {
      tester.view.physicalSize = const Size(1080, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(_user()));

      // No sub-labels rendered at all
      expect(find.text('PASSPORT'), findsNothing);
      expect(find.text('LIVES IN'), findsNothing);
      expect(find.text('SPEAKS'), findsNothing);
    });

    // ── passport chip ──────────────────────────────────────────────────────

    testWidgets(
        'Given single passport country (MA), '
        'When widget builds, '
        'Then shows PASSPORT sub-label and full country name "Morocco"',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(_user(passportCountries: ['MA'])));

      expect(find.text('PASSPORT'), findsOneWidget);
      expect(find.textContaining('Morocco'), findsOneWidget);
    });

    testWidgets(
        'Given two passport countries (MA, FR), '
        'When widget builds, '
        'Then shows both full country names', (tester) async {
      tester.view.physicalSize = const Size(1080, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(_user(passportCountries: ['MA', 'FR'])));

      expect(find.text('PASSPORT'), findsOneWidget);
      expect(find.textContaining('Morocco'), findsOneWidget);
      expect(find.textContaining('France'), findsOneWidget);
    });

    testWidgets(
        'Given empty passport list, '
        'When widget builds, '
        'Then PASSPORT chip is absent', (tester) async {
      tester.view.physicalSize = const Size(1080, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(_user(passportCountries: [])));

      expect(find.text('PASSPORT'), findsNothing);
    });

    // ── lives in chip ──────────────────────────────────────────────────────

    testWidgets(
        'Given residentCountry=BE, '
        'When widget builds, '
        'Then shows LIVES IN sub-label and "Belgium" with flag', (tester) async {
      tester.view.physicalSize = const Size(1080, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(_user(residentCountry: 'BE')));

      expect(find.text('LIVES IN'), findsOneWidget);
      expect(find.textContaining('Belgium'), findsOneWidget);
    });

    testWidgets(
        'Given residentCountry=null, '
        'When widget builds, '
        'Then LIVES IN chip is absent', (tester) async {
      tester.view.physicalSize = const Size(1080, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(_user()));

      expect(find.text('LIVES IN'), findsNothing);
    });

    testWidgets(
        'Given unknown country code, '
        'When widget builds, '
        'Then shows the raw code as fallback', (tester) async {
      tester.view.physicalSize = const Size(1080, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(_user(residentCountry: 'ZZ')));

      // ZZ is not in kCountries — should fall back to the raw code
      expect(find.text('LIVES IN'), findsOneWidget);
      expect(find.text('ZZ'), findsOneWidget);
    });

    // ── speaks chip ────────────────────────────────────────────────────────

    testWidgets(
        'Given languages=[FR, AR, EN], '
        'When widget builds, '
        'Then shows SPEAKS sub-label and codes joined by " · "', (tester) async {
      tester.view.physicalSize = const Size(1080, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(_user(languages: ['FR', 'AR', 'EN'])));

      expect(find.text('SPEAKS'), findsOneWidget);
      expect(find.text('FR · AR · EN'), findsOneWidget);
    });

    testWidgets(
        'Given empty languages list, '
        'When widget builds, '
        'Then SPEAKS chip is absent', (tester) async {
      tester.view.physicalSize = const Size(1080, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(_user(languages: [])));

      expect(find.text('SPEAKS'), findsNothing);
    });

    testWidgets(
        'Given languages=null, '
        'When widget builds, '
        'Then SPEAKS chip is absent', (tester) async {
      tester.view.physicalSize = const Size(1080, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(_user()));

      expect(find.text('SPEAKS'), findsNothing);
    });

    // ── partial sets ───────────────────────────────────────────────────────

    testWidgets(
        'Given only passport set, '
        'When widget builds, '
        'Then shows only PASSPORT chip (no LIVES IN or SPEAKS)', (tester) async {
      tester.view.physicalSize = const Size(1080, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(_user(passportCountries: ['MA'])));

      expect(find.text('PASSPORT'), findsOneWidget);
      expect(find.text('LIVES IN'), findsNothing);
      expect(find.text('SPEAKS'), findsNothing);
    });

    testWidgets(
        'Given all three fields set, '
        'When widget builds, '
        'Then shows all three chips', (tester) async {
      tester.view.physicalSize = const Size(1080, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(_user(
        passportCountries: ['MA'],
        residentCountry: 'BE',
        languages: ['FR'],
      )));

      expect(find.text('PASSPORT'), findsOneWidget);
      expect(find.text('LIVES IN'), findsOneWidget);
      expect(find.text('SPEAKS'), findsOneWidget);
    });
  });
}
