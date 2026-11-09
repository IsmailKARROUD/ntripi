// test/features/bug_report/bug_report_theme_change_test.dart
//
// The bug reporter after the app's theme or language changed since launch.
//
// The feedback package keeps state from the moment its layer is first built:
// its pen is drawColors[0] of the theme in force then (feedback 3.2.0), and
// its draw controls assert that the pens on offer still include it. The app's
// saved preferences land AFTER that moment — themeModeProvider answers
// ThemeMode.system until the keystore does, over a platform channel — and the
// theme can change later too: the phone's dark mode flips under System, or
// the user switches in Settings. On 2026-11-09 a phone in dark mode with the
// app set to Light opened the reporter onto a failed assertion: the debugger
// stopped on it, which on Android is an ANR, and without a debugger the red
// error screen replaced the app.
//
// Each test changes the theme (or the language) one way, then opens the
// reporter the way a shake does — startBugReport — through the app's own
// NtripiFeedback and the real preference providers. Only the keystore under
// flutter_secure_storage is faked, at its platform channel, and it answers
// when the test lets it: after the app is up, as on a real phone.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/providers/locale_provider.dart';
import 'package:ntripi/core/providers/theme_mode_provider.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/bug_report/presentation/bug_report_entry.dart';
import 'package:ntripi/features/bug_report/presentation/bug_report_sheet.dart';
import 'package:ntripi/features/bug_report/presentation/bug_report_theme.dart';
import 'package:ntripi/features/bug_report/presentation/ntripi_feedback.dart';
import 'package:ntripi/l10n/app_localizations.dart';

const _shakeKey = Key('shake');

/// The phone's keystore, as flutter_secure_storage reaches it: over its
/// platform channel. It answers when the test lets it.
class _Keystore {
  _Keystore(this._values);

  static const _channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  final Map<String, String> _values;
  Completer<void>? _held;

  void install(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, _answer);
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  }

  /// Answers nothing until [release].
  void hold() => _held = Completer<void>();

  void release() {
    _held?.complete();
    _held = null;
  }

  Future<Object?> _answer(MethodCall call) async {
    await _held?.future;
    final arguments = (call.arguments as Map).cast<String, Object?>();
    final key = arguments['key'] as String?;
    switch (call.method) {
      case 'read':
        return _values[key];
      case 'write':
        _values[key!] = arguments['value']! as String;
      case 'delete':
        _values.remove(key);
      case 'readAll':
        return Map<String, String>.of(_values);
      case 'deleteAll':
        _values.clear();
      case 'containsKey':
        return _values.containsKey(key);
    }
    return null;
  }
}

/// What NtripiApp builds around the reporter: the real preference providers,
/// the app's own NtripiFeedback and a MaterialApp following both.
Widget _app() {
  return ProviderScope(
    child: Consumer(
      builder: (context, ref, _) {
        final locale = ref.watch(localeProvider);
        final themeMode = ref.watch(themeModeProvider);
        return NtripiFeedback(
          themeMode: themeMode,
          locale: locale,
          child: MaterialApp(
            theme: buildNtripiTheme(),
            darkTheme: buildNtripiDarkTheme(),
            themeMode: themeMode,
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const _AnyScreen(),
          ),
        );
      },
    ),
  );
}

/// Stands in for whichever screen the phone is shaken on.
class _AnyScreen extends ConsumerWidget {
  const _AnyScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: TextButton(
          key: _shakeKey,
          // Exactly what ShakeToReport does on a shake.
          onPressed: () => startBugReport(context, ref),
          child: const Text('shake'),
        ),
      ),
    );
  }
}

/// A phone, held in [brightness] mode, whose keystore holds [saved].
_Keystore _phone(
  WidgetTester tester,
  Brightness brightness, {
  Map<String, String> saved = const {},
}) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  _phoneSwitchesTo(tester, brightness);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  return _Keystore({...saved})..install(tester);
}

/// The phone's own light/dark setting changes.
void _phoneSwitchesTo(WidgetTester tester, Brightness brightness) =>
    tester.platformDispatcher.platformBrightnessTestValue = brightness;

/// Launches the app on a phone in [phone] mode. The app — the reporter's layer
/// included — is up before the keystore answers, as on a real phone; only
/// then does what was saved land.
Future<void> _launch(
  WidgetTester tester,
  _Keystore keystore, {
  required Brightness phone,
}) async {
  keystore.hold();
  await tester.pumpWidget(_app());
  await tester.pump();
  // The premise: up, in the phone's brightness, with nothing saved landed yet.
  // That is the moment the reporter takes its pen from.
  expect(_appBrightness(tester), phone);
  keystore.release();
  await tester.pumpAndSettle();
}

