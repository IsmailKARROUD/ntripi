// The pieces every Google surface reads a stop through: where Google can find
// it (mapPointOf), the trip as one route (tripRoute), where a search looks
// first (searchBias), and the address of a Google map (GoogleEmbed).
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
import 'package:ntripi/features/itineraries/data/google_embed_urls.dart';
import 'package:ntripi/features/itineraries/domain/map_point.dart';
import 'package:ntripi/features/itineraries/domain/search_bias.dart';
import 'package:ntripi/features/itineraries/domain/stop.dart';
import 'package:ntripi/features/itineraries/domain/track.dart';
import 'package:ntripi/features/itineraries/domain/trip_route.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/google_map_embed.dart';

const _placeId = 'ChIJLU7jZClu5kcR4PcOOO6p3I0';

Stop _stop(
  String id, {
  String? name = 'Harbour',
  double? lat,
  double? lng,
  String? mapUrl,
  String? placeId,
  String? query,
  bool missing = false,
}) =>
    Stop(
      id: id,
      itineraryId: 'trip',
      trackId: 't',
      rank: 'a0',
      type: StopType.waypoint,
      placeName: name,
      lat: lat,
      lng: lng,
      mapUrl: mapUrl,
      googlePlaceId: placeId,
      googlePlaceQuery: query,
      googlePlaceMissing: missing,
      createdAt: DateTime.utc(2026, 10, 31),
    );

Track _track(String id, List<Stop> stops) =>
    Track(id: id, itineraryId: 'trip', rank: id, stops: stops);

