// test/widgets/delete_account_screen_test.dart
//
// Widget tests for DeleteAccountScreen's account-type branch: password
// accounts re-enter a password; passwordless (SSO/Google) accounts re-auth
// with the provider instead. We override myProfileProvider with a fake
// notifier (never mock providers directly) and assert on the rendered
// re-auth affordance. Deletion itself hits the Google plugin / go_router and
// is covered end-to-end by the backend integration tests.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/profile/data/profile_repository.dart';
import 'package:social_flutter/features/profile/presentation/delete_account_screen.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';

User _user({required bool hasPassword, bool hasGoogle = false}) => User(
      id: 'user-1',
      username: 'ismauo',
      displayName: 'Ismail',
      isPrivate: false,
      followersCount: 0,
      followingCount: 0,
      hasPassword: hasPassword,
      hasGoogle: hasGoogle,
      createdAt: DateTime(2024),
    );

class _FakeMyProfile extends MyProfileNotifier {
  _FakeMyProfile(this._u);
  final User _u;
  @override
  Future<User> build() async => _u;
}

/// Records whether the delete call reached the repository — used to prove the
/// empty-password guard short-circuits before any network call.
class _RecordingRepo extends ProfileRepository {
  _RecordingRepo() : super(Dio());
  bool deleteCalled = false;
  @override
  Future<void> deleteAccount({String? password, String? googleIdToken}) async {
    deleteCalled = true;
  }
}

Widget _buildScreen(User user, {ProfileRepository? repo}) {
  FlutterSecureStorage.setMockInitialValues({});
  return ProviderScope(
    overrides: [
      myProfileProvider.overrideWith(() => _FakeMyProfile(user)),
      if (repo != null) profileRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const DeleteAccountScreen(),
    ),
  );
}

void main() {
  group('DeleteAccountScreen re-auth branch', () {
    testWidgets(
        'Given a password account, When the screen builds, '
        'Then it shows the password field', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildScreen(_user(hasPassword: true)));
      await tester.pump();
      await tester.pump(); // settle the profile future

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Enter your password to confirm'), findsOneWidget);
      // No Google re-auth copy for password accounts.
      expect(find.textContaining('Google Sign-In'), findsNothing);
    });

    testWidgets(
        'Given a passwordless (Google) account, When the screen builds, '
        'Then it shows the Google re-auth affordance and no password field',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildScreen(_user(hasPassword: false)));
      await tester.pump();
      await tester.pump();

      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('Google Sign-In'), findsOneWidget);
      // The destructive CTA is still present for both account types.
      expect(find.text('Delete My Account'), findsOneWidget);
    });

    testWidgets(
        'Given a dual-method account (password + Google), When the screen '
        'builds, Then it shows the password field AND a Google alternative',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
          _buildScreen(_user(hasPassword: true, hasGoogle: true)));
      await tester.pump();
      await tester.pump();

      // Password path is present…
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Enter your password to confirm'), findsOneWidget);
      // …and Google is offered as an alternative below the OR divider.
      expect(find.text('OR'), findsOneWidget);
      expect(find.textContaining('Prefer Google'), findsOneWidget);
    });
  });

  group('DeleteAccountScreen empty-password guard', () {
    testWidgets(
        'Given a password account with an empty field, When Delete is tapped, '
        'Then it shows the enter-password error and never calls the repository',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _RecordingRepo();
      await tester
          .pumpWidget(_buildScreen(_user(hasPassword: true), repo: repo));
      await tester.pump();
      await tester.pump();

      await tester.tap(
          find.widgetWithText(ElevatedButton, 'Delete My Account'));
      await tester.pump();

      expect(
          find.text('Please enter your password to continue.'), findsOneWidget);
      expect(repo.deleteCalled, isFalse);
    });
  });
}
