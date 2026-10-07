// features/translation/domain/translation.dart — what POST /translations and
// GET /translations/config answer, and what a request names.
//
// The client names content, never sends text: the server loads the text
// itself, so a reader can only ever have translated what they may read.

/// What happened to one field of one piece of content.
enum TranslationStatus {
  /// A translation came back — `text` carries it.
  translated,

  /// Already in the reader's language: nothing to show instead.
  sameLanguage,

  /// The field is blank.
  empty,

  /// The reader's hourly allowance is spent.
  rateLimited,

  /// No engine could translate it right now. The original stays on screen.
  unavailable;

  /// Unknown values from a newer backend degrade to [unavailable] — the
  /// conservative reading: keep the original, never crash a deployed client.
  static TranslationStatus fromString(String? raw) => switch (raw) {
        'translated' => translated,
        'same_language' => sameLanguage,
        'empty' => empty,
        'rate_limited' => rateLimited,
        _ => unavailable,
      };
}

class FieldTranslation {
  final TranslationStatus status;
  final String? text;
  final String? provider;
  final String? sourceLang;

  const FieldTranslation({
    required this.status,
    this.text,
    this.provider,
    this.sourceLang,
  });

  factory FieldTranslation.fromJson(Map<String, dynamic> json) =>
      FieldTranslation(
        status: TranslationStatus.fromString(json['status'] as String?),
        text: json['text'] as String?,
        provider: json['provider'] as String?,
        sourceLang: json['source_lang'] as String?,
      );

  /// Only a translated field with text has anything to show.
  bool get hasText => status == TranslationStatus.translated && text != null;
}

class TranslationItemResult {
  final String contentType;
  final String contentId;

  /// False when the server answered `not_found`: missing, not visible to this
  /// reader, or taken down — deliberately indistinguishable.
  final bool found;
  final Map<String, FieldTranslation> fields;

  const TranslationItemResult({
    required this.contentType,
    required this.contentId,
    required this.found,
    this.fields = const {},
  });

  factory TranslationItemResult.fromJson(Map<String, dynamic> json) {
    final raw = (json['fields'] as Map<String, dynamic>?) ?? const {};
    return TranslationItemResult(
      contentType: json['content_type'] as String,
      contentId: json['content_id'] as String,
      found: json['status'] == 'ok',
      fields: {
        for (final entry in raw.entries)
          entry.key:
              FieldTranslation.fromJson(entry.value as Map<String, dynamic>),
      },
    );
  }
}

/// One piece of content a request names, with the fields wanted.
class TranslationRequestItem {
  final String contentType;
  final String contentId;
  final List<String> fields;

  const TranslationRequestItem({
    required this.contentType,
    required this.contentId,
    required this.fields,
  });

  Map<String, dynamic> toJson() => {
        'content_type': contentType,
        'content_id': contentId,
        'fields': fields,
      };
}

class TranslationConfig {
  final bool enabled;
  final List<String> targetLangs;

  const TranslationConfig({required this.enabled, required this.targetLangs});

  /// What a client assumes when it cannot ask: no button anywhere.
  static const disabled = TranslationConfig(enabled: false, targetLangs: []);

  factory TranslationConfig.fromJson(Map<String, dynamic> json) =>
      TranslationConfig(
        enabled: json['enabled'] as bool? ?? false,
        targetLangs: (json['target_langs'] as List<dynamic>? ?? const [])
            .cast<String>(),
      );

  /// Whether a reader whose app is in [lang] may be offered a translation.
  bool offers(String lang) => enabled && targetLangs.contains(lang);
}

/// A feed card's cached title translation, sent with the feed for `?lang=`.
class TitleTranslation {
  final String lang;
  final String text;

  const TitleTranslation({required this.lang, required this.text});

  static TitleTranslation? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final lang = json['lang'] as String?;
    final text = json['text'] as String?;
    if (lang == null || text == null) return null;
    return TitleTranslation(lang: lang, text: text);
  }
}

/// Languages written right to left. A translation is laid out by the language
/// it is in, not by the app's — they differ whenever the two are not the same.
const kRtlLanguages = {'ar', 'he', 'fa', 'ur'};

bool isRtlLanguage(String? lang) => kRtlLanguages.contains(lang);
