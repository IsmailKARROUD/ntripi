// test/features/reports/report_content_sheet_test.dart
//
// Regression test for a silent failure: the sheet caught the DioException and
// called showSnackBar, but it deliberately stays open on failure, so the root
// messenger rendered the snackbar behind the modal barrier where nobody could
// see it. The user saw the loader appear, disappear, and nothing else.
//
// The failure is now reported inline, and the chosen reason and typed notes
// survive it so Submit retries — which is what these tests pin down.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/reports/data/report_repository.dart';
import 'package:social_flutter/features/reports/domain/report_target.dart';
import 'package:social_flutter/features/reports/presentation/report_content_sheet.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

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

  @override
  Future<void> report({
    required ReportTarget target,
    required String reason,
    String? notes,
  }) async {}
}

Widget _harness(ReportRepository repo) {
  return ProviderScope(
    overrides: [reportRepositoryProvider.overrideWithValue(repo)],
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
