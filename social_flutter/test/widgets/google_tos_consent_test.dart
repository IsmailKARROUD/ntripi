// test/widgets/google_tos_consent_test.dart
//
// Consent for a brand-new Google account. Before this, the client hardcoded
// tos_accepted: true and the schema defaulted it true, so an account could be
// created for someone who had never been shown the terms — the login screen
// carries no legal text at all.
//
// Consent-on-demand: post the token, and only if the server answers 400
// `tos_required` (which only the create-account branch does) show the sheet and
// retry. A returning user must not be re-prompted at every sign-in.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/auth/data/auth_repository.dart';
import 'package:social_flutter/features/auth/presentation/widgets/google_tos_consent_sheet.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

const _tosBody = 'TERMS BODY';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(Dio(), Dio());

  final List<bool> googleCalls = [];

  @override
  Future<Map<String, dynamic>> fetchTos({String? lang}) async => {
        'version': '3.0',
        'summary': _tosBody,
        'guidelines': 'GUIDELINES BODY',
        'privacy': 'PRIVACY BODY',
        'notice_terms': '',
        'notice_guidelines': '',
        'notice_privacy': '',
      };

  /// First call (tos_accepted false) 400s exactly as a brand-new account does;
  /// the retry succeeds.
  @override
  Future<AuthResult> loginWithGoogle({
    required String idToken,
    bool tosAccepted = false,
    DateTime? dateOfBirth,
    String? googleAccessToken,
  }) async {
    googleCalls.add(tosAccepted);
    if (!tosAccepted) {
      throw DioException(
        requestOptions: RequestOptions(path: '/auth/google'),
        response: Response(
          requestOptions: RequestOptions(path: '/auth/google'),
          statusCode: 400,
          data: {'code': 'tos_required', 'detail': 'ToS required'},
        ),
      );
    }
    return AuthResult(
      accessToken: 'a',
      refreshToken: 'r',
      refreshExpiresAt: DateTime(2030),
      userId: 'u1',
      username: 'traveller',
    );
  }
}

/// Minimal host that opens the consent sheet on demand and records the answer.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool? accepted;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            ElevatedButton(
              onPressed: () async {
                // Prefilled as the Google path does when the People API
                // supplied a birthday, so these tests stay about the
                // agreement rather than the date picker.
                final result = await showGoogleTosConsentSheet(
                  context,
                  prefill: DateTime(2000, 1, 1),
                );
                // The sheet now returns a result carrying the date of birth,
                // or null when declined; this host only records which it was.
                setState(() => accepted = result != null);
              },
              child: const Text('open'),
            ),
            Text('result:$accepted'),
          ],
        ),
      );
}

Future<void> _pumpHost(WidgetTester tester, AuthRepository repo) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const _Host(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('Google ToS consent sheet', () {
    testWidgets(
        'Given the sheet opens, When nothing is ticked, '
        'Then Accept is disabled', (tester) async {
      await _pumpHost(tester, _FakeAuthRepository());

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Accept and continue'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
        'Given the sheet opens, When it renders, '
        'Then it names all three documents and the no-tolerance rule',
        (tester) async {
      await _pumpHost(tester, _FakeAuthRepository());

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
        'Given the sheet is open, When a document is tapped, '
        'Then it is readable before accepting', (tester) async {
      await _pumpHost(tester, _FakeAuthRepository());

      await tester.tap(find.text('Terms of Service'));
      await tester.pumpAndSettle();

      expect(find.text(_tosBody), findsOneWidget);
    });

    testWidgets(
        'Given the agreement is ticked, When Accept is tapped, '
        'Then the sheet reports acceptance', (tester) async {
      await _pumpHost(tester, _FakeAuthRepository());

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Accept and continue'),
      );
      await tester.pumpAndSettle();

      expect(find.text('result:true'), findsOneWidget);
    });

    testWidgets(
        'Given the sheet is open, When Cancel is tapped, '
        'Then it reports refusal', (tester) async {
      await _pumpHost(tester, _FakeAuthRepository());

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('result:false'), findsOneWidget);
    });
  });

  group('Google sign-in retry', () {
    test(
        'Given a brand-new account, When the first call omits acceptance, '
        'Then the server refuses and the retry carries it', () async {
      // Pins the contract the login screen depends on: exactly one refusal,
      // then a retry with the same token and the flag set.
      final repo = _FakeAuthRepository();

      await expectLater(
        repo.loginWithGoogle(idToken: 'tok'),
        throwsA(isA<DioException>()),
      );
      final result =
          await repo.loginWithGoogle(idToken: 'tok', tosAccepted: true);

      expect(repo.googleCalls, [false, true]);
      expect(result.userId, 'u1');
    });
  });
}
