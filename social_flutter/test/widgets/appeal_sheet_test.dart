// test/widgets/appeal_sheet_test.dart
//
// The appeal sheet was extracted out of account_status_screen so the hidden
// banner could open it with a raw target type + id. These tests pin the part
// that extraction could silently break: the sheet must post the target it was
// given, not the one the violations list happens to be showing.
//
// They also cover the failure path, which matters because the sheet stays open
// on error — a snackbar would render behind the modal barrier, so the message
// has to appear inline (same defect already fixed in report_content_sheet).
//
// An appeal answers with the Account status list as it now stands; filed from
// that screen, the list on it is the answer, never a second download.
//
// Appeal is pinned below the body (SheetActionBar); unlike the other sheets,
// the error stays on the field it is about, and the bar carries none.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/features/profile/data/profile_repository.dart';
import 'package:ntripi/features/profile/domain/violation.dart';
import 'package:ntripi/features/profile/presentation/account_status_screen.dart';
import 'package:ntripi/features/profile/providers/profile_provider.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/appeal_sheet.dart';
import 'package:ntripi/shared/widgets/editorial_widgets.dart';

/// One hidden itinerary, before and after its appeal.
Violation _hidden({bool appealed = false}) => Violation(
      id: 'log-1',
      action: ModerationAction.hide,
      targetType: 'itinerary',
      targetId: 'itin-1',
      itemTitle: 'Coast walk',
      createdAt: DateTime.utc(2026, 10, 1),
      active: true,
      appealable: !appealed,
      appealStatus: appealed ? AppealStatus.pending : null,
    );

/// Records what the sheet posted so the test can assert the target survived,
/// and answers like the server: the list with the appeal on it.
class _RecordingRepo extends ProfileRepository {
  _RecordingRepo() : super(Dio());

  int calls = 0;
  int listReads = 0;
  String? targetType;
  String? targetId;
  String? reason;

  @override
  Future<List<Violation>> getViolations({bool forceRefresh = false}) async {
    listReads++;
    return [_hidden()];
  }

  @override
  Future<List<Violation>> submitAppeal({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    calls++;
    this.targetType = targetType;
    this.targetId = targetId;
    this.reason = reason;
    return [_hidden(appealed: true)];
  }
}

/// Rejects with the coded 409 the backend returns for a duplicate appeal.
class _AlreadyPendingRepo extends ProfileRepository {
  _AlreadyPendingRepo() : super(Dio());

  @override
  Future<List<Violation>> submitAppeal({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    final request = RequestOptions(path: '/appeals');
    throw DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: request,
        statusCode: 409,
        data: const {'code': 'appeal_already_pending', 'detail': 'Already open.'},
      ),
    );
  }
}

/// Holds the appeal until the test answers it.
class _HeldRepo extends ProfileRepository {
  _HeldRepo() : super(Dio());

  final answer = Completer<List<Violation>>();

  @override
  Future<List<Violation>> submitAppeal({
    required String targetType,
    required String targetId,
    required String reason,
  }) =>
      answer.future;
}

