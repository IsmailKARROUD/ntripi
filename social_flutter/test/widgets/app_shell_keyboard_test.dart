// The bottom-nav shell lifts its tabs above the keyboard exactly once.
//
// Regression: the shell rebuilt its tabs' MediaQuery from a context above its
// own Scaffold, putting back the keyboard inset that Scaffold had consumed.
// Every tab saw the keyboard again, so a resizing tab Scaffold lifted a second
// time (a keyboard-high blank band) and a sheet opened from a tab padded itself
// by a keyboard that was already accounted for. Eighteen screens then set
// `resizeToAvoidBottomInset: false` to hide it — which became "no keyboard
// avoidance at all" once the itinerary screens moved to the root navigator.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/router/app_router.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/widgets/keyboard_avoidance.dart';

const _keyboardTop = 800.0 - 300;

/// The real shell around [tab] (branch 0) and four empty branches.
Widget _shell(Widget tab) {
  final router = GoRouter(
    initialLocation: '/b0',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => appShellForTesting(shell),
        branches: [
          for (var i = 0; i < 5; i++)
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/b$i',
                builder: (context, state) => i == 0 ? tab : const SizedBox(),
              ),
            ]),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [isOnlineProvider.overrideWith((ref) => Stream.value(true))],
    child: MaterialApp.router(
      theme: buildNtripiTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a tab Scaffold ends at the keyboard, not a keyboard higher',
      (tester) async {
    _phone(tester);
    const body = Key('tab-body');
    // Default resizeToAvoidBottomInset, as every tab now has.
    await tester.pumpWidget(_shell(const Scaffold(body: SizedBox.expand(key: body))));
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byKey(body)).bottom, _keyboardTop);
  });

  testWidgets('a sheet opened from a tab rests on the keyboard, no blank band',
      (tester) async {
    _phone(tester);
    late BuildContext tabContext;
    await tester.pumpWidget(_shell(Scaffold(
      body: Builder(builder: (c) {
        tabContext = c;
        return const SizedBox.expand();
      }),
    )));
    await tester.pumpAndSettle();

    // Opened on the branch navigator (the default), as the appeal and report
    // sheets are from Account status and a profile.
    showModalBottomSheet<void>(
      context: tabContext,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const KeyboardSafeSheetBody(
        child: TextField(key: Key('field'), autofocus: true),
      ),
    );
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    final field = tester.getRect(find.byKey(const Key('field')));
    expect(field.bottom, lessThanOrEqualTo(_keyboardTop));
    expect(field.bottom, greaterThan(_keyboardTop - 60),
        reason: 'counted twice, the keyboard would leave a 300pt gap');
  });
}
