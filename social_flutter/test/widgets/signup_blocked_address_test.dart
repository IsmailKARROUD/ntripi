// test/widgets/signup_blocked_address_test.dart
//
// Erasing a suspended account blocks its address from signing up again, and both
// sign-up paths answer 400 `email_unavailable`
// (docs/features/account-deletion.md). These tests drive the real screens against
// a fake repository and look at what the person sees:
//
//   - the refusal in their own language, never the server's English `detail`;
//   - everything they typed still there, and nobody signed in;
//   - on the Google path, no consent sheet and no birthday prompt for an answer
//     that was always going to be no — only `tos_required` opens the sheet.
//
// The Google plugin cannot run under test, so `googleSignInServiceProvider` hands
// the login screen a fake. Web's rendered button (kIsWeb) shares
// `_completeGoogleSignIn` with the path driven here.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/auth/google_signin_service.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/auth/data/auth_repository.dart';
import 'package:ntripi/features/auth/presentation/login_screen.dart';
import 'package:ntripi/features/auth/presentation/register_screen.dart';
import 'package:ntripi/features/auth/providers/auth_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/date_of_birth_field.dart';

const _blocked = 'blocked@example.com';

/// What the server sends: an English `detail` no reader should have to read.
const _serverDetail = "This email address can't be used to create an account.";

DioException _answer(String path, String code) {
  final options = RequestOptions(path: path);
  return DioException(
    requestOptions: options,
    response: Response(
      requestOptions: options,
      statusCode: code == 'account_deactivated' ? 403 : 400,
      data: {'detail': _serverDetail, 'code': code},
    ),
    type: DioExceptionType.badResponse,
  );
}

/// Refuses every request and records what was sent. Subclassing the real
/// repository keeps the provider contract honest. Nothing here succeeds on
/// purpose: a success goes on to `landHome`, which needs a router, and these tests
/// are about the person who never gets that far.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.googleCodes = const []}) : super(Dio(), Dio());

  /// What each post to /auth/google answers, in order.
  final List<String> googleCodes;
  final List<({bool tosAccepted, DateTime? dateOfBirth})> googleCalls = [];

  final List<String> registerEmails = [];

  /// Holds the next register open, to look at the screen mid-request.
  Completer<void>? holdNextRegister;

  @override
  Future<Map<String, dynamic>> fetchTos({String? lang}) async => {
        'version': '3.3',
        'summary': 'TERMS BODY',
        'guidelines': 'GUIDELINES BODY',
        'privacy': 'PRIVACY BODY',
        'notice_terms': '',
        'notice_guidelines': '',
        'notice_privacy': '',
      };

  @override
  Future<AuthResult> register({
    required String username,
    required String email,
    required String password,
    String? displayName,
    required bool tosAccepted,
    required DateTime dateOfBirth,
  }) async {
    registerEmails.add(email);
    final hold = holdNextRegister;
    holdNextRegister = null;
    if (hold != null) await hold.future;
    throw _answer(kRegisterEndpoint, 'email_unavailable');
  }

  @override
  Future<AuthResult> loginWithGoogle({
    required String idToken,
    bool tosAccepted = false,
    DateTime? dateOfBirth,
    String? googleAccessToken,
  }) async {
    final code = googleCodes[googleCalls.length];
    googleCalls.add((tosAccepted: tosAccepted, dateOfBirth: dateOfBirth));
    throw _answer(kGoogleAuthEndpoint, code);
  }
}

class _FakeGoogle implements GoogleSignInService {
  _FakeGoogle({this.idToken = 'id-token', this.pluginFails = false});

  final String? idToken;
  final bool pluginFails;
  int birthdayPrompts = 0;

  @override
  Future<String?> obtainIdToken() async {
    if (pluginFails) throw StateError('the plugin failed');
    return idToken;
  }

  /// Null is the ordinary outcome of a declined scope, and it keeps the test off
  /// the People API; the prompt having been shown is what gets counted.
  @override
  Future<String?> obtainBirthdayAccessToken() async {
    birthdayPrompts++;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<AppLocalizations> _pump(
  WidgetTester tester,
  Widget screen,
  _FakeAuthRepository repo, {
  _FakeGoogle? google,
  String lang = 'en',
  Size size = const Size(1080, 2400),
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        googleSignInServiceProvider.overrideWithValue(google ?? _FakeGoogle()),
      ],
      child: MaterialApp(
        theme: buildNtripiTheme(),
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return lookupAppLocalizations(Locale(lang));
}

/// Who the app thinks is signed in, as the screen's own provider scope sees it.
String? _signedIn(WidgetTester tester, Type screen) =>
    ProviderScope.containerOf(tester.element(find.byType(screen)))
        .read(authNotifierProvider);

Future<void> _fillRegisterForm(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(1), 'newtraveller');
  await tester.enterText(find.byType(TextFormField).at(2), _blocked);
  await tester.enterText(find.byType(TextFormField).at(3), 'testpass1');
  await tester.enterText(find.byType(TextFormField).at(4), 'testpass1');
  // The field's callback rather than Material's date picker: the dialog is
  // Flutter's code, and it is not what these tests are about.
  tester
      .widget<DateOfBirthField>(find.byType(DateOfBirthField))
      .onChanged(DateTime(2000, 1, 1));
  await tester.pump();
  await tester.ensureVisible(find.byType(Checkbox));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Checkbox));
  await tester.pumpAndSettle();
}

