// features/translation/providers/translation_providers.dart — Riverpod state
// for "See translation".
//
// translationConfigProvider — whether the server translates, and into which
//   languages. Signed out, or when it cannot be read, translation is off and no
//   button is drawn.
// contentTranslationProvider — one notifier per content group and language:
//   a trip header with its trip-wide notes, a stop with its notes and
//   annotations, or one review. One tap sends one request for the whole group.
//
// Both are keep-alive and listed in auth_provider's _userScopedProviders: a
// translation of something one account could read must not survive into the
// next account's session on the same device.

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/features/translation/data/translation_repository.dart';
import 'package:social_flutter/features/translation/domain/translation.dart';

final translationConfigProvider = FutureProvider<TranslationConfig>((ref) async {
  // Both endpoints need a session; signed out, asking would only earn a 401.
  if (!await ref.watch(hasSessionProvider.future)) {
    return TranslationConfig.disabled;
  }
  try {
    return await ref.read(translationRepositoryProvider).getConfig();
  } catch (_) {
    if (!ref.mounted) return TranslationConfig.disabled;
    // Off for now, asked again on the next return to the foreground or the
    // network — auto-retry is off app-wide (main.dart), and a failure kept for
    // the session would hide every button until sign-out.
    final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
    ref.onDispose(lifecycle.dispose);
    ref.listen(isOnlineProvider, (previous, next) {
      if (previous?.value == false && next.value == true) ref.invalidateSelf();
    });
    return TranslationConfig.disabled;
  }
});

/// A translation group, named by its anchor: the trip, stop or review whose
/// toggle covers it.
typedef TranslationAnchor = ({String contentType, String contentId});

/// The anchor of a translation group, and the language it is translated into.
typedef TranslationKey = ({
  String contentType,
  String contentId,
  String targetLang,
});

TranslationKey translationKey(TranslationAnchor anchor, String targetLang) => (
      contentType: anchor.contentType,
      contentId: anchor.contentId,
      targetLang: targetLang,
    );

/// Mirrors MAX_ITEMS_PER_REQUEST in schemas/translation.py — a trip with more
/// trip-wide notes than this goes out in several requests.
const kMaxTranslationItemsPerRequest = 50;

/// One piece of content in a group: what to name in the request, and the text
/// each field holds right now.
class TranslationMember {
  final String contentType;
  final String contentId;

  /// Field name → current original text (null or blank = nothing there).
  final Map<String, String?> fields;

  /// The server's detected language for this content, if any.
  final String? sourceLang;

  const TranslationMember({
    required this.contentType,
    required this.contentId,
    required this.fields,
    this.sourceLang,
  });

  bool get hasText => fields.values.any(_isText);

  /// Worth offering to a reader in [lang]: something to translate, in a
  /// language that is not already theirs — or one the server could not tell.
  bool offersTo(String lang) => hasText && sourceLang != lang;
}

bool _isText(String? text) => text != null && text.trim().isNotEmpty;

String translationFieldKey(String contentType, String contentId, String field) =>
    '$contentType:$contentId:$field';

enum TranslationPhase { idle, loading, shown, original, failed }

/// Why a request produced nothing to show.
enum TranslationProblem { failed, unavailable, rateLimited }

class ContentTranslationState {
  final TranslationPhase phase;

  /// Field key → the server's final answer (translated, same language, or
  /// empty). Transient answers — unavailable, rate limited — are never kept:
  /// a field without an answer is asked again on the next tap.
  final Map<String, FieldTranslation> results;

  /// Field key → the original text the answer was made from. A field whose
  /// text has changed since is stale: its original shows, and the next tap
  /// asks again.
  final Map<String, String> madeFrom;

  final TranslationProblem? problem;

  const ContentTranslationState({
    this.phase = TranslationPhase.idle,
    this.results = const {},
    this.madeFrom = const {},
    this.problem,
  });

  ContentTranslationState copyWith({
    TranslationPhase? phase,
    Map<String, FieldTranslation>? results,
    Map<String, String>? madeFrom,
    TranslationProblem? problem,
    bool clearProblem = false,
  }) =>
      ContentTranslationState(
        phase: phase ?? this.phase,
        results: results ?? this.results,
        madeFrom: madeFrom ?? this.madeFrom,
        problem: clearProblem ? null : (problem ?? this.problem),
      );

  /// The answer for one field, if it was made from [original].
  FieldTranslation? _answer(
      String contentType, String contentId, String field, String original) {
    final key = translationFieldKey(contentType, contentId, field);
    return madeFrom[key] == original ? results[key] : null;
  }

  /// The translation to show in place of [original], or null for the original.
  String? textFor(
      String contentType, String contentId, String field, String? original) {
    if (phase != TranslationPhase.shown || original == null) return null;
    final answer = _answer(contentType, contentId, field, original);
    return answer != null && answer.hasText ? answer.text : null;
  }

  /// Whether every non-blank field of [members] has an answer made from its
  /// current text — tapping again would need no request.
  bool isFreshFor(List<TranslationMember> members) => members.every((m) =>
      m.fields.entries.every((f) =>
          !_isText(f.value) ||
          _answer(m.contentType, m.contentId, f.key, f.value!) != null));

