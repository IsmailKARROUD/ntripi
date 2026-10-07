// test/repositories/translation_repository_test.dart
//
// The HTTP contract of the two translation endpoints. The request names
// content and never carries its text — the server loads the text itself, which
// is what keeps a reader from translating anything they may not read.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/translation/data/translation_repository.dart';
import 'package:social_flutter/features/translation/domain/translation.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late TranslationRepository repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: kApiBaseUrl));
    adapter = DioAdapter(dio: dio);
    repository = TranslationRepository(dio);
  });

  test('Given the server translates, When the config is read, Then it parses',
      () async {
    adapter.onGet(
      kTranslationsConfigEndpoint,
      (server) => server.reply(200, {
        'enabled': true,
        'target_langs': ['en', 'fr', 'ar'],
      }),
    );

    final config = await repository.getConfig();

    expect(config.enabled, isTrue);
    expect(config.targetLangs, ['en', 'fr', 'ar']);
  });

  test(
      'Given named content, When translated, '
      'Then the body carries ids and field names only, and the answer parses',
      () async {
    adapter.onPost(
      kTranslationsEndpoint,
      (server) => server.reply(200, {
        'target_lang': 'fr',
        'items': [
          {
            'content_type': 'stop',
            'content_id': 'stop-1',
            'status': 'ok',
            'fields': {
              'notes': {
                'status': 'translated',
                'text': 'Arrivez tôt',
                'provider': 'openai',
                'source_lang': 'en',
              },
            },
          },
          {
            'content_type': 'stop_annotation',
            'content_id': 'note-1',
            'status': 'not_found',
            'fields': <String, dynamic>{},
          },
        ],
      }),
      // http_mock_adapter matches the body exactly: no text, no user data.
      data: {
        'target_lang': 'fr',
        'items': [
          {
            'content_type': 'stop',
            'content_id': 'stop-1',
            'fields': ['notes'],
          },
          {
            'content_type': 'stop_annotation',
            'content_id': 'note-1',
            'fields': ['content'],
          },
        ],
      },
    );

    final items = await repository.translate(
      targetLang: 'fr',
      items: const [
        TranslationRequestItem(
            contentType: 'stop', contentId: 'stop-1', fields: ['notes']),
        TranslationRequestItem(
            contentType: 'stop_annotation',
            contentId: 'note-1',
            fields: ['content']),
      ],
    );

    expect(items, hasLength(2));
    expect(items[0].fields['notes']!.text, 'Arrivez tôt');
    expect(items[1].found, isFalse);
  });

  test('Given translation is switched off, When translating, Then the 404 surfaces',
      () async {
    adapter.onPost(
      kTranslationsEndpoint,
      (server) => server.reply(404, {'detail': 'Not Found'}),
      data: Matchers.any,
    );

    expect(
      () => repository.translate(targetLang: 'fr', items: const [
        TranslationRequestItem(
            contentType: 'rating', contentId: 'r-1', fields: ['note']),
      ]),
      throwsA(isA<DioException>().having(
          (e) => e.response?.statusCode, 'status', 404)),
    );
  });
}
