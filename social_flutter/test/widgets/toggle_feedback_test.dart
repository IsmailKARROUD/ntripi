// test/widgets/toggle_feedback_test.dart
//
// Every switch in the app acknowledges a flip through toggleFeedback, and the
// two rules that makes possible are easy to break silently:
//   · it fires in BOTH directions — off is as much a flip as on;
//   · the preference is written BEFORE it fires, so play() reads the new value.
//     That ordering is the only reason switching sound off is silent and
//     switching it back on is not; reversed, the sound switch would announce its
//     own silencing and then stay mute forever after.
//
// The fake records the sound preference as it stood at the moment play() was
// called, which is exactly what the real gate inside SfxService.play reads. So
// the second rule is asserted here rather than merely commented there.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/providers/sound_effects_enabled_provider.dart';
import 'package:social_flutter/core/services/sfx_service.dart';
import 'package:social_flutter/features/profile/presentation/widgets/profile_settings_sheet.dart';
import 'package:social_flutter/features/profile/providers/profile_provider.dart';
import 'package:social_flutter/l10n/app_localizations.dart';
import 'package:social_flutter/shared/models/user.dart';

// ── Test fixtures ─────────────────────────────────────────────────────────

final _user = User(
  id: 'user-1',
  username: 'ismauo',
  displayName: 'Ismail duo',
  isPrivate: false,
  followersCount: 2,
  followingCount: 1,
  createdAt: DateTime(2024),
);

class _FakeMyProfile extends MyProfileNotifier {
  _FakeMyProfile(this._u);
  final User _u;
  @override
  Future<User> build() async => _u;
}

/// Records what was played and, with it, the preference the real gate would
/// have read at that instant.
class _RecordingSfx extends SfxService {
  _RecordingSfx(this._recordRef) : super(_recordRef);

  final Ref _recordRef;
  final played = <Sfx>[];
  final soundPrefWhenPlayed = <bool>[];

  @override
  Future<void> play(Sfx sfx) async {
    played.add(sfx);
    soundPrefWhenPlayed.add(_recordRef.read(soundEffectsEnabledProvider));
  }
}

// ── Harness ───────────────────────────────────────────────────────────────

/// Pumps the settings sheet already open. Switch order in the sheet is
/// sound (0), haptics (1), shake-to-report (2) — the shake row renders because
/// the test host is not web.
Future<_RecordingSfx> _pumpSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  FlutterSecureStorage.setMockInitialValues({});

  late _RecordingSfx recorder;

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        myProfileProvider.overrideWith(() => _FakeMyProfile(_user)),
        sfxServiceProvider.overrideWith((ref) {
          recorder = _RecordingSfx(ref);
          return recorder;
        }),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () =>
                    showProfileSettingsSheet(context, onLogout: () {}),
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

  // The provider is lazy and nothing has flipped a switch yet, so read it once
  // here — otherwise `recorder` is still uninitialised when the test returns.
  ProviderScope.containerOf(tester.element(find.text('open')), listen: false)
      .read(sfxServiceProvider);
  return recorder;
}

// ═══════════════════════════════════════════════════════════════════════════

void main() {
  group('toggle feedback', () {
    testWidgets(
        'Given sound cues are on, When the sound switch is turned off, '
        'Then the cue still fires and sees the preference already false',
        (tester) async {
      final sfx = await _pumpSheet(tester);

      await tester.tap(find.byType(Switch).at(0));
      await tester.pumpAndSettle();

      expect(sfx.played, [Sfx.toggle]);
      // The write landed first, so the real gate inside play() would swallow the
      // audio — silent on the way off, with the haptic tap left to acknowledge.
      expect(sfx.soundPrefWhenPlayed, [false]);
    });

    testWidgets(
        'Given sound cues are off, When the sound switch is turned back on, '
        'Then the cue fires with the preference already true', (tester) async {
      final sfx = await _pumpSheet(tester);

      await tester.tap(find.byType(Switch).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).at(0));
      await tester.pumpAndSettle();

      expect(sfx.played, [Sfx.toggle, Sfx.toggle]);
      expect(sfx.soundPrefWhenPlayed, [false, true]);
    });

    testWidgets(
        'Given the haptics switch, When it is flipped either way, '
        'Then the same cue fires — the acknowledgement is not sound-specific',
        (tester) async {
      final sfx = await _pumpSheet(tester);

      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();

      expect(sfx.played, [Sfx.toggle, Sfx.toggle]);
      // The sound preference was never touched, so the cue stays audible.
      expect(sfx.soundPrefWhenPlayed, [true, true]);
    });

    testWidgets(
        'Given a row whose whole surface toggles, When the row is tapped '
        'rather than its switch, Then it acknowledges exactly once',
        (tester) async {
      final sfx = await _pumpSheet(tester);

      await tester.tap(find.text('Shake to report'));
      await tester.pumpAndSettle();

      expect(sfx.played, [Sfx.toggle]);
    });
  });
}
