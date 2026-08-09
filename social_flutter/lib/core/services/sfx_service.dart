// core/services/sfx_service.dart — one-shot UI sound cues.
//
// One long-lived AudioPlayer behind a root provider. Every cue goes through
// play(), which is also where the user's on/off preference is read, so a new
// call site cannot forget to check it.
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

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/providers/sound_effects_enabled_provider.dart';

/// The cues the app can play. `path` is relative to `assets/` — see the header.
enum Sfx {
  openItinerary('SFX/Open_itinerary.wav');

  const Sfx(this.path);
  final String path;
}

// Below 1.0 so a cue sits under the app rather than announcing itself.
const _kCueVolume = 0.6;

// A cue must not behave like media playback.
//   iOS `ambient`: obeys the physical mute switch and never interrupts other
//     audio. It implies mixing, which is why no `mixWithOthers` option is set —
//     AudioContextIOS asserts that option is only legal with playback /
//     playAndRecord / multiRoute.
//   Android: no audio focus request at all, so a podcast or music app is not
//     paused or ducked for a 2-second sound.
final _cueContext = AudioContext(
  iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  android: const AudioContextAndroid(
    contentType: AndroidContentType.sonification,
    usageType: AndroidUsageType.assistanceSonification,
    audioFocus: AndroidAudioFocus.none,
  ),
);

class SfxService {
  SfxService(this._ref) {
    // stop, not release: keeps the prepared source around so a second play
    // does not re-copy the asset out of the bundle.
    _player.setReleaseMode(ReleaseMode.stop);
  }

  final Ref _ref;
  final AudioPlayer _player = AudioPlayer();
  bool _contextSet = false;

  Future<void> play(Sfx sfx) async {
    if (!_ref.read(soundEffectsEnabledProvider)) return;
    try {
      if (!_contextSet) {
        _contextSet = true; // set before awaiting so a fast re-entry can't double it
        await AudioPlayer.global.setAudioContext(_cueContext);
      }
      // Restart rather than no-op if the previous cue is still playing.
      await _player.stop();
      await _player.play(AssetSource(sfx.path), volume: _kCueVolume);
    } catch (_) {
      // Never surfaced, never rethrown. A decorative sound has no failure the
      // user can act on, and two of them are routine: browsers block autoplay
      // when a page is opened by deep link with no preceding gesture, and the
      // plugin is absent under `flutter test` (MissingPluginException).
    }
  }

  void dispose() => _player.dispose();
}

final sfxServiceProvider = Provider<SfxService>((ref) {
  final service = SfxService(ref);
  ref.onDispose(service.dispose);
  return service;
});
