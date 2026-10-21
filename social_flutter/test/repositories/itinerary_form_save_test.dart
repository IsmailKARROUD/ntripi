// test/repositories/itinerary_form_save_test.dart — the itinerary form saves in
// one multipart request.
//
// The Edit itinerary form used to send the cover first (POST|DELETE /image) and
// the fields after it (PATCH /itineraries/{id}) with an If-Match read before
// the cover write moved it — a 412 on every save that changed the cover's row.
// These pin the replacement: one request carrying the fields as JSON, the cover
// change, If-Match and the edit claim. The adapter matches the FormData by its
// fields and by each file's name, type and length, and the headers partially.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';

const _itinId = 'itin-1';
const _etag = '"2026-10-21T10:00:00.000Z"';
const _token = 'lock-token';
const _coverUrl = '/uploads/itineraries/itin-1.jpg';
final _cover = Uint8List.fromList(List<int>.generate(64, (i) => i));

/// An ItinerarySummary, as both form routes answer.
Map<String, dynamic> _summaryJson({String? coverUrl}) => {
      'id': _itinId,
      'user_id': 'user-1',
      'title': 'Coast walk',
      'cover_image_url': coverUrl,
      'total_duration_min': 0,
      'total_cost': 0.0,
      'currency': 'EUR',
      'visibility': 'public',
      'created_at': '2026-10-21T09:00:00.000000Z',
      'updated_at': '2026-10-21T10:00:05.000000Z',
      'rating_avg': null,
      'rating_count': 0,
      'stops_count': 0,
    };

/// A Dio on the mock adapter, plus every request it sent — so "one request" is
/// an exact assertion, not an absence of errors.
(Dio, DioAdapter, List<RequestOptions>) _makeDio() {
  final dio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
  final adapter = DioAdapter(dio: dio);
  final sent = <RequestOptions>[];
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    sent.add(options);
    handler.next(options);
  }));
  return (dio, adapter, sent);
}

List<String> _lines(List<RequestOptions> sent) =>
    sent.map((o) => '${o.method} ${o.path}').toList();

