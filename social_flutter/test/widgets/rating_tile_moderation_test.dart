// test/widgets/rating_tile_moderation_test.dart
//
// Two guards on the review tile, both of which fail silently if broken:
//
//  1. The hidden banner is author-only. The server already filters other
//     people's hidden reviews out of the list and forces every non-author row
//     to 'approved', so a banner appearing on someone else's tile would mean a
//     status leaked — and would tell a reader that a stranger was moderated.
//  2. Report/Block never appears on your own review. The tile compares
//     rating.user.userId against viewerId; when a caller forgets to pass
//     viewerId it defaults to null and the guard silently passes for everyone
//     (the bug that shipped on the per-dimension screen).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/itineraries/domain/ratings_page.dart';
import 'package:social_flutter/features/itineraries/presentation/ratings_page_screen.dart';
import 'package:social_flutter/features/reports/presentation/ugc_actions.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/moderation_status.dart';
import 'package:social_flutter/shared/widgets/moderation_hidden_banner.dart';

const _viewerId = 'viewer-1';
const _strangerId = 'stranger-9';

RatingWithUser _rating({
  required String authorId,
  ModerationStatus status = ModerationStatus.approved,
  String? id = 'rating-1',
  String? note = 'a note',
}) {
  return RatingWithUser(
    score: 4,
    note: note,
    updatedAt: DateTime.utc(2026, 1, 1),
    id: id,
    moderationStatus: status,
    user: RaterInfo(
      userId: authorId,
      username: 'someone',
      displayName: 'Someone',
      avatarUrl: null,
    ),
  );
}

void main() {
  Future<void> pumpTile(
    WidgetTester tester,
    RatingWithUser rating, {
    String? viewerId = _viewerId,
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RatingListTile(rating: rating, viewerId: viewerId),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('hidden banner', () {
    testWidgets(
        'Given my own hidden review, When rendered, Then the banner shows',
        (tester) async {
      await pumpTile(
        tester,
        _rating(authorId: _viewerId, status: ModerationStatus.hidden),
      );

      expect(find.byType(ModerationHiddenBanner), findsOneWidget);
    });

    testWidgets('Given my own rejected review, Then the banner also shows',
        (tester) async {
      await pumpTile(
        tester,
        _rating(authorId: _viewerId, status: ModerationStatus.rejected),
      );

      expect(find.byType(ModerationHiddenBanner), findsOneWidget);
    });

    testWidgets('Given an approved review, When rendered, Then no banner shows',
        (tester) async {
      await pumpTile(tester, _rating(authorId: _viewerId));

      expect(find.byType(ModerationHiddenBanner), findsNothing);
    });

    testWidgets(
        'Given an internal state, When rendered, Then no banner shows',
        (tester) async {
      for (final internal in [
        ModerationStatus.pending,
        ModerationStatus.flagged,
      ]) {
        await pumpTile(
          tester,
          _rating(authorId: _viewerId, status: internal),
        );

        expect(find.byType(ModerationHiddenBanner), findsNothing,
            reason: '$internal must never be surfaced');
      }
    });

    testWidgets(
        'Given a hidden review with no note, When rendered, Then the banner '
        'still shows', (tester) async {
      // The banner and the note live in the same conditional column — the
      // banner must not depend on there being note text.
      await pumpTile(
        tester,
        _rating(
          authorId: _viewerId,
          status: ModerationStatus.hidden,
          note: null,
        ),
      );

      expect(find.byType(ModerationHiddenBanner), findsOneWidget);
    });

    testWidgets(
        'Given a hidden review with no id, When rendered, Then the banner shows '
        'without an appeal action', (tester) async {
      // A response cached before the id field existed cannot be appealed
      // against — the banner still explains why the review is invisible.
      await pumpTile(
        tester,
        _rating(
          authorId: _viewerId,
          status: ModerationStatus.hidden,
          id: null,
        ),
      );

      expect(find.byType(ModerationHiddenBanner), findsOneWidget);
      expect(find.byKey(const Key('moderationAppealButton')), findsNothing);
    });
  });

  group('report/block guard', () {
    testWidgets(
        "Given someone else's review, When rendered, Then the actions menu shows",
        (tester) async {
      await pumpTile(tester, _rating(authorId: _strangerId));

      expect(find.byType(UgcActionsMenu), findsOneWidget);
    });

    testWidgets(
        'Given my own review, When rendered, Then no actions menu shows',
        (tester) async {
      await pumpTile(tester, _rating(authorId: _viewerId));

      expect(find.byType(UgcActionsMenu), findsNothing);
    });

    testWidgets(
        'Given viewerId was not passed, When rendered against my own review, '
        'Then the guard fails open', (tester) async {
      // Documents why every call site must pass viewerId: with it null the
      // tile offers Report/Block on the viewer's own review.
      await pumpTile(tester, _rating(authorId: _viewerId), viewerId: null);

      expect(find.byType(UgcActionsMenu), findsOneWidget);
    });

    testWidgets('Given a review with no id, Then no actions menu shows',
        (tester) async {
      await pumpTile(tester, _rating(authorId: _strangerId, id: null));

      expect(find.byType(UgcActionsMenu), findsNothing);
    });
  });
}
