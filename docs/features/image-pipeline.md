# Image pipeline and storage

**Status:** shipped
**Tables:** none (writes URLs onto `itineraries`, `users`, `bug_reports`)
**Config:** `STORAGE_BACKEND`, `STORAGE_FILESYSTEM_PATH`, `STORAGE_PUBLIC_URL_PREFIX`, `R2_*`

## Purpose

Every image upload in the app goes through one function. It decodes and validates
the file, resizes and crops it, **strips EXIF**, re-encodes as JPEG, optionally
scans it, and writes it to whichever storage backend is configured. Calling code
never touches a filesystem path or an S3 client.

## Rules

### `process_and_store` — the single entry point

`image_service.process_and_store(raw, key, processor, *, cache_bust, moderation=None)`
(`image_service.py:126`). Order inside it is load-bearing:

1. **`await asyncio.to_thread(processor, raw_bytes)`** — Pillow decode + resize +
   encode is pure CPU, and `process_and_store` always runs on the event loop —
   awaited by an `async` endpoint, or handed there by a sync one through
   `anyio.from_thread.run` — so a large phone photo would block the loop for
   every other in-flight request. **Never call a `process_*_image` function
   directly from an `async def`.**
2. **Scan, if a `ModerationContext` was passed** — *after* processing, *before*
   storage, so rejected bytes are never persisted.
3. `await storage().save(key, processed, "image/jpeg")`.
4. Append `?v=<epoch_ms>` **if `cache_bust`**.

### The three processors

| Processor | Output | Min input | Used by |
|---|---|---|---|
| `process_cover_image` | 1200×630 cover-crop JPEG | 600 px | itinerary covers, user cover images |
| `process_avatar_image` | 800×800 square cover-crop JPEG | 600 px | avatars |
| `process_screenshot_image` | aspect preserved, longest side ≤1600 | **200 px** | bug-report screenshots |

- `ALLOWED_FORMATS = {JPEG, PNG, WEBP}`; `MAX_FILE_SIZE = 10 MB`.
- Cropping is **cover behaviour, no letterboxing** (`_crop_to_aspect`).
- **EXIF is always stripped** — including GPS — by the re-encode. There is no
  path that stores an original file.
- **A bug-report screenshot must not use the cover/avatar processors**: they
  cover-crop (destroying a portrait capture) and reject anything under 600 px.
  `process_screenshot_image` relaxes the floor via
  `_decode_and_validate(min_dimension=…)`.
- `ImageProcessingError` → the router answers **400** with an **untranslated
  English message**.

### `cache_bust`, and why it differs

`True` for **user avatar and cover** — their storage keys are stable
(`avatars/{user_id}.jpg`, `covers/{user_id}.jpg`), so without `?v=` a replaced
image would keep being served from `CachedNetworkImage`, the browser and the CDN.
`False` for **itinerary covers**, which never carried a `?v=`.

### Storage abstraction

`app/storage/base.py` defines `Storage`: `save`, `read`, `delete`, `public_url`,
`exists`. **Calling code uses `storage().save()` / `.delete()` only.**

- **`storage()` is `@lru_cache(maxsize=1)` and is called eagerly at startup**
  (`main.py:314`), so a misconfiguration surfaces on boot rather than on the
  first upload.
- **`STORAGE_BACKEND=r2` with any `R2_*` var missing raises `ValueError`**
  (`factory.py:31`) rather than falling back. Silently writing to a filesystem
  path production no longer serves would strand every upload **and** take the
  images out from behind Cloudflare, where the CSAM scan happens.
- An unknown `STORAGE_BACKEND` also raises.
- **An `R2_PUBLIC_URL` containing `.r2.dev` logs a warning**
  (`factory.py:56`): *"traffic bypasses Cloudflare, so CSAM scanning does not
  run. Use a proxied custom domain."* This is a documented compliance hole, not
  an error.
- **R2**: all boto3 I/O via `asyncio.to_thread`; uploads carry
  `CacheControl: public, max-age=3600`; `read()` returns `None` on 404 /
  `NoSuchKey` and re-raises anything else.
- **Filesystem**: `public_url` returns a **relative** `/uploads/…` path — which
  is why `share_service.absolute_storage_url` exists for anything leaving the
  site (emails, Jira tickets, OG crawlers). R2 URLs are already absolute and
  pass through.
- The `/uploads` mount only exists when `STORAGE_BACKEND == "filesystem"`
  (`main.py:303`). The filesystem backend needs a persistent volume at
  `/app/uploads` or images vanish on redeploy.

### Deterministic keys

| Key pattern | Owner |
|---|---|
| `avatars/{user_id}.jpg` | user avatar |
| `covers/{user_id}.jpg` | user cover image |
| itinerary cover key | itinerary cover |
| `bug_reports/{report_id}.jpg` | bug-report screenshot |

`admin_service.parse_storage_key` normalises whatever an operator pastes (full
URL, bare key, `/uploads/` prefix, `?v=` suffix) against the **three
deterministic content patterns** and **refuses anything it does not recognise** —
guessing could suspend an unrelated account. Bug-report screenshots are
deliberately outside that set, which is one reason `screenshot_key` stores a key
rather than a URL.

### Sync and async upload endpoints

**A sync `def` can take an upload.** FastAPI reads and parses the multipart body
before it calls the endpoint, so an `UploadFile` parameter arrives with its
bytes already in a spooled temporary file, and `file.file.read()` is a plain
blocking read on the endpoint's worker thread. Only a handler that parses the
body itself, with `await request.form()`, needs to be `async`. The two form
routes (`POST /itineraries/form`, `PATCH /itineraries/{id}/form`) are therefore
sync, like every other text write, and reach `process_and_store` with
`anyio.from_thread.run(functools.partial(...))` — `from_thread.run` passes no
keyword arguments. The coroutine runs on the event loop while the worker
thread waits; anyio copies the worker's context into it, so the request-timing
record still collects its database and outbound time.

