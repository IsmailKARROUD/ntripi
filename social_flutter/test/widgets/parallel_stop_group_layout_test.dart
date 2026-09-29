// test/widgets/parallel_stop_group_layout_test.dart
//
// Each parallel page used to be wrapped in IntrinsicHeight. Read-mode notes
// measure themselves with a LayoutBuilder, which throws on intrinsic queries,
// so any track with parallel stops and notes collapsed to 0 px in view mode
// and re-threw on every relayout — the app froze while scrolling past it.

import 'package:expandable_page_view/expandable_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/parallel_stop_group.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/stop_card.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

Stop _stop(int i, {String? notes}) => Stop(
      id: 's$i',
      itineraryId: 'itin',
      trackId: 't1',
      rank: 'a$i',
      placeName: 'Stop $i',
      placeAddress: '12 rue de la Paix, Paris',
      cost: 12,
      notes: notes,
      type: StopType.waypoint,
      createdAt: DateTime.utc(2026, 5, 11),
      annotations: [
        Annotation(
          id: 'a$i',
          stopId: 's$i',
          type: AnnotationType.advice,
          content: 'go early',
          createdAt: DateTime.utc(2026, 5, 11),
          updatedAt: DateTime.utc(2026, 5, 11),
        ),
      ],
    );

Widget _host(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: buildNtripiTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          // The detail screen's list is a CustomScrollView too.
          body: CustomScrollView(slivers: [
            SliverList(delegate: SliverChildListDelegate([child])),
          ]),
        ),
      ),
    );

Widget _group(List<Stop> stops, {required bool editMode, List<int>? pages}) =>
    _host(ParallelStopGroup(
      stops: stops,
      currency: 'EUR',
      itineraryId: 'itin',
      editMode: editMode,
      trackIndex: 1,
      getSegment: (_) => null,
      onEditStop: (_) {},
      onAddAnnotation: (_) {},
      onAddParallel: (_) {},
      onPageChanged: pages?.add,
    ));

final _longNote = 'A long note about this place. ' * 20;

void main() {
  testWidgets(
      'Given parallel stops with notes in view mode, When the group lays out, '
      'Then it sizes to the card and does not throw', (tester) async {
    await tester.pumpWidget(_group(
      [_stop(0, notes: 'Short note'), _stop(1, notes: _longNote)],
      editMode: false,
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final pageHeight = tester.getSize(find.byType(ExpandablePageView)).height;
    expect(pageHeight, greaterThan(0));

    // Same height as the card rendered on its own — the extra height that
    // IntrinsicHeight was originally added to remove must not come back.
    await tester.pumpWidget(_host(StopCard(
      stop: _stop(0, notes: 'Short note'),
      currency: 'EUR',
      trackIndex: 1,
    )));
    await tester.pumpAndSettle();
    expect(pageHeight, tester.getSize(find.byType(StopCard)).height);
  });

  testWidgets(
      'Given parallel stops with notes in view mode, When the user swipes and '
      'expands a long note, Then the page changes and the group grows',
      (tester) async {
    final pages = <int>[];
    await tester.pumpWidget(_group(
      [_stop(0, notes: 'Short note'), _stop(1, notes: _longNote)],
      editMode: false,
      pages: pages,
    ));
    await tester.pumpAndSettle();

    await tester.fling(
        find.byType(ExpandablePageView), const Offset(-600, 0), 2000);
    await tester.pumpAndSettle();
    expect(pages.last, 1);

    final collapsed = tester.getSize(find.byType(ExpandablePageView)).height;
    await tester.tap(find.text('... view more'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ExpandablePageView)).height,
        greaterThan(collapsed));
  });

  testWidgets(
      'Given parallel stops with notes in edit mode, When the group lays out, '
      'Then it does not throw', (tester) async {
    await tester.pumpWidget(_group(
      [_stop(0, notes: 'Short note'), _stop(1, notes: _longNote)],
      editMode: true,
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ExpandablePageView)).height,
        greaterThan(0));
  });
}
