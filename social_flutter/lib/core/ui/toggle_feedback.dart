// core/ui/toggle_feedback.dart — the acknowledgement every switch gives.
//
// One function so a flip feels the same wherever it happens: the settings sheet,
// the notification preferences, the private-account row, the "this stop is free"
// field in a form. Direction does not matter — turning a switch off acknowledges
// exactly as turning it on does.
//
// It is a single line because SfxService.play is already the single door to both
// channels: it fires the paired haptic first (gated inside HapticsService.fire on
// hapticsEnabledProvider) and then gates the audio on soundEffectsEnabledProvider.
// Nothing here re-implements either gate, so sound and haptics stay independently
// switchable and a silenced app still taps.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/services/sfx_service.dart';

/// Acknowledges a switch flip with the toggle cue: a sound if sound cues are on,
/// a selection tap if haptics are, both if both, and nothing if neither.
///
/// Call it *after* the flip has been written, never before. play() reads the very
/// preferences it is confirming, and the two preference switches are their own
/// subject: called first, the sound switch would announce its own silencing and
/// then stay mute when switched back on, and the haptics switch would buzz to
/// confirm you had just stopped it buzzing. Called after, both fall out right —
/// setEnabled assigns `state` synchronously ahead of its first await, so the value
/// read here is already the new one.
///
/// Unawaited because a decorative cue must never hold up the switch repainting.
void toggleFeedback(WidgetRef ref) =>
    unawaited(ref.read(sfxServiceProvider).play(Sfx.toggle));
