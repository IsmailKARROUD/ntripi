// test/models/translation_models_test.dart
//
// What POST /translations, GET /translations/config and the feed's
// title_translation parse into, and the source_lang every translatable model
// now carries. Unknown values from a newer backend must degrade, never throw.

import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/feed/domain/feed_item.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary_annotation.dart';
import 'package:social_flutter/features/itineraries/domain/ratings_page.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';
import 'package:social_flutter/features/translation/domain/translation.dart';

const _at = '2026-10-07T10:00:00.000000Z';

Map<String, dynamic> _feedRow({Map<String, dynamic>? titleTranslation}) => {
      'id': 'itin-1',
      'user_id': 'owner-1',
      'title': 'Three days in Lisbon',
      'cover_image_url': null,
      'total_duration_min': 120,
      'total_cost': 0.0,
      'currency': 'EUR',
      'visibility': 'public',
      'created_at': _at,
      'updated_at': _at,
      'rating_avg': null,
      'rating_count': 0,
      'stops_count': 3,
      'owner': {
        'user_id': 'owner-1',
        'username': 'amina',
        'display_name': null,
        'avatar_url': null,
      },
      'source_lang': 'en',
      'title_translation': titleTranslation,
    };

void main() {
  group('TranslationStatus.fromString', () {
    test('Given each wire value, Then it maps to its status', () {
      expect(TranslationStatus.fromString('translated'),
          TranslationStatus.translated);
      expect(TranslationStatus.fromString('same_language'),
          TranslationStatus.sameLanguage);
      expect(TranslationStatus.fromString('empty'), TranslationStatus.empty);
      expect(TranslationStatus.fromString('rate_limited'),
          TranslationStatus.rateLimited);
      expect(TranslationStatus.fromString('unavailable'),
          TranslationStatus.unavailable);
    });

    test(
        'Given a value this client does not know, '
        'Then it reads as unavailable — the original stays on screen', () {
      expect(TranslationStatus.fromString('summarised'),
          TranslationStatus.unavailable);
      expect(TranslationStatus.fromString(null), TranslationStatus.unavailable);
    });
  });

  group('TranslationItemResult.fromJson', () {
    test('Given an ok item, Then its fields parse and it is found', () {
      final item = TranslationItemResult.fromJson({
        'content_type': 'itinerary',
        'content_id': 'itin-1',
        'status': 'ok',
        'fields': {
          'title': {
            'status': 'translated',
            'text': 'Trois jours à Lisbonne',
            'provider': 'openai',
            'source_lang': 'en',
          },
          'description': {'status': 'empty'},
        },
      });

      expect(item.found, isTrue);
      expect(item.fields['title']!.hasText, isTrue);
      expect(item.fields['title']!.text, 'Trois jours à Lisbonne');
      expect(item.fields['title']!.sourceLang, 'en');
      expect(item.fields['description']!.hasText, isFalse);
    });

    test(
        'Given not_found — missing, hidden or forbidden alike — '
        'Then it is not found and carries no fields', () {
      final item = TranslationItemResult.fromJson({
        'content_type': 'rating',
        'content_id': 'r-1',
        'status': 'not_found',
        'fields': <String, dynamic>{},
      });

      expect(item.found, isFalse);
      expect(item.fields, isEmpty);
    });
  });

  group('TranslationConfig', () {
    test('Given enabled with targets, Then it offers exactly those', () {
      final config = TranslationConfig.fromJson({
        'enabled': true,
        'target_langs': ['en', 'fr'],
      });

      expect(config.offers('fr'), isTrue);
      expect(config.offers('ar'), isFalse);
    });

    test('Given disabled, Then it offers nothing, whatever it lists', () {
      final config = TranslationConfig.fromJson({
        'enabled': false,
        'target_langs': ['fr'],
      });

      expect(config.offers('fr'), isFalse);
      expect(TranslationConfig.disabled.offers('en'), isFalse);
    });
  });

  group('FeedItem.fromJson', () {
    test('Given a cached title translation, Then the card carries it', () {
      final item = FeedItem.fromJson(_feedRow(
        titleTranslation: {'lang': 'fr', 'text': 'Trois jours à Lisbonne'},
      ));

      expect(item.titleTranslation!.lang, 'fr');
      expect(item.titleTranslation!.text, 'Trois jours à Lisbonne');
      expect(item.itinerary.sourceLang, 'en');
    });

    test('Given none, Then the card has no translation', () {
      expect(FeedItem.fromJson(_feedRow()).titleTranslation, isNull);
    });
  });

  group('source_lang on the translatable models', () {
    test('Given an itinerary, Then source_lang parses and round-trips', () {
      final itinerary = Itinerary.fromJson({
        ..._feedRow(),
        'description': null,
        'tracks': <Map<String, dynamic>>[],
        'segments': <Map<String, dynamic>>[],
        'annotations': <Map<String, dynamic>>[],
        'source_lang': 'pt',
      });

      expect(itinerary.sourceLang, 'pt');
      expect(itinerary.toJson()['source_lang'], 'pt');
    });

    test('Given both annotation kinds, Then source_lang parses', () {
      final stopNote = Annotation.fromJson({
        'id': 'a-1',
        'stop_id': 's-1',
        'type': 'advice',
        'content': 'Ve temprano',
        'created_at': _at,
        'updated_at': _at,
        'source_lang': 'es',
      });
      final tripNote = ItineraryAnnotation.fromJson({
        'id': 'ia-1',
        'itinerary_id': 'itin-1',
        'type': 'info',
        'content': 'Bring cash',
        'created_at': _at,
        'updated_at': _at,
        'source_lang': null,
      });

      expect(stopNote.sourceLang, 'es');
      expect(tripNote.sourceLang, isNull);
    });

    test('Given a review, Then source_lang parses', () {
      final rating = RatingWithUser.fromJson({
        'id': 'r-1',
        'score': 4,
        'note': 'Sehr schön',
        'updated_at': _at,
        'user': {'user_id': 'u-1', 'username': 'jo'},
        'source_lang': 'de',
      });

      expect(rating.sourceLang, 'de');
    });

    test('Given a transport leg, Then source_lang parses and round-trips', () {
      final leg = TransportLeg.fromJson({
        'id': 'leg-1',
        'segment_id': 'seg-1',
        'position': 1,
        'mode': 'metro',
        'notes': 'Prenez la deuxième voiture',
        'created_at': _at,
        'source_lang': 'fr',
      });

      expect(leg.sourceLang, 'fr');
      expect(leg.hasNotes, isTrue);
      expect(leg.toJson()['source_lang'], 'fr');
      expect(leg.copyWith(position: 2).sourceLang, 'fr');
    });

    test('Given a leg with blank notes, Then it has no thoughts to show', () {
      final leg = TransportLeg.fromJson({
        'id': 'leg-1',
        'segment_id': 'seg-1',
        'position': 1,
        'mode': 'walk',
        'notes': '   ',
        'created_at': _at,
      });

      expect(leg.hasNotes, isFalse);
      expect(leg.sourceLang, isNull);
      expect(leg.toJson().containsKey('source_lang'), isFalse);
    });
  });
}