The older upload endpoints — `POST /itineraries/{id}/image`, the avatar, the
profile cover and the bug-report intake — are `async def` because they await the
pipeline directly, not because a sync `def` could not read their body; they are
left as they are. They run sync SQLAlchemy on the loop for a local round trip.
So does the scan inside `process_and_store` on every path, sync routes included:
`moderate_or_raise` writes its audit row, and on a reject commits, from the
loop. **What must stay off the loop is the CPU work**, which `process_and_store`
hands to `asyncio.to_thread`, and the blocking calls: the scan's provider
request and the operator emails it sends (`send_email` is a `requests.post`
with a 10 s timeout) go there too.

## API surface

Seven image endpoints; every one that takes a file takes it as multipart:

| Method | Path | Auth | File part | Processor | `cache_bust` | Scanned |
|---|---|---|---|---|---|---|
| POST | `/itineraries/form` | verified email | `image` (required) | cover | false | yes |
| PATCH | `/itineraries/{id}/form` | `require_edit_access`; the cover parts owner only | `image` (optional) | cover | false | yes |
| POST | `/itineraries/{id}/image` | **owner only** | `file` | cover | false | yes |
| DELETE | `/itineraries/{id}/image` | owner only | — | — | — | — |
| POST | `/users/me/avatar` | Bearer, 10/min | `file` | avatar | true | yes |
| POST | `/users/me/cover-image` | Bearer, 10/min | `file` | cover | true | yes |
| POST | `/bug-reports` | **optional** | screenshot | screenshot | false | **no** |

Errors: **400** (uncoded) `ImageProcessingError`, **422
`image_moderation_rejected`**.

The cover image is **owner-only, not editor-writable** — it is the trip's public
face, and every upload spends a paid Rekognition scan.

**The app changes an itinerary cover only through the form routes**, which carry
it with the form's fields under the edit lock and `If-Match`
([itineraries.md](itineraries.md)). `POST` and `DELETE /itineraries/{id}/image`
take neither and move `updated_at` when they change the row, so the PATCH the
form used to send after them was refused as stale. They stay, unchanged, for
builds already installed, and go once no build in testing calls them
([backlog.md](../backlog.md)).

## Flutter surface

- **`cover_image_field.dart`** — the picker plus `openImageCropOverlay`, which
  inserts into `Navigator.of(context, rootNavigator: true).overlay`, **not**
  `Overlay.of(context, rootOverlay: true)`. The latter is `BetterFeedback`'s
  overlay, outside `MaterialApp` — see [bug-reports.md](bug-reports.md).
  Regression test: `test/widgets/cover_crop_overlay_test.dart`.
- The crop editor can rotate a picked image 90° (`71f8c44`).
- `_CropScreen` is private to `cover_image_field.dart`.
- `core/cache/image_cache.dart` — the project-wide image cache; `?v=` is what
  gives it cross-device freshness.
- `image_picker` for selection; `UserAvatar` and
  `itinerary_cover_placeholder.dart` render the `nt.sand` placeholders.
- `core/moderation/nsfw_precheck*.dart` — the client pre-check facade, currently
  inert on both platforms. See [image-moderation.md](image-moderation.md).

## Known gaps / TODOs

- **`Storage.exists()` is declared on the ABC, implemented by both backends, and
  has no caller anywhere in `app/`.**
- **`ImageProcessingError` messages are user-facing and untranslated** — the
  router's 400 carries no error code
  (`users.py:446,499`, `itineraries.py` `_cover_refusal`).
- **An itinerary cover is written to its stable key before the request
  commits** — on the form routes exactly as on `POST /image`. A commit that
  fails afterwards leaves the new image at `itineraries/{id}.jpg`; the create
  route deletes it again best-effort, the edit route cannot (the old image is
  already overwritten). Unguessable per-upload keys, approved as step 2 of the
  share-teaser work ([backlog.md](../backlog.md)), would remove the overwrite.
- **A cover removed through the form is deleted after the commit, best-effort,
  and never retried.** A failed delete leaves the object reachable at its key,
  with no row pointing at it — and `delete_itinerary` deletes the object only
  while a cover URL is set.
- `storage/filesystem.py:7` still calls itself "Phase 1 implementation" although
  R2 superseded it on 2026-05-02; `media_pipeline_spec.md:149` keeps filesystem
  only as the rollback path.
- `scripts/migrate_to_r2.py` is the one-time backfill (`--dry-run`,
  `--old-base`); it rewrites `itineraries.cover_image_url`, `users.avatar_url`
  and `users.cover_image_url`.

## Related

- [image-moderation.md](image-moderation.md) — the scan step
- [content-reports.md](content-reports.md) — the CSAM takedown and `parse_storage_key`
- [itineraries.md](itineraries.md) · [accounts-and-profiles.md](accounts-and-profiles.md) — the upload owners
- [bug-reports.md](bug-reports.md) — the screenshot path
- [sharing.md](sharing.md) — `absolute_storage_url` for OG tags
- [web-and-platform.md](web-and-platform.md) — the `/uploads` mount
- [constraints.md](../constraints.md#portability) — the storage-abstraction rule
- `../../social_api/docs/media_pipeline_spec.md` — the full pipeline spec

## OPEN QUESTIONS

- **Is `Storage.exists()` reserved or dead?** It is fully implemented twice and
  called nowhere.
