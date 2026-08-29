// core/services/haptics_service.dart — one-shot UI haptic cues.
//
// The companion to sfx_service.dart, and built the same way: every cue goes
// through fire(), which is also where the user's on/off preference is read, so
// a new call site cannot forget to check it.
//
// Flutter's own HapticFeedback rather than a vibration package, deliberately.
// The cues here are all one to three discrete taps, never an amplitude-shaped
// waveform, and HapticFeedback expresses those with no dependency, no
// android.permission.VIBRATE, the correct iOS Taptic Engine feel, and — the
// part a package cannot buy back — obedience to the OS-level haptics setting
// on both platforms.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/providers/haptics_enabled_provider.dart';

/// How hard one tap in a cue lands.
enum HapticWeight { selection, light, medium, heavy }

/// One tap, and how long after the previous one it falls.
class HapticStep {
  const HapticStep(this.weight, this.delayMs);

  final HapticWeight weight;

  /// Milliseconds to wait *before* this tap. 0 on the first step of every cue.
  final int delayMs;
}

/// The haptic cues the app can fire.
///
/// The delays are tuned against the accents of the sound each cue is paired
/// with in [Sfx], so a two-step cue reads as one gesture rather than two
/// events. They are the only place those numbers live — retune here.
enum Haptic {
  /// A bare acknowledgement with no sound: the long-press affordance.
  selection([HapticStep(HapticWeight.selection, 0)]),

  /// A trip opening — light, then a softer second as the map settles.
  open([
    HapticStep(HapticWeight.light, 0),
    HapticStep(HapticWeight.light, 120),
  ]),

  /// Folding it closed — the heavier beat first, trailing off.
  fold([
    HapticStep(HapticWeight.medium, 0),
    HapticStep(HapticWeight.light, 90),
  ]),

  /// Destructive, so a single unambiguous thud rather than a flourish.
  delete([HapticStep(HapticWeight.heavy, 0)]),

  /// An arrival — a quick tick that rises, the shape of a notification.
  arrival([
    HapticStep(HapticWeight.light, 0),
    HapticStep(HapticWeight.medium, 70),
  ]);

  const Haptic(this.steps);
  final List<HapticStep> steps;
}

class HapticsService {
  HapticsService(this._ref);

  final Ref _ref;

  /// Bumped by every fire(). A running sequence abandons itself once this no
  /// longer matches its own token, so a rapid second cue replaces the first
  /// instead of interleaving with it — the same restart-don't-stutter rule
  /// SfxService gets from _player.stop().
  int _token = 0;

  /// Latched the first time the platform channel turns out not to exist (web,
  /// and under `flutter test`). Only MissingPluginException may set it: a
  /// transient failure must not cost a real device its haptics for the session.
  bool _unsupported = false;

  /// Fires [haptic] and returns immediately.
  ///
  /// Synchronous and void on purpose — callers must never await a decorative
  /// cue, least of all SfxService.play(), which fires this before the awaits on
  /// its own audio path precisely so the tap and the sound land together.
  void fire(Haptic haptic) {
    if (_unsupported) return;
    if (!_ref.read(hapticsEnabledProvider)) return;
    unawaited(_run(haptic, ++_token));
  }

  Future<void> _run(Haptic haptic, int token) async {
    for (final step in haptic.steps) {
      if (step.delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: step.delayMs));
        if (token != _token) return; // a newer cue took over mid-sequence
      }
      try {
        await _tap(step.weight);
      } on MissingPluginException {
        _unsupported = true;
        return;
      } catch (_) {
        // Never surfaced, never rethrown — same reasoning as the audio cue: a
        // haptic that did not fire has no failure the user can act on.
      }
    }
  }

  Future<void> _tap(HapticWeight weight) {
    switch (weight) {
      case HapticWeight.selection:
        return HapticFeedback.selectionClick();
      case HapticWeight.light:
        return HapticFeedback.lightImpact();
      case HapticWeight.medium:
        return HapticFeedback.mediumImpact();
      case HapticWeight.heavy:
        return HapticFeedback.heavyImpact();
    }
  }
}

final hapticsServiceProvider =
    Provider<HapticsService>(HapticsService.new);
