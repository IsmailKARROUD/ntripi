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

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/profile/data/profile_repository.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/appeal_sheet.dart';

/// Records what the sheet posted so the test can assert the target survived.
class _RecordingRepo extends ProfileRepository {
  _RecordingRepo() : super(Dio());

  int calls = 0;
  String? targetType;
  String? targetId;
  String? reason;

  @override
  Future<void> submitAppeal({
    required String targetType,
    required String targetId,
    required String reason,
  }) async {
    calls++;
    this.targetType = targetType;
    this.targetId = targetId;
    this.reason = reason;
  }
}

/// Rejects with the coded 409 the backend returns for a duplicate appeal.
class _AlreadyPendingRepo extends ProfileRepository {
  _AlreadyPendingRepo() : super(Dio());

  @override
  Future<void> submitAppeal({
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

void main() {
  const reasonField = Key('appealReasonField');
  const submitButton = Key('appealSubmitButton');

  Future<void> pumpSheet(
    WidgetTester tester,
    ProfileRepository repo, {
    String targetType = 'rating',
    String targetId = 'rating-1',
  }) async {
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
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showAppealSheet(
                  context,
                  ref,
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
    // The typed reason survives so Submit can retry.
    expect(field.controller?.text, 'a reason');
  });
}
