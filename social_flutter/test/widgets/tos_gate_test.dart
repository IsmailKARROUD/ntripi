// test/widgets/tos_gate_test.dart
//
// The re-acceptance gate. Accounts created before a ToS revision carry the old
// version, and the server reports that as tos_current: false — this widget is
// what stops them using the app until they accept.
//
// The gate is mounted in MaterialApp.router's builder, above every route, so
// these tests exercise it directly with a stand-in child.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/auth/data/auth_repository.dart';
import 'package:social_flutter/features/auth/presentation/accept_terms_screen.dart';
import 'package:social_flutter/features/auth/presentation/widgets/tos_gate.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';

const _appContent = 'THE APP';

User _user({required bool tosCurrent}) => User(
      id: 'u1',
      username: 'traveller',
      email: 'traveller@example.com',
      createdAt: DateTime(2026, 1, 1),
      isPrivate: false,
      followersCount: 0,
      followingCount: 0,
      tosCurrent: tosCurrent,
    );

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(Dio(), Dio());

  int acceptCount = 0;

  @override
  Future<void> acceptTos() async => acceptCount++;
}

/// Stands in for MyProfileNotifier so the gate reads a known tos_current
/// without an HTTP round-trip.
class _FakeProfileNotifier extends MyProfileNotifier {
  _FakeProfileNotifier(this.user);

  final User user;

  @override
  Future<User> build() async => user;
}

Future<void> _pumpGate(
  WidgetTester tester, {
  required bool tosCurrent,
  required bool signedIn,
  AuthRepository? repo,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasSessionProvider.overrideWith((ref) async => signedIn),
        myProfileProvider.overrideWith(
          () => _FakeProfileNotifier(_user(tosCurrent: tosCurrent)),
        ),
        if (repo != null) authRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TosGate(child: Scaffold(body: Text(_appContent))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('TosGate', () {
    testWidgets(
        'Given a signed-in user on the current revision, When the app builds, '
        'Then the app renders normally', (tester) async {
      await _pumpGate(tester, tosCurrent: true, signedIn: true);

      expect(find.text(_appContent), findsOneWidget);
      expect(find.byType(AcceptTermsScreen), findsNothing);
    });

    testWidgets(
        'Given a signed-in user on an older revision, When the app builds, '
        'Then the accept-terms screen replaces it', (tester) async {
      await _pumpGate(tester, tosCurrent: false, signedIn: true);

      expect(find.byType(AcceptTermsScreen), findsOneWidget);
      expect(find.text(_appContent), findsNothing);
    });

    testWidgets(
        'Given nobody is signed in, When the app builds, '
        'Then the gate stays out of the way', (tester) async {
      // Otherwise /login and /register would be blocked by a profile they
      // have no token to fetch.
      await _pumpGate(tester, tosCurrent: false, signedIn: false);

      expect(find.text(_appContent), findsOneWidget);
      expect(find.byType(AcceptTermsScreen), findsNothing);
    });
  });

  group('AcceptTermsScreen', () {
    testWidgets(
        'Given the gate is showing, When nothing is ticked, '
        'Then Accept is disabled', (tester) async {
      await _pumpGate(tester, tosCurrent: false, signedIn: true);

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Accept and continue'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
        'Given the gate is showing, When the agreement is ticked, '
        'Then accepting records it with the server', (tester) async {
      final repo = _FakeAuthRepository();
      await _pumpGate(
        tester, tosCurrent: false, signedIn: true, repo: repo,
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Accept and continue'),
      );
      await tester.pumpAndSettle();

      expect(repo.acceptCount, 1);
    });

    testWidgets(
        'Given a user who will not accept, When the gate is showing, '
        'Then there is still a way out', (tester) async {
      // A gate with no exit is a lockout — they must at least be able to sign
      // out, which is also how they reach account deletion.
      await _pumpGate(tester, tosCurrent: false, signedIn: true);

      expect(find.widgetWithText(TextButton, 'Log out'), findsOneWidget);
    });
  });
}
