# NSFW pre-check assets (web)

The client-side NSFW pre-check on **Flutter web** uses NSFWJS (TensorFlow.js),
bridged by `nsfw_glue.js` (committed). The heavy libraries and model weights are
**not committed** — drop them here to activate the web pre-check. Until then the
glue's `load()` fails gracefully and the pre-check is a no-op (never-block
contract in `lib/core/moderation/nsfw_precheck_web.dart`).

## Required files

```
web/nsfw/tf.min.js          # TensorFlow.js (UMD build)
web/nsfw/nsfwjs.min.js       # NSFWJS (UMD build)
web/nsfw/model/model.json    # MobileNetV2Mid graph model manifest
web/nsfw/model/*.bin         # model weight shards (~4.2 MB total)
```

## How to source them

```bash
cd web/nsfw
curl -L -o tf.min.js https://unpkg.com/@tensorflow/tfjs@3.21.0/dist/tf.min.js
curl -L -o nsfwjs.min.js https://unpkg.com/nsfwjs@2.4.2/dist/nsfwjs.min.js
# MobileNetV2Mid graph model (from the nsfwjs repo's example/nsfw_demo model):
#   https://github.com/infinitered/nsfwjs → models/mobilenet_v2_mid/
# Place model.json + the group1-shard*.bin files under web/nsfw/model/.
```

`nsfw_glue.js` calls `nsfwjs.load('nsfw/model/')`. If you use a different model
variant, adjust that path/options in `nsfw_glue.js`.

## Content-Security-Policy note

Everything is served same-origin from `web/nsfw/` — no CDN at runtime — so no CSP
changes are needed. Do **not** switch `nsfw_glue.js` back to a CDN URL.
