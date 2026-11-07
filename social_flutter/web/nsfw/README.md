# NSFW pre-check assets (web)

The client-side NSFW pre-check on **Flutter web** uses NSFWJS (TensorFlow.js),
bridged by `nsfw_glue.js`. Everything it loads is committed here and served
same-origin. The decision over the scores (thresholds, time budget) is the
Dart side's, shared with the phones: `lib/core/moderation/nsfw_precheck.dart`.

## Files

```
web/nsfw/nsfw_glue.js        # the bridge: window.ntripiNsfw = { load, classify }
web/nsfw/nsfwjs.min.js       # NSFWJS UMD build — carries its own TensorFlow.js (3.7.0)
web/nsfw/model/model.json    # GantMan MobileNetV2 (224×224, 5 classes), a *graph* model
web/nsfw/model/*.bin         # its weight shards (~17 MB, float32)
```

It is the same network as the phones' `assets/models/nsfw_mobilenet.tflite`, so
both platforms score a picture alike.

## The model is a graph model

`model.json` says `"format": "graph-model"`, so the glue must load it with
`nsfwjs.load('nsfw/model/', { type: 'graph' })`. Without `type: 'graph'` NSFWJS
reads it as a layers model, the load throws ("Improper config format"), and the
pre-check is silently off — which is how the web shipped until 2026-11-07.
`test/core/moderation/nsfw_web_assets_test.dart` fails if the two disagree.

## No separate TensorFlow.js

`nsfwjs.min.js` bundles TensorFlow.js. Loading `tf.min.js` as well registered
every backend and kernel twice (hundreds of console warnings) and cost a 1.3 MB
download; it was removed on 2026-11-07. Do not add it back.

## Content-Security-Policy note

Everything is served same-origin from `web/nsfw/` — no CDN at runtime — so no CSP
changes are needed. Do **not** switch `nsfw_glue.js` to a CDN URL.
