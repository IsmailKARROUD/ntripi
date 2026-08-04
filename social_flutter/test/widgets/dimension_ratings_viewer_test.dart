// test/widgets/dimension_ratings_viewer_test.dart
//
// Regression test for a shipped bug: DimensionRatingsScreen built its rating
// tiles without passing viewerId, so it defaulted to null and the tile's
// `user.userId != viewerId` guard was always true. On the per-dimension screen
// the viewer was offered Report and Block on their OWN review — tapping through
// gets a 400 report_own_content, or an offer to block yourself.
//
// The parent ratings page passed it correctly, which is exactly why this went
// unnoticed: both screens render the same tile, only one wired it up.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/itineraries/domain/dimension_key.dart';
import 'package:social_flutter/features/itineraries/domain/ratings_page.dart';
import 'package:social_flutter/features/itineraries/presentation/dimension_ratings_screen.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/features/reports/presentation/ugc_actions.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';

const _itineraryId = 'itinerary-1';
const _viewerId = 'viewer-1';
const _strangerId = 'stranger-9';

final _viewer = User(
  id: _viewerId,
  username: 'viewer1',
  isPrivate: false,
  followersCount: 0,
  followingCount: 0,
  createdAt: DateTime(2024),
);

class _FakeMyProfile extends MyProfileNotifier {
  _FakeMyProfile(this._u);
  final User _u;
  @override
  Future<User> build() async => _u;
}

class _FakeRatingsPage extends RatingsPageNotifier {
  // The family argument is a constructor param on this notifier, not a build()
  // param — the super call is what makes the override type-check.
  _FakeRatingsPage(this._page) : super(_itineraryId);
  final RatingsPage _page;
  @override
  Future<RatingsPage> build() async => _page;
}

/// A review scored on the safety dimension, so the screen's filter keeps it.
RatingWithUser _rating(String authorId) => RatingWithUser(
      score: 4,
      scoreSafety: 4,
      note: 'a note',
      updatedAt: DateTime.utc(2026, 1, 1),
      id: 'rating-$authorId',
      user: RaterInfo(
        userId: authorId,
        username: 'someone',
        displayName: 'Someone',
        avatarUrl: null,
      ),
    );

RatingsPage _page(List<RatingWithUser> ratings) => RatingsPage(
      ratingAvg: 4,
      ratingCount: ratings.length,
      distribution: const RatingDistribution(
        five: 0,
        four: 1,
        three: 0,
        two: 0,
        one: 0,
      ),
      ratings: ratings,
    );

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    List<RatingWithUser> ratings,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith(() => _FakeMyProfile(_viewer)),
          ratingsPageProvider(_itineraryId)
              .overrideWith(() => _FakeRatingsPage(_page(ratings))),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DimensionRatingsScreen(
            itineraryId: _itineraryId,
            dimension: DimensionKey.safety,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Given my own review on the dimension screen, When rendered, Then no '
      'Report/Block menu is offered', (tester) async {
    await pumpScreen(tester, [_rating(_viewerId)]);

    expect(find.byType(UgcActionsMenu), findsNothing);
  });

  testWidgets(
      "Given someone else's review, When rendered, Then the menu is offered",
      (tester) async {
    await pumpScreen(tester, [_rating(_strangerId)]);

    expect(find.byType(UgcActionsMenu), findsOneWidget);
  });

  testWidgets(
      'Given a mixed list, When rendered, Then only the stranger row gets a menu',
      (tester) async {
    await pumpScreen(tester, [_rating(_viewerId), _rating(_strangerId)]);

    expect(find.byType(UgcActionsMenu), findsOneWidget);
  });
}
