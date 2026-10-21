// test/widgets/itinerary_form_save_error_test.dart — a refused save keeps the
// itinerary form open, with everything the user put in it.
//
// The form saves its fields and its cover in one request, so one refusal now
// answers for both. Whatever the reason — the trip changed elsewhere (412), the
// claim was taken (409), the text or the image was refused (422) — the user's
// title and picked cover are the only copy of their work: the form must not
// pop, clear a controller or drop the image. On create the same holds: a
// refused cover creates nothing, so there is no trip to navigate to.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/domain/edit_lock.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/presentation/itinerary_form_screen.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/cover_image_field.dart';
import 'package:ntripi/features/itineraries/providers/edit_lock_provider.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';

typedef _Sent = ({Map<String, dynamic> data, Uint8List? coverBytes});

/// Answers every save with [failure], recording what each one carried.
class _RefusingRepo extends ItineraryRepository {
  _RefusingRepo(this.failure) : super(Dio());

  final Exception failure;
  final saves = <_Sent>[];
  final creates = <_Sent>[];

  @override
  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    final ts = DateTime.utc(2026, 10, 21);
    return Itinerary(
      id: 'itin-1',
      userId: 'user-1',
      title: 'Coast walk',
      totalDurationMin: 0,
      totalCost: 0.0,
      currency: 'EUR',
      visibility: ItineraryVisibility.public,
      createdAt: ts,
      updatedAt: ts,
      canEdit: true,
    );
  }

  @override
  Future<List<Itinerary>> getMyItineraries({bool forceRefresh = false}) async =>
      const [];

  @override
  Future<Itinerary> saveItineraryForm(
    String id,
    Map<String, dynamic> data, {
    Uint8List? coverBytes,
    String? coverFilename,
    bool removeCover = false,
    required String etag,
    required String? lockToken,
  }) async {
    saves.add((data: data, coverBytes: coverBytes));
    throw failure;
  }

  @override
  Future<Itinerary> createItineraryWithCover(
    Map<String, dynamic> data, {
    required Uint8List coverBytes,
    String? coverFilename,
  }) async {
    creates.add((data: data, coverBytes: coverBytes));
    throw failure;
  }
}

/// The claim, without the network or the heartbeat Timer the real one starts.
class _FakeEditLock extends EditLockNotifier {
  _FakeEditLock(super.arg);

  @override
  EditSession build() {
    super.build();
    return const EditSession(token: 'lock-token');
  }

  @override
  Future<EditLockStatus?> peek() async => null;
}

class _FakeMyProfile extends MyProfileNotifier {
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

DioException _refused(Map<String, dynamic> body) {
  final options = RequestOptions(path: '/itineraries/itin-1/form');
  return DioException(
    requestOptions: options,
    response: Response(requestOptions: options, statusCode: 422, data: body),
    type: DioExceptionType.badResponse,
  );
}

final _imageRefused = _refused({
  'detail': 'This image appears to contain prohibited content and was not uploaded.',
  'code': 'image_moderation_rejected',
});

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

/// Pushes [form] over a page, as the app does — so a pop would be visible.
Future<_RefusingRepo> _pump(
    WidgetTester tester, Widget form, Exception failure) async {
  // Tall enough that the whole form is laid out at once.
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repo = _RefusingRepo(failure);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('beneath'))),
    GoRoute(path: '/target', builder: (_, _) => form),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      itineraryRepositoryProvider.overrideWithValue(repo),
      myProfileProvider.overrideWith(_FakeMyProfile.new),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      editLockProvider.overrideWith2(_FakeEditLock.new),
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
  return repo;
}

/// What the cover field reports back to the form, as a real pick does.
void _pickCover(WidgetTester tester, Uint8List bytes) => tester
    .widget<CoverImageField>(find.byType(CoverImageField))
    .onImageSelected(bytes, 'cover.png');

void _expectFormIntact(WidgetTester tester, String title, Uint8List cover) {
  expect(find.byType(ItineraryFormScreen), findsOneWidget);
  expect(find.widgetWithText(TextFormField, title), findsOneWidget);
  expect(tester.widget<CoverImageField>(find.byType(CoverImageField)).initialBytes,
      same(cover));
  expect(find.byType(SnackBar), findsOneWidget);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  final failures = <(String, Exception, String?)>[
    ('412 stale', const ItineraryStaleException(),
        'The itinerary was modified — please reload.'),
    ('409 lost claim', const EditLockLostException(null),
        'Your editing session was taken over. Your changes were not saved.'),
    ('422 refused image', _imageRefused,
        "This image can't be uploaded because it may contain prohibited content."),
    ('422 refused text', _refused({
      'detail': 'This text appears to violate the community guidelines and was not saved.',
      'code': 'text_moderation_rejected',
      'categories': ['harassment'],
    }), null),
  ];

  for (final (name, failure, message) in failures) {
    testWidgets('a $name keeps the edit form open with its title and cover',
        (tester) async {
      final cover = await _pngBytes(tester);
      final repo = await _pump(
          tester, const ItineraryFormScreen(itineraryId: 'itin-1'), failure);

      await tester.enterText(find.byType(TextFormField), 'Coast walk, revised');
      _pickCover(tester, cover);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // One request, carrying both — never a cover sent ahead on its own.
      expect(repo.saves, hasLength(1));
      expect(repo.saves.single.data['title'], 'Coast walk, revised');
      expect(repo.saves.single.coverBytes, same(cover));
      _expectFormIntact(tester, 'Coast walk, revised', cover);
      if (message != null) expect(find.text(message), findsOneWidget);
    });
  }

  testWidgets('a refused cover at create creates nothing and keeps the New '
      'itinerary form open', (tester) async {
    final cover = await _pngBytes(tester);
    final repo = await _pump(tester, const ItineraryFormScreen(), _imageRefused);

    await tester.enterText(find.byType(TextFormField), 'Islands');
    await tester.tap(find.text('Show optional fields'));
    await tester.pumpAndSettle();
    _pickCover(tester, cover);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.creates, hasLength(1));
    expect(repo.creates.single.coverBytes, same(cover));
    _expectFormIntact(tester, 'Islands', cover);
    expect(
        find.text(
            "This image can't be uploaded because it may contain prohibited content."),
        findsOneWidget);
  });
}
