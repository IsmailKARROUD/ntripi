// test/providers/content_translation_test.dart
//
// ContentTranslationNotifier: one group, one request, one toggle.
//
// What it must guarantee:
//   - only content not already in the reader's language is sent, and only its
//     non-blank fields;
//   - an answer is shown only while the original it was made from is still the
//     text on screen;
//   - transient answers (unavailable, rate limited, a failed request) are never
//     kept, so the next tap asks again — the client form of "never cache
//     failures";
//   - a 404/400 re-reads the config, which is what takes the button away.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/auth/providers/auth_provider.dart';
import 'package:social_flutter/features/translation/data/translation_repository.dart';
import 'package:social_flutter/features/translation/domain/translation.dart';
import 'package:social_flutter/features/translation/providers/translation_providers.dart';

typedef _Answer = FutureOr<List<TranslationItemResult>> Function(
    List<TranslationRequestItem> items);

class _FakeRepository implements TranslationRepository {
  _FakeRepository(this.answer);

  _Answer answer;
  final calls = <List<TranslationRequestItem>>[];

  @override
  Future<TranslationConfig> getConfig() async =>
      const TranslationConfig(enabled: true, targetLangs: ['en', 'fr', 'ar']);

  @override
  Future<List<TranslationItemResult>> translate({
    required String targetLang,
    required List<TranslationRequestItem> items,
  }) async {
    calls.add(items);
    return answer(items);
  }
}

/// Every requested field comes back with [status]; translated ones carry
/// `fr:{content id}:{field}`.
_Answer _every(TranslationStatus status) => (items) => [
      for (final item in items)
        TranslationItemResult(
          contentType: item.contentType,
          contentId: item.contentId,
          found: true,
          fields: {
            for (final field in item.fields)
              field: FieldTranslation(
                status: status,
                text: status == TranslationStatus.translated
                    ? 'fr:${item.contentId}:$field'
                    : null,
              ),
          },
        ),
    ];

const _key = (contentType: 'stop', contentId: 'stop-1', targetLang: 'fr');

const _stop = TranslationMember(
  contentType: 'stop',
  contentId: 'stop-1',
  sourceLang: 'en',
  fields: {'notes': 'Arrive early'},
);

const _noteInFrench = TranslationMember(
  contentType: 'stop_annotation',
  contentId: 'note-fr',
  sourceLang: 'fr',
  fields: {'content': 'Déjà en français'},
);

const _noteUndetected = TranslationMember(
  contentType: 'stop_annotation',
  contentId: 'note-x',
  fields: {'content': 'Ok'},
);

