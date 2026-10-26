// test/widgets/itinerary_form_cover_cache_test.dart — a saved cover change
// clears the cached cover, and an image cache that cannot be cleared never
// turns the save into a failure.
//
// An itinerary cover keeps its storage key when it is replaced, so after a
// save that changed it the form clears the cached copy under the URL from
// before the save and the one after — a first cover too, since a cover deleted
// earlier can have left a copy under that key. It used to do that inside the
// try that reports a failed save: an image cache that threw left a saved form
// open under an error message. It now goes through the best-effort
// ImageCacheEviction, like the pulls.
//
// The trip starts without a cover: the form would otherwise draw the stored
// one, which starts the real image cache, and that cannot run in a test.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/core/cache/image_cache.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/domain/edit_lock.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/domain/trip_edit_answer.dart';
import 'package:ntripi/features/itineraries/presentation/itinerary_form_screen.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/cover_image_field.dart';
import 'package:ntripi/features/itineraries/providers/edit_lock_provider.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';

import '../support/held_claim.dart';

/// Stored relative, as filesystem storage serves it; R2's is absolute and kept.
const _cover = '/uploads/itineraries/itin-1.jpg';

Itinerary _trip({String? cover}) => Itinerary(
      id: 'itin-1',
      userId: 'user-1',
      title: 'Coast walk',
      totalDurationMin: 0,
      totalCost: 0.0,
      currency: 'EUR',
      visibility: ItineraryVisibility.public,
      coverImageUrl: cover,
      createdAt: DateTime.utc(2026, 10, 21),
      updatedAt: DateTime.utc(2026, 10, 21),
      canEdit: true,
    );

/// Answers the form's save with the trip and its new cover.
class _AnsweringRepo extends ItineraryRepository {
  _AnsweringRepo() : super(Dio());

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async =>
      _trip();

  @override
  Future<List<Itinerary>> getMyItineraries({bool forceRefresh = false}) async =>
      const [];

  @override
  Future<TripEditAnswer> saveItineraryForm(
    String id,
    Map<String, dynamic> data, {
    Uint8List? coverBytes,
    String? coverFilename,
    bool removeCover = false,
    required String etag,
    required String? lockToken,
  }) async =>
      TripEditAnswer(_trip(cover: _cover));
}

/// The claim, without the network or the heartbeat Timer the real one starts.
class _FakeEditLock extends HeldClaim {
  _FakeEditLock(super.arg);

  @override
  Future<EditLockStatus?> peek() async => null;
}

class _Owner extends MyProfileNotifier {
  @override
  Future<User> build() async => User(
        id: 'user-1',
        username: 'me',
        isPrivate: false,
        followersCount: 0,
        followingCount: 0,
        createdAt: DateTime.utc(2026, 1, 1),
      );
}

Future<Uint8List> _pngBytes(WidgetTester tester) async {
  late Uint8List bytes;
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 40, 40), Paint()..color = Colors.teal);
    final image = await recorder.endRecording().toImage(40, 40);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    bytes = data!.buffer.asUint8List();
  });
  return bytes;
}

/// The edit form pushed over a page, as the app does — so closing shows.
Future<void> _pump(WidgetTester tester, ImageCacheEviction eviction) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('beneath'))),
    GoRoute(
      path: '/target',
      builder: (_, _) => const ItineraryFormScreen(itineraryId: 'itin-1'),
    ),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      itineraryRepositoryProvider.overrideWithValue(_AnsweringRepo()),
      myProfileProvider.overrideWith(_Owner.new),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      editLockProvider.overrideWith2(_FakeEditLock.new),
      imageCacheEvictionProvider.overrideWithValue(eviction),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  router.push('/target');
  await tester.pumpAndSettle();
}

/// A picked cover, as the cover field reports a real pick.
Future<void> _pickCover(WidgetTester tester) async {
  final bytes = await _pngBytes(tester);
  tester
      .widget<CoverImageField>(find.byType(CoverImageField))
      .onImageSelected(bytes, 'cover.png');
  await tester.pump();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
      'Given a picked cover, When the form saves, '
      'Then its URL is cleared from the image cache and the form closes',
      (tester) async {
    final cleared = <String>[];
    await _pump(
        tester, ImageCacheEviction(evictOne: (url) async => cleared.add(url)));

    await _pickCover(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // No URL before the save; the one after, stored relative, cleared absolute.
    expect(cleared, ['$kApiBaseUrl$_cover']);
    expect(find.text('beneath'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
      'Given an image cache that cannot be cleared, When the form saves a '
      'picked cover, Then the save still closes the form with no error',
      (tester) async {
    await _pump(
      tester,
      ImageCacheEviction(
          evictOne: (_) async => throw const FileSystemException(
              'the image cache could not be opened')),
    );

    await _pickCover(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('beneath'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}
