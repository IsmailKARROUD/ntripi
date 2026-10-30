// test/features/reports/report_content_sheet_test.dart
//
// Regression test for a silent failure: the sheet caught the DioException and
// called showSnackBar, but it deliberately stays open on failure, so the root
// messenger rendered the snackbar behind the modal barrier where nobody could
// see it. The user saw the loader appear, disappear, and nothing else.
//
// The failure is now reported inline, and the chosen reason and typed notes
// survive it so Submit retries — which is what these tests pin down. Submit
// itself stays on screen while a note is typed: it is pinned below the body,
// where as its last child it sat under the keyboard. The failure message rides
// in that pinned bar, above the buttons.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/features/reports/data/report_repository.dart';
import 'package:ntripi/features/reports/domain/report_target.dart';
import 'package:ntripi/features/reports/presentation/report_content_sheet.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/editorial_widgets.dart';

/// Fails every report the way the backend did — a 500 carrying FastAPI's
/// generic detail body.
class _FailingRepo extends ReportRepository {
  _FailingRepo() : super(Dio());

  int calls = 0;

  @override
  Future<void> report({
    required ReportTarget target,
    required String reason,
    String? notes,
  }) async {
    calls++;
    final request = RequestOptions(path: '/reports');
    throw DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: request,
        statusCode: 500,
        data: const {'detail': 'Internal Server Error'},
      ),
    );
  }
}

class _OkRepo extends ReportRepository {
  _OkRepo() : super(Dio());

  int calls = 0;

  @override
  Future<void> report({
    required ReportTarget target,
    required String reason,
    String? notes,
  }) async {
    calls++;
  }
}

/// Holds the report until the test answers it.
class _HeldRepo extends ReportRepository {
  _HeldRepo() : super(Dio());

  final answer = Completer<void>();

  @override
  Future<void> report({
    required ReportTarget target,
    required String reason,
    String? notes,
  }) =>
      answer.future;
}

Widget _harness(ReportRepository repo, {bool online = true}) {
  return ProviderScope(
    overrides: [
      reportRepositoryProvider.overrideWithValue(repo),
      isOnlineProvider.overrideWith((ref) => Stream.value(online)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => showReportContentSheet(
              context,
              ref,
              const ReportTarget.itinerary('itinerary-1'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

/// Opens the sheet and selects "Violence or threats" — the reason whose
/// hide-threshold of 1 made the backend 500 on the very first report.
Future<void> _openAndPickViolence(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Violence or threats'));
  await tester.pump();
}

void main() {
  setUp(() {
    // The sheet is 70% of screen height; a short default view clips the
    // buttons out of the hit-test area.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets(
      'Given a short phone, When a note is typed with the keyboard up, '
      'Then Submit stays on screen above the keyboard', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(_OkRepo()));
    await _openAndPickViolence(tester);

    await tester.showKeyboard(find.byType(TextField));
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, 'Submit report');
    expect(submit.hitTestable(), findsOneWidget);
    expect(tester.getRect(submit).bottom, lessThanOrEqualTo(667 - 260));
  });

  group('ReportContentSheet buttons', () {
    setUp(() {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(1080, 1920);
      view.devicePixelRatio = 1.0;
    });

    tearDown(() {
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.reset();
    });

    final submit = find.descendant(
        of: find.byType(SheetActionBar), matching: find.byType(FilledButton));
    final cancel = find.widgetWithText(OutlinedButton, 'Cancel');

    testWidgets(
        'Given a reason picked, When Cancel is tapped, Then the sheet closes '
        'without reporting', (tester) async {
      final repo = _OkRepo();
      await tester.pumpWidget(_harness(repo));
      await _openAndPickViolence(tester);

      await tester.tap(cancel);
      await tester.pumpAndSettle();

      expect(repo.calls, 0);
      expect(find.byType(SheetActionBar), findsNothing);
    });

    testWidgets(
        'Given the device is offline, When a reason is picked, Then Submit '
        'stays disabled', (tester) async {
      await tester.pumpWidget(_harness(_OkRepo(), online: false));
      await _openAndPickViolence(tester);
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    });

    testWidgets(
        'Given a report in flight, When it is answered, Then both buttons '
        'waited and the sheet closes', (tester) async {
      final repo = _HeldRepo();
      await tester.pumpWidget(_harness(repo));
      await _openAndPickViolence(tester);

      await tester.tap(submit);
      // Bounded pump: the loader animates for as long as the report is held.
      await tester.pump();

      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(cancel).onPressed, isNull);

      repo.answer.complete();
      await tester.pumpAndSettle();

      expect(find.byType(SheetActionBar), findsNothing);
    });
  });

  group('ReportContentSheet failure handling', () {
    testWidgets(
        'Given the report POST fails with a 500, When the user submits, '
        'Then the sheet stays open and shows the error inline', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FailingRepo();
      await tester.pumpWidget(_harness(repo));
      await _openAndPickViolence(tester);

      await tester.enterText(find.byType(TextField), 'threatened me');
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      expect(repo.calls, 1);
      // The message is visible in the sheet, not stranded in a snackbar behind it.
      expect(find.text('Internal Server Error'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      // In the pinned bar, above Submit — wherever the body is scrolled to.
      expect(
        find.descendant(
          of: find.byType(SheetActionBar),
          matching: find.text('Internal Server Error'),
        ),
        findsOneWidget,
      );
      // Sheet is still up, with the user's input intact so Submit can retry.
      expect(find.text('Submit report'), findsOneWidget);
      expect(find.text('threatened me'), findsOneWidget);
    });

    testWidgets(
        'Given a failed attempt, When the user submits again, '
        'Then the stale error is cleared and the call is retried',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FailingRepo();
      await tester.pumpWidget(_harness(repo));
      await _openAndPickViolence(tester);

      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      expect(find.text('Internal Server Error'), findsOneWidget);

      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      expect(repo.calls, 2);
      expect(find.text('Internal Server Error'), findsOneWidget);
    });

    testWidgets(
        'Given the report succeeds, When the user submits, '
        'Then the sheet closes with no error shown', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_harness(_OkRepo()));
      await _openAndPickViolence(tester);

      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.text('Submit report'), findsNothing); // sheet popped
    });
  });
}