/// The user's pick in Settings ▸ Appearance.
Future<void> _pickInSettings(WidgetTester tester, ThemeMode mode) async {
  await ProviderScope.containerOf(tester.element(find.byKey(_shakeKey)))
      .read(themeModeProvider.notifier)
      .setMode(mode);
  await tester.pumpAndSettle();
}

/// The phone is shaken: the reporter opens.
Future<void> _shake(WidgetTester tester) async {
  await tester.tap(find.byKey(_shakeKey));
  await tester.pumpAndSettle();
}

/// The reporter's own close button.
Future<void> _closeReporter(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('close_controls_column')));
  await tester.pumpAndSettle();
}

/// The brightness the app itself is drawn in now.
Brightness _appBrightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byKey(_shakeKey))).brightness;

/// The pens the reporter offers in [brightness].
List<Color> _pensOffered(Brightness brightness) => ntripiFeedbackTheme(
        brightness == Brightness.dark ? NtripiColors.dark : NtripiColors.light)
    .drawColors;

/// The pens the draw controls show as the one in hand.
List<Color> _penInHand(Brightness brightness) => [
      for (final pen in _pensOffered(brightness))
        if (find
            .descendant(
              of: find.byKey(ValueKey<Color>(pen)),
              matching: find.byIcon(Icons.lens),
            )
            .evaluate()
            .isNotEmpty)
          pen,
    ];

/// The reporter is open and whole: nothing threw, the compose sheet and the
/// draw controls are up, every pen is offered with exactly one in hand, and the
/// sheet is drawn in [brightness].
void _expectReporterOpen(WidgetTester tester, {required Brightness brightness}) {
  expect(tester.takeException(), isNull);
  expect(find.byType(BugReportSheet), findsOneWidget);
  expect(find.byKey(const ValueKey<String>('draw_button')), findsOneWidget);
  for (final pen in _pensOffered(brightness)) {
    expect(find.byKey(ValueKey<Color>(pen)), findsOneWidget);
  }
  expect(_penInHand(brightness), hasLength(1));
  expect(Theme.of(tester.element(find.byType(BugReportSheet))).brightness,
      brightness);
}

/// One way the theme can change between launch and a shake.
class _Change {
  const _Change({
    required this.given,
    required this.when,
    required this.phone,
    required this.saved,
    required this.opensIn,
    this.after,
  });

  final String given;
  final String when;

  /// The phone's light/dark setting at launch.
  final Brightness phone;

  /// The app's saved theme mode, as the keystore holds it; null when never
  /// chosen.
  final String? saved;

  /// What changes once the app is up, beyond the saved choice landing.
  final Future<void> Function(WidgetTester tester)? after;

  /// The brightness the reporter must open in.
  final Brightness opensIn;
}

Future<void> _phoneTurnsDark(WidgetTester tester) async {
  _phoneSwitchesTo(tester, Brightness.dark);
  await tester.pumpAndSettle();
}

Future<void> _phoneTurnsLight(WidgetTester tester) async {
  _phoneSwitchesTo(tester, Brightness.light);
  await tester.pumpAndSettle();
}

final _changes = <_Change>[
  // The report of 2026-11-09.
  const _Change(
    given: 'a phone in dark mode and the app saved to Light',
    when: 'the saved choice lands once the app is up',
    phone: Brightness.dark,
    saved: 'light',
    opensIn: Brightness.light,
  ),
  const _Change(
    given: 'a phone in light mode and the app saved to Dark',
    when: 'the saved choice lands once the app is up',
    phone: Brightness.light,
    saved: 'dark',
    opensIn: Brightness.dark,
  ),
  const _Change(
    given: 'a phone in light mode and the app following it',
    when: 'the phone switches to dark mode',
    phone: Brightness.light,
    saved: 'system',
    after: _phoneTurnsDark,
    opensIn: Brightness.dark,
  ),
  const _Change(
    given: 'a phone in dark mode and the app following it',
    when: 'the phone switches to light mode',
    phone: Brightness.dark,
    saved: 'system',
    after: _phoneTurnsLight,
    opensIn: Brightness.light,
  ),
  _Change(
    given: 'the app saved to Light on a phone in light mode',
    when: 'the user picks Dark in Settings',
    phone: Brightness.light,
    saved: 'light',
    after: (tester) => _pickInSettings(tester, ThemeMode.dark),
    opensIn: Brightness.dark,
  ),
  _Change(
    given: 'the app saved to Dark on a phone in dark mode',
    when: 'the user picks Light in Settings',
    phone: Brightness.dark,
    saved: 'dark',
    after: (tester) => _pickInSettings(tester, ThemeMode.light),
    opensIn: Brightness.light,
  ),
  // Controls: the theme in force never changes.
  const _Change(
    given: 'the app saved to Dark on a phone in dark mode',
    when: 'nothing changes',
    phone: Brightness.dark,
    saved: 'dark',
    opensIn: Brightness.dark,
  ),
  const _Change(
    given: 'a phone in light mode and no theme ever chosen',
    when: 'nothing changes',
    phone: Brightness.light,
    saved: null,
    opensIn: Brightness.light,
  ),
  const _Change(
    given: 'the app saved to Light on a phone in light mode',
    when: 'the phone switches to dark mode',
    phone: Brightness.light,
    saved: 'light',
    after: _phoneTurnsDark,
    opensIn: Brightness.light,
  ),
];

