// test/features/bug_report/bug_report_sheet_test.dart
//
// Two things are pinned down here.
//
// 1. The compose sheet renders OUTSIDE MaterialApp — BetterFeedback has to wrap
//    it, because its bottom sheet builds a bare Navigator that would otherwise
//    inherit (and assert on) the app's HeroController. So the sheet gets its
//    l10n from the delegates passed to BetterFeedback and its theme from the
//    feedbackBuilder, and if either is dropped the sheet throws or silently
//    renders in Material defaults. These tests fail if that wiring regresses.
//
// 2. The sheet's failure behaviour, mirroring report_content_sheet_test: the
//    error is shown inline (a snackbar would render behind the full-screen
//    feedback UI) and the typed message survives it so Send retries.
//
// 3. Send is in view the moment the reporter opens, and stays above the
//    keyboard — and wherever the sheet is dragged. The package opens its sheet
//    shorter than this form, so a Send at the end of the list started out of
//    sight on every phone. The message, which Send waits for, comes first.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/bug_report/presentation/bug_report_localizations.dart';
import 'package:ntripi/features/bug_report/presentation/bug_report_sheet.dart';
import 'package:ntripi/features/bug_report/presentation/bug_report_theme.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/editorial_widgets.dart';
import 'package:ntripi/shared/widgets/loaders.dart';

/// Mirrors the mount in lib/main.dart: ProviderScope above everything, then
/// BetterFeedback, then MaterialApp. `home` is what a real screen sees.
Widget _appHarness({required Widget home, Locale locale = const Locale('en')}) {
  return ProviderScope(
    child: _feedbackApp(home: home, locale: locale),
  );
}

Widget _feedbackApp({required Widget home, required Locale locale}) {
  return BetterFeedback(
    theme: ntripiFeedbackTheme(NtripiColors.light),
    darkTheme: ntripiFeedbackTheme(NtripiColors.dark),
    themeMode: ThemeMode.light,
    localizationsDelegates: [
      const NtripiFeedbackLocalizationsDelegate(),
      ...AppLocalizations.localizationsDelegates,
    ],
    localeOverride: locale,
    feedbackBuilder: (ctx, onSubmit, scrollController) => Theme(
      data: ntripiFeedbackAppTheme(ctx, ThemeMode.light),
      child: BugReportSheet(
        onSubmit: onSubmit,
        scrollController: scrollController,
      ),
    ),
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildNtripiTheme(),
      home: home,
    ),
  );
}

/// Mounts the sheet alone, with the same Theme + delegates main.dart hands it.
///
/// The full BetterFeedback flow cannot be driven here: show()'s callback only
/// fires after the package captures a real screenshot off the render tree,
/// which flutter_test has no pipeline for. The sheet's own behaviour is what
/// these tests are about, so they drive its OnSubmit directly.
Widget _sheetHarness({required OnSubmit onSubmit, bool online = true}) {
  return ProviderScope(
    overrides: [isOnlineProvider.overrideWith((ref) => Stream.value(online))],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildNtripiTheme(),
      home: Scaffold(
        body: BugReportSheet(onSubmit: onSubmit, scrollController: null),
      ),
    ),
  );
}

