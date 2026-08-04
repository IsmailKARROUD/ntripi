// test/widgets/follow_action_row_test.dart
//
// Isolated widget tests for FollowActionRow.
// Verifies the FollowButton renders with the right label per follow state
// and that the decorative message button placeholder is present.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/profile/presentation/widgets/follow_action_row.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';
import 'package:social_flutter/shared/widgets/follow_button.dart';

User _makeUser({
  bool isPrivate = false,
  bool isFollowing = false,
  bool followIsPending = false,
}) =>
    User(
      id: 'target-1',
      username: 'kma',
      displayName: 'Karim',
      avatarUrl: null,
      isPrivate: isPrivate,
      followersCount: 0,
      followingCount: 0,
      isFollowing: isFollowing,
      followIsPending: followIsPending,
      createdAt: DateTime(2024),
    );

Widget _host({required User user, required FollowStateChanged onChanged}) {
  FlutterSecureStorage.setMockInitialValues({});
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: FollowActionRow(user: user, onChanged: onChanged),
      ),
    ),
  );
}

void main() {
  group('FollowActionRow', () {
    testWidgets(
        'Given not following public user, When widget builds, '
        'Then FollowButton label is "Follow"', (tester) async {
      await tester.pumpWidget(_host(
        user: _makeUser(),
        onChanged: ({required isFollowing, required followIsPending}) {},
      ));
      await tester.pump();

      expect(find.text('Follow'), findsOneWidget);
    });

    testWidgets(
        'Given already following, When widget builds, '
        'Then FollowButton label is "Following"', (tester) async {
      await tester.pumpWidget(_host(
        user: _makeUser(isFollowing: true),
        onChanged: ({required isFollowing, required followIsPending}) {},
      ));
      await tester.pump();

      expect(find.text('Following'), findsOneWidget);
    });

    testWidgets(
        'Given following, When Following tapped and dismissed, '
        'Then no unfollow happens', (tester) async {
      var changed = false;
      await tester.pumpWidget(_host(
        user: _makeUser(isFollowing: true),
        onChanged: ({required isFollowing, required followIsPending}) =>
            changed = true,
      ));
      await tester.pump();

      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle(); // ConfirmDialog entrance is 220ms
      expect(find.text('Unfollow @kma?'), findsOneWidget);

      await tester.tap(find.text('Stay following'));
      await tester.pumpAndSettle();

      expect(find.text('Unfollow @kma?'), findsNothing);
      expect(find.text('Following'), findsOneWidget);
      expect(changed, isFalse);
    });

    testWidgets(
        'Given private user with pending request, When widget builds, '
        'Then FollowButton label is "Requested"', (tester) async {
      await tester.pumpWidget(_host(
        user: _makeUser(isPrivate: true, followIsPending: true),
        onChanged: ({required isFollowing, required followIsPending}) {},
      ));
      await tester.pump();

      expect(find.text('Requested'), findsOneWidget);
    });

    testWidgets(
        'Given widget rendered, When it builds, '
        'Then decorative mail icon and FollowButton are both present',
        (tester) async {
      await tester.pumpWidget(_host(
        user: _makeUser(),
        onChanged: ({required isFollowing, required followIsPending}) {},
      ));
      await tester.pump();

      expect(find.byType(FollowButton), findsOneWidget);
      expect(find.byIcon(Icons.mail_outline_rounded), findsOneWidget);
    });
  });
}
