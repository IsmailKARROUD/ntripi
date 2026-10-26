// test/shared/widgets/reload_report_test.dart — how a screen reports a reload
// the user started.
//
// A reload that kept the content through a failure hands that failure back,
// and the screen says so once, in a SnackBar, while it is still on screen. A
// reload that succeeded, or that had nothing on screen to keep — the error view
// already says it — hands back null and shows nothing.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/providers/reload_keeps_content.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/reload_report.dart';

const _offline =
    'No internet connection. Please check your network and try again.';

ReloadFailure _timeout() => ReloadFailure(
      DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.receiveTimeout,
      ),
      StackTrace.empty,
    );

ReloadFailure _serverError() {
  final sent = RequestOptions(path: '/y');
  return ReloadFailure(
    DioException.badResponse(
      statusCode: 500,
      requestOptions: sent,
      response: Response(
        requestOptions: sent,
        statusCode: 500,
        data: {'detail': 'Internal Server Error'},
      ),
    ),
    StackTrace.empty,
  );
}

/// A base page that pushes the reloading screen, so a test can leave it.
Widget _app(List<Future<ReloadFailure?>> Function() reloads) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => reportReloads(context, reloads()),
                  child: const Text('Reload'),
                ),
              ),
            )),
            child: const Text('Open'),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'Given every reload succeeded, When reported, Then no SnackBar shows',
      (tester) async {
    await tester.pumpWidget(_app(() => [Future.value(), Future.value()]));
    await _open(tester);

    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
      'Given a reload kept the content through a timeout, When reported, '
      'Then its reason shows in a SnackBar', (tester) async {
    await tester.pumpWidget(_app(() => [Future.value(_timeout())]));
    await _open(tester);

    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(_offline), findsOneWidget);
  });

  testWidgets(
      'Given two reloads failed, When reported, '
      'Then one SnackBar shows the first failure', (tester) async {
    await tester.pumpWidget(_app(() => [
          Future.value(),
          Future.value(_timeout()),
          Future.value(_serverError()),
        ]));
    await _open(tester);

    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(_offline), findsOneWidget);
    expect(find.text('Internal Server Error'), findsNothing);
  });

  testWidgets(
      'Given the user left the screen before the reload failed, When reported, '
      'Then nothing shows and nothing throws', (tester) async {
    final reload = Completer<ReloadFailure?>();
    await tester.pumpWidget(_app(() => [reload.future]));
    await _open(tester);

    await tester.tap(find.text('Reload'));
    await tester.pump();
    Navigator.of(tester.element(find.text('Reload'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);

    reload.complete(_timeout());
    await tester.pumpAndSettle();

    // The SnackBar would have landed on the page below, about a screen the
    // user had already left.
    expect(find.byType(SnackBar), findsNothing);
  });
}
