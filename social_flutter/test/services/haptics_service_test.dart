// test/services/haptics_service_test.dart — how a cue picks its engine.
//
// HapticsService now drives two of them: HapticFeedback for the derived tap
// patterns, and the vibration package for the one cue specified as a length.
// The routing between them carries three claims the source only asserts in
// comments, and each is the kind that breaks silently:
//
//   · a buzz is only ever attempted where the device can hold one, and where it
//     cannot the step still fires — as its fallback tap, never as silence;
//   · a vibration failure costs the buzz its duration and nothing else. It must
//     not latch _unsupported, which would take every tap in the app with it for
//     the rest of the session;
//   · hapticsEnabledProvider still governs the buzz. It is the only switch left
//     standing over it, because Android's Vibrator does not consult the
//     OS-level touch-vibration setting the way performHapticFeedback does.
//
// The fake platform is what makes the buzz branch reachable at all: the test
// host is neither Android nor iOS, so the real implementation answers
// hasVibrator() false before it ever reaches a method channel.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/providers/haptics_enabled_provider.dart';
import 'package:social_flutter/core/services/haptics_service.dart';
import 'package:vibration_platform_interface/vibration_platform_interface.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────

class _FakeVibration extends VibrationPlatform {
  _FakeVibration({this.canBuzz = true, this.failVibrate = false});

  final bool canBuzz;
  final bool failVibrate;

  /// The duration of every buzz actually requested, in order.
  final durations = <int>[];

  @override
  Future<bool> hasVibrator() async => canBuzz;

  @override
  Future<bool> hasCustomVibrationsSupport() async => canBuzz;

  @override
  Future<void> vibrate({
    int duration = 500,
    List<int> pattern = const [],
    int repeat = -1,
    List<int> intensities = const [],
    int amplitude = -1,
    double sharpness = 0.5,
  }) async {
    durations.add(duration);
    if (failVibrate) throw PlatformException(code: 'no_vibrator');
  }
}

class _FixedHapticsEnabled extends HapticsEnabledNotifier {
  _FixedHapticsEnabled(this._value);
  final bool _value;
  @override
  bool build() => _value;
}

// ── Harness ───────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VibrationPlatform originalPlatform;
  late List<String> taps;

  setUp(() {
    originalPlatform = VibrationPlatform.instance;
    taps = <String>[];
    // HapticFeedback rides SystemChannels.platform; with no handler installed
    // it throws MissingPluginException, which is the very thing under test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        taps.add(call.arguments as String? ?? 'standard');
      }
      return null;
    });
  });

  tearDown(() {
    VibrationPlatform.instance = originalPlatform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// Builds the service against [platform] and lets its constructor probe
  /// settle — nothing exposes that probe, so a cue fired sooner would take the
  /// fallback and prove nothing.
  Future<HapticsService> serviceWith(
    _FakeVibration platform, {
    bool hapticsEnabled = true,
  }) async {
    VibrationPlatform.instance = platform;
    final container = ProviderContainer(
      overrides: [
        hapticsEnabledProvider
            .overrideWith(() => _FixedHapticsEnabled(hapticsEnabled)),
      ],
    );
    addTearDown(container.dispose);
    final service = container.read(hapticsServiceProvider);
    await pumpEventQueue();
    return service;
  }

  /// Lets the fired cue run to completion — fire() is void and returns before
  /// its own sequence has started.
  Future<void> settle() => pumpEventQueue();

  // ═════════════════════════════════════════════════════════════════════════

  group('Haptic.rating', () {
    test('Given the cue, Then it is one 20 ms unit with a tap to fall back on',
        () {
      final steps = Haptic.rating.steps;

      expect(steps, hasLength(1));
      // Per star, not per tap — five of these is the 100 ms top of the range.
      expect(steps.single.durationMs, 20);
      expect(steps.single.delayMs, 0);
      // Not decoration — this is what fires wherever a duration is impossible.
      expect(steps.single.weight, HapticWeight.medium);
    });

    test('Given a derived cue, Then every step is a tap, never a buzz', () {
      for (final haptic in Haptic.values.where((h) => h != Haptic.rating)) {
        expect(haptic.steps.every((s) => s.durationMs == 0), isTrue,
            reason: '${haptic.name} should not have grown a duration');
      }
    });
  });

  group('HapticsService buzz routing', () {
    test(
        'Given a device that can hold a buzz, When the rating cue fires at each '
        'star, Then the buzz grows 20 ms a star and never also taps', () async {
      final platform = _FakeVibration();
      final service = await serviceWith(platform);

      for (var star = 1; star <= 5; star++) {
        service.fire(Haptic.rating, scale: star);
        await settle();
      }

      // The whole point of the scale: the hand feels the score, not just the
      // tap. Five stars is 100 ms, one star is a fifth of it.
      expect(platform.durations, [20, 40, 60, 80, 100]);
      expect(taps, isEmpty);
    });

    test(
        'Given a derived cue, When it is fired with a scale, Then the scale is '
        'inert — a tap has no length to stretch', () async {
      final platform = _FakeVibration();
      final service = await serviceWith(platform);

      service.fire(Haptic.selection, scale: 5);
      await settle();

      expect(platform.durations, isEmpty);
      expect(taps, ['HapticFeedbackType.selectionClick']);
    });

    test(
        'Given a device that cannot, When the rating cue fires, '
        'Then it degrades to the fallback tap rather than to silence', () async {
      final platform = _FakeVibration(canBuzz: false);
      final service = await serviceWith(platform);

      service.fire(Haptic.rating, scale: 3);
      await settle();

      expect(platform.durations, isEmpty);
      expect(taps, ['HapticFeedbackType.mediumImpact']);
    });

    test(
        'Given haptics are switched off, When the rating cue fires, '
        'Then nothing buzzes and nothing taps', () async {
      final platform = _FakeVibration();
      final service = await serviceWith(platform, hapticsEnabled: false);

      service.fire(Haptic.rating, scale: 5);
      await settle();

      expect(platform.durations, isEmpty);
      expect(taps, isEmpty);
    });

    test(
        'Given the vibration channel fails, When the rating cue fires twice, '
        'Then the first falls back to a tap and the second stops asking',
        () async {
      final platform = _FakeVibration(failVibrate: true);
      final service = await serviceWith(platform);

      service.fire(Haptic.rating, scale: 5);
      await settle();
      service.fire(Haptic.rating, scale: 5);
      await settle();

      // Attempted once, then written off — but the cue still landed both times.
      expect(platform.durations, [100]);
      expect(taps, [
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.mediumImpact',
      ]);
    });

    test(
        'Given a vibration failure has already happened, When a tap-only cue '
        'fires, Then the taps are untouched — the two channels fail apart',
        () async {
      final platform = _FakeVibration(failVibrate: true);
      final service = await serviceWith(platform);

      service.fire(Haptic.rating, scale: 5);
      await settle();
      taps.clear();

      service.fire(Haptic.selection);
      await settle();

      expect(taps, ['HapticFeedbackType.selectionClick']);
    });
  });
}
