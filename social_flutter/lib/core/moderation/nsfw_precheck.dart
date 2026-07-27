// Cross-platform NSFW image pre-check — the fast/free client tier of the
// two-tier moderation pipeline (the backend AWS Rekognition scan is the
// un-bypassable authority). This gives the user instant feedback and drops
// obvious NSFW uploads before they ever hit the network.
//
// Platform split via conditional export (same shape as map_embed_web_view.dart):
//   - mobile/desktop → nsfw_precheck_io.dart   (tflite_flutter + bundled model)
//   - web            → nsfw_precheck_web.dart   (NSFWJS via JS interop)
//
// Both impls expose the same two functions:
//   void warmUpNsfwPrecheck()          — fire-and-forget model load; call when
//                                        an upload UI mounts so it never blocks.
//   Future<bool> isLikelyNsfw(bytes)   — true if porn/hentai confidence > 60%.
//
// CONTRACT: isLikelyNsfw MUST return false on ANY failure (model missing, load
// error, inference error, unsupported platform). The pre-filter never blocks a
// legitimate upload — the backend is the source of truth.
export 'nsfw_precheck_io.dart' if (dart.library.html) 'nsfw_precheck_web.dart';
