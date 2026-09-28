// test/widgets/parallel_stop_group_clamp_test.dart
//
// The group's State survives rebuilds — the detail screen keys each one with a
// per-track GlobalKey — so deleting (or moving out) the parallel stop on screen
// left the page index past the end of the new list, and build threw a
// RangeError at `widget.stops[_currentPage]`.

import 'package:expandable_page_view/expandable_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/parallel_stop_group.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

Stop _stop(int i) => Stop(
      id: 's$i',
      itineraryId: 'itin',
      trackId: 't1',
      rank: 'a$i',
      placeName: 'Stop $i',
      placeAddress: null,
      lat: null,
      lng: null,
      placeType: null,
      durationMin: null,
      cost: 0.0,
      isFree: true,
      notes: null,
      type: StopType.waypoint,
      createdAt: DateTime.utc(2026, 5, 11),
      annotations: const [],
    );

void main() {
  testWidgets(
      'Given the last parallel is on screen, When it is removed, '
      'Then the group falls back to the new last page instead of throwing',
      (tester) async {
    final key = GlobalKey();
    final pages = <int>[];

    Widget group(List<Stop> stops) => ProviderScope(
          child: MaterialApp(
            theme: buildNtripiTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ParallelStopGroup(
                  key: key,
                  stops: stops,
                  currency: 'EUR',
                  itineraryId: 'itin',
                  editMode: false,
                  trackIndex: 0,
                  getSegment: (_) => null,
                  onPageChanged: pages.add,
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(group([_stop(0), _stop(1), _stop(2)]));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.fling(find.byType(ExpandablePageView), const Offset(-600, 0), 2000);
      await tester.pumpAndSettle();
    }
    expect(pages.last, 2);

    await tester.pumpWidget(group([_stop(0), _stop(1)]));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(pages.last, 1);
    expect(find.text('Stop 1'), findsWidgets);
  });
}
