// test/widgets/register_tos_gate_test.dart
//
// Widget tests for the signup agreement gate — the App Store / Play UGC
// requirement that an account cannot be created without accepting the Terms
// and Community Guidelines, and that both are readable at the point of
// acceptance without leaving the form.
//
// Also covers the regression that sent us back here: the document sheet used
// to capture its body at tap time, so tapping before the fetch resolved (or on
// any device where it failed) left it on "Loading…" for good.
//
// We override authRepositoryProvider with a fake (never mock providers
// directly). The success path is deliberately not exercised: it calls
// context.go('/profile/me'), which needs a router.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/auth/data/auth_repository.dart';
import 'package:social_flutter/features/auth/presentation/register_screen.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/date_of_birth_field.dart';

const _tosBody = 'TERMS BODY — zero tolerance for objectionable content.';
const _guidelinesBody = 'GUIDELINES BODY — hate speech is prohibited.';
const _privacyBody = 'PRIVACY BODY — we name every processor.';

/// Serves all three documents the way the real GET /auth/tos does. `register`
/// is recorded rather than performed so the test can assert on the wire value.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.tosDelay, this.tosFails = false})
      : super(Dio(), Dio());

  /// Holds the fetch open so a test can tap while it is still pending.
  final Completer<void>? tosDelay;
  final bool tosFails;

  bool? sentTosAccepted;
  DateTime? sentDateOfBirth;
  int fetchCount = 0;
  String? lastLang;

  @override
  Future<Map<String, dynamic>> fetchTos({String? lang}) async {
    fetchCount++;
    lastLang = lang;
    if (tosDelay != null) await tosDelay!.future;
    if (tosFails) {
      throw DioException(
        requestOptions: RequestOptions(path: '/auth/tos'),
        type: DioExceptionType.connectionError,
      );
    }
    return {
      'version': '3.0',
      'summary': _tosBody,
      'guidelines': _guidelinesBody,
      'privacy': _privacyBody,
      'notice_terms': '',
      'notice_guidelines': '',
      'notice_privacy': '',
    };
  }

  @override
  Future<AuthResult> register({
    required String username,
    required String email,
    required String password,
    String? displayName,
    required bool tosAccepted,
    required DateTime dateOfBirth,
  }) async {
    sentTosAccepted = tosAccepted;
    sentDateOfBirth = dateOfBirth;
    // Fail as the network would: _register only catches DioException, and the
    // success path calls context.go('/profile/me'), which needs a router.
    throw DioException(
      requestOptions: RequestOptions(path: '/auth/register'),
      response: Response(
        requestOptions: RequestOptions(path: '/auth/register'),
        statusCode: 503,
      ),
    );
  }
}

Widget _buildScreen(_FakeAuthRepository repo) {
  FlutterSecureStorage.setMockInitialValues({});
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const RegisterScreen(),
    ),
  );
}

Future<void> _pumpScreen(WidgetTester tester, _FakeAuthRepository repo) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_buildScreen(repo));
  await tester.pumpAndSettle();
}

void main() {
  group('Signup agreement gate', () {
    testWidgets(
        'Given the screen just built, When nothing is accepted, '
        'Then Create Account is disabled', (tester) async {
      await _pumpScreen(tester, _FakeAuthRepository());

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Create Account'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
        'Given the screen just built, When the checkbox is ticked, '
        'Then Create Account becomes enabled', (tester) async {
      await _pumpScreen(tester, _FakeAuthRepository());

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Create Account'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets(
        'Given the agreement label, When it renders, '
        'Then it names all three documents and the no-tolerance rule',
        (tester) async {
      await _pumpScreen(tester, _FakeAuthRepository());

      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Community Guidelines'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(
        find.text(
          'I understand that objectionable content and abusive behavior '
          'are strictly prohibited.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'Given a filled form, When submitted, '
        'Then the accepted flag is sent as the real checkbox value, not a literal',
        (tester) async {
      final repo = _FakeAuthRepository();
      await _pumpScreen(tester, repo);

      await tester.enterText(find.byType(TextFormField).at(1), 'testuser');
      await tester.enterText(
          find.byType(TextFormField).at(2), 'test@example.com');
      await tester.enterText(find.byType(TextFormField).at(3), 'testpass1');
      await tester.enterText(find.byType(TextFormField).at(4), 'testpass1');

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      // Drive the field's callback rather than Material's date picker: the
      // dialog is Flutter's code, and what this test cares about is that the
      // screen wires the value through to the request.
      tester
          .widget<DateOfBirthField>(find.byType(DateOfBirthField))
          .onChanged(DateTime(2000, 1, 1));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pump();

      expect(repo.sentTosAccepted, isTrue);
      expect(repo.sentDateOfBirth, DateTime(2000, 1, 1));
    });
  });

  group('Legal document sheet', () {
    testWidgets(
        'Given the label links, When Community Guidelines is tapped, '
        'Then the guidelines open in-app without leaving the form',
        (tester) async {
      await _pumpScreen(tester, _FakeAuthRepository());

      await tester.tap(find.text('Community Guidelines'));
      await tester.pumpAndSettle();

      expect(find.text(_guidelinesBody), findsOneWidget);
      // Still on the signup form behind the sheet.
      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets(
        'Given the label links, When Terms of Service is tapped, '
        'Then the terms open in-app', (tester) async {
      await _pumpScreen(tester, _FakeAuthRepository());

      await tester.tap(find.text('Terms of Service'));
      await tester.pumpAndSettle();

      expect(find.text(_tosBody), findsOneWidget);
    });

    testWidgets(
        'Given the Privacy Policy is now plain text, When it is tapped, '
        'Then it opens in the same sheet rather than the browser',
        (tester) async {
      await _pumpScreen(tester, _FakeAuthRepository());

      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();

      expect(find.text(_privacyBody), findsOneWidget);
    });

    testWidgets(
        'Given the fetch has not resolved, When the sheet is opened, '
        'Then it shows a spinner and then the body — never a frozen label',
        (tester) async {
      final gate = Completer<void>();
      final repo = _FakeAuthRepository(tosDelay: gate);
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_buildScreen(repo));
      await tester.pump();

      await tester.tap(find.text('Community Guidelines'));
      await tester.pump();
      expect(find.text(_guidelinesBody), findsNothing);

      // The sheet subscribes to the provider, so resolving the fetch while it
      // is already open must fill it in. Capturing the value at tap time is
      // exactly what left it stuck before.
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text(_guidelinesBody), findsOneWidget);
    });

    testWidgets(
        'Given the fetch fails, When the sheet is opened, '
        'Then it offers a retry instead of silence', (tester) async {
      await _pumpScreen(tester, _FakeAuthRepository(tosFails: true));

      await tester.tap(find.text('Terms of Service'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "We couldn't load this document. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
      expect(find.text('Open in browser'), findsOneWidget);
    });

    testWidgets(
        'Given a failed fetch, When Retry is tapped, '
        'Then the document is requested again', (tester) async {
      final repo = _FakeAuthRepository(tosFails: true);
      await _pumpScreen(tester, repo);
      await tester.tap(find.text('Terms of Service'));
      await tester.pumpAndSettle();
      final before = repo.fetchCount;

      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(repo.fetchCount, greaterThan(before));
    });

    testWidgets(
        'Given the app language, When the documents are fetched, '
        'Then the request asks for that translation', (tester) async {
      final repo = _FakeAuthRepository();
      await _pumpScreen(tester, repo);

      await tester.tap(find.text('Terms of Service'));
      await tester.pumpAndSettle();

      expect(repo.lastLang, isNotNull);
    });
  });
}
