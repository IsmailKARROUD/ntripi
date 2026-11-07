// Cross-platform NSFW image pre-check — the fast/free client tier of the
// two-tier moderation pipeline (the backend image scan is the
// un-bypassable authority). This gives the user instant feedback and drops
// obvious NSFW uploads before they ever hit the network.
//
// The platform files only score a picture (conditional import, the same shape
// as api_connection_pool.dart):
//   - mobile/desktop → nsfw_precheck_io.dart   (tflite_flutter + bundled model)
//   - web            → nsfw_precheck_web.dart   (NSFWJS via JS interop)
// Both run the same network (GantMan MobileNetV2, 5 classes). This file is the
// one decision over its scores — thresholds and time budget — so a picture a
// phone refuses is refused on the web too.
//
// CONTRACT: isLikelyNsfw answers false on ANY failure (model missing, load
// error, inference error, unsupported platform) and when the model cannot
// answer within kNsfwPrecheckBudget. The pre-filter never blocks a legitimate
// upload, nor holds the picker — the backend is the source of truth.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:ntripi/core/moderation/nsfw_precheck_io.dart'
    if (dart.library.js_interop) 'package:ntripi/core/moderation/nsfw_precheck_web.dart'
    as platform;

/// One picture's scores from the model, each 0..1.
typedef NsfwScores = ({double porn, double hentai, double sexy});

/// A porn or hentai score above this refuses the picture.
const double kNsfwThreshold = 0.6;

/// A sexy score refuses only above this — the owner's tuning (9d57ebf).
const double kNsfwSexyThreshold = 0.999;

/// The longest the pre-check may hold the picker. The model loads in the
/// background when an upload screen opens; a pick made before it is ready (on
/// the web it is about 20 MB to download) goes on unchecked to the server's
/// scan rather than wait on a spinner.
const Duration kNsfwPrecheckBudget = Duration(seconds: 5);

/// Fire-and-forget model load; call when an upload UI mounts so the check is
/// ready by the time the user picks.
void warmUpNsfwPrecheck() => platform.warmUpNsfwModel();

/// True when [imageBytes] should be refused before it is uploaded.
Future<bool> isLikelyNsfw(Uint8List imageBytes) =>
    nsfwVerdict(platform.nsfwScores(imageBytes));

/// The decision over a scoring that may fail, never answer, or answer null.
@visibleForTesting
Future<bool> nsfwVerdict(
  Future<NsfwScores?> scoring, {
  Duration budget = kNsfwPrecheckBudget,
}) async {
  try {
    final scores = await scoring.timeout(budget, onTimeout: () => null);
    if (scores == null) return false;
    return scores.porn > kNsfwThreshold ||
        scores.hentai > kNsfwThreshold ||
        scores.sexy > kNsfwSexyThreshold;
  } catch (e) {
    // Any failure → allow the upload; the backend scan is authoritative.
    if (kDebugMode) debugPrint('NSFW pre-check errored (allowing): $e');
    return false;
  }
}
