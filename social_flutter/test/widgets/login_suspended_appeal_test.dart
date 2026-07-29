// test/widgets/login_suspended_appeal_test.dart
//
// A moderator-suspended account must never hit a dead end: when the backend
// answers a sign-in with `account_deactivated`, the login error banner grows a
// tappable appeal link. Every other failure keeps the plain banner.
//
// The AuthInterceptor also routes such a response to /suspended, but this
// screen is where the user lands again if they walk back and retry.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/auth/data/auth_repository.dart';
import 'package:social_flutter/features/auth/presentation/login_screen.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

/// Fails every login with a fixed backend response. Subclassing the real
/// repository keeps the provider contract honest — no mocking framework.
class _FailingAuthRepository extends AuthRepository {
  _FailingAuthRepository(this._statusCode, this._body) : super(Dio(), Dio());

  final int _statusCode;
  final Map<String, dynamic> _body;

  @override
  Future<AuthResult> login({
    required String identifier,
    required String password,
  }) async {
    final options = RequestOptions(path: '/auth/login');
    throw DioException(
      requestOptions: options,
      response: Response(
        requestOptions: options,
        statusCode: _statusCode,
        data: _body,
      ),
      type: DioExceptionType.badResponse,
    );
  }
}

Widget _host(AuthRepository repo) {
  FlutterSecureStorage.setMockInitialValues({});
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
    ],
    child: MaterialApp(
      theme: buildNtripiTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const LoginScreen(),
    ),
  );
}

Future<void> _signIn(WidgetTester tester, AuthRepository repo) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_host(repo));
  await tester.pump(); // connectivity stream

  await tester.enterText(find.byType(TextFormField).first, 'banned@test.com');
  await tester.enterText(find.byType(TextFormField).last, 'test1234');

  final signIn = find.text('Sign In');
  await tester.ensureVisible(signIn);
  await tester.tap(signIn);
  await tester.pump(); // run the failing login
  await tester.pump(); // rebuild with the error banner
}

void main() {
  group('Login error banner — appeal link', () {
    testWidgets(
        'Given the backend suspends the account, When sign-in fails, '
        'Then the banner offers a tappable appeal link', (tester) async {
      await _signIn(
        tester,
        _FailingAuthRepository(403, {
          'code': 'account_deactivated',
          'detail': 'Your account has been deactivated.',
        }),
      );

      expect(find.text('Your account has been deactivated.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Appeal this decision'),
          findsOneWidget);
    });

    testWidgets(
        'Given bad credentials, When sign-in fails, '
        'Then no appeal link is offered', (tester) async {
      await _signIn(
        tester,
        _FailingAuthRepository(401, {
          'code': 'login_invalid',
          'detail': 'Incorrect email/username or password.',
        }),
      );

      expect(find.text('Incorrect email/username or password.'),
          findsOneWidget);
      expect(find.text('Appeal this decision'), findsNothing);
    });
  });
}
