// test/widgets/leg_thoughts_test.dart — a transport leg's "Thoughts" reach the
// reader.
//
// They show under the leg on the trip page's transit card and on the stop page,
// folded to two lines. No page grows a toggle of its own: the trip's "See
// translation" covers every transit card, and a stop's covers the transport in
// and out of it. Whoever is editing reads the original, and the editable
// transit card shows no thoughts — tapping a leg there opens its form.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/edit_lock.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/domain/track.dart';
import 'package:social_flutter/features/itineraries/domain/transit_segment.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';
import 'package:social_flutter/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:social_flutter/features/itineraries/presentation/stop_detail_screen.dart';
import 'package:social_flutter/features/itineraries/providers/edit_lock_provider.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/features/translation/data/translation_repository.dart';
import 'package:social_flutter/features/translation/domain/translation.dart';
import 'package:social_flutter/features/translation/presentation/translatable_text.dart';
import 'package:social_flutter/features/translation/providers/translation_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';

const _owner = 'user-1';
const _tripPath = '/itineraries/itin-1';
// The transit arrives at stop-2, so it is that stop's inbound transport.
const _stopPath = '/itineraries/itin-1/stops/stop-2';

const _viewMore = '... view more';
const _viewLess = 'view less';

// Long enough to need more than two lines in either card at this viewport.
const _thought = 'Take the second car from the front: the exit stairs come up '
    'right at the museum entrance, and walking back along the platform at rush '
    'hour takes longer than the ride itself. Buy a carnet of ten at the machine '
    'by the gates rather than single tickets at the desk, and keep one spare for '
    'the ride back in the evening, when the queue at the machines is longest.';

const _translatedThought = 'fr: transport_leg leg-1';

class _FakeRepo extends ItineraryRepository {
  _FakeRepo() : super(Dio());

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    final ts = DateTime.utc(2026, 10, 8);
    Stop stop(String id, String trackId, StopType type, String name,
            {String? notes}) =>
        Stop(
          id: id,
          itineraryId: 'itin-1',
          trackId: trackId,
          rank: 'a',
          type: type,
          placeName: name,
          notes: notes,
          createdAt: ts,
        );
    return Itinerary(
      id: 'itin-1',
      userId: _owner,
      title: 'Trip',
      totalDurationMin: 0,
      totalCost: 0.0,
      currency: 'EUR',
      visibility: ItineraryVisibility.onlyMe,
      createdAt: ts,
      updatedAt: ts,
      tracks: [
        Track(
          id: 'track-1',
          itineraryId: 'itin-1',
          rank: 'a',
          stops: [
            stop('stop-1', 'track-1', StopType.origin, 'Old Port',
                notes: 'Arrive early.'),
          ],
        ),
        Track(
          id: 'track-2',
          itineraryId: 'itin-1',
          rank: 'b',
          stops: [stop('stop-2', 'track-2', StopType.arrival, 'Museum')],
        ),
      ],
      segments: [
        TransitSegment(
          id: 'seg-1',
          itineraryId: 'itin-1',
          fromStopId: 'stop-1',
          toStopId: 'stop-2',
          totalDurationMin: 17,
          totalCost: 2.1,
          createdAt: ts,
          legs: [
            TransportLeg(
              id: 'leg-1',
              segmentId: 'seg-1',
              position: 1,
              mode: TransportMode.metro,
              line: 'M1',
              durationMin: 12,
              cost: 2.1,
              notes: _thought,
              sourceLang: 'en',
              createdAt: ts,
            ),
            // No thoughts: nothing to show, nothing to ask for.
            TransportLeg(
              id: 'leg-2',
              segmentId: 'seg-1',
              position: 2,
              mode: TransportMode.walk,
              durationMin: 5,
              isFree: true,
              createdAt: ts,
            ),
          ],
        ),
      ],
    );
  }
}

/// A claim without the network or the heartbeat Timer.
class _FakeEditLock extends EditLockNotifier {
  _FakeEditLock(super.arg, {required this.initial});

  final EditSession initial;

  @override
  EditSession build() {
    // super.build registers the real teardown, which cancels the detach grace
    // timer when the container goes.
    super.build();
    return initial;
  }

  @override
  Future<bool> acquire({bool takeover = false}) async {
    state = const EditSession(token: 'lock-token');
    return true;
  }

  @override
  Future<EditLockStatus?> peek() async => null;

  @override
  Future<void> release() async {
    state = const EditSession();
  }
}

class _FakeMyProfile extends MyProfileNotifier {
  @override
  Future<User> build() async => User(
        id: _owner,
        username: 'me',
        isPrivate: false,
        followersCount: 0,
        followingCount: 0,
        createdAt: DateTime.utc(2026, 1, 1),
      );
}

/// The reader's language — the translation target. The app itself stays in
/// English, so the toggle reads "See translation".
class _FixedLocale extends LocaleNotifier {
  @override
  Locale build() => const Locale('fr');
}

/// Answers every field with a text naming what was asked for, and keeps each
/// request so a test can see what was named.
class _FakeTranslations implements TranslationRepository {
  final requests = <List<TranslationRequestItem>>[];

  Iterable<TranslationRequestItem> get items => requests.expand((r) => r);

