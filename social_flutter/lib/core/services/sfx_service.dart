// core/services/sfx_service.dart — one-shot UI cues.
//
// A cue is two channels, sound and haptic, and play() is the single door to
// both. Each channel reads its own preference behind that door (the sound gate
// is here, the haptic gate is inside HapticsService.fire), so a call site can
// neither forget a check nor let the two drift apart.
//
// One long-lived AudioPlayer behind a root provider carries the audio half.
//
// Two things here are load-bearing and easy to get wrong:
//
//   Asset paths drop the `assets/` prefix. AudioCache prepends it (its default
//   `prefix` is 'assets/'), so `assets/SFX/Open_itinerary.wav` is addressed as
//   'SFX/Open_itinerary.wav'. Getting this wrong fails silently.
//
//   The default AudioContext is wrong for a cue. audioplayers defaults to iOS
//   `playback` + Android audio-focus `gain` — media settings, which ignore the
//   ring/silent switch and stop whatever the user is listening to. _cueContext
//   below asks for the opposite on both platforms.
//
//   A cold cue is a broken cue, and on Android it goes cold again and again.
//   The output enters standby after a few seconds of silence, and reopening it
//   swallows the first 100-200 ms — which is the whole of a 136 ms cue, so it
//   reads as silence rather than as a quiet start. MediaPlayer cannot win that
//   race; SoundPool (PlayerMode.lowLatency) is Android's answer for short UI
//   sounds and is what the `lowLatency` cues below are routed to. warmUp() does
//   the rest of the one-time setup at splash.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/providers/sound_effects_enabled_provider.dart';
import 'package:social_flutter/core/services/haptics_service.dart';

/// The cues the app can play. `path` is relative to `assets/` — see the header.
/// `haptic` is the tap pattern timed to that sound; both fire from [play].
/// `lowLatency` marks a cue short enough to be lost inside Android's audio-output
/// cold start — see the header. Those get a SoundPool player each; the rest run
/// on the shared MediaPlayer one, where seconds of audio make the same gap
/// imperceptible and SoundPool's short-sample brief does not fit.
enum Sfx {
  openItinerary('SFX/Open_itinerary.wav', Haptic.open),
  closeItinerary('SFX/fold-a-map.wav', Haptic.fold),
  deleteItinerary('SFX/Delete_itinerary.wav', Haptic.delete),
  // 840 ms, and its one onset is at 90 ms — inside the gap, like toggle's.
  newNotification('SFX/New_notification.wav', Haptic.arrival, lowLatency: true),
  // Every switch in the app, either direction — fired through toggleFeedback in
  // core/ui/toggle_feedback.dart, which is also where the one rule a call site
  // can get wrong (write the preference first) is written down. Paired with the
  // acknowledgement tap rather than a pattern derived from this waveform: a
  // settings row can be flipped ten times in a row, and its own full-scale onset
  // would derive a heavy thud each time.
  toggle('SFX/Turn_on_SFX.wav', Haptic.selection, lowLatency: true);

  const Sfx(this.path, this.haptic, {this.lowLatency = false});
  final String path;
  final Haptic haptic;
  final bool lowLatency;
}

// Full scale. The asset is mastered well below 0 dBFS, so anything less than
// 1.0 here is inaudible over ambient noise — trim the file, not this number.
const _kCueVolume = 1.0;

// A cue must not *interrupt*, but it must still be audible.
//   iOS `ambient`: obeys the physical mute switch and never interrupts other
//     audio. It implies mixing, which is why no `mixWithOthers` option is set —
//     AudioContextIOS asserts that option is only legal with playback /
//     playAndRecord / multiRoute.
//   Android: media usage/content so the cue rides the media volume the user
//     actually adjusts in-app. The sonification usage types route to
//     STREAM_SYSTEM, which is separately (and usually lower) capped — that is
//     an inaudible cue, not a polite one. Not interrupting comes from
//     audioFocus.none, which asks for no focus at all, so a podcast or music
//     app is never paused or ducked for a 2-second sound.
final _cueContext = AudioContext(
  iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  android: const AudioContextAndroid(
    contentType: AndroidContentType.music,
    usageType: AndroidUsageType.media,
    audioFocus: AndroidAudioFocus.none,
  ),
);

class SfxService {
  SfxService(this._ref);

  final Ref _ref;

  /// The long cues, on the default MediaPlayer engine.
  final AudioPlayer _media = AudioPlayer();

