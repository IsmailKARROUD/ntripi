// test/widgets/trip_long_texts_test.dart — a trip's long texts on its page.
//
// The description holds up to 10,000 characters and the best-time note
// ("Why this time?") up to 4,000, both written in the markdown editor. On the
// trip page the description folds to three lines and the note to two, each
// with "view more" opening it in place, formatted. The folded lines are the
// words without the markup — a `**` or a `#` is never shown as typed — and a
// text short enough to need no fold shows formatted at once.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/domain/recommended_period.dart';
import 'package:ntripi/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';

class _FakeRepo extends ItineraryRepository {
  final String? description;
  final String? note;
  _FakeRepo({this.description, this.note}) : super(Dio());

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    final ts = DateTime.utc(2026, 11, 9);
    return Itinerary(
      id: 'itin-1',
      userId: 'user-1',
      title: 'Trip',
      description: description,
      recommendedPeriod:
          note == null ? null : RecommendedPeriod(weekdays: const [6], note: note),
      totalDurationMin: 0,
      totalCost: 0.0,
      currency: 'EUR',
      visibility: ItineraryVisibility.public,
      createdAt: ts,
      updatedAt: ts,
    );
  }
}

/// A reader: someone other than the owner, so the page is in read mode.
class _Reader extends MyProfileNotifier {
  @override
  Future<User> build() async => User(
        id: 'user-2',
        username: 'reader',
        isPrivate: false,
        followersCount: 0,
        followingCount: 0,
        createdAt: DateTime.utc(2026, 1, 1),
      );
}

Future<AppLocalizations> _pumpTrip(WidgetTester tester,
    {String? description, String? note}) async {
  tester.view.physicalSize = const Size(400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      itineraryRepositoryProvider
          .overrideWithValue(_FakeRepo(description: description, note: note)),
      myProfileProvider.overrideWith(_Reader.new),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ItineraryDetailScreen(itineraryId: 'itin-1'),
    ),
  ));
  await tester.pumpAndSettle();
  return AppLocalizations.of(
      tester.element(find.byType(ItineraryDetailScreen)))!;
}

/// A long markdown text: a heading, bold words, then many sentences.
String _markdown(String heading, int sentences) =>
    '# $heading\n\nThe **old town** is best on foot. '
    '${List.filled(sentences, 'Walk the ramparts at dawn before the heat.').join(' ')}';

void main() {
  group('the description', () {
    testWidgets(
        'Given a long one, Then three lines of its plain words show, with '
        '"view more" opening the formatted text', (tester) async {
      final description = _markdown('Why go', 200);
      final l10n = await _pumpTrip(tester, description: description);

      final folded = tester.widget<Text>(find.byWidgetPredicate((w) =>
          w is Text && (w.data ?? '').startsWith('Why go\nThe old town')));
      expect(folded.maxLines, 3);
      expect(folded.data, isNot(contains('**')));
      expect(find.byType(MarkdownBody), findsNothing);

      await tester.tap(find.text(l10n.viewMore).first);
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.text(l10n.viewLess), findsOneWidget);
    });

    testWidgets('Given a short one, Then it shows formatted at once',
        (tester) async {
      final l10n =
          await _pumpTrip(tester, description: 'The **old town** on foot.');

      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.text('The **old town** on foot.'), findsNothing);
      expect(find.text(l10n.viewMore), findsNothing);
    });
  });

  group('the best-time note', () {
    testWidgets(
        'Given a long one, Then two lines of its plain words show, with '
        '"view more" opening the formatted text', (tester) async {
      final note = _markdown('Spring', 80);
      final l10n = await _pumpTrip(tester, note: note);

      final folded = tester.widget<Text>(find.byWidgetPredicate((w) =>
          w is Text && (w.data ?? '').startsWith('Spring\nThe old town')));
      expect(folded.maxLines, 2);

      await tester.tap(find.text(l10n.viewMore));
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('Given a short one, Then it shows formatted at once',
        (tester) async {
      final l10n = await _pumpTrip(tester, note: 'Go for the **blossom**.');

      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.text('Go for the **blossom**.'), findsNothing);
      expect(find.text(l10n.viewMore), findsNothing);
    });
  });
}
