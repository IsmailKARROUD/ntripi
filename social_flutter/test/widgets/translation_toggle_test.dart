// test/widgets/translation_toggle_test.dart
//
// The toggle and the text it swaps. The toggle must be absent whenever there
// is nothing a tap could do — translation off, a language the server does not
// target, content already in the reader's language — because a button that
// answers "same language" is a button that trains people to ignore it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/translation/data/translation_repository.dart';
import 'package:social_flutter/features/translation/domain/translation.dart';
import 'package:social_flutter/features/translation/presentation/translatable_text.dart';
import 'package:social_flutter/features/translation/providers/translation_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class _FixedLocale extends LocaleNotifier {
  _FixedLocale(this.code);
  final String code;

  @override
  Locale build() => Locale(code);
}

class _FakeRepository implements TranslationRepository {
  /// Completes each request; replaced to hold one open or fail it.
  Future<List<TranslationItemResult>> Function(
      String lang, List<TranslationRequestItem> items) answer = _translated;

  int calls = 0;

  static Future<List<TranslationItemResult>> _translated(
          String lang, List<TranslationRequestItem> items) async =>
      [
        for (final item in items)
          TranslationItemResult(
            contentType: item.contentType,
            contentId: item.contentId,
            found: true,
            fields: {
              for (final field in item.fields)
                field: FieldTranslation(
                  status: TranslationStatus.translated,
                  text: '$lang: translated $field',
                ),
            },
          ),
      ];

  @override
  Future<TranslationConfig> getConfig() async => TranslationConfig.disabled;

  @override
  Future<List<TranslationItemResult>> translate({
    required String targetLang,
    required List<TranslationRequestItem> items,
  }) {
    calls++;
    return answer(targetLang, items);
  }
}

const _anchor = (contentType: 'stop', contentId: 'stop-1');
const _original = 'Arrive early, the queue builds by ten.';

TranslationMember _member({String? sourceLang = 'en'}) => TranslationMember(
      contentType: 'stop',
      contentId: 'stop-1',
      sourceLang: sourceLang,
      fields: const {'notes': _original},
    );

Widget _harness({
  required _FakeRepository repository,
  String readerLang = 'fr',
  TranslationConfig config =
      const TranslationConfig(enabled: true, targetLangs: ['en', 'fr', 'ar']),
  Stream<bool>? online,
  TranslationMember? member,
  bool textEnabled = true,
}) =>
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        localeProvider.overrideWith(() => _FixedLocale(readerLang)),
        translationConfigProvider.overrideWith((ref) async => config),
        translationRepositoryProvider.overrideWithValue(repository),
        isOnlineProvider.overrideWith((ref) => online ?? Stream.value(true)),
      ],
      child: MaterialApp(
        theme: buildNtripiTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TranslationToggle(
                anchor: _anchor,
                members: [member ?? _member()],
              ),
              TranslatableText(
                anchor: _anchor,
                contentType: 'stop',
                contentId: 'stop-1',
                field: 'notes',
                original: _original,
                enabled: textEnabled,
                builder: (context, text) => Text(text),
              ),
            ],
          ),
        ),
      ),
    );

void main() {
  late _FakeRepository repository;

  setUp(() => repository = _FakeRepository());

  group('the toggle is absent when a tap could do nothing', () {
    testWidgets('Given translation is off, Then there is no toggle',
        (tester) async {
      await tester.pumpWidget(_harness(
          repository: repository, config: TranslationConfig.disabled));
      await tester.pumpAndSettle();

      expect(find.text('See translation'), findsNothing);
      expect(find.byIcon(Icons.translate_rounded), findsNothing);
    });

    testWidgets(
        'Given the app language is not a translation target, '
        'Then there is no toggle', (tester) async {
      await tester.pumpWidget(_harness(
        repository: repository,
        config: const TranslationConfig(enabled: true, targetLangs: ['en']),
      ));
      await tester.pumpAndSettle();

      expect(find.text('See translation'), findsNothing);
    });

    testWidgets(
        'Given the content is already in the reader\'s language, '
        'Then there is no toggle', (tester) async {
      await tester.pumpWidget(_harness(
          repository: repository, member: _member(sourceLang: 'fr')));
      await tester.pumpAndSettle();

      expect(find.text('See translation'), findsNothing);
    });
  });

  testWidgets(
      'Given content whose language the server could not tell, '
      'Then the toggle is offered — the server decides', (tester) async {
    await tester.pumpWidget(
        _harness(repository: repository, member: _member(sourceLang: null)));
    await tester.pumpAndSettle();

    expect(find.text('See translation'), findsOneWidget);
  });

  testWidgets(
      'Given a tap, Then it reads "Translating…", then swaps the text and '
      'labels it, and "See original" swaps it back', (tester) async {
    final gate = Completer<void>();
    repository.answer = (lang, items) async {
      await gate.future;
      return _FakeRepository._translated(lang, items);
    };
    await tester.pumpWidget(_harness(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('See translation'));
    await tester.pump();
    expect(find.text('Translating…'), findsOneWidget);
    expect(find.text(_original), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('fr: translated notes'), findsOneWidget);
    expect(find.text(_original), findsNothing);
    expect(
        find.text('Automatically translated · See original',
            findRichText: true),
        findsOneWidget);

    await tester.tap(find.text('Automatically translated · See original',
        findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text(_original), findsOneWidget);
    expect(find.text('See translation'), findsOneWidget);
    expect(repository.calls, 1);
  });

  testWidgets(
      'Given every engine fails, Then the original stays and the reason shows',
      (tester) async {
    repository.answer = (lang, items) async => [
          for (final item in items)
            TranslationItemResult(
              contentType: item.contentType,
              contentId: item.contentId,
              found: true,
              fields: {
                for (final field in item.fields)
                  field: const FieldTranslation(
                      status: TranslationStatus.unavailable),
              },
            ),
        ];
    await tester.pumpWidget(_harness(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('See translation'));
    await tester.pumpAndSettle();

    expect(find.text(_original), findsOneWidget);
    expect(find.text("Translation isn't available right now."), findsOneWidget);
    // Still offered: a failure is never the last word.
    expect(find.text('See translation'), findsOneWidget);
  });

  testWidgets(
      'Given the device is offline, When tapped, '
      'Then it explains instead of sending', (tester) async {
    await tester.pumpWidget(
        _harness(repository: repository, online: Stream.value(false)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('See translation'));
    await tester.pumpAndSettle();

    expect(find.text("You're offline"), findsOneWidget);
    expect(repository.calls, 0);
  });

  testWidgets(
      'Given an Arabic reader, Then the translation is laid out right to left',
      (tester) async {
    await tester.pumpWidget(_harness(repository: repository, readerLang: 'ar'));
    await tester.pumpAndSettle();

    // The harness app runs in English, so the toggle reads in English while
    // the reader's language — the translation target — is Arabic.
    await tester.tap(find.text('See translation'));
    await tester.pumpAndSettle();

    final direction = tester.widget<Directionality>(find
        .ancestor(
          of: find.text('ar: translated notes'),
          matching: find.byType(Directionality),
        )
        .first);
    expect(direction.textDirection, TextDirection.rtl);
  });

  testWidgets(
      'Given the group is translated, When a field is in edit mode, '
      'Then that field keeps its original', (tester) async {
    await tester.pumpWidget(
        _harness(repository: repository, textEnabled: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('See translation'));
    await tester.pumpAndSettle();

    expect(find.text(_original), findsOneWidget);
    expect(find.text('fr: translated notes'), findsNothing);
  });
}
