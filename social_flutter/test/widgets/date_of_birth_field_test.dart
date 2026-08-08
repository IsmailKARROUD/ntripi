// The shared birthdate field. Its age check mirrors the server's, so the two
// have to agree on the boundary — the server is still the authority, but a
// client that disagreed would either nag a valid user or promise an underage
// one an account it will not get.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/date_of_birth_field.dart';

/// A birth date making someone exactly [years] old today, shifted by
/// [offsetDays] (positive = younger). Built relative to now for the same
/// reason the backend tests are: a literal stops testing anything in a year.
DateTime _dobForAge(int years, {int offsetDays = 0}) {
  final now = DateTime.now();
  return DateTime(now.year - years, now.month, now.day)
      .add(Duration(days: offsetDays));
}

Future<void> _pumpField(
  WidgetTester tester, {
  required DateTime? value,
  required GlobalKey<FormState> formKey,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Form(
          key: formKey,
          child: DateOfBirthField(value: value, onChanged: (_) {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('DateOfBirthField.isOldEnough', () {
    test('the sixteenth birthday itself counts', () {
      expect(DateOfBirthField.isOldEnough(DateTime(2010, 8, 8),
          now: DateTime(2026, 8, 8)), isTrue);
    });

    test('one day short does not', () {
      expect(DateOfBirthField.isOldEnough(DateTime(2010, 8, 9),
          now: DateTime(2026, 8, 8)), isFalse);
    });

    test('a leap-day birth has not aged on 28 February', () {
      // Born 29 Feb 2008: the birthday has not happened yet on 28 Feb 2024.
      expect(DateOfBirthField.isOldEnough(DateTime(2008, 2, 29),
          now: DateTime(2024, 2, 28)), isFalse);
      expect(DateOfBirthField.isOldEnough(DateTime(2008, 2, 29),
          now: DateTime(2024, 3, 1)), isTrue);
    });

    test('a birthday later this year is not yet counted', () {
      expect(DateOfBirthField.isOldEnough(DateTime(2010, 12, 31),
          now: DateTime(2026, 1, 1)), isFalse);
    });
  });

  group('DateOfBirthField validation', () {
    testWidgets('an empty field reports that it is required', (tester) async {
      final formKey = GlobalKey<FormState>();
      await _pumpField(tester, value: null, formKey: formKey);

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Your date of birth is required.'), findsOneWidget);
    });

    testWidgets('an underage date reports the minimum', (tester) async {
      final formKey = GlobalKey<FormState>();
      await _pumpField(
        tester, value: _dobForAge(kMinimumAge, offsetDays: 1), formKey: formKey,
      );

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('You must be at least 16 to use Ntripi.'), findsOneWidget);
    });

    testWidgets('an adult date validates cleanly', (tester) async {
      final formKey = GlobalKey<FormState>();
      await _pumpField(tester, value: _dobForAge(30), formKey: formKey);

      expect(formKey.currentState!.validate(), isTrue);
    });

    testWidgets('exactly the minimum validates', (tester) async {
      final formKey = GlobalKey<FormState>();
      await _pumpField(tester, value: _dobForAge(kMinimumAge), formKey: formKey);

      expect(formKey.currentState!.validate(), isTrue);
    });

    testWidgets('nothing is preselected — the screen must stay neutral',
        (tester) async {
      // Opening on a plausible adult birthday would be a leading question.
      final formKey = GlobalKey<FormState>();
      await _pumpField(tester, value: null, formKey: formKey);

      expect(find.text('Select your date of birth'), findsOneWidget);
    });
  });
}
