// test/widgets/rate_itinerary_sheet_test.dart
//
// The rate sheet's buttons are pinned below its body (SheetActionBar). Rating
// Overall reveals five more rows, which on a short phone carries the body past
// the sheet's cap, and the review brings up the keyboard: as the body's last
// child, Save sat below the fold in the first case and under the keyboard in
// the second.
//
// A failed save or removal is reported in the bar, above the buttons, with
// every score intact so the action retries. The haptics of the rating glyphs
// are rate_itinerary_haptics_test.dart's.
//
// The server is faked at the repository, so the sheet's buttons go through the
// real MyRatingNotifier, as they do in the app.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/services/haptics_service.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/domain/my_rating.dart';
import 'package:ntripi/features/itineraries/domain/ratings_page.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/rate_itinerary_dialog.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/editorial_widgets.dart';

const _itineraryId = 'itin-1';

/// Answers the rating endpoints as the server does, recording what it was sent.
class _RatingServer extends ItineraryRepository {
  _RatingServer(this.current) : super(Dio());

  final MyRating? current;
  final submitted = <MyRating>[];
  int deletes = 0;
  Exception? failWith;

  @override
  Future<MyRating?> getMyRating(String itineraryId) async => current;

  @override
  Future<({MyRating rating, RatingAggregate aggregate, RatingsPage? page})>
      submitRating(
    String itineraryId,
    MyRating rating, {
    bool withRatingsPage = false,
  }) async {
    submitted.add(rating);
    final failure = failWith;
    if (failure != null) throw failure;
    return (
      rating: rating,
      aggregate: RatingAggregate(avg: rating.stars.toDouble(), count: 1),
      page: null,
    );
  }

  @override
  Future<({RatingAggregate aggregate, RatingsPage? page})> deleteMyRating(
    String itineraryId, {
    bool withRatingsPage = false,
  }) async {
    deletes++;
    final failure = failWith;
    if (failure != null) throw failure;
    return (aggregate: const RatingAggregate(avg: null, count: 0), page: null);
  }
}

class _SilentHaptics implements HapticsService {
  @override
  void fire(Haptic haptic, {int scale = 1}) {}
}

DioException _serverError() {
  final request = RequestOptions(path: '/itineraries/$_itineraryId/ratings');
  return DioException(
    requestOptions: request,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: request,
      statusCode: 500,
      data: const {'detail': 'Internal Server Error'},
    ),
  );
}

