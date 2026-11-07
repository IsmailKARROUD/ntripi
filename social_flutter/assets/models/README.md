# NSFW pre-check model (mobile)

The client-side NSFW pre-check on **iOS/Android** loads a TensorFlow Lite model
from this directory. The model is **committed** (`nsfw_mobilenet.tflite`,
~17 MB, since 2026-07-28). If it fails to load, the mobile pre-check is a no-op —
every image is allowed through to the backend image scan, which is the actual
authority (never-block contract in `lib/core/moderation/nsfw_precheck.dart`).

The web runs the same network as a TensorFlow.js graph model
(`web/nsfw/model/`), and both platforms' scores go through one decision —
thresholds and time budget — in `lib/core/moderation/nsfw_precheck.dart`.

## File

```
assets/models/nsfw_mobilenet.tflite
```

## Where it comes from

The GantMan `nsfw_model` MobileNetV2 model (5 classes, 224×224 input):

- Prebuilt/community TFLite export of https://github.com/GantMan/nsfw_model, **or**
- Convert the Keras `nsfw.299x299.h5` / MobileNetV2 SavedModel to TFLite:

  ```python
  import tensorflow as tf
  m = tf.keras.models.load_model("nsfw_mobilenet2.224x224.h5")
  open("nsfw_mobilenet.tflite", "wb").write(
      tf.lite.TFLiteConverter.from_keras_model(m).convert()
  )
  ```

## Contract the model must satisfy

The Dart preprocessing in `nsfw_precheck_io.dart` assumes:

- **Input:** `[1, 224, 224, 3]` float32, RGB, normalized to `0..1` (`/255`).
- **Output:** `[1, 5]` softmax over the alphabetical classes
  `drawings, hentai, neutral, porn, sexy` (indices 0–4).

If a replacement model differs (e.g. 299×299 input, `-1..1` normalization,
different class order), update the constants in `nsfw_precheck_io.dart`
accordingly — and replace the web's model too, so both platforms still score a
picture alike — then verify on a device before shipping.
