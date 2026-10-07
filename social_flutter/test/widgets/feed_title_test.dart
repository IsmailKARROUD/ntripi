// test/widgets/feed_title_test.dart
//
// The feed's title rule. A title written in a language the reader lists as
// spoken shows as written, one tap from its translation; any other title shows
// translated and marked, one tap from the original. Neither tap is a request —
// the translation arrived with the feed page.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/providers/locale_provider.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/feed/domain/feed_item.dart';
import 'package:social_flutter/features/feed/presentation/widgets/feed_card.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';

class _FixedLocale extends LocaleNotifier {
  _FixedLocale(this.code);
  final String code;

  @override
  Locale build() => Locale(code);
}

class _FakeMyProfile extends MyProfileNotifier {
  _FakeMyProfile(this._languages);
  final List<String> _languages;

  @override
  Future<User> build() async => User(
        id: 'reader-1',
        username: 'reader',
        isPrivate: false,
        followersCount: 0,
        followingCount: 0,
        createdAt: DateTime(2026),
        languages: _languages,
      );
}

const _original = 'Three days in Lisbon';
const _translated = 'Trois jours à Lisbonne';

FeedItem _item({String translationLang = 'fr'}) => FeedItem.fromJson({
      'id': 'itin-1',
      'user_id': 'owner-1',
      'title': _original,
      'cover_image_url': null,
      'total_duration_min': 120,
      'total_cost': 0.0,
      'currency': 'EUR',
      'visibility': 'public',
      'created_at': '2026-10-07T10:00:00Z',
      'updated_at': '2026-10-07T10:00:00Z',
      'rating_avg': null,
      'rating_count': 0,
      'stops_count': 3,
      'owner': {'user_id': 'owner-1', 'username': 'amina'},
      'source_lang': 'en',
      'title_translation': {'lang': translationLang, 'text': _translated},
    });

Widget _harness({
  required List<String> spoken,
  String readerLang = 'fr',
  required Widget child,
}) {
  FlutterSecureStorage.setMockInitialValues({});
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      localeProvider.overrideWith(() => _FixedLocale(readerLang)),
      myProfileProvider.overrideWith(() => _FakeMyProfile(spoken)),
    ],
    child: MaterialApp(
      theme: buildNtripiTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  testWidgets(
      'Given a title in a language the reader does not speak, '
      'Then it shows translated and marked, and one tap shows the original',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_harness(
      spoken: const ['ES'],
      child: FeedCard(item: _item()),
    ));
    await tester.pumpAndSettle();

    expect(find.text(_translated), findsOneWidget);
    expect(find.text(_original), findsNothing);
    // Its own node, so a screen reader can find and flip it.
    expect(find.bySemanticsLabel(RegExp('^Translated title')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.translate_rounded));
    await tester.pumpAndSettle();

    expect(find.text(_original), findsOneWidget);
    expect(find.text(_translated), findsNothing);
    semantics.dispose();
  });

  testWidgets(
      'Given a title in a language the reader lists as spoken, '
      'Then it shows as written, and one tap shows the translation',
      (tester) async {
    await tester.pumpWidget(_harness(
      // Profile codes are upper case; the detected language is lower case.
      spoken: const ['EN', 'ES'],
      child: FeedCard(item: _item()),
    ));
    await tester.pumpAndSettle();

    expect(find.text(_original), findsOneWidget);
    expect(find.text(_translated), findsNothing);

    await tester.tap(find.byIcon(Icons.translate_rounded));
    await tester.pumpAndSettle();

    expect(find.text(_translated), findsOneWidget);
  });

  testWidgets(
      'Given a page fetched before the reader switched language, '
      'Then its titles are not offered as theirs', (tester) async {
    await tester.pumpWidget(_harness(
      spoken: const [],
      readerLang: 'de',
      child: FeedCard(item: _item(translationLang: 'fr')),
    ));
    await tester.pumpAndSettle();

    expect(find.text(_original), findsOneWidget);
    expect(find.byIcon(Icons.translate_rounded), findsNothing);
  });

  testWidgets('Given no cached translation, Then the card is unchanged',
      (tester) async {
    final item = FeedItem.fromJson(_itemJsonWithout());
    await tester.pumpWidget(_harness(
      spoken: const [],
      child: FeedCard(item: item),
    ));
    await tester.pumpAndSettle();

    expect(find.text(_original), findsOneWidget);
    expect(find.byType(FeedTitle), findsNothing);
  });
}

Map<String, dynamic> _itemJsonWithout() => {
      'id': 'itin-2',
      'user_id': 'owner-1',
      'title': _original,
      'cover_image_url': null,
      'total_duration_min': 0,
      'total_cost': 0.0,
      'currency': 'EUR',
      'visibility': 'public',
      'created_at': '2026-10-07T10:00:00Z',
      'updated_at': '2026-10-07T10:00:00Z',
      'rating_avg': null,
      'rating_count': 0,
      'stops_count': 0,
      'owner': {'user_id': 'owner-1', 'username': 'amina'},
      'source_lang': 'en',
      'title_translation': null,
    };