Future<void> _submitRegisterForm(WidgetTester tester, AppLocalizations l10n) async {
  final button = find.widgetWithText(ElevatedButton, l10n.registerCreateAccount);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
}

Future<void> _continueWithGoogle(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.text(l10n.loginContinueWithProvider('Google')));
  await tester.pumpAndSettle();
}

/// The login screen stays busy behind the consent sheet, and that overlay's spinner
/// never lets `pumpAndSettle` return while the sheet is open.
Future<void> _pumpUnderTheSpinner(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _continueToTheConsentSheet(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  await tester.tap(find.text(l10n.loginContinueWithProvider('Google')));
  await _pumpUnderTheSpinner(tester);
}

void main() {
  group('RegisterScreen, an address that may not sign up', () {
    for (final lang in ['fr', 'ar']) {
      testWidgets(
          'Given the blocked address and a reader in "$lang", '
          'When the form is submitted, '
          'Then the refusal is in their language and nothing is lost',
          (tester) async {
        final repo = _FakeAuthRepository();
        final l10n = await _pump(tester, const RegisterScreen(), repo, lang: lang);

        await _fillRegisterForm(tester);
        await _submitRegisterForm(tester, l10n);
        await tester.pumpAndSettle();

        expect(find.text(l10n.apiErrorEmailUnavailable), findsOneWidget);
        expect(find.text(_serverDetail), findsNothing);
        // What they typed is the only copy of it.
        expect(find.text(_blocked), findsOneWidget);
        expect(find.text('newtraveller'), findsOneWidget);
        expect(repo.registerEmails, [_blocked]);
        expect(_signedIn(tester, RegisterScreen), isNull);
        // Free to try another address: the screen is not left busy.
        final button = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, l10n.registerCreateAccount),
        );
        expect(button.onPressed, isNotNull);
      });
    }

    testWidgets(
        'Given the refusal on screen, '
        'When the person changes the address and submits again, '
        'Then the refusal clears while it is asked and the new address is sent',
        (tester) async {
      final repo = _FakeAuthRepository();
      final l10n = await _pump(tester, const RegisterScreen(), repo);
      await _fillRegisterForm(tester);
      await _submitRegisterForm(tester, l10n);
      await tester.pumpAndSettle();
      expect(find.text(l10n.apiErrorEmailUnavailable), findsOneWidget);

      final answer = Completer<void>();
      repo.holdNextRegister = answer;
      await tester.enterText(find.byType(TextFormField).at(2), 'other@example.com');
      await _submitRegisterForm(tester, l10n);
      await tester.pump(); // the spinner runs while it is held: never settles

      expect(find.text(l10n.apiErrorEmailUnavailable), findsNothing);
      expect(repo.registerEmails, [_blocked, 'other@example.com']);

      answer.complete();
      await tester.pumpAndSettle();
      expect(find.text(l10n.apiErrorEmailUnavailable), findsOneWidget);
    });

    testWidgets(
        'Given a phone, where the form scrolls, '
        'When the refusal comes back, '
        'Then it is on screen without scrolling back up to look for it',
        (tester) async {
      // Not 390 wide: the test font draws "Tripi" at 102 px, not 44, and overflows the header.
      const phone = Size(412, 732);
      final repo = _FakeAuthRepository();
      final l10n = await _pump(tester, const RegisterScreen(), repo, size: phone);

      await _fillRegisterForm(tester);
      await _submitRegisterForm(tester, l10n);
      await tester.pumpAndSettle();

      final refusal = find.text(l10n.apiErrorEmailUnavailable);
      // The premise: this phone really did have to scroll down to the button.
      expect(Scrollable.of(tester.element(refusal)).position.pixels, greaterThan(0));
      final rect = tester.getRect(refusal);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(phone.height));
    });
  });

  group('LoginScreen, signing up with Google', () {
    testWidgets(
        'Given the blocked address, '
        'When the first post is refused, '
        'Then it says so with no consent sheet, birthday prompt or second post',
        (tester) async {
      final repo = _FakeAuthRepository(googleCodes: ['email_unavailable']);
      final google = _FakeGoogle();
      final l10n = await _pump(
        tester, const LoginScreen(), repo, google: google, lang: 'fr',
      );

      await _continueWithGoogle(tester, l10n);

      expect(find.text(l10n.apiErrorEmailUnavailable), findsOneWidget);
      expect(find.text(_serverDetail), findsNothing);
      expect(find.text(l10n.googleTosAccept), findsNothing);
      expect(google.birthdayPrompts, 0);
      expect(repo.googleCalls, hasLength(1));
      expect(repo.googleCalls.single.tosAccepted, isFalse);
      expect(_signedIn(tester, LoginScreen), isNull);
      // Nothing to appeal: the account is gone. Only a suspension offers that.
      expect(find.text(l10n.suspendedAppealButton), findsNothing);
    });

    testWidgets(
        'Given the address is blocked between the two posts, '
        'When the person accepts the terms, '
        'Then the sheet closes and the refusal shows on the login screen',
        (tester) async {
      final repo = _FakeAuthRepository(
        googleCodes: ['tos_required', 'email_unavailable'],
      );
      final google = _FakeGoogle();
      final l10n = await _pump(
        tester, const LoginScreen(), repo, google: google, lang: 'fr',
      );

      await _continueToTheConsentSheet(tester, l10n);
      expect(find.text(l10n.googleTosAccept), findsOneWidget);
      expect(google.birthdayPrompts, 1);

      tester
          .widget<DateOfBirthField>(find.byType(DateOfBirthField))
          .onChanged(DateTime(2000, 1, 1));
      await tester.pump();
      await tester.tap(find.byType(Checkbox));
      await _pumpUnderTheSpinner(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, l10n.googleTosAccept));
      await tester.pumpAndSettle();

      expect(find.text(l10n.googleTosAccept), findsNothing);
      expect(find.text(l10n.apiErrorEmailUnavailable), findsOneWidget);
      expect(repo.googleCalls.map((call) => call.tosAccepted), [false, true]);
      expect(repo.googleCalls.last.dateOfBirth, DateTime(2000, 1, 1));
      expect(_signedIn(tester, LoginScreen), isNull);
    });

    testWidgets(
        'Given a suspended account that still exists, '
        'When Google is refused with account_deactivated, '
        'Then the appeal link is offered, as the erased case never is',
        (tester) async {
      final repo = _FakeAuthRepository(googleCodes: ['account_deactivated']);
      final l10n = await _pump(tester, const LoginScreen(), repo);

      await _continueWithGoogle(tester, l10n);

      expect(find.text(l10n.suspendedAppealButton), findsOneWidget);
      expect(find.text(l10n.googleTosAccept), findsNothing);
    });

    testWidgets(
        'Given a brand-new account, '
        'When the person declines the terms, '
        'Then nothing is posted again and no error is shown', (tester) async {
      final repo = _FakeAuthRepository(googleCodes: ['tos_required']);
      final l10n = await _pump(tester, const LoginScreen(), repo);

      await _continueToTheConsentSheet(tester, l10n);
      await tester.tap(find.widgetWithText(TextButton, l10n.cancel));
      await tester.pumpAndSettle();

      expect(find.text(l10n.googleTosAccept), findsNothing);
      expect(repo.googleCalls, hasLength(1));
      expect(find.text(_serverDetail), findsNothing);
      expect(_signedIn(tester, LoginScreen), isNull);
    });

    testWidgets(
        'Given the Google picker, '
        'When the person cancels it, '
        'Then nothing is posted and no error is shown', (tester) async {
      final repo = _FakeAuthRepository();
      final l10n = await _pump(
        tester, const LoginScreen(), repo, google: _FakeGoogle(idToken: null),
      );

      await _continueWithGoogle(tester, l10n);

      expect(repo.googleCalls, isEmpty);
      expect(find.text(l10n.errorGenericRetry), findsNothing);
    });

    testWidgets(
        'Given the Google plugin fails, '
        'When the person continues with Google, '
        'Then a generic retry message shows and nothing is posted',
        (tester) async {
      final repo = _FakeAuthRepository();
      final l10n = await _pump(
        tester, const LoginScreen(), repo, google: _FakeGoogle(pluginFails: true),
      );

      await _continueWithGoogle(tester, l10n);

      expect(find.text(l10n.errorGenericRetry), findsOneWidget);
      expect(repo.googleCalls, isEmpty);
    });
  });
}
