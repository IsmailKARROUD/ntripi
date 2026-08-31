// test/widgets/rate_itinerary_haptics_test.dart — the rating glyphs buzz.
//
// The cue is wired at the single tap site inside _RatingSliderRow rather than
// at the six onChanged closures that call it, which is what makes it true of
// every dimension at once: Overall, the four star rows, and the Crowdedness
// person glyphs. Asserting it per-row here is the check that the wiring stayed
// in that one place — six near-identical rows are exactly the shape that
// invites a seventh with the cue quietly missing.
//
// Clearing a score by re-tapping the glyph already showing it is the same
// physical gesture, so it buzzes too.
//
// The scale is the other half of the wiring: the buzz is 20 ms per star, so a
// row that fires the cue without passing its star still buzzes and still feels
// wrong. It is scaled by the glyph pressed rather than by the score that
// results, so clearing a score stays as tactile as setting one.
//
// What a scale of N *becomes* — 20 ms of buzz apiece, and what it degrades to
// where a device cannot hold one — belongs to the service, and is asserted in
// test/services/haptics_service_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/services/haptics_service.dart';
import 'package:social_flutter/features/itineraries/domain/my_rating.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/rate_itinerary_dialog.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

const _itineraryId = 'itin-1';

class _RecordingHaptics implements HapticsService {
  final fired = <Haptic>[];

  /// The star each cue was scaled by, in order.
  final scales = <int>[];

  @override
  void fire(Haptic haptic, {int scale = 1}) {
    fired.add(haptic);
    scales.add(scale);
  }

  void clear() {
    fired.clear();
    scales.clear();
  }
}

class _FakeMyRating extends MyRatingNotifier {
  _FakeMyRating(super.arg, this._current);
  final MyRating? _current;
  @override
  Future<MyRating?> build() async => _current;
}

/// Opens the sheet and returns the recorder behind it.
Future<_RecordingHaptics> _pumpSheet(
  WidgetTester tester, {
  MyRating? current,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  FlutterSecureStorage.setMockInitialValues({});
  final haptics = _RecordingHaptics();

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        hapticsServiceProvider.overrideWith((_) => haptics),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        myRatingProvider(_itineraryId)
            .overrideWith(() => _FakeMyRating(_itineraryId, current)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Center(
              child: ElevatedButton(
                onPressed: () => showRateItineraryDialog(
                  context,
                  ref,
                  itineraryId: _itineraryId,
                  current: current,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return haptics;
}

/// The [index]-th rating glyph of the row carrying [label].
///
/// Scoped through the row's own Column rather than by a flat glyph index:
/// scoring a row swaps its outline glyphs for filled ones, so any index into
/// the whole sheet means something different after every tap.
///
/// The size is part of the match, not noise. Each row also carries a leading
/// label icon in the same Column, and Overall's is `Icons.star_rounded` — the
/// very glyph its stars use — so matching on the icon alone counts the label as
/// a sixth star and every index below it lands one glyph short.
Finder _glyph(String label, IconData icon, int index) => find
    .descendant(
      of: find
          .ancestor(of: find.textContaining(label), matching: find.byType(Column))
          .first,
      matching: find.byWidgetPredicate(
        (w) => w is Icon && w.icon == icon && w.size == 26,
      ),
    )
    .at(index);

Future<void> _tapGlyph(WidgetTester tester, Finder glyph) async {
  await tester.ensureVisible(glyph);
  await tester.pumpAndSettle();
  await tester.tap(glyph);
  await tester.pumpAndSettle();
}

void main() {
  group('rating glyph haptics', () {
    testWidgets(
        'Given the sheet just opened, When an Overall star is tapped, '
        'Then the rating cue fires', (tester) async {
      final haptics = await _pumpSheet(tester);

      await _tapGlyph(tester, _glyph('Overall', Icons.star_outline_rounded, 3));

      expect(haptics.fired, [Haptic.rating]);
      expect(haptics.scales, [4]); // the fourth glyph, so four stars' worth
    });

    testWidgets(
        'Given the sheet just opened, When each Overall star is tapped in turn, '
        'Then the cue is scaled by the star pressed', (tester) async {
      final haptics = await _pumpSheet(tester);

      for (var star = 1; star <= 5; star++) {
        // Scoring N leaves N filled and 5-N outline, so the next outline glyph
        // is always the first one — index 0 walks the row upwards.
        await _tapGlyph(tester, _glyph('Overall', Icons.star_outline_rounded, 0));
      }

      expect(haptics.scales, [1, 2, 3, 4, 5]);
    });

    testWidgets(
        'Given Overall is scored, When a star in each revealed dimension is '
        'tapped, Then every row buzzes', (tester) async {
      final haptics = await _pumpSheet(tester);

      // Score Overall first — the four dimension rows only mount after that.
      await _tapGlyph(tester, _glyph('Overall', Icons.star_outline_rounded, 4));
      haptics.clear();

      for (final label in const [
        'Safety',
        'Experience',
        'Accessibility',
        'Family-friendly',
      ]) {
        await _tapGlyph(tester, _glyph(label, Icons.star_outline_rounded, 0));
      }

      expect(haptics.fired, List.filled(4, Haptic.rating));
      // Every row was tapped on its first glyph, so every row scaled by one.
      expect(haptics.scales, List.filled(4, 1));
    });

    testWidgets(
        'Given Overall is scored, When a Crowdedness person glyph is tapped, '
        'Then it buzzes like a star — the cue is not glyph-specific',
        (tester) async {
      final haptics = await _pumpSheet(tester);

      await _tapGlyph(tester, _glyph('Overall', Icons.star_outline_rounded, 4));
      haptics.clear();

      await _tapGlyph(tester, _glyph('Uncrowded', Icons.person_outline, 0));

      expect(haptics.fired, [Haptic.rating]);
      expect(haptics.scales, [1]);
    });

    testWidgets(
        'Given a score is already set, When its own glyph is re-tapped to '
        'clear it, Then it buzzes — clearing is the same gesture',
        (tester) async {
      final haptics = await _pumpSheet(
        tester,
        current: const MyRating(stars: 3),
      );

      // The third filled star is the one carrying the current score.
      await _tapGlyph(tester, _glyph('Overall', Icons.star_rounded, 2));

      expect(haptics.fired, [Haptic.rating]);
      // Three, from the glyph pressed — the resulting score is none, and
      // scaling by that would have made this the one silent tap in the sheet.
      expect(haptics.scales, [3]);
      // And it really did clear, so the cue is not standing in for a no-op.
      expect(find.text('3/5'), findsNothing);
    });
  });
}