void main() {
  group('mapPointOf', () {
    test('a Google place is found by its ID, with the search words beside it',
        () {
      expect(mapPointOf(_stop('s', placeId: _placeId, query: 'eiffel')),
          const PlacePoint(_placeId, 'eiffel'));
    });

    test('without search words the name stands in for Maps URLs', () {
      expect(mapPointOf(_stop('s', name: 'Tower', placeId: _placeId)),
          const PlacePoint(_placeId, 'Tower'));
    });

    test('a place Google lost is nowhere', () {
      expect(mapPointOf(_stop('s', placeId: _placeId, missing: true)), isNull);
    });

    test('coordinates locate an ordinary stop', () {
      expect(mapPointOf(_stop('s', lat: 50.85, lng: 4.35)),
          const CoordPoint(50.85, 4.35));
    });

    test("a link is read from its own text — never fetched", () {
      expect(
        mapPointOf(_stop('s',
            mapUrl: 'https://www.google.com/maps/search/?api=1&query=x'
                '&query_place_id=$_placeId')),
        const PlacePoint(_placeId, 'Harbour'),
      );
      expect(
        mapPointOf(_stop('s',
            mapUrl: 'https://www.google.com/maps/place/X/@48.85,2.29,17z')),
        const CoordPoint(48.85, 2.29),
      );
      // A share link names no place.
      expect(mapPointOf(_stop('s', mapUrl: 'https://maps.app.goo.gl/abc')),
          isNull);
    });
  });

  group('tripRoute', () {
    test('one point per track: the alternative on screen', () {
      final tracks = [
        _track('t1', [_stop('a', lat: 1, lng: 1), _stop('b', lat: 2, lng: 2)]),
        _track('t2', [_stop('c', placeId: _placeId, query: 'q')]),
      ];

      final route = tripRoute(tracks, {'t1': 1});

      expect(route.points,
          [const CoordPoint(2, 2), const PlacePoint(_placeId, 'q')]);
      expect(route.unmapped, 0);
    });

    test('a stop nothing locates is left out and counted', () {
      final tracks = [
        _track('t1', [_stop('a', lat: 1, lng: 1)]),
        _track('t2', [_stop('b', mapUrl: 'https://maps.app.goo.gl/x')]),
        _track('t3', [_stop('c', placeId: _placeId, missing: true)]),
        _track('t4', [_stop('d', lat: 4, lng: 4)]),
      ];

      final route = tripRoute(tracks, const {});

      expect(route.points, [const CoordPoint(1, 1), const CoordPoint(4, 4)]);
      expect(route.unmapped, 2);
    });
  });

  group('searchBias', () {
    final tracks = [
      _track('t1', [_stop('a', lat: 10, lng: 10)]),
      _track('t2', [_stop('b', placeId: _placeId), _stop('c', lat: 20, lng: 20)]),
      _track('t3', [_stop('d', mapUrl: 'https://maps.app.goo.gl/x')]),
    ];

    test('an alternative in the same track first', () {
      expect(searchBias(tracks: tracks, trackId: 't2'), (lat: 20.0, lng: 20.0));
    });

    test('a stop never anchors its own search', () {
      expect(
        searchBias(tracks: tracks, trackId: 't2', editingStopId: 'c'),
        (lat: 10.0, lng: 10.0),
      );
    });

    test('a new track looks back to the nearest earlier stop', () {
      expect(searchBias(tracks: tracks, afterTrackId: 't3'),
          (lat: 20.0, lng: 20.0));
      expect(searchBias(tracks: tracks, beforeTrackId: 't2'),
          (lat: 10.0, lng: 10.0));
    });

    test('the device only when the trip has no coordinates, rounded to 0.1°',
        () {
      final none = [_track('t1', [_stop('a', placeId: _placeId)])];
      expect(
        searchBias(tracks: none, deviceLat: 50.85045, deviceLng: 4.34878),
        (lat: 50.9, lng: 4.3),
      );
      expect(searchBias(tracks: none), isNull);
    });
  });

  group('GoogleEmbed', () {
    test('every map is a page on our own server', () {
      final uri = GoogleEmbed.point(const PlacePoint(_placeId, 'x'), 'fr');

      expect(uri.toString(), startsWith('$kApiBaseUrl/embed/place?'));
      expect(uri.queryParameters, {'id': _placeId, 'language': 'fr'});
    });

    test('`language`, never `lang`: the site cookie reads lang', () {
      for (final uri in [
        GoogleEmbed.point(const CoordPoint(1.5, 2.5), 'de'),
        GoogleEmbed.search('Café', 'de'),
        GoogleEmbed.directions(
            const [CoordPoint(1, 2), PlacePoint(_placeId, 'x')], 'de'),
      ]) {
        expect(uri.queryParameters.containsKey('lang'), isFalse);
        expect(uri.queryParameters['language'], 'de');
      }
    });

    test('a point, a search and a route', () {
      expect(GoogleEmbed.point(const CoordPoint(1.5, 2.5), 'en').queryParameters,
          {'lat': '1.5', 'lng': '2.5', 'language': 'en'});
      expect(GoogleEmbed.search('Café de Flore', 'en').queryParameters['q'],
          'Café de Flore');
      final route = GoogleEmbed.directions(
          const [CoordPoint(1, 2), PlacePoint(_placeId, 'x'), CoordPoint(3, 4)],
          'en');
      expect(route.path, '/embed/directions');
      expect(route.queryParameters['points'], '1.0,2.0|place_id:$_placeId|3.0,4.0');
    });
  });

  group('edge cases', () {
    test(
        'Given a Google place with no search words and no name, When located, '
        'Then the Maps URL text is empty, never null', () {
      expect(mapPointOf(_stop('s', name: null, placeId: _placeId)),
          const PlacePoint(_placeId, ''));
    });

    test('Given each kind of point, When written for Google, Then the tokens '
        'are the ones the embed page and Maps URLs read', () {
      const place = PlacePoint(_placeId, 'eiffel');
      const coords = CoordPoint(48.85, -2.5);
      expect([place.embedToken, place.urlText, place.placeId],
          ['place_id:$_placeId', 'eiffel', _placeId]);
      expect([coords.embedToken, coords.urlText, coords.placeId],
          ['48.85,-2.5', '48.85,-2.5', null]);
    });

    test('Given a track with no stops, When routed, Then it is neither a point '
        'nor counted as unplaced', () {
      final route = tripRoute([
        _track('t1', []),
        _track('t2', [_stop('a', lat: 1, lng: 1)]),
      ], const {});
      expect(route.points, [const CoordPoint(1, 1)]);
      expect(route.unmapped, 0);
    });

    test('Given an alternative index past the track, When routed, Then the '
        'last alternative is taken', () {
      final route = tripRoute([
        _track('t1', [_stop('a', lat: 1, lng: 1), _stop('b', lat: 2, lng: 2)]),
      ], {'t1': 9});
      expect(route.points, [const CoordPoint(2, 2)]);
    });

    test('Given a track id the trip no longer has, When biased, Then the '
        "trip's first stop with coordinates is the anchor", () {
      final tracks = [
        _track('t1', [_stop('a', placeId: _placeId)]),
        _track('t2', [_stop('b', lat: 7, lng: 8)]),
      ];
      expect(searchBias(tracks: tracks, trackId: 'gone'), (lat: 7.0, lng: 8.0));
    });

    test('Given a device south and west of zero, When rounded, Then it rounds '
        'to 0.1° like any other', () {
      expect(searchBias(tracks: const [], deviceLat: -33.8567, deviceLng: -70.6483),
          (lat: -33.9, lng: -70.6));
    });
  });

  group('GoogleEmbed.capRoute', () {
    List<MapPoint> points(int n) =>
        [for (var i = 0; i < n; i++) CoordPoint(i.toDouble(), i.toDouble())];

    test('Given 22 points, When capped, Then all of them stay', () {
      expect(GoogleEmbed.capRoute(points(22)), points(22));
    });

    test(
        'Given 30 points, When capped, Then the first 21 and the destination '
        'stay', () {
      final capped = GoogleEmbed.capRoute(points(30));
      expect(capped.length, GoogleEmbed.maxRoutePoints);
      expect(capped.take(21), points(21));
      expect(capped.last, const CoordPoint(29, 29));
    });
  });

  group('embedNavigationAllowed', () {
    const api = 'ntripi.app';

    test('Given one of our /embed pages, When it is the page, Then it loads', () {
      expect(
          embedNavigationAllowed('https://ntripi.app/embed/place?id=x',
              isMainFrame: true, apiHost: api),
          isTrue);
    });

    for (final url in [
      'https://ntripi.app/app/',
      'https://ntripi.app/share/i/x',
      'https://www.google.com/maps/place/x',
      'https://evil.example/embed/place',
      'not a url at all %%',
    ]) {
      test('Given $url, When it would replace the page, Then it is refused', () {
        expect(embedNavigationAllowed(url, isMainFrame: true, apiHost: api),
            isFalse);
      });
    }

    test("Given Google's map frame and its assets, When framed, Then they load",
        () {
      for (final url in [
        'https://www.google.com/maps/embed/v1/place?q=x',
        'https://maps.gstatic.com/tiles/x.png',
        'about:blank',
      ]) {
        expect(embedNavigationAllowed(url, isMainFrame: false, apiHost: api),
            isTrue, reason: url);
      }
    });

    test('Given any other site, When framed, Then it is refused', () {
      expect(
          embedNavigationAllowed('https://ads.example/frame',
              isMainFrame: false, apiHost: api),
          isFalse);
      expect(
          embedNavigationAllowed('https://notgoogle.com/x',
              isMainFrame: false, apiHost: api),
          isFalse);
    });
  });
}
