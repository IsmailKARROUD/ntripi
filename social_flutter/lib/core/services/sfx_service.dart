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

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/providers/sound_effects_enabled_provider.dart';
import 'package:social_flutter/core/services/haptics_service.dart';

/// The cues the app can play. `path` is relative to `assets/` — see the header.
/// `haptic` is the tap pattern timed to that sound; both fire from [play].
enum Sfx {
  openItinerary('SFX/Open_itinerary.wav', Haptic.open),
  closeItinerary('SFX/fold-a-map.wav', Haptic.fold),
  deleteItinerary('SFX/Delete_itinerary.wav', Haptic.delete),
  newNotification('SFX/New_notification.wav', Haptic.arrival);

  const Sfx(this.path, this.haptic);
  final String path;
  final Haptic haptic;
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
  SfxService(this._ref) {
    // stop, not release: keeps the prepared source around so a second play
    // does not re-copy the asset out of the bundle.
    _player.setReleaseMode(ReleaseMode.stop);
  }

  final Ref _ref;
  final AudioPlayer _player = AudioPlayer();
  bool _contextSet = false;

  Future<void> play(Sfx sfx) async {
    // First, and synchronously: the audio path below awaits a stop() and a
    // decode, so firing the tap after them would land it late enough to read as
    // a second, separate event. Above the sound gate too, because a muted app
    // is exactly when the tap is the only feedback left — fire() reads its own
    // preference, so the two channels stay independently switchable.
    _ref.read(hapticsServiceProvider).fire(sfx.haptic);
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