  /// Whether some field of [members] has a translation for its current text.
  bool translatesAny(List<TranslationMember> members) => members.any((m) =>
      m.fields.entries.any((f) =>
          _isText(f.value) &&
          (_answer(m.contentType, m.contentId, f.key, f.value!)?.hasText ??
              false)));
}

class ContentTranslationNotifier extends Notifier<ContentTranslationState> {
  ContentTranslationNotifier(this.arg); // family argument: anchor + language

  final TranslationKey arg;

  @override
  ContentTranslationState build() => const ContentTranslationState();

  /// Translate [members] into the key's language and show the result. Members
  /// already in that language are left out of the request.
  Future<void> translate(List<TranslationMember> members) async {
    if (state.phase == TranslationPhase.loading) return;
    final offered = [
      for (final m in members)
        if (m.offersTo(arg.targetLang)) m,
    ];
    if (offered.isEmpty) return;
    // Everything already answered for the current text: no request.
    if (state.isFreshFor(offered)) {
      state = state.copyWith(
        phase: state.translatesAny(offered)
            ? TranslationPhase.shown
            : TranslationPhase.original,
        clearProblem: true,
      );
      return;
    }

    state = state.copyWith(phase: TranslationPhase.loading, clearProblem: true);
    final byContent = {
      for (final m in offered) (m.contentType, m.contentId): m,
    };
    // Only fields with no answer for their current text: the rest are on hand.
    final items = <TranslationRequestItem>[];
    for (final m in offered) {
      final fields = [
        for (final f in m.fields.entries)
          if (_isText(f.value) &&
              state._answer(m.contentType, m.contentId, f.key, f.value!) ==
                  null)
            f.key,
      ];
      if (fields.isNotEmpty) {
        items.add(TranslationRequestItem(
          contentType: m.contentType,
          contentId: m.contentId,
          fields: fields,
        ));
      }
    }
    try {
      final answers = <TranslationItemResult>[];
      for (var i = 0; i < items.length; i += kMaxTranslationItemsPerRequest) {
        final end = i + kMaxTranslationItemsPerRequest;
        answers.addAll(await ref.read(translationRepositoryProvider).translate(
              targetLang: arg.targetLang,
              items: items.sublist(i, end < items.length ? end : items.length),
            ));
        if (!ref.mounted) return; // disposed mid-request (sign-out)
      }

      final results = Map<String, FieldTranslation>.of(state.results);
      final madeFrom = Map<String, String>.of(state.madeFrom);
      var rateLimited = false;
      var unavailable = false;
      for (final answer in answers) {
        final member = byContent[(answer.contentType, answer.contentId)];
        // Missing, no longer visible, or taken down — deliberately alike.
        if (!answer.found || member == null) {
          unavailable = true;
          continue;
        }
        for (final entry in answer.fields.entries) {
          switch (entry.value.status) {
            case TranslationStatus.rateLimited:
              rateLimited = true;
            case TranslationStatus.unavailable:
              unavailable = true;
            case _:
              final key = translationFieldKey(
                  answer.contentType, answer.contentId, entry.key);
              results[key] = entry.value;
              madeFrom[key] = member.fields[entry.key] ?? '';
          }
        }
      }

      final next = ContentTranslationState(results: results, madeFrom: madeFrom);
      // Partly translated still shows: the fields that failed keep their
      // original, and the next tap asks for them again.
      state = next.translatesAny(offered)
          ? next.copyWith(phase: TranslationPhase.shown)
          : rateLimited
              ? next.copyWith(
                  phase: TranslationPhase.failed,
                  problem: TranslationProblem.rateLimited)
              : unavailable
                  ? next.copyWith(
                      phase: TranslationPhase.failed,
                      problem: TranslationProblem.unavailable)
                  // Blank or already in the reader's language, all of it.
                  : next.copyWith(phase: TranslationPhase.original);
    } on DioException catch (e) {
      if (!ref.mounted) return;
      final status = e.response?.statusCode;
      // 404: switched off since the config was read. 400: this language was
      // withdrawn. Either way the config is stale, and re-reading it takes the
      // button away with it.
      final withdrawn = status == 404 || status == 400;
      if (withdrawn) ref.invalidate(translationConfigProvider);
      state = state.copyWith(
        phase: TranslationPhase.failed,
        problem: status == 429
            ? TranslationProblem.rateLimited
            : withdrawn
                ? TranslationProblem.unavailable
                : TranslationProblem.failed,
      );
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: TranslationPhase.failed,
        problem: TranslationProblem.failed,
      );
    }
  }

  void showOriginal() {
    if (state.phase == TranslationPhase.shown) {
      state = state.copyWith(phase: TranslationPhase.original);
    }
  }
}

/// Not autoDispose: a translation survives the stop page being popped and
/// pushed again within a session.
final contentTranslationProvider = NotifierProvider.family<
    ContentTranslationNotifier, ContentTranslationState, TranslationKey>(
  ContentTranslationNotifier.new,
);
