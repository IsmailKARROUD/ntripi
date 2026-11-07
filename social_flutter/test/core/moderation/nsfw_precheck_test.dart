// The client NSFW pre-check's one decision, shared by the phones (TFLite) and
// the web (NSFWJS): the same scores refuse the same picture on both, and a
// model that cannot answer in time never holds the picker.
//
// Regression (2026-11-07): the web model never loaded, so the web let every
// picture through to the crop editor while Android refused it on the spot —
// and the two platforms decided with different thresholds besides.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/moderation/nsfw_precheck.dart';

Future<NsfwScores?> _answer({
  double porn = 0,
  double hentai = 0,
  double sexy = 0,
}) =>
    Future.value((porn: porn, hentai: hentai, sexy: sexy));

void main() {
  group('the decision', () {
    test('porn or hentai above the threshold refuses', () async {
      expect(await nsfwVerdict(_answer(porn: 0.61)), isTrue);
      expect(await nsfwVerdict(_answer(hentai: 0.61)), isTrue);
    });

    test('porn or hentai at the threshold allows', () async {
      expect(await nsfwVerdict(_answer(porn: kNsfwThreshold)), isFalse);
      expect(await nsfwVerdict(_answer(hentai: kNsfwThreshold)), isFalse);
    });

    test('sexy refuses only above near-certainty', () async {
      expect(await nsfwVerdict(_answer(sexy: 0.99)), isFalse,
          reason: 'the line for sexy is 0.999, not the 0.6 of the others');
      expect(await nsfwVerdict(_answer(sexy: 0.9995)), isTrue);
    });

    test('a neutral picture allows', () async {
      expect(await nsfwVerdict(_answer(porn: 0.002, hentai: 0.07, sexy: 0.01)),
          isFalse);
    });

    test('no answer allows — the model is missing or could not read it',
        () async {
      expect(await nsfwVerdict(Future.value(null)), isFalse);
    });

    test('a scoring that fails allows', () async {
      expect(
          await nsfwVerdict(Future<NsfwScores?>.error(StateError('no model'))),
          isFalse);
    });
  });

  group('the time budget', () {
    testWidgets('a model that never answers allows once the budget is spent',
        (tester) async {
      bool? verdict;
      nsfwVerdict(Completer<NsfwScores?>().future).then((v) => verdict = v);

      await tester.pump(kNsfwPrecheckBudget - const Duration(milliseconds: 1));
      expect(verdict, isNull, reason: 'still waiting inside the budget');

      await tester.pump(const Duration(milliseconds: 1));
      expect(verdict, isFalse,
          reason: 'the picker must not wait on a model still loading');
    });

    testWidgets('an answer inside the budget decides', (tester) async {
      final scoring = Completer<NsfwScores?>();
      bool? verdict;
      nsfwVerdict(scoring.future).then((v) => verdict = v);

      await tester.pump(kNsfwPrecheckBudget - const Duration(seconds: 1));
      scoring.complete((porn: 0.95, hentai: 0.0, sexy: 0.0));
      await tester.pump();

      expect(verdict, isTrue);
    });

    testWidgets('an answer after the budget is too late to refuse',
        (tester) async {
      final scoring = Completer<NsfwScores?>();
      bool? verdict;
      nsfwVerdict(scoring.future).then((v) => verdict = v);

      await tester.pump(kNsfwPrecheckBudget);
      scoring.complete((porn: 0.95, hentai: 0.0, sexy: 0.0));
      await tester.pump();

      expect(verdict, isFalse,
          reason: 'the picture already went on to the crop editor');
    });
  });
}
