import time
from io import BytesIO
from typing import TYPE_CHECKING, Callable

from PIL import Image
from PIL.Image import Resampling

from app.services import moderation_service
from app.storage.factory import storage

if TYPE_CHECKING:
    from app.services.moderation_service import ModerationContext

ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP"}
TARGET_WIDTH = 1200
TARGET_HEIGHT = 630
AVATAR_SIZE = 800  # square; rendered inside a circle on the client
MIN_DIMENSION = 600
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10 MB


class ImageProcessingError(Exception):
    pass


def _decode_and_validate(raw_bytes: bytes) -> Image.Image:
    """Reject oversized/undersized/unsupported uploads and return an RGB image.

    Shared front-half of the cover and avatar pipelines: size guard, decode,
    format check, minimum-dimension check, and RGB conversion (handles RGBA,
    palette-mode PNGs, etc.). Raises ImageProcessingError with a user-readable
    message on any failure.
    """
    if len(raw_bytes) > MAX_FILE_SIZE:
        raise ImageProcessingError(
            f"Image exceeds {MAX_FILE_SIZE // (1024 * 1024)} MB limit."
        )

    try:
        img = Image.open(BytesIO(raw_bytes))
    except Exception as exc:
        raise ImageProcessingError(f"Could not read image: {exc}") from exc

    if img.format not in ALLOWED_FORMATS:
        raise ImageProcessingError(
            f"Unsupported format '{img.format}'. Upload a JPEG, PNG, or WebP file."
        )

    if img.width < MIN_DIMENSION or img.height < MIN_DIMENSION:
        raise ImageProcessingError(
            f"Image too small ({img.width}×{img.height}). "
            f"Minimum size is {MIN_DIMENSION}×{MIN_DIMENSION}."
        )

    if img.mode != "RGB":
        img = img.convert("RGB")

    return img


def _encode_jpeg(img: Image.Image) -> bytes:
    buf = BytesIO()
    # save() with format="JPEG" never copies source EXIF — EXIF stripping
    # is implicit because we're constructing a new Image object in memory.
    img.save(buf, format="JPEG", quality=85, optimize=True)
    return buf.getvalue()


def process_cover_image(raw_bytes: bytes) -> bytes:
    """Validate, resize, strip EXIF, and re-encode a cover image as JPEG.

    Processing steps:
      1. Reject files over 10 MB.
      2. Validate format is JPEG, PNG, or WebP.
      3. Reject images smaller than 600×600 (too low-res for OG preview).
      4. Convert to RGB (handles RGBA, palette-mode PNGs, etc.).
      5. Cover-crop to the 1200:630 aspect ratio.
      6. Resize to exactly 1200×630.
      7. Save as JPEG quality=85 — re-encoding strips all EXIF metadata,
         including GPS coordinates embedded by phone cameras (privacy).

    Raises ImageProcessingError with a user-readable message on any failure.
    Returns processed JPEG bytes.
    """
    img = _decode_and_validate(raw_bytes)
    img = _crop_to_aspect(img, TARGET_WIDTH, TARGET_HEIGHT)
    img = img.resize((TARGET_WIDTH, TARGET_HEIGHT), Resampling.LANCZOS)
    return _encode_jpeg(img)


def process_avatar_image(raw_bytes: bytes) -> bytes:
    """Validate, resize, strip EXIF, and re-encode an avatar image as JPEG.

    Identical pipeline to process_cover_image but produces a square 800×800
    image — avatars render inside a circular ClipOval on the client, so the
    client's square crop must be preserved end-to-end.
    """
    img = _decode_and_validate(raw_bytes)
    img = _crop_to_aspect(img, AVATAR_SIZE, AVATAR_SIZE)
    img = img.resize((AVATAR_SIZE, AVATAR_SIZE), Resampling.LANCZOS)
    return _encode_jpeg(img)


async def process_and_store(raw_bytes: bytes, key: str,
                            processor: Callable[[bytes], bytes], *,
                            cache_bust: bool,
                            moderation: "ModerationContext | None" = None) -> str:
    """Process an upload through `processor` and store it under `key`.

    `processor` (process_cover_image / process_avatar_image) raises
    ImageProcessingError on a bad upload — the router translates that to 400.
    When cache_bust is set, a `?v=<ms>` suffix busts every URL-keyed cache
    (CachedNetworkImage, browser, CDN) since storage keys are stable per user.

    When a ModerationContext is passed, the processed bytes are scanned before
    storage — a hard-reject raises ModerationRejectedError (router → 422) so the
    rejected image is never written. Omitting it (or moderation being disabled)
    stores the image exactly as before.
    """
    processed = processor(raw_bytes)
    if moderation is not None:
        # Scan sits after Pillow processing, before storage — rejected bytes
        # are never persisted.
        await moderation_service.moderate_or_raise(processed, moderation)
    url = await storage().save(key, processed, "image/jpeg")
    if cache_bust:
        url = f"{url}?v={int(time.time() * 1000)}"
    return url


def _crop_to_aspect(img: Image.Image, target_w: int, target_h: int) -> Image.Image:
    """Crop to match target aspect ratio (cover behaviour — no letterboxing)."""
    target_ratio = target_w / target_h
    src_ratio = img.width / img.height

    if abs(src_ratio - target_ratio) < 0.01:
        return img

    if src_ratio > target_ratio:
        # Source is wider than target — crop left and right sides equally.
        new_w = int(img.height * target_ratio)
        offset = (img.width - new_w) // 2
        return img.crop((offset, 0, offset + new_w, img.height))
    else:
        # Source is taller than target — crop top and bottom equally.
        new_h = int(img.width / target_ratio)
        offset = (img.height - new_h) // 2
        return img.crop((0, offset, img.width, offset + new_h))