void main() {
  late _FakeRepository repository;
  late ProviderContainer container;

  ContentTranslationNotifier notifier() =>
      container.read(contentTranslationProvider(_key).notifier);
  ContentTranslationState state() =>
      container.read(contentTranslationProvider(_key));

  setUp(() {
    repository = _FakeRepository(_every(TranslationStatus.translated));
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [translationRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
  });

  test(
      'Given a group, When translated, '
      'Then only content not in the reader\'s language is sent, and shown',
      () async {
    await notifier().translate([_stop, _noteInFrench, _noteUndetected]);

    expect(repository.calls, hasLength(1));
    final sent = repository.calls.single;
    // The French note is the reader's own language; an undetected one is sent.
    expect(sent.map((i) => i.contentId), ['stop-1', 'note-x']);
    expect(sent.first.fields, ['notes']);
    expect(state().phase, TranslationPhase.shown);
    expect(state().textFor('stop', 'stop-1', 'notes', 'Arrive early'),
        'fr:stop-1:notes');
    expect(
        state().textFor(
            'stop_annotation', 'note-fr', 'content', 'Déjà en français'),
        isNull);
  });

  test('Given blank fields, Then they are never asked for', () async {
    await notifier().translate([
      const TranslationMember(
        contentType: 'itinerary',
        contentId: 'itin-1',
        fields: {
          'title': 'Lisbon',
          'description': '   ',
          'recommended_period_note': null,
        },
      ),
    ]);

    expect(repository.calls.single.single.fields, ['title']);
  });

  test(
      'Given a translation already held, When shown again, '
      'Then it needs no request', () async {
    await notifier().translate([_stop]);
    notifier().showOriginal();
    expect(state().phase, TranslationPhase.original);
    expect(state().textFor('stop', 'stop-1', 'notes', 'Arrive early'), isNull);

    await notifier().translate([_stop]);

    expect(repository.calls, hasLength(1));
    expect(state().phase, TranslationPhase.shown);
  });

  test(
      'Given the text was edited since, '
      'Then the old translation is not shown and only the edit is asked for',
      () async {
    const note = TranslationMember(
      contentType: 'stop_annotation',
      contentId: 'note-1',
      sourceLang: 'en',
      fields: {'content': 'Cash only'},
    );
    await notifier().translate([_stop, note]);

    const edited = TranslationMember(
      contentType: 'stop_annotation',
      contentId: 'note-1',
      sourceLang: 'en',
      fields: {'content': 'Cards accepted now'},
    );
    expect(
        state().textFor(
            'stop_annotation', 'note-1', 'content', 'Cards accepted now'),
        isNull);
    expect(state().isFreshFor([_stop, edited]), isFalse);

    notifier().showOriginal();
    await notifier().translate([_stop, edited]);

    expect(repository.calls, hasLength(2));
    expect(repository.calls.last.map((i) => i.contentId), ['note-1']);
  });

  test(
      'Given every engine is down, When translated, '
      'Then the original stays, the reason is kept, and the next tap asks again',
      () async {
    repository.answer = _every(TranslationStatus.unavailable);

    await notifier().translate([_stop]);

    expect(state().phase, TranslationPhase.failed);
    expect(state().problem, TranslationProblem.unavailable);
    expect(state().textFor('stop', 'stop-1', 'notes', 'Arrive early'), isNull);
    expect(state().isFreshFor([_stop]), isFalse);

    repository.answer = _every(TranslationStatus.translated);
    await notifier().translate([_stop]);

    expect(repository.calls, hasLength(2));
    expect(state().phase, TranslationPhase.shown);
  });

  test('Given the hourly limit is spent, Then it says so', () async {
    repository.answer = _every(TranslationStatus.rateLimited);

    await notifier().translate([_stop]);

    expect(state().phase, TranslationPhase.failed);
    expect(state().problem, TranslationProblem.rateLimited);
  });

  test(
      'Given the server finds everything already in the reader\'s language, '
      'Then there is nothing to offer until the text changes', () async {
    repository.answer = _every(TranslationStatus.sameLanguage);

    await notifier().translate([_noteUndetected]);

    expect(state().phase, TranslationPhase.original);
    expect(state().isFreshFor([_noteUndetected]), isTrue);
    expect(state().translatesAny([_noteUndetected]), isFalse);
  });

  test(
      'Given one field translates and one fails, '
      'Then the translation shows and the failed one keeps its original',
      () async {
    const note = TranslationMember(
      contentType: 'stop_annotation',
      contentId: 'note-1',
      sourceLang: 'en',
      fields: {'content': 'Cash only'},
    );
    repository.answer = (items) => [
          TranslationItemResult(
            contentType: 'stop',
            contentId: 'stop-1',
            found: true,
            fields: {
              'notes': const FieldTranslation(
                  status: TranslationStatus.translated, text: 'Arrivez tôt'),
            },
          ),
          TranslationItemResult(
            contentType: 'stop_annotation',
            contentId: 'note-1',
            found: true,
            fields: {
              'content': const FieldTranslation(
                  status: TranslationStatus.unavailable),
            },
          ),
        ];

    await notifier().translate([_stop, note]);

    expect(state().phase, TranslationPhase.shown);
    expect(state().textFor('stop', 'stop-1', 'notes', 'Arrive early'),
        'Arrivez tôt');
    expect(
        state().textFor('stop_annotation', 'note-1', 'content', 'Cash only'),
        isNull);
  });

  test('Given content the reader may no longer see, Then it reads unavailable',
      () async {
    repository.answer = (items) => [
          for (final item in items)
            TranslationItemResult(
              contentType: item.contentType,
              contentId: item.contentId,
              found: false,
            ),
        ];

    await notifier().translate([_stop]);

    expect(state().problem, TranslationProblem.unavailable);
  });

  test(
      'Given translation was switched off since the config was read, '
      'When the POST 404s, Then the config is read again', () async {
    var configReads = 0;
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        translationRepositoryProvider.overrideWithValue(repository),
        translationConfigProvider.overrideWith((ref) async {
          configReads++;
          return const TranslationConfig(enabled: true, targetLangs: ['fr']);
        }),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(translationConfigProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(translationConfigProvider.future);
    repository.answer = (_) => throw DioException(
          requestOptions: RequestOptions(path: '/translations'),
          response: Response(
            requestOptions: RequestOptions(path: '/translations'),
            statusCode: 404,
          ),
        );

    await notifier().translate([_stop]);
    await container.read(translationConfigProvider.future);

    expect(state().problem, TranslationProblem.unavailable);
    expect(configReads, 2);
  });

  test('Given the request fails outright, Then it reads as failed', () async {
    repository.answer = (_) => throw DioException.connectionError(
          requestOptions: RequestOptions(path: '/translations'),
          reason: 'offline',
        );

    await notifier().translate([_stop]);

    expect(state().phase, TranslationPhase.failed);
    expect(state().problem, TranslationProblem.failed);
  });

  test('Given a request in flight, When tapped again, Then nothing is sent twice',
      () async {
    final gate = Completer<void>();
    repository.answer = (items) async {
      await gate.future;
      return _every(TranslationStatus.translated)(items);
    };

    final first = notifier().translate([_stop]);
    expect(state().phase, TranslationPhase.loading);
    await notifier().translate([_stop]);
    gate.complete();
    await first;

    expect(repository.calls, hasLength(1));
  });

  test(
      'Given more trip-wide notes than one request may name, '
      'Then they go out in several requests', () async {
    final members = [
      for (var i = 0; i < 120; i++)
        TranslationMember(
          contentType: 'itinerary_annotation',
          contentId: 'n$i',
          fields: {'content': 'note $i'},
        ),
    ];

    await notifier().translate(members);

    expect(repository.calls.map((c) => c.length),
        [kMaxTranslationItemsPerRequest, kMaxTranslationItemsPerRequest, 20]);
    expect(state().textFor('itinerary_annotation', 'n119', 'content', 'note 119'),
        'fr:n119:content');
  });

  test(
      'Given a translation on screen, When another account signs in, '
      'Then it is gone', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    await notifier().translate([_stop]);
    expect(state().phase, TranslationPhase.shown);

    container.read(authNotifierProvider.notifier).setAuthenticated('user-2');

    expect(state().phase, TranslationPhase.idle);
    expect(state().results, isEmpty);
  });
}
