// test/repositories/edit_lock_repository_test.dart — the client half of the
// edit-lock contract.
//
// Two things are worth pinning here, because getting either wrong is invisible
// until somebody loses work:
//
//   1. Every guarded mutation carries X-Edit-Lock. The header is attached per
//      call rather than by an interceptor, precisely so it cannot drift onto
//      requests that must not have it — which also means nothing catches a
//      missing one but a test.
//
//   2. The three rejections map to three distinct exception types. 409 and 423
//      look similar and mean opposite things to the UI: one says protect the
//      user's unsaved text, the other says offer to wait.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/edit_lock.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary_editor.dart';

void main() {
  (Dio, DioAdapter) makeDio() {
    final dio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
    return (dio, DioAdapter(dio: dio));
  }

  const itinId = 'itin-1';
  const etag = '"2026-05-11T10:22:56.909029Z"';
  const token = 'claim-token-abc';

  Map<String, dynamic> lockJson({
    String state = 'active',
    bool isYou = false,
  }) =>
      {
        'holder_id': 'user-2',
        'holder_username': 'bobby',
        'holder_display_name': 'Bobby',
        'holder_avatar_url': null,
        'is_you': isYou,
        'state': state,
        'acquired_at': '2026-08-12T10:00:00Z',
        'last_heartbeat_at': '2026-08-12T10:04:00Z',
        'idle_at': '2026-08-12T10:05:30Z',
        'takeover_available_at': '2026-08-12T10:09:00Z',
      };

  Map<String, dynamic> stopJson() => {
        'id': 'stop-1',
        'itinerary_id': itinId,
        'track_id': 't1',
        'rank': 'a0',
        'place_name': 'Paris',
        'place_address': null,
        'lat': null,
        'lng': null,
        'map_url': null,
        'place_type': null,
        'duration_min': null,
        'cost': 0,
        'is_free': true,
        'notes': null,
        'annotations': <dynamic>[],
        'created_at': '2026-08-12T10:00:00Z',
      };

  group('the claim rides on every guarded mutation', () {
    test('addStop sends X-Edit-Lock alongside If-Match', () async {
      final (dio, adapter) = makeDio();
      adapter.onPost(
        itineraryStopsEndpoint(itinId),
        (server) => server.reply(201, stopJson()),
        data: {'place_name': 'Paris'},
        headers: {'If-Match': etag, kEditLockHeader: token},
      );

      final stop = await ItineraryRepository(dio).addStop(
        itinId, {'place_name': 'Paris'},
        etag: etag, lockToken: token,
      );

      // The matcher above is the assertion: a missing or wrong header fails to
      // match the stub and the call throws instead of returning.
      expect(stop.id, 'stop-1');
    });

    test('updateItinerary carries both preconditions', () async {
      // It carried neither before collaborative editing — the header PATCH was
      // the one write that skipped concurrency control entirely.
      final (dio, adapter) = makeDio();
      adapter.onPatch(
        itineraryEndpoint(itinId),
        (server) => server.reply(200, {
          'id': itinId,
          'user_id': 'user-1',
          'title': 'Renamed',
          'cover_image_url': null,
          'total_duration_min': 0,
          'total_cost': 0,
          'currency': 'EUR',
          'visibility': 'only_me',
          'created_at': '2026-08-12T10:00:00Z',
          'updated_at': '2026-08-12T10:05:00Z',
          'rating_avg': null,
          'rating_count': 0,
          'stops_count': 0,
        }),
        data: {'title': 'Renamed'},
        headers: {'If-Match': etag, kEditLockHeader: token},
      );

      final updated = await ItineraryRepository(dio).updateItinerary(
        itinId, {'title': 'Renamed'},
        etag: etag, lockToken: token,
      );

      expect(updated.title, 'Renamed');
    });
  });

  group('rejections map to distinct types', () {
    test('409 edit_lock_lost → EditLockLostException carrying the new holder',
        () async {
      final (dio, adapter) = makeDio();
      adapter.onPost(
        itineraryStopsEndpoint(itinId),
        (server) => server.reply(409, {
          'code': 'edit_lock_lost',
          'detail': 'taken over',
          'lock': lockJson(),
        }),
        data: {'place_name': 'Paris'},
        headers: {'If-Match': etag, kEditLockHeader: token},
      );

      await expectLater(
        ItineraryRepository(dio).addStop(itinId, {'place_name': 'Paris'},
            etag: etag, lockToken: token),
        throwsA(
          isA<EditLockLostException>().having(
            (e) => e.holder?.holderUsername,
            'names who has it now',
            'bobby',
          ),
        ),
      );
    });

    test('423 → ItineraryLockedException, not the lost one', () async {
      // The two are answered differently by the UI: 423 offers to wait or take
      // over, 409 says protect the unsaved text. Collapsing them loses that.
      final (dio, adapter) = makeDio();
      adapter.onPost(
        itineraryLockEndpoint(itinId),
        (server) => server.reply(423, {
          'code': 'itinerary_locked',
          'detail': 'busy',
          'lock': lockJson(),
        }),
        data: {'takeover': false},
      );

      await expectLater(
        ItineraryRepository(dio).acquireLock(itinId),
        throwsA(isA<ItineraryLockedException>()),
      );
    });

    test('428 edit_lock_required → EditLockRequiredException', () async {
      final (dio, adapter) = makeDio();
      adapter.onPost(
        itineraryStopsEndpoint(itinId),
        (server) => server.reply(428, {
          'code': 'edit_lock_required',
          'detail': 'no session',
        }),
        data: {'place_name': 'Paris'},
        headers: {'If-Match': etag},
      );

      await expectLater(
        ItineraryRepository(dio).addStop(itinId, {'place_name': 'Paris'},
            etag: etag, lockToken: null),
        throwsA(isA<EditLockRequiredException>()),
      );
    });

    test('412 still maps to ItineraryStaleException', () async {
      final (dio, adapter) = makeDio();
      adapter.onPost(
        itineraryStopsEndpoint(itinId),
        (server) => server.reply(412, {'code': 'itinerary_stale'}),
        data: {'place_name': 'Paris'},
        headers: {'If-Match': etag, kEditLockHeader: token},
      );

      await expectLater(
        ItineraryRepository(dio).addStop(itinId, {'place_name': 'Paris'},
            etag: etag, lockToken: token),
        throwsA(isA<ItineraryStaleException>()),
      );
    });
  });

  group('lock lifecycle', () {
    test('acquire returns the raw token and the server-supplied cadence',
        () async {
      final (dio, adapter) = makeDio();
      adapter.onPost(
        itineraryLockEndpoint(itinId),
        (server) => server.reply(200, {
          'token': token,
          'lock': lockJson(isYou: true),
          'heartbeat_interval_seconds': 30,
          'ttl_seconds': 300,
        }),
        data: {'takeover': true},
      );

      final claim =
          await ItineraryRepository(dio).acquireLock(itinId, takeover: true);

      expect(claim.token, token);
      expect(claim.heartbeatInterval, const Duration(seconds: 30));
      expect(claim.lock.isYou, isTrue);
    });

    test('heartbeat sends the token and no body', () async {
      final (dio, adapter) = makeDio();
      adapter.onPost(
        itineraryLockHeartbeatEndpoint(itinId),
        (server) => server.reply(200, lockJson(isYou: true)),
        headers: {kEditLockHeader: token},
      );

      final lock = await ItineraryRepository(dio).heartbeatLock(itinId, token);

      expect(lock.isYou, isTrue);
      expect(lock.state, EditLockState.active);
    });
  });

  group('EditLockState.fromString', () {
    test('degrades an unknown value to active, never takeable', () {
      // The conservative direction: a newer backend must not make an older
      // client offer a takeover it does not understand.
      expect(EditLockState.fromString('something-new'), EditLockState.active);
      expect(EditLockState.fromString(null), EditLockState.active);
      expect(EditLockState.fromString('idle'), EditLockState.idle);
      expect(EditLockState.fromString('takeable'), EditLockState.takeable);
    });
  });

  group('granting an editor', () {
    test('409 editor_cannot_view surfaces the remedy, not a raw error',
        () async {
      final (dio, adapter) = makeDio();
      adapter.onPost(
        itineraryEditorsEndpoint(itinId),
        (server) => server.reply(409, {
          'code': 'editor_cannot_view',
          'detail': 'cannot see it',
          'visibility': 'restricted',
          'can_fix_with_allowlist': true,
        }),
        data: {'user_id': 'user-2', 'grant_view': false},
      );

      await expectLater(
        ItineraryRepository(dio).addEditor(itinId, 'user-2'),
        throwsA(
          isA<EditorCannotViewException>()
              .having((e) => e.canFixWithAllowlist, 'offers the allowlist fix',
                  isTrue)
              .having((e) => e.visibility, 'names the visibility', 'restricted'),
        ),
      );
    });

    test('grant_view is only ever sent when the caller asks for it', () async {
      final (dio, adapter) = makeDio();
      adapter.onPost(
        itineraryEditorsEndpoint(itinId),
        (server) => server.reply(201, {
          'user_id': 'user-2',
          'username': 'bobby',
          'display_name': 'Bobby',
          'avatar_url': null,
          'created_at': '2026-08-12T10:00:00Z',
        }),
        data: {'user_id': 'user-2', 'grant_view': true},
      );

      final editor = await ItineraryRepository(dio)
          .addEditor(itinId, 'user-2', grantView: true);

      expect(editor, isA<ItineraryEditor>());
      expect(editor.username, 'bobby');
    });
  });
}