void main() {
  group('ItineraryRepository.saveItineraryForm', () {
    final fields = <String, dynamic>{
      'title': 'Coast walk',
      'currency': 'EUR',
      'visibility': 'public',
    };

    test('Given a new cover, Then fields and image go in one PATCH with both '
        'preconditions', () async {
      final (dio, adapter, sent) = _makeDio();
      adapter.onPatch(
        itineraryFormEndpoint(_itinId),
        (server) => server.reply(200, _summaryJson(coverUrl: _coverUrl)),
        data: FormData.fromMap({
          'fields': jsonEncode(fields),
          'image': MultipartFile.fromBytes(_cover, filename: 'mine.jpg'),
        }),
        headers: {'If-Match': _etag, kEditLockHeader: _token},
      );

      final saved = await ItineraryRepository(dio).saveItineraryForm(
        _itinId,
        fields,
        coverBytes: _cover,
        coverFilename: 'mine.jpg',
        etag: _etag,
        lockToken: _token,
      );

      expect(_lines(sent), ['PATCH ${itineraryFormEndpoint(_itinId)}']);
      expect(saved.coverImageUrl, _coverUrl);
      expect(saved.updatedAt, DateTime.parse('2026-10-21T10:00:05.000000Z'));
    });

    test('Given a picked cover with no name, Then it is sent as cover.jpg',
        () async {
      final (dio, adapter, sent) = _makeDio();
      adapter.onPatch(
        itineraryFormEndpoint(_itinId),
        (server) => server.reply(200, _summaryJson(coverUrl: _coverUrl)),
        data: FormData.fromMap({
          'fields': jsonEncode(fields),
          'image': MultipartFile.fromBytes(_cover, filename: 'cover.jpg'),
        }),
      );

      await ItineraryRepository(dio).saveItineraryForm(
        _itinId, fields, coverBytes: _cover, etag: _etag, lockToken: _token,
      );

      final image = (sent.single.data as FormData).files.single;
      expect((image.key, image.value.filename), ('image', 'cover.jpg'));
    });

    test('Given a removed cover, Then remove_cover rides along and no image is '
        'sent', () async {
      final (dio, adapter, sent) = _makeDio();
      adapter.onPatch(
        itineraryFormEndpoint(_itinId),
        (server) => server.reply(200, _summaryJson()),
        data: FormData.fromMap({
          'fields': jsonEncode(fields),
          'remove_cover': 'true',
        }),
        headers: {'If-Match': _etag, kEditLockHeader: _token},
      );

      final saved = await ItineraryRepository(dio).saveItineraryForm(
        _itinId, fields, removeCover: true, etag: _etag, lockToken: _token,
      );

      expect(_lines(sent), ['PATCH ${itineraryFormEndpoint(_itinId)}']);
      expect(saved.coverImageUrl, isNull);
    });

    test('Given no cover change, Then only the fields part is sent — an '
        "editor's save, with no visibility key", () async {
      final (dio, adapter, sent) = _makeDio();
      final editorFields = {'title': 'Edited by a friend', 'currency': 'JPY'};
      adapter.onPatch(
        itineraryFormEndpoint(_itinId),
        (server) => server.reply(200, _summaryJson()),
        data: FormData.fromMap({'fields': jsonEncode(editorFields)}),
        headers: {'If-Match': _etag, kEditLockHeader: _token},
      );

      await ItineraryRepository(dio).saveItineraryForm(
        _itinId, editorFields, etag: _etag, lockToken: _token,
      );

      final form = sent.single.data as FormData;
      final sentFields =
          jsonDecode(form.fields.single.value) as Map<String, dynamic>;
      expect(sentFields.containsKey('visibility'), isFalse);
      expect(form.files, isEmpty);
    });

    test('412 throws ItineraryStaleException', () async {
      final (dio, adapter, _) = _makeDio();
      adapter.onPatch(
        itineraryFormEndpoint(_itinId),
        (server) => server.reply(412, {
          'detail': 'itinerary modified, please reload',
          'code': 'itinerary_stale',
        }),
        data: Matchers.any,
      );

      expect(
        () => ItineraryRepository(dio).saveItineraryForm(
          _itinId, fields, coverBytes: _cover, etag: _etag, lockToken: _token,
        ),
        throwsA(isA<ItineraryStaleException>()),
      );
    });

    test('409 edit_lock_lost throws EditLockLostException', () async {
      final (dio, adapter, _) = _makeDio();
      adapter.onPatch(
        itineraryFormEndpoint(_itinId),
        (server) => server.reply(409, {
          'detail': 'Your editing session was taken over.',
          'code': 'edit_lock_lost',
        }),
        data: Matchers.any,
      );

      expect(
        () => ItineraryRepository(dio).saveItineraryForm(
          _itinId, fields, etag: _etag, lockToken: _token,
        ),
        throwsA(isA<EditLockLostException>()),
      );
    });
  });

  group('ItineraryRepository.createItineraryWithCover', () {
    test('Given a picked cover, Then the trip and its cover go in one POST, '
        'with no preconditions to carry', () async {
      final (dio, adapter, sent) = _makeDio();
      final fields = {'title': 'Islands', 'visibility': 'public'};
      adapter.onPost(
        kItineraryFormEndpoint,
        (server) => server.reply(201, _summaryJson(coverUrl: _coverUrl)),
        data: FormData.fromMap({
          'fields': jsonEncode(fields),
          'image': MultipartFile.fromBytes(_cover, filename: 'mine.jpg'),
        }),
      );

      final created = await ItineraryRepository(dio).createItineraryWithCover(
        fields,
        coverBytes: _cover,
        coverFilename: 'mine.jpg',
      );

      expect(_lines(sent), ['POST $kItineraryFormEndpoint']);
      expect(sent.single.headers.containsKey('If-Match'), isFalse);
      expect(sent.single.headers.containsKey(kEditLockHeader), isFalse);
      expect(created.coverImageUrl, _coverUrl);
    });
  });
}