/// The backend's generic 500, as the intake answers it.
DioException _serverError() {
  final request = RequestOptions(path: '/bug-reports');
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
  // The sheet is a fraction of the screen height and its content is a lazy
  // ListView. On the default 800×600 test surface it would be ~270 px tall and
  // the categories, last in the list, would never be built.
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1000, 2400);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  group('BetterFeedback wrapping MaterialApp', () {
    testWidgets('leaves AppLocalizations working for the app below it',
        (tester) async {
      await tester.pumpWidget(_appHarness(
        home: Builder(
          // The bang is the app-wide idiom; a broken scope would throw here
          // rather than render.
          builder: (context) => Text(AppLocalizations.of(context)!.cancel),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('the sheet resolves the app locale, not the platform one',
        (tester) async {
      await tester.pumpWidget(_appHarness(
        locale: const Locale('fr'),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => BetterFeedback.of(context).show((_) async {}),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The sheet renders outside MaterialApp, so this only passes if the app's
      // delegates were handed to BetterFeedback AND localeOverride was set.
      expect(find.text('Signaler un problème'), findsOneWidget);
    });
  });

  group('BugReportSheet', () {
    testWidgets('Send stays disabled until something is typed', (tester) async {
      await tester.pumpWidget(_sheetHarness(onSubmit: (_, {extras}) async {}));
      await tester.pumpAndSettle();

      final send = find.widgetWithText(FilledButton, 'Send report');
      expect(send, findsOneWidget);
      expect(tester.widget<FilledButton>(send).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'The map is blank');
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
    });

    testWidgets('a failed submit reports inline and keeps the text',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(_sheetHarness(onSubmit: (_, {extras}) async {
        calls++;
        throw _serverError();
      }));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'The map is blank');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Send report'));
      await tester.pumpAndSettle();

      expect(calls, 1);
      // Inline, not a snackbar — the feedback UI covers the whole screen, so a
      // root-messenger snackbar would render behind it and never be seen.
      expect(find.text('Internal Server Error'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      // In the pinned bar, above Send — wherever the list is scrolled to.
      expect(
        find.descendant(
          of: find.byType(SheetActionBar),
          matching: find.text('Internal Server Error'),
        ),
        findsOneWidget,
      );
      // The user's words survive so Send retries rather than starting over.
      expect(find.text('The map is blank'), findsOneWidget);
    });

    testWidgets('the selected category rides along in extras', (tester) async {
      Map<String, dynamic>? seen;
      await tester.pumpWidget(_sheetHarness(onSubmit: (_, {extras}) async {
        seen = extras;
      }));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Something looks wrong'));
      await tester.enterText(find.byType(TextField), 'Overlapping labels');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Send report'));
      // Bounded pumps, not pumpAndSettle: on success the sheet deliberately
      // stays in its saving state — BetterFeedback is what dismisses it — so
      // the loader keeps animating and "no frames scheduled" never arrives.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(seen?['category'], 'visual');
    });

    testWidgets('asks for the message before the optional category',
        (tester) async {
      await tester.pumpWidget(_sheetHarness(onSubmit: (_, {extras}) async {}));
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(TextField)).bottom,
          lessThan(tester.getRect(find.text('The app froze or closed')).top));
    });

    testWidgets('offline, Send stays disabled with a message typed',
        (tester) async {
      await tester.pumpWidget(
          _sheetHarness(online: false, onSubmit: (_, {extras}) async {}));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'The map is blank');
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Send report'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('while sending, the buttons and the message wait; a failure '
        'hands them back', (tester) async {
      final answer = Completer<void>();
      await tester.pumpWidget(
          _sheetHarness(onSubmit: (_, {extras}) => answer.future));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'The map is blank');
      await tester.pumpAndSettle();

      final send = find.descendant(
          of: find.byType(SheetActionBar), matching: find.byType(FilledButton));
      final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
      bool fieldEnabled() =>
          tester.widget<TextField>(find.byType(TextField)).enabled ?? true;

      await tester.tap(send);
      // Bounded pump: the loader animates for as long as the send is held.
      await tester.pump();

      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      expect(find.descendant(of: send, matching: find.byType(NTripiRingLoader)),
          findsOneWidget);
      expect(tester.widget<OutlinedButton>(cancel).onPressed, isNull);
      expect(fieldEnabled(), isFalse);

      answer.completeError(_serverError());
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
      expect(tester.widget<OutlinedButton>(cancel).onPressed, isNotNull);
      expect(fieldEnabled(), isTrue);
    });
  });

  group('on a phone', () {
    // The sheet opens at 45 % of 844 — 380 px, shorter than the form.
    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
    }

    Future<void> openReporter(WidgetTester tester) async {
      await tester.pumpWidget(_appHarness(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => BetterFeedback.of(context).show((_) async {}),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    final send = find.widgetWithText(FilledButton, 'Send report');

    testWidgets('the reporter opens with the message field and Send in view',
        (tester) async {
      phone(tester);
      await openReporter(tester);

      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      expect(send.hitTestable(), findsOneWidget);
    });

    testWidgets('Send stays above the keyboard while the message is typed',
        (tester) async {
      phone(tester);
      await openReporter(tester);

      await tester.showKeyboard(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      final sendRect = tester.getRect(send);
      expect(sendRect.bottom, lessThanOrEqualTo(844 - 300));
      expect(tester.getRect(find.byType(TextField)).bottom,
          lessThanOrEqualTo(sendRect.top));
    });

    testWidgets('dragging the sheet up keeps Send at its foot', (tester) async {
      phone(tester);
      await openReporter(tester);
      final atRest = tester.getRect(send);
      // The premise: at rest the last category is out of reach.
      expect(find.text('Something else').hitTestable(), findsNothing);

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(find.text('Something else').hitTestable(), findsOneWidget);
      expect(send.hitTestable(), findsOneWidget);
      expect(tester.getRect(send).bottom, atRest.bottom);
    });

    testWidgets('Cancel closes the reporter', (tester) async {
      phone(tester);
      await openReporter(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(BetterFeedback.of(tester.element(find.text('open'))).isVisible,
          isFalse);
      expect(find.byType(BugReportSheet), findsNothing);
    });
  });
}
