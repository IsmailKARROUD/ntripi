// features/translation/data/translation_repository.dart — the two translation
// endpoints, over the shared Dio client.
//
// The config GET goes through the HTTP cache like every other GET (ETag/304,
// served stale offline). The POST is never cached.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/api/api_client.dart';
import 'package:social_flutter/core/api/api_endpoints.dart';
import 'package:social_flutter/features/translation/domain/translation.dart';

class TranslationRepository {
  final Dio _dio;

  const TranslationRepository(this._dio);

  Future<TranslationConfig> getConfig() async {
    final response =
        await _dio.get<Map<String, dynamic>>(kTranslationsConfigEndpoint);
    final data = response.data;
    return data == null
        ? TranslationConfig.disabled
        : TranslationConfig.fromJson(data);
  }

  /// [targetLang] travels in the body: one explicit value the server
  /// validates, rather than whatever Accept-Language a platform sends.
  Future<List<TranslationItemResult>> translate({
    required String targetLang,
    required List<TranslationRequestItem> items,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      kTranslationsEndpoint,
      data: {
        'target_lang': targetLang,
        'items': [for (final item in items) item.toJson()],
      },
    );
    return ((response.data?['items'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TranslationItemResult.fromJson)
        .toList();
  }
}

final translationRepositoryProvider = Provider<TranslationRepository>((ref) {
  return TranslationRepository(dio);
});
