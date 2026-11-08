// test/widgets/itinerary_detail_cover_tap_test.dart — What a tap on the trip
// page's cover does.
//
// A cover that shows opens full screen in the viewer a profile's photo uses
// (showFullscreenImage), for the owner and a reader alike, and a screen reader
// finds it as a "Cover image" button. The placeholder keeps its own tap: the
// owner's add-cover hint anchored to the Edit details button, nothing for
// anyone else — also when a cover fails to load, since the placeholder then
// says "No cover image". Also guards the hero scrim's IgnorePointer — without
// it the scrim's BoxDecoration swallows the tap before it reaches the cover or
// the placeholder.
//
// The cover is drawn from Flutter's in-memory image cache, seeded under the
// key the hero and the viewer both ask for: the real disk cache cannot run in
// a test.
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/presentation/itinerary_detail_screen.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';
import 'package:ntripi/shared/widgets/itinerary_cover_placeholder.dart';
import 'package:photo_view/photo_view.dart';

const _cover = 'https://images.example/itineraries/itin-1.jpg';

class _FakeRepo extends ItineraryRepository {
  final String? coverUrl;
  _FakeRepo({this.coverUrl}) : super(Dio());

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    final ts = DateTime.utc(2026, 7, 11);
    return Itinerary(
      id: 'itin-1',
      userId: 'user-1',
      title: 'Trip',
      totalDurationMin: 0,
      totalCost: 0.0,
      currency: 'EUR',
      visibility: ItineraryVisibility.onlyMe,
      coverImageUrl: coverUrl,
      createdAt: ts,
      updatedAt: ts,
    );
  }
}

class _FakeMyProfile extends MyProfileNotifier {
  final bool owner;
  _FakeMyProfile({required this.owner});

  @override
  Future<User> build() async => User(
        id: owner ? 'user-1' : 'user-2',
        username: 'me',
        isPrivate: false,
        followersCount: 0,
        followingCount: 0,
        createdAt: DateTime.utc(2026, 1, 1),
      );
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required bool owner,
  String? coverUrl,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      itineraryRepositoryProvider
          .overrideWithValue(_FakeRepo(coverUrl: coverUrl)),
      myProfileProvider.overrideWith(() => _FakeMyProfile(owner: owner)),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ItineraryDetailScreen(itineraryId: 'itin-1'),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Clears what a test put in the in-memory image cache.
void _clearImageCacheAfterwards() {
  final cache = PaintingBinding.instance.imageCache;
  addTearDown(() {
    cache.clear();
    cache.clearLiveImages();
  });
}

/// [url]'s picture, ready in the in-memory image cache under the key the hero
/// and the viewer both resolve: `CachedNetworkImageProvider`'s equality is the
/// URL, the scale and the size caps — never the cache manager.
Future<void> _seedCover(WidgetTester tester, String url) async {
  final image =
      (await tester.runAsync(() => createTestImage(width: 120, height: 63)))!;
  addTearDown(image.dispose);
  _clearImageCacheAfterwards();
  PaintingBinding.instance.imageCache.putIfAbsent(
    CachedNetworkImageProvider(url),
    () => OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: image.clone()))),
  );
}

/// [url]'s picture, still loading; fail it once the hero is listening, so the
/// hero's own error path runs.
Completer<ImageInfo> _seedLoadingCover(String url) {
  final picture = Completer<ImageInfo>();
  _clearImageCacheAfterwards();
  PaintingBinding.instance.imageCache.putIfAbsent(
    CachedNetworkImageProvider(url),
    () => OneFrameImageStreamCompleter(picture.future),
  );
  return picture;
}

void main() {
  // Past the first-visit long-press tip: a cover makes the trip a long-press
  // target, and the tip in the Overlay would take the owner's first tap.
  setUp(() => FlutterSecureStorage.setMockInitialValues(
      {'ntripi_longpress_hint_seen': 'true'}));

  testWidgets('owner tap on placeholder cover shows add-cover hint',
      (tester) async {
    await _pumpDetail(tester, owner: true);

    expect(find.byType(ItineraryCoverPlaceholder), findsOneWidget);
    await tester.tap(find.byType(ItineraryCoverPlaceholder),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Add a cover image'), findsOneWidget);
    expect(find.text('To add a cover image, tap this button at the top.'),
        findsOneWidget);
  });

  testWidgets('viewer tap on placeholder cover does nothing', (tester) async {
    await _pumpDetail(tester, owner: false);

    expect(find.byType(ItineraryCoverPlaceholder), findsOneWidget);
    await tester.tap(find.byType(ItineraryCoverPlaceholder),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Add a cover image'), findsNothing);
  });

  group('a cover that shows', () {
    testWidgets(
        'a tap opens it full screen in the shared viewer, and ✕ brings the '
        'trip back', (tester) async {
      await _seedCover(tester, _cover);
      await _pumpDetail(tester, owner: false, coverUrl: _cover);
      expect(find.byType(ItineraryCoverPlaceholder), findsNothing);

      await tester.tap(find.byType(CachedNetworkImage));
      await tester.pumpAndSettle();

      // The same picture, from the same cache entry the hero drew.
      final viewer = tester.widget<PhotoView>(find.byType(PhotoView));
      expect(viewer.imageProvider, isA<CachedNetworkImageProvider>());
      expect((viewer.imageProvider! as CachedNetworkImageProvider).url, _cover);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(PhotoView), findsNothing);
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(find.text('Trip'), findsWidgets);
    });

    testWidgets(
        "the owner's tap opens it too — the add-cover hint is the "
        "placeholder's alone", (tester) async {
      await _seedCover(tester, _cover);
      await _pumpDetail(tester, owner: true, coverUrl: _cover);

      await tester.tap(find.byType(CachedNetworkImage));
      await tester.pumpAndSettle();

      expect(find.byType(PhotoView), findsOneWidget);
      expect(find.text('Add a cover image'), findsNothing);
    });

    testWidgets('a screen reader hears a "Cover image" button that opens it',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _seedCover(tester, _cover);
      await _pumpDetail(tester, owner: false, coverUrl: _cover);

      expect(
        tester.getSemantics(find.byType(CachedNetworkImage)),
        isSemantics(label: 'Cover image', isButton: true, hasTapAction: true),
      );

      tester.semantics.tap(find.semantics.byLabel('Cover image'));
      await tester.pumpAndSettle();

      expect(find.byType(PhotoView), findsOneWidget);
      semantics.dispose();
    });
  });

  testWidgets(
      'a cover that fails to load shows the placeholder, and a tap on it '
      'opens nothing', (tester) async {
    final picture = _seedLoadingCover(_cover);
    await _pumpDetail(tester, owner: false, coverUrl: _cover);

    picture.completeError(Exception('the picture could not be read'));
    await tester.pumpAndSettle();

    expect(find.byType(ItineraryCoverPlaceholder), findsOneWidget);
    expect(find.text('No cover image'), findsOneWidget);

    await tester.tap(find.byType(ItineraryCoverPlaceholder),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(PhotoView), findsNothing);
  });
}
