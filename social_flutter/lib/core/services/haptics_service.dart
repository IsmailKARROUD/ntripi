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
/// Every pattern below is derived from the waveform of the sound it is paired
/// with in Sfx, by `scripts/analyze_sfx.py` — re-run it to retune, and after
/// swapping any asset in assets/SFX/. How many taps and how hard each lands
/// come from the analysis; *when* they land does not. The taps fire as a short
/// burst at the head of the cue rather than at the accents' real times, because
/// those times are useless: Open_itinerary.wav opens with 450 ms of silence and
/// Delete_itinerary.wav saves its loudest moment for 2913 ms, long after the
/// trip is gone.
///
/// The 60 ms spacing is the perceptual floor — closer together and two taps
/// smear into one buzz.
enum Haptic {
  /// A bare acknowledgement with no sound: the long-press affordance. The only
  /// member the analysis does not derive, because nothing is playing.
  selection([HapticStep(HapticWeight.selection, 0)]),

  /// A trip opening — loud and low, so it lands as weight rather than detail.
  /// The first to revisit if it feels heavy: that sound is both loud and dull,
  /// and the dull-brightness rule pushes every tier up a step.
  open([
    // PHASE 1: Initial Tug & First Flap (0ms - 450ms)
    // Breaking the primary fold open.
    HapticStep(HapticWeight.medium, 50),
    HapticStep(HapticWeight.light, 100),
    HapticStep(HapticWeight.light, 300), // Pause: map swings open in hands

    // PHASE 2: Main Unfold & Center Creases (450ms - 1400ms)
    // Rapid burst of panel flips and paper friction.
    HapticStep(HapticWeight.light, 40),
    HapticStep(HapticWeight.light, 30),
    HapticStep(HapticWeight.medium, 120), // Heavy center crease popping
    HapticStep(HapticWeight.light, 60),
    HapticStep(HapticWeight.light, 200), // Pause: hand repositions on edges
    HapticStep(HapticWeight.medium, 80),
    HapticStep(HapticWeight.light, 40),
    HapticStep(HapticWeight.light, 50),
    HapticStep(HapticWeight.medium, 330), // Lull: pulling the last corner open

    // PHASE 3: Flattening & Snap Taut (1400ms - 2000ms)
    // Smoothing out the paper and locking it flat.
    HapticStep(HapticWeight.light, 40),
    HapticStep(HapticWeight.light, 60),
    HapticStep(HapticWeight.light, 150),
    HapticStep(HapticWeight.medium, 350), // Tension building as it reaches full extension
    HapticStep(HapticWeight.heavy, 0),    // Final taut snap (2000ms mark)
  ]),

  /// Folding closed — the thump, then the two bright crinkles after it.
  fold([
  // PHASE 1: Initial Swing & Collapse (0.0s – 0.25s)
  // Gathering the open panels inward. Light sliding surface friction.
  HapticStep(HapticWeight.light, 100),
  HapticStep(HapticWeight.medium, 150),  // First wide crease swinging shut

  // PHASE 2: Multi-Layer Stack Compression (0.25s – 0.70s)
  // Rapid micro-bursts as multiple accordion folds trap air and slap together
  HapticStep(HapticWeight.light, 50),
  HapticStep(HapticWeight.light, 60),
  HapticStep(HapticWeight.medium, 100),  // Center stack catching
  HapticStep(HapticWeight.light, 40),
  HapticStep(HapticWeight.medium, 200),  // Pause as hands press the stack flat

  // PHASE 3: The Final Fold & Slap Shut (0.70s – 1.04s)
  // The final half-fold that locks the map into its compact rectangle
  HapticStep(HapticWeight.medium, 140),  // Edges aligning
  HapticStep(HapticWeight.heavy, 200),   // Final firm press locking the stack shut
]),

  /// Two light crinkles and the dull thud that ends the sound (brightness 0.05,
  /// the deepest onset in any of the four assets).
  delete([
    HapticStep(HapticWeight.light, 0),
    HapticStep(HapticWeight.light, 120),
    HapticStep(HapticWeight.heavy, 120),
  ]),

  /// One bright tick — the sound has exactly one onset, so the cue has one tap.
  arrival([HapticStep(HapticWeight.medium, 0)]);

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