void main() {
  const reasonField = Key('appealReasonField');
  const submitButton = Key('appealSubmitButton');

  Future<void> pumpSheet(
    WidgetTester tester,
    ProfileRepository repo, {
    String targetType = 'rating',
    String targetId = 'rating-1',
    Size size = const Size(1000, 1400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showAppealSheet(
                  context,
                  targetType: targetType,
                  targetId: targetId,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(submitButton));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Given a rating target, When submitted, Then it posts that target',
      (tester) async {
    final repo = _RecordingRepo();
    await pumpSheet(tester, repo, targetType: 'rating', targetId: 'rating-42');

    await tester.enterText(find.byKey(reasonField), 'This was a fair review.');
    await submit(tester);

    expect(repo.calls, 1);
    expect(repo.targetType, 'rating');
    expect(repo.targetId, 'rating-42');
    expect(repo.reason, 'This was a fair review.');
  });

  testWidgets(
      'Given a user target, When submitted, Then the target type is not hardcoded',
      (tester) async {
    final repo = _RecordingRepo();
    await pumpSheet(tester, repo, targetType: 'user', targetId: 'user-7');

    await tester.enterText(find.byKey(reasonField), 'My bio is not offensive.');
    await submit(tester);

    expect(repo.targetType, 'user');
    expect(repo.targetId, 'user-7');
  });

  testWidgets(
      'Given a short window, When the reason is typed with the keyboard up, '
      'Then Submit stays on screen above the keyboard', (tester) async {
    await pumpSheet(tester, _RecordingRepo(), size: const Size(320, 568));

    await tester.showKeyboard(find.byKey(reasonField));
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    // Pinned below the body: as its last child it sat under the keyboard.
    expect(find.byKey(submitButton).hitTestable(), findsOneWidget);
    expect(tester.getRect(find.byKey(submitButton)).bottom,
        lessThanOrEqualTo(568 - 260));
  });

  testWidgets('Given an empty reason, When submitted, Then nothing is posted',
      (tester) async {
    final repo = _RecordingRepo();
    await pumpSheet(tester, repo);

    await submit(tester);

    expect(repo.calls, 0);
    expect(find.byKey(reasonField), findsOneWidget); // sheet stayed open
  });

  testWidgets(
      'Given a whitespace-only reason, When submitted, Then nothing is posted',
      (tester) async {
    final repo = _RecordingRepo();
    await pumpSheet(tester, repo);

    await tester.enterText(find.byKey(reasonField), '    ');
    await submit(tester);

    expect(repo.calls, 0);
  });

  testWidgets('Given the reason has padding, When submitted, Then it is trimmed',
      (tester) async {
    final repo = _RecordingRepo();
    await pumpSheet(tester, repo);

    await tester.enterText(find.byKey(reasonField), '  please review  ');
    await submit(tester);

    expect(repo.reason, 'please review');
  });

  testWidgets('Given a successful appeal, When submitted, Then the sheet closes',
      (tester) async {
    await pumpSheet(tester, _RecordingRepo());

    await tester.enterText(find.byKey(reasonField), 'a reason');
    await submit(tester);

    expect(find.byKey(reasonField), findsNothing);
  });

  testWidgets(
      'Given the server rejects it, When submitted, Then the sheet stays open '
      'with an inline error', (tester) async {
    await pumpSheet(tester, _AlreadyPendingRepo());

    await tester.enterText(find.byKey(reasonField), 'a reason');
    await submit(tester);

    // Still open — a snackbar here would render behind the modal barrier.
    expect(find.byKey(reasonField), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(reasonField));
    expect(field.decoration?.errorText, isNotNull);
    // On the field only — the pinned bar does not say it a second time.
    expect(
      find.descendant(
        of: find.byType(SheetActionBar),
        matching: find.byType(SheetErrorRow),
      ),
      findsNothing,
    );
    // The typed reason survives so Submit can retry.
    expect(field.controller?.text, 'a reason');
  });

  testWidgets(
      'Given an appeal in flight, When it is answered, Then the button and '
      'the reason waited and the sheet closes', (tester) async {
    final repo = _HeldRepo();
    await pumpSheet(tester, repo);
    await tester.enterText(find.byKey(reasonField), 'a reason');

    await tester.tap(find.byKey(submitButton));
    // Bounded pump: the spinner animates for as long as the appeal is held.
    await tester.pump();

    expect(tester.widget<FilledButton>(find.byKey(submitButton)).onPressed,
        isNull);
    expect(
      find.descendant(
        of: find.byKey(submitButton),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(find.byKey(reasonField)).enabled, isFalse);

    repo.answer.complete([_hidden(appealed: true)]);
    await tester.pumpAndSettle();

    expect(find.byKey(reasonField), findsNothing);
  });

  testWidgets(
      'Given Account status is open, When an appeal is filed from it, '
      'Then the list shows the answer and is not downloaded again',
      (tester) async {
    final repo = _RecordingRepo();
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AccountStatusScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Appeal available'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Appeal'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(reasonField), 'It was a real place.');
    await submit(tester);

    expect(repo.calls, 1);
    expect(find.text('Appeal under review'), findsOneWidget);
    expect(repo.listReads, 1, reason: 'the answer was the list');
  });
}