void main() {
  group('A theme change between launch and a shake', () {
    for (final change in _changes) {
      testWidgets(
          'Given ${change.given}, '
          'When ${change.when} and the phone is shaken, '
          'Then the reporter opens whole, in ${change.opensIn.name}',
          (tester) async {
        final keystore = _phone(tester, change.phone, saved: {
          if (change.saved != null) 'ntripi_theme_mode': change.saved!,
        });

        await _launch(tester, keystore, phone: change.phone);
        await change.after?.call(tester);
        expect(_appBrightness(tester), change.opensIn);

        await _shake(tester);

        _expectReporterOpen(tester, brightness: change.opensIn);
      });
    }
  });

  group('State that outlives one opening', () {
    testWidgets(
        'Given a pen picked in light, '
        'When the app turns dark and the phone is shaken again, '
        'Then that pen is still offered and still in hand', (tester) async {
      final keystore = _phone(tester, Brightness.light);
      await _launch(tester, keystore, phone: Brightness.light);
      await _shake(tester);
      final picked = _pensOffered(Brightness.light)[1];
      await tester.tap(find.byKey(ValueKey<Color>(picked)));
      await tester.pumpAndSettle();
      expect(_penInHand(Brightness.light), [picked]);
      await _closeReporter(tester);

      await _pickInSettings(tester, ThemeMode.dark);
      await _shake(tester);

      _expectReporterOpen(tester, brightness: Brightness.dark);
      expect(_penInHand(Brightness.dark), [picked]);
    });

    testWidgets(
        'Given the reporter open in light, '
        'When the user turns the app dark from it, '
        'Then it stays open and whole, and its sheet turns dark',
        (tester) async {
      final keystore = _phone(tester, Brightness.light);
      await _launch(tester, keystore, phone: Brightness.light);
      await _shake(tester);
      _expectReporterOpen(tester, brightness: Brightness.light);

      // The reporter's Navigate mode reaches Settings while it stays open.
      await _pickInSettings(tester, ThemeMode.dark);

      _expectReporterOpen(tester, brightness: Brightness.dark);
    });

    testWidgets(
        'Given the reporter open while the app follows a phone in light mode, '
        'When the phone switches to dark mode, '
        'Then it stays open and whole, and its sheet turns dark',
        (tester) async {
      final keystore = _phone(tester, Brightness.light);
      await _launch(tester, keystore, phone: Brightness.light);
      await _shake(tester);
      _expectReporterOpen(tester, brightness: Brightness.light);

      await _phoneTurnsDark(tester);

      _expectReporterOpen(tester, brightness: Brightness.dark);
    });
  });

  group('The language, which also lands once the app is up', () {
    testWidgets(
        'Given Arabic saved, '
        'When it lands once the app is up and the phone is shaken, '
        'Then the reporter speaks Arabic, right to left', (tester) async {
      final keystore = _phone(tester, Brightness.light,
          saved: {'ntripi_app_locale': 'ar'});

      await _launch(tester, keystore, phone: Brightness.light);
      expect(Localizations.localeOf(tester.element(find.byKey(_shakeKey))),
          const Locale('ar'));
      await _shake(tester);

      _expectReporterOpen(tester, brightness: Brightness.light);
      final arabic = lookupAppLocalizations(const Locale('ar'));
      expect(find.text(arabic.bugReportTitle), findsOneWidget);
      expect(find.text(arabic.bugReportNavigate), findsOneWidget);
      expect(find.text(arabic.bugReportDraw), findsOneWidget);
      expect(Directionality.of(tester.element(find.byType(BugReportSheet))),
          TextDirection.rtl);
    });
  });

  group('The pens', () {
    test(
        'Given the light and the dark feedback themes, '
        'Then they offer the same pens, in the same order: the brand\'s', () {
      expect(_pensOffered(Brightness.light),
          orderedEquals(_pensOffered(Brightness.dark)));
      expect(_pensOffered(Brightness.light),
          orderedEquals(NtripiBrand.markerPens));
    });
  });
}
