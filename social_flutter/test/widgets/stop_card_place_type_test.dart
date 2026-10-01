// test/widgets/stop_card_place_type_test.dart — The stop list's number badge
// takes its tint and corner icon from the place type, and an untyped stop keeps
// the plain mist circle it always had.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/stop_card.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

Widget _wrap(Widget child, {ThemeData? theme}) => ProviderScope(
      overrides: [
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: MaterialApp(
        theme: theme ?? buildNtripiTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    );

Stop _stop({PlaceType? placeType}) => Stop(
      id: 'stop-1',
      itineraryId: 'itin-1',
      trackId: 'track-1',
      rank: 'a0',
      type: StopType.origin,
      placeName: 'Café Lyon',
      placeType: placeType,
      createdAt: DateTime.utc(2026, 1, 1),
    );

/// The 32 px circle holding the track number.
BoxDecoration _numberCircle(WidgetTester tester) {
  final container = tester.widget<Container>(find
      .ancestor(of: find.text('3'), matching: find.byType(Container))
      .first);
  return container.decoration! as BoxDecoration;
}

void main() {
  testWidgets(
      'Given a typed stop, When rendered, Then the badge wears the place color and icon',
      (tester) async {
    await tester.pumpWidget(_wrap(
      StopCard(
        stop: _stop(placeType: PlaceType.eatDrink),
        currency: 'EUR',
        trackIndex: 3,
      ),
    ));
    await tester.pumpAndSettle();

    final circle = _numberCircle(tester);
    expect((circle.border! as Border).top.color,
        NtripiColors.light.placeEatDrink);
    expect(find.byIcon(Icons.restaurant), findsOneWidget);

    // The digit stays dark — the place color is too light for 14 px text.
    final digit = tester.widget<Text>(find.text('3'));
    expect(digit.style!.color, NtripiColors.light.bark);
  });

  testWidgets(
      'Given a typed stop, When read by a screen reader, Then the place type is named',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(
      StopCard(
        stop: _stop(placeType: PlaceType.sleep),
        currency: 'EUR',
        trackIndex: 3,
      ),
    ));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(StopCard)))!;
    // The card's InkWell merges the row into one node, read as "3, Sleep, Café Lyon".
    expect(
        find.bySemanticsLabel(
            RegExp(RegExp.escape(PlaceType.sleep.label(l10n)))),
        findsOneWidget);
    handle.dispose();
  });

  testWidgets(
      'Given an untyped stop, When rendered, Then the badge is the plain mist circle',
      (tester) async {
    await tester.pumpWidget(_wrap(
      StopCard(stop: _stop(), currency: 'EUR', trackIndex: 3),
    ));
    await tester.pumpAndSettle();

    final circle = _numberCircle(tester);
    expect(circle.color, NtripiColors.light.mist);
    expect(circle.border, isNull);
    for (final type in PlaceType.values) {
      expect(find.byIcon(type.icon), findsNothing);
    }
  });

  testWidgets(
      'Given dark mode, When a typed stop renders, Then the corner glyph uses the dark surface',
      (tester) async {
    await tester.pumpWidget(_wrap(
      StopCard(
        stop: _stop(placeType: PlaceType.sight),
        currency: 'EUR',
        trackIndex: 3,
      ),
      theme: buildNtripiDarkTheme(),
    ));
    await tester.pumpAndSettle();

    final icon = tester.widget<Icon>(find.byIcon(Icons.photo_camera_outlined));
    expect(icon.color, NtripiColors.dark.surface);
  });
}