void main() {
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  /// Opens the sheet and returns the server behind it.
  Future<_RatingServer> openSheet(
    WidgetTester tester, {
    MyRating? current,
    Size size = const Size(1080, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    FlutterSecureStorage.setMockInitialValues({});
    final server = _RatingServer(current);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          hapticsServiceProvider.overrideWith((_) => _SilentHaptics()),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
          itineraryRepositoryProvider.overrideWithValue(server),
        ],
        child: MaterialApp(
          theme: buildNtripiTheme(),
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
    return server;
  }

  /// Gives Overall [stars] — on an unrated sheet its glyphs are the only ones.
  Future<void> rateOverall(WidgetTester tester, int stars) async {
    await tester.tap(find
        .byWidgetPredicate((w) =>
            w is Icon && w.icon == Icons.star_outline_rounded && w.size == 26)
        .at(stars - 1));
    await tester.pumpAndSettle();
  }

  Finder save() => find.widgetWithText(FilledButton, en.saveButton);
  Finder inBar(Finder finder) =>
      find.descendant(of: find.byType(SheetActionBar), matching: finder);

  group('on a short phone', () {
    // 667 tall, the height that matters here; 430 wide because the test font's
    // square glyphs need it for the section label and the review's toolbar.
    const shortPhone = Size(430, 667);

    testWidgets(
        'Given Overall rated, When the five more rows appear, Then Save is '
        'still on screen', (tester) async {
      await openSheet(tester, size: shortPhone);

      await rateOverall(tester, 4);

      // The premise: the body now runs past the sheet's cap.
      expect(find.text(en.crowdednessLabel).hitTestable(), findsNothing);
      expect(save().hitTestable(), findsOneWidget);
      expect(tester.widget<FilledButton>(save()).onPressed, isNotNull);
    });

    testWidgets(
        'Given Overall rated, When the review is typed with the keyboard up, '
        'Then Save stays on screen above the keyboard', (tester) async {
      await openSheet(tester, size: shortPhone);
      await rateOverall(tester, 4);

      await tester.showKeyboard(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();

      expect(save().hitTestable(), findsOneWidget);
      expect(tester.getRect(save()).bottom, lessThanOrEqualTo(667 - 260));
    });
  });

  group('Save', () {
    testWidgets(
        'Given the sheet just opened, When nothing is rated, Then Save is '
        'disabled', (tester) async {
      await openSheet(tester);

      expect(tester.widget<FilledButton>(save()).onPressed, isNull);
    });

    testWidgets(
        'Given Overall and a review, When Save is tapped, Then the rating is '
        'sent and the sheet closes', (tester) async {
      final server = await openSheet(tester);
      await rateOverall(tester, 5);
      await tester.enterText(find.byType(TextField), '  Worth the climb  ');

      await tester.tap(save());
      await tester.pumpAndSettle();

      expect(server.submitted.single.stars, 5);
      expect(server.submitted.single.note, 'Worth the climb');
      expect(find.byType(SheetActionBar), findsNothing);
    });

    testWidgets(
        'Given the save fails, When Save is tapped, Then the error shows in '
        'the pinned bar and the score survives for a retry', (tester) async {
      final server = await openSheet(tester);
      server.failWith = _serverError();
      await rateOverall(tester, 4);

      await tester.tap(save());
      await tester.pumpAndSettle();

      expect(server.submitted, hasLength(1));
      expect(inBar(find.text('Internal Server Error')), findsOneWidget);
      expect(find.text('4/5'), findsOneWidget);
      expect(tester.widget<FilledButton>(save()).onPressed, isNotNull);
    });
  });

  group('Cancel', () {
    testWidgets(
        'Given a score, When Cancel is tapped, Then the sheet closes and '
        'nothing is sent', (tester) async {
      final server = await openSheet(tester);
      await rateOverall(tester, 2);

      await tester.tap(find.widgetWithText(OutlinedButton, en.cancel));
      await tester.pumpAndSettle();

      expect(server.submitted, isEmpty);
      expect(find.byType(SheetActionBar), findsNothing);
    });
  });

  group('Remove my rating', () {
    testWidgets(
        'Given no rating yet, When the sheet opens, Then the bar offers no '
        'remove button', (tester) async {
      await openSheet(tester);

      expect(find.byTooltip(en.removeMyRatingTooltip), findsNothing);
    });

    testWidgets(
        'Given my rating, When removing it is confirmed, Then it is removed '
        'and the sheet closes', (tester) async {
      final server = await openSheet(tester, current: const MyRating(stars: 3));
      expect(inBar(find.byTooltip(en.removeMyRatingTooltip)), findsOneWidget);

      await tester.tap(find.byTooltip(en.removeMyRatingTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.removeButton));
      await tester.pumpAndSettle();

      expect(server.deletes, 1);
      expect(find.byType(SheetActionBar), findsNothing);
    });

    testWidgets(
        'Given removing my rating fails, When it is confirmed, Then the error '
        'shows in the pinned bar and the sheet stays open', (tester) async {
      final server = await openSheet(tester, current: const MyRating(stars: 3));
      server.failWith = _serverError();

      await tester.tap(find.byTooltip(en.removeMyRatingTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.removeButton));
      await tester.pumpAndSettle();

      expect(server.deletes, 1);
      expect(inBar(find.text('Internal Server Error')), findsOneWidget);
      expect(find.text('3/5'), findsOneWidget);
    });
  });
}
