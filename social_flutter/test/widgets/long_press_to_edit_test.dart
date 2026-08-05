// test/widgets/long_press_to_edit_test.dart — The owner's long-press-to-edit
// shortcut: fires when online, explains itself when offline, and is completely
// inert when null so a viewer's own long-press (report) still reaches the child.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/stop.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/annotation_chip.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/long_press_to_edit.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/stop_card.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

Widget _wrap(Widget child, {required bool online}) => ProviderScope(
      overrides: [
        isOnlineProvider.overrideWith((ref) => Stream.value(online)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    );

Annotation _annotation() => Annotation(
      id: 'anno-1',
      stopId: 'stop-1',
      type: AnnotationType.advice,
      content: 'Bring cash',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('LongPressToEdit', () {
    testWidgets('Given online owner, When long-pressed, Then edit fires',
        (tester) async {
      var edits = 0;
      await tester.pumpWidget(_wrap(
        LongPressToEdit(
          onEdit: () => edits++,
          child: const SizedBox(width: 100, height: 100),
        ),
        online: true,
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.byType(SizedBox).first);
      await tester.pumpAndSettle();

      expect(edits, 1);
    });

    testWidgets(
        'Given offline owner, When long-pressed, Then offline hint shows and edit does not fire',
        (tester) async {
      var edits = 0;
      await tester.pumpWidget(_wrap(
        LongPressToEdit(
          onEdit: () => edits++,
          child: const SizedBox(width: 100, height: 100),
        ),
        online: false,
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.byType(SizedBox).first);
      await tester.pumpAndSettle();

      expect(edits, 0);
      expect(find.text("You're offline"), findsOneWidget);
    });

    testWidgets(
        'Given null onEdit, When built, Then no detector is inserted at all',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const LongPressToEdit(
          onEdit: null,
          child: SizedBox(width: 100, height: 100),
        ),
        online: true,
      ));
      await tester.pumpAndSettle();

      // The wrapper must be transparent so a viewer's report long-press —
      // defined by the child — is not shadowed.
      expect(
        find.descendant(
          of: find.byType(LongPressToEdit),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });
  });

  group('AnnotationChip long-press is role-disjoint', () {
    testWidgets('Given a viewer, When long-pressed, Then report fires',
        (tester) async {
      var reports = 0;
      var edits = 0;
      await tester.pumpWidget(_wrap(
        AnnotationChip(
          annotation: _annotation(),
          onReport: () => reports++,
          onLongPressEdit: null, // viewers never get the edit shortcut
        ),
        online: true,
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Bring cash'));
      await tester.pumpAndSettle();

      expect(reports, 1);
      expect(edits, 0);
    });

    testWidgets('Given the author, When long-pressed, Then edit fires',
        (tester) async {
      var edits = 0;
      await tester.pumpWidget(_wrap(
        AnnotationChip(
          annotation: _annotation(),
          onReport: null, // authors never report themselves
          onLongPressEdit: () => edits++,
        ),
        online: true,
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Bring cash'));
      await tester.pumpAndSettle();

      expect(edits, 1);
    });
  });

  group('StopCard', () {
    Stop stop() => Stop(
          id: 'stop-1',
          itineraryId: 'itin-1',
          trackId: 'track-1',
          rank: 'a0',
          type: StopType.origin,
          placeName: 'Eiffel Tower',
          createdAt: DateTime.utc(2026, 1, 1),
        );

    testWidgets(
        'Given read mode with the shortcut wired, When long-pressed, Then it fires and tap still views',
        (tester) async {
      var edits = 0;
      var views = 0;
      await tester.pumpWidget(_wrap(
        StopCard(
          stop: stop(),
          currency: 'EUR',
          trackIndex: 1,
          onTap: () => views++,
          onLongPressEdit: () => edits++,
        ),
        online: true,
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Eiffel Tower'));
      await tester.pumpAndSettle();
      expect(edits, 1);

      // The long-press wrapper must not have stolen the ordinary tap.
      await tester.tap(find.text('Eiffel Tower'));
      await tester.pumpAndSettle();
      expect(views, 1);
    });

    testWidgets(
        'Given a viewer (no shortcut), When long-pressed, Then the card behaves as before',
        (tester) async {
      var views = 0;
      await tester.pumpWidget(_wrap(
        StopCard(
          stop: stop(),
          currency: 'EUR',
          trackIndex: 1,
          onTap: () => views++,
          onLongPressEdit: null,
        ),
        online: true,
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Eiffel Tower'));
      await tester.pumpAndSettle();

      // Unchanged pre-existing behavior: with no long-press recognizer to
      // compete, the root InkWell claims the gesture as a tap and opens the
      // stop. The shortcut adds nothing for viewers, it just doesn't break them.
      expect(views, 1);
    });
  });
}
