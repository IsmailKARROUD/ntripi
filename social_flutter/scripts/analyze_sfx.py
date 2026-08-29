#!/usr/bin/env python3
"""Derive the haptic tap patterns in lib/core/services/haptics_service.dart
from the waveforms in assets/SFX/.

Run from the Flutter project root:

    python3 scripts/analyze_sfx.py

and paste the printed `Haptic` enum members into haptics_service.dart. This
script never ships and never runs on a device — its whole output is twelve
numbers that end up as const enum data.

Why this exists: the tap patterns were originally guessed from what each cue is
called, and the guesses were wrong in kind. Open_itinerary.wav opens with 450 ms
of silence; New_notification.wav has exactly one onset, not two. Committing the
derivation makes the numbers auditable and re-derivable when a sound changes.

Pure stdlib on purpose — numpy is not installed on the dev machine, and audioop
was removed from Python in 3.13, so the PCM handling is hand-rolled below.
"""

import math
import os
import struct
import sys
import wave

SFX_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'SFX')

# Which enum member each asset feeds. Sfx.selection has no paired sound (it is
# the long-press acknowledgement) so nothing here derives it.
CUES = [
    ('Open_itinerary.wav', 'open'),
    ('fold-a-map.wav', 'fold'),
    ('Delete_itinerary.wav', 'delete'),
    ('New_notification.wav', 'arrival'),
]

WIN_S = 0.010          # RMS window
HOP_S = 0.005          # hop between windows
ONSET_HI = 0.25        # rising crossing of this (fraction of peak) opens an onset
ONSET_LO = 0.12        # falling below this re-arms the detector
ONSET_MIN_GAP_S = 0.060
PEAK_LOOKAHEAD_S = 0.040

SIGNIFICANT = 0.45     # onsets quieter than this are texture, not accents
MAX_TAPS = 3           # more than three reads as a buzz rather than an event
GAP_MS = 60            # perceptual floor for two taps to read as two

WEIGHTS = ['selection', 'light', 'medium', 'heavy']


def load_mono(path):
    """Return (samples, sample_rate) as a mono float list from a 16-bit PCM wav."""
    with wave.open(path, 'rb') as w:
        nch, sampwidth, rate, nframes = (
            w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes())
        raw = w.readframes(nframes)
    if sampwidth != 2:
        raise SystemExit('%s: expected 16-bit PCM, got %d-byte samples' % (path, sampwidth))
    s = struct.unpack('<%dh' % (len(raw) // 2), raw)
    if nch == 2:
        s = [(s[i] + s[i + 1]) * 0.5 for i in range(0, len(s), 2)]
    return list(s), rate


def envelope(samples, rate):
    """Per-window (level, brightness), level normalised to the file's peak.

    Brightness is the RMS of the first difference over the RMS of the signal — a
    crude high-pass ratio standing in for a spectral centroid. It needs no FFT
    and still separates the dull thud ending Delete_itinerary (0.05) from the
    bright tick of New_notification (1.44), which is the only distinction the
    weight mapping asks it to make.
    """
    win = max(1, int(rate * WIN_S))
    hop = max(1, int(rate * HOP_S))
    levels, brights = [], []
    for i in range(0, len(samples) - win, hop):
        seg = samples[i:i + win]
        rms = math.sqrt(sum(v * v for v in seg) / len(seg))
        diff = [seg[j + 1] - seg[j] for j in range(len(seg) - 1)]
        drms = math.sqrt(sum(v * v for v in diff) / len(diff)) if diff else 0.0
        levels.append(rms)
        brights.append((drms / rms) if rms > 1e-6 else 0.0)
    peak = max(levels) if levels else 1.0
    return [l / (peak or 1.0) for l in levels], brights, hop


def find_onsets(levels, brights, hop, rate):
    """Rising crossings of ONSET_HI, measured at the local max just after."""
    out, last_t, armed = [], -1e9, True
    step_s = hop / rate
    look = int(PEAK_LOOKAHEAD_S / step_s)
    for i, lv in enumerate(levels):
        t = i * step_s
        if armed and lv >= ONSET_HI and (t - last_t) >= ONSET_MIN_GAP_S:
            j = min(len(levels), i + look)
            k = max(range(i, j), key=lambda x: levels[x])
            out.append((t * 1000.0, levels[k], brights[k]))
            last_t, armed = t, False
        elif not armed and lv < ONSET_LO:
            armed = True
    return out


def weight_for(level, bright):
    """Loudness picks the tier; brightness shifts it one step.

    The four HapticFeedback presets differ in character as well as size —
    selection/light read as crisp, heavy reads as deep and dull — so a sharp
    onset goes one step lighter and a dull one goes one step heavier. That is
    the only way 'frequency' can land on a four-value scale: no platform exposes
    vibration frequency, and Android has no such API at all.
    """
    tier = 3 if level >= 0.75 else 2 if level >= 0.50 else 1 if level >= 0.30 else 0
    if bright >= 0.90:
        tier -= 1
    elif bright < 0.35:
        tier += 1
    return WEIGHTS[max(0, min(3, tier))]


def sparkline(samples, rate, cell_s=0.05):
    bars = ' .:-=+*#%@'
    hop = max(1, int(rate * cell_s))
    rows = []
    for i in range(0, len(samples) - hop, hop):
        seg = samples[i:i + hop]
        rows.append(math.sqrt(sum(v * v for v in seg) / len(seg)))
    peak = max(rows) if rows else 1.0
    return ''.join(bars[min(9, int(r / (peak or 1.0) * 9.99))] for r in rows)


def main():
    dart = []
    for fname, cue in CUES:
        path = os.path.join(SFX_DIR, fname)
        if not os.path.exists(path):
            raise SystemExit('missing asset: %s' % path)
        samples, rate = load_mono(path)
        levels, brights, hop = envelope(samples, rate)
        onsets = find_onsets(levels, brights, hop, rate)

        print('=== %s  (%.2f s, %d Hz)' % (fname, len(samples) / rate, rate))
        print('    |%s|  (each char = 50 ms)' % sparkline(samples, rate))
        for t, lv, br in onsets:
            mark = '*' if lv >= SIGNIFICANT else ' '
            print('  %s %7.0f ms  level=%.2f  bright=%.2f  -> %s'
                  % (mark, t, lv, br, weight_for(lv, br)))

        # the strongest few accents, restored to the order they occur in
        picked = [o for o in onsets if o[1] >= SIGNIFICANT]
        picked = sorted(sorted(picked, key=lambda o: -o[1])[:MAX_TAPS], key=lambda o: o[0])
        if not picked:
            raise SystemExit('%s: no onset above %.2f — lower SIGNIFICANT' % (fname, SIGNIFICANT))

        steps = ['HapticStep(HapticWeight.%s, %d)' % (weight_for(lv, br), 0 if i == 0 else GAP_MS)
                 for i, (t, lv, br) in enumerate(picked)]
        print('    -> %d tap(s)\n' % len(steps))
        if len(steps) == 1:
            dart.append('  %s([%s]),' % (cue, steps[0]))
        else:
            dart.append('  %s([\n%s\n  ]),' % (cue, '\n'.join('    %s,' % s for s in steps)))

    print('--- paste into the Haptic enum in lib/core/services/haptics_service.dart ---')
    print('\n'.join(dart))
    return 0


if __name__ == '__main__':
    sys.exit(main())
