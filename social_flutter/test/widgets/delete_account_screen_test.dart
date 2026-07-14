// test/widgets/delete_account_screen_test.dart
//
// Widget tests for DeleteAccountScreen's account-type branch: password
// accounts re-enter a password; passwordless (SSO/Google) accounts re-auth
// with the provider instead. We override myProfileProvider with a fake
// notifier (never mock providers directly) and assert on the rendered
// re-auth affordance. Deletion itself hits the Google plugin / go_router and
// is covered end-to-end by the backend integration tests.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/profile/presentation/delete_account_screen.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';

User _user({required bool hasPassword}) => User(
      id: 'user-1',
      username: 'ismauo',
      displayName: 'Ismail',
      isPrivate: false,
      followersCount: 0,
      followingCount: 0,
      hasPassword: hasPassword,
      createdAt: DateTime(2024),
    );

class _FakeMyProfile extends MyProfileNotifier {
  _FakeMyProfile(this._u);
  final User _u;
  @override
  Future<User> build() async => _u;
}

Widget _buildScreen(User user) {
  FlutterSecureStorage.setMockInitialValues({});
  return ProviderScope(
    overrides: [
      myProfileProvider.overrideWith(() => _FakeMyProfile(user)),
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
  });
}
