// nsfw_glue.js — bridges Flutter web to NSFWJS without pulling TensorFlow.js
// into app boot. Exposes window.ntripiNsfw = { load(), classify(bytes) }.
//
// load()          lazily injects the vendored tf.min.js + nsfwjs.min.js and
//                 loads the local model — only on first call (when an upload
//                 UI mounts), so it never blocks the initial page load.
// classify(bytes) returns { porn, hentai } confidences (0..1). Resolves to null
//                 if the model isn't available, so the Dart side never-blocks.
//
// The heavy assets are NOT committed — drop them into web/nsfw/ per README.md.
// Until then load() rejects and classify() returns null (pre-check disabled).
(function () {
  'use strict';

  var _ready = null;
  var _model = null;

  function loadScript(src) {
    return new Promise(function (resolve, reject) {
      var s = document.createElement('script');
      s.src = src;
      s.onload = resolve;
      s.onerror = function () { reject(new Error('failed to load ' + src)); };
      document.head.appendChild(s);
    });
  }

  function load() {
    if (_ready) return _ready;
    _ready = (async function () {
      await loadScript('nsfw/tf.min.js');
      await loadScript('nsfw/nsfwjs.min.js');
      // Vendored MobileNetV2Mid graph model (model.json + shards).
      _model = await nsfwjs.load('nsfw/model/');
    })().catch(function (e) {
      // Leave _model null so classify() returns null (never-block).
      console.warn('[ntripiNsfw] model load failed; pre-check disabled:', e);
      _model = null;
    });
    return _ready;
  }

  function loadImage(url) {
    return new Promise(function (resolve, reject) {
      var img = new Image();
      img.onload = function () { resolve(img); };
      img.onerror = function () { reject(new Error('image decode failed')); };
      img.src = url;
    });
  }

  async function classify(bytes) {
    await load();
    if (!_model) return null;
    var url = URL.createObjectURL(new Blob([bytes]));
    try {
      var img = await loadImage(url);
      var preds = await _model.classify(img);
      var out = { porn: 0, hentai: 0 };
      preds.forEach(function (p) {
        if (p.className === 'Porn') out.porn = p.probability;
        else if (p.className === 'Hentai') out.hentai = p.probability;
      });
      return out;
    } catch (e) {
      console.warn('[ntripiNsfw] classify failed; allowing:', e);
      return null;
    } finally {
      // Free the decoded-image blob immediately (tensors are disposed by nsfwjs).
      URL.revokeObjectURL(url);
    }
  }

  window.ntripiNsfw = { load: load, classify: classify };
})();