  @override
  Future<TranslationConfig> getConfig() async => TranslationConfig.disabled;

  @override
  Future<List<TranslationItemResult>> translate({
    required String targetLang,
    required List<TranslationRequestItem> items,
  }) async {
    requests.add(items);
    return [
      for (final item in items)
        TranslationItemResult(
          contentType: item.contentType,
          contentId: item.contentId,
          found: true,
          fields: {
            for (final field in item.fields)
              field: FieldTranslation(
                status: TranslationStatus.translated,
                text: '$targetLang: ${item.contentType} ${item.contentId}',
              ),
          },
        ),
    ];
  }
}

Future<_FakeTranslations> _pump(
  WidgetTester tester, {
  String start = _tripPath,
  EditSession initial = const EditSession(),
}) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final translations = _FakeTranslations();
  final router = GoRouter(
    initialLocation: start,
    routes: [
      GoRoute(
        path: '/itineraries/:id',
        builder: (_, s) =>
            ItineraryDetailScreen(itineraryId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/itineraries/:id/stops/:stopId',
        builder: (_, s) => StopDetailScreen(
          itineraryId: s.pathParameters['id']!,
          stopId: s.pathParameters['stopId']!,
        ),
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      itineraryRepositoryProvider.overrideWithValue(_FakeRepo()),
      myProfileProvider.overrideWith(_FakeMyProfile.new),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      localeProvider.overrideWith(_FixedLocale.new),
      translationConfigProvider.overrideWith((ref) async =>
          const TranslationConfig(enabled: true, targetLangs: ['en', 'fr'])),
      translationRepositoryProvider.overrideWithValue(translations),
      editLockProvider
          .overrideWith2((id) => _FakeEditLock(id, initial: initial)),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return translations;
}

Future<void> _tapSeeTranslation(WidgetTester tester) async {
  await tester.tap(find.text('See translation'));
  await tester.pumpAndSettle();
}

/// The `transport_leg` items the reader's taps asked for, by id.
Set<String> _legsAskedFor(_FakeTranslations translations) => {
      for (final item in translations.items)
        if (item.contentType == 'transport_leg') item.contentId,
    };

void main() {
  // The one-time long-press tip would sit over the trip page in read mode.
  setUp(() => FlutterSecureStorage.setMockInitialValues(
      {'ntripi_longpress_hint_seen': 'true'}));

  group('the trip page', () {
    testWidgets('shows a leg\'s thoughts in its transit card, folded',
        (tester) async {
      await _pump(tester);

      expect(find.text(_thought), findsOneWidget);
      expect(tester.widget<Text>(find.text(_thought)).maxLines, 2);
      expect(find.text(_viewMore), findsOneWidget);

      await tester.tap(find.text(_viewMore));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(_thought)).maxLines, isNull);
      expect(find.text(_viewLess), findsOneWidget);
    });

    testWidgets(
        'the trip\'s one toggle asks for the thoughts too, and swaps them — '
        'an unfolded thought stays unfolded', (tester) async {
      final translations = await _pump(tester);
      await tester.tap(find.text(_viewMore));
      await tester.pumpAndSettle();

      await _tapSeeTranslation(tester);

      expect(translations.requests, hasLength(1));
      expect(_legsAskedFor(translations), {'leg-1'});
      final leg = translations.items
          .singleWhere((item) => item.contentType == 'transport_leg');
      expect(leg.fields, ['notes']);
      expect(find.text(_translatedThought), findsOneWidget);
      expect(find.text(_thought), findsNothing);
      expect(find.text(_viewLess), findsOneWidget);
      // Still one toggle on the page — the transit card did not grow its own.
      expect(find.byType(TranslationToggle, skipOffstage: false),
          findsOneWidget);
    });

    testWidgets(
        'in edit mode the card is the editable one, without thoughts — the '
        'leg\'s form holds them', (tester) async {
      await _pump(tester, initial: const EditSession(token: 'lock-token'));

      expect(find.text(_thought), findsNothing);
      expect(find.byType(TranslationToggle, skipOffstage: false),
          findsNothing);
    });
  });

  group('the stop page', () {
    testWidgets('shows the thoughts on its transport, folded', (tester) async {
      await _pump(tester, start: _stopPath);

      expect(find.text(_thought), findsOneWidget);
      expect(tester.widget<Text>(find.text(_thought)).maxLines, 2);
      expect(find.text(_viewMore), findsOneWidget);
    });

    testWidgets('the stop\'s one toggle asks for them and swaps them',
        (tester) async {
      final translations = await _pump(tester, start: _stopPath);

      await _tapSeeTranslation(tester);

      expect(_legsAskedFor(translations), {'leg-1'});
      expect(find.text(_translatedThought), findsOneWidget);
      expect(find.byType(TranslationToggle, skipOffstage: false),
          findsOneWidget);
    });

    testWidgets(
        'while the trip is being edited, the thoughts show as written and '
        'nothing is offered', (tester) async {
      final translations = await _pump(tester,
          start: _stopPath, initial: const EditSession(token: 'lock-token'));

      expect(find.text(_thought), findsOneWidget);
      expect(find.byType(TranslationToggle, skipOffstage: false),
          findsNothing);
      expect(translations.requests, isEmpty);
    });
  });
}