  /// One SoundPool player per short cue, and one *each* deliberately: the
  /// plugin's UrlSource.setForSoundPool releases the player before taking a new
  /// source, which unloads the sample it was holding — so a shared low-latency
  /// player would reload from disk every time two short cues alternated.
  final Map<Sfx, AudioPlayer> _lowLatency = {};

  AudioPlayer _playerFor(Sfx sfx) => _lowLatency[sfx] ?? _media;

  /// The one-time engine setup, held so concurrent callers share one attempt.
  Future<void>? _ready;

  /// Does the setup a cue would otherwise pay for at the instant it is meant to
  /// be heard: the plugin's global init, the audio-session category, extracting
  /// the assets out of the bundle, and loading each short cue's SoundPool
  /// sample. Called once from the splash screen, out of the same brand-flash
  /// budget it already spends warming the access token.
  ///
  /// It does not fix the Android standby gap in the header — nothing done ahead
  /// of time can, since the output goes cold again after a few seconds of
  /// silence. That is what the lowLatency routing is for.
  ///
  /// Fire-and-forget by contract: never awaited by its caller and never throws,
  /// for the same reason play() swallows — a cue that could not be prepared has
  /// no failure the user can act on, and play() will retry the setup anyway.
  ///
  /// Deliberately NOT gated on the sound preference. Turning sound on plays a
  /// cue in the same breath, so a warm-up that waited for the preference would
  /// leave exactly that cue cold.
  Future<void> warmUp() async {
    try {
      await _ensureReady();
    } catch (_) {}
  }

  Future<void> _ensureReady() async {
    final pending = _ready;
    if (pending != null) return pending;
    final started = _prepareEngine();
    _ready = started;
    try {
      await started;
    } catch (_) {
      // Never cache a failed attempt — one bad launch would mute the whole
      // session. The next cue starts the setup again.
      _ready = null;
      rethrow;
    }
  }

  Future<void> _prepareEngine() async {
    await AudioPlayer.global.setAudioContext(_cueContext);
    // stop, not release: keeps the prepared source around so a second play does
    // not re-copy the asset out of the bundle.
    await _media.setReleaseMode(ReleaseMode.stop);
    // Copies each cue out of the bundle into the temp file the native side
    // reads. Skipped on web, where "loading" is an HTTP GET per file and the
    // cues total ~1.3 MB nobody has asked for yet.
    if (!kIsWeb) {
      await AudioCache.instance.loadAll([for (final s in Sfx.values) s.path]);
    }
    for (final sfx in Sfx.values.where((s) => s.lowLatency)) {
      // Kept in the map before it is configured, so a retry after a failed
      // setup reuses this player instead of stranding it undisposed.
      final player = _lowLatency[sfx] ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      // Before the source: the mode setter recreates the native player, which
      // would throw away a sample already loaded.
      await player.setPlayerMode(PlayerMode.lowLatency);
      // Loads the sample into the SoundPool ahead of the first tap. A no-op on
      // iOS and web, where setPlayerMode is explicitly ignored.
      await player.setSource(AssetSource(sfx.path));
    }
  }

  Future<void> play(Sfx sfx) async {
    // First, and synchronously: the audio path below awaits a stop() and a
    // decode, so firing the tap after them would land it late enough to read as
    // a second, separate event. Above the sound gate too, because a muted app
    // is exactly when the tap is the only feedback left — fire() reads its own
    // preference, so the two channels stay independently switchable.
    _ref.read(hapticsServiceProvider).fire(sfx.haptic);
    if (!_ref.read(soundEffectsEnabledProvider)) return;
    try {
      // Normally already settled from splash, so this costs a microtask.
      await _ensureReady();
      final player = _playerFor(sfx);
      // Restart rather than no-op if the previous cue is still playing — and on
      // a SoundPool player this is load-bearing rather than polish: stop() is
      // what clears the finished streamId, and start() only opens a new stream
      // when there is none, so without it every cue after the first is silent.
      await player.stop();
      await player.play(AssetSource(sfx.path), volume: _kCueVolume);
    } catch (_) {
      // Never surfaced, never rethrown. A decorative sound has no failure the
      // user can act on, and two of them are routine: browsers block autoplay
      // when a page is opened by deep link with no preceding gesture, and the
      // plugin is absent under `flutter test` (MissingPluginException).
    }
  }

  void dispose() {
    _media.dispose();
    for (final player in _lowLatency.values) {
      player.dispose();
    }
  }
}

final sfxServiceProvider = Provider<SfxService>((ref) {
  final service = SfxService(ref);
  ref.onDispose(service.dispose);
  return service;
});
