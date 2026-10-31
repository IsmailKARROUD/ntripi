// Reading a Google Maps link's own text — never fetching it. The form's link
// field, its short-link hint and the trip's route all decide through these.
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/features/itineraries/data/google_maps_links.dart';

const _placeId = 'ChIJLU7jZClu5kcR4PcOOO6p3I0';

void main() {
  group('isGoogleMapsUrl', () {
    for (final url in [
      'https://maps.app.goo.gl/abc123',
      'https://maps.google.com/?q=48.85,2.29',
      'https://www.google.com/maps/place/Eiffel+Tower/',
      'https://google.com/maps/search/?api=1&query=x',
      'https://goo.gl/maps/xyz',
      '  https://maps.app.goo.gl/abc123  ',
    ]) {
      test('Given $url, When checked, Then it is a Google Maps link', () {
        expect(isGoogleMapsUrl(url), isTrue);
      });
    }

    for (final url in [
      'https://www.google.com/search?q=maps',
      'https://goo.gl/abc',
      'https://www.google.fr/maps/place/x',
      'https://youtube.com/watch?v=x',
      'ftp://maps.google.com/x',
      'maps.app.goo.gl/abc',
      '',
    ]) {
      test('Given "$url", When checked, Then it is refused', () {
        expect(isGoogleMapsUrl(url), isFalse);
      });
    }
  });

  group('extractMapCoords', () {
    test(
        "Given a place link, When read, Then the place's pin wins over the "
        "viewport centre", () {
      const url = 'https://www.google.com/maps/place/X/@48.80,2.20,17z/'
          'data=!3d48.8583701!4d2.2944813';
      expect(extractMapCoords(url), (48.8583701, 2.2944813));
    });

    test('Given a query parameter, When read, Then its coordinates come back',
        () {
      expect(
        extractMapCoords('https://www.google.com/maps/search/?api=1&query=50.85,4.35'),
        (50.85, 4.35),
      );
    });

    test('Given only a viewport, When read, Then the centre is the fallback',
        () {
      expect(
        extractMapCoords('https://www.google.com/maps/@-33.8567,151.2153,15z'),
        (-33.8567, 151.2153),
      );
    });

    test('Given coordinates out of range, When read, Then none come back', () {
      expect(extractMapCoords('https://www.google.com/maps/@95.1,200.2,15z'),
          isNull);
    });

    test('Given a short link, When read, Then there is nothing to read', () {
      expect(extractMapCoords('https://maps.app.goo.gl/abc123'), isNull);
    });
  });

  group('extractPlaceId', () {
    test('Given place_id: or query_place_id=, When read, Then the ID comes back',
        () {
      expect(extractPlaceId('https://www.google.com/maps/place/?q=place_id:$_placeId'),
          _placeId);
      expect(
        extractPlaceId('https://www.google.com/maps/search/?api=1&query=x'
            '&query_place_id=$_placeId'),
        _placeId,
      );
    });

    test('Given a !1s data field holding a ChIJ ID, When read, Then it comes back',
        () {
      expect(extractPlaceId('https://www.google.com/maps/place/X/data=!4m2!1s$_placeId'),
          _placeId);
    });

    test(
        'Given the hex feature ID most long links carry, When read, Then it is '
        'not taken for a place ID', () {
      expect(
        extractPlaceId('https://www.google.com/maps/place/X/data=!4m6!3m5'
            '!1s0x47e66e2964e34e2d:0x8ddca9ee380ef7e0'),
        isNull,
      );
    });

    test('Given a place_id too short to be one, When read, Then none comes back',
        () {
      expect(extractPlaceId('https://www.google.com/maps?place_id=abc'), isNull);
    });
  });
}
