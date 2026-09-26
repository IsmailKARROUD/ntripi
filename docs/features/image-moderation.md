# Image moderation

**Status:** shipped (**off by default**)
**Tables:** `image_moderation_logs`, writes `itineraries.moderation_status`
**Config:** `MODERATION_ENABLED`, `MODERATION_AWS_*`, `MODERATION_REJECT_THRESHOLD`, `MODERATION_FLAG_THRESHOLD`, `OPERATOR_EMAIL`

## Purpose

Scans uploaded images for sexual content, violence and gore before they are
stored, using AWS Rekognition `DetectModerationLabels`. Four layers exist in the
overall design; this document covers layer 2. Layer 3 (known-CSAM hash matching)
happens at the Cloudflare edge and has **no app config** — see
[content-reports.md](content-reports.md) and
`../../social_api/docs/media_pipeline_spec.md`.

## Rules

- **Disabled by default.** `MODERATION_ENABLED=False`, or **any** missing AWS
  credential, means uploads are stored unscanned exactly as before
  (`is_enabled`, `moderation_service.py:98`).
- **The scan runs after Pillow processing and before storage**, so rejected bytes
  are never written. It is passed to `process_and_store` as a
  `ModerationContext`; omitting it skips the scan.
- **Three outcomes**, by confidence threshold (0–100):
  | Outcome | Condition | Effect |
  |---|---|---|
  | **hard reject** | a `REJECT_CATEGORIES` label ≥ `MODERATION_REJECT_THRESHOLD` (default 80) | `ModerationRejectedError` → **422 `image_moderation_rejected`**; nothing stored |
  | **soft flag** | any label ≥ `MODERATION_FLAG_THRESHOLD` (default 50) | stored, logged, operator emailed |
  | **fail-open** | an AWS error | **stored**, logged as `error_allowed`, status set `pending` |
- `REJECT_CATEGORIES` (`moderation_service.py:58`) — `Explicit Nudity`,
  `Explicit`, `Violence`, `Graphic Violence`, `Visually Disturbing`. Both the
  pre-v7 and v7 Rekognition top-level names are listed so a model upgrade does
  not silently stop rejecting.
- **Fail-open is deliberate**: an AWS outage must not block every upload. The
  `pending` status is what the sweep's post-outage re-check looks for.
- **The cover endpoints never lower `itineraries.moderation_status`.** The column
  also carries text-tier flags and a moderator's `rejected`, and the owner's
  request cannot tell which tier raised it. So `upload_itinerary_image` writes the
  scan result through `apply_moderation_status` (escalate-only), and
  `delete_itinerary_image` leaves the status alone — removing a flagged cover
  keeps the itinerary in the moderator queue until someone reviews it. Before
  2026-09-26 an upload assigned the verdict and a delete reset it to `approved`,
  which cleared text flags and let an owner undo `remove_flagged_image`'s
  `rejected`.
- The Rekognition call is offloaded with `asyncio.to_thread`, like the Pillow
  work and the boto3 I/O.
- **IAM needs only `rekognition:DetectModerationLabels`.** Set an AWS Budgets
  $50/mo alert.
- **A bug-report screenshot is never scanned** — it is never served to another
  user, so a hard reject could only drop a real bug report because our own UI
  tripped a classifier.

### The client pre-check

`lib/core/moderation/nsfw_precheck*.dart` is a **UX and cost optimisation only —
the backend is the authority.** It is currently **inert on both platforms**:

- **Mobile** (`nsfw_precheck_io.dart:8`): *"The model file
  (assets/models/nsfw_mobilenet.tflite, ~3 MB) is NOT vendored in the repo …
  Until it's dropped in, this tier is a no-op."* The required contract is in
  `social_flutter/assets/models/README.md` — input `[1,224,224,3]` float32 RGB
  `/255`, output `[1,5]` softmax over `drawings, hentai, neutral, porn, sexy`.
- **Web** (`social_flutter/web/nsfw/README.md`): TensorFlow.js and NSFWJS weights
  are not committed. `load()` fails gracefully and the pre-check is a no-op.
  Everything is served same-origin from `web/nsfw/` — **do not switch
  `nsfw_glue.js` back to a CDN URL**, which would need a CSP change.

### Audit retention

- **`LOG_RETENTION = 90 days`**, but `PRESERVED_ACTION = "rejected_csam"` rows
  are **never purged, downgraded, or touched**. On a CSAM takedown the object is
  deleted in the same action, so the row and its SHA-256 are the only surviving
  evidence and their retention is a legal duty.
- Automated rows carry no raw text, email or display name.

## Data model

`image_moderation_logs` — `image_hash` VARCHAR(64) (SHA-256), `target_kind`
(`itinerary_cover` / `avatar` / `user_cover`), `target_itinerary_id` FK SET NULL,
`uploader_user_id` FK SET NULL, `action`, `labels` JSON, `reviewed_at`.

- CHECK `ck_moderation_action`: `approved, flagged, rejected, error_allowed,
  rejected_csam`
- CHECK `ck_moderation_target_kind`

Full columns:
[reference/data-model.md](../reference/data-model.md#image_moderation_logs).
Migrations: `b858424a1092` created it; `7f6e757d452c` added the CSAM hash-match
tier.

## API surface

No endpoints of its own. It is a step inside the five upload paths listed in
[image-pipeline.md](image-pipeline.md#api-surface), and it surfaces on two admin
lanes: `GET /admin/flagged` and `POST /admin/flagged/{log_id}/action`.

`remove_flagged_image` **deletes the actual file** — unlike content soft-delete —
and leaves the scan record as evidence.

## Config

| Var | Default | Effect |
|---|---|---|
| `MODERATION_ENABLED` | `False` | master switch |
| `MODERATION_AWS_ACCESS_KEY_ID` / `_SECRET_ACCESS_KEY` / `_REGION` | unset | any missing ⇒ disabled |
| `MODERATION_REJECT_THRESHOLD` | `80.0` | hard reject → 422 |
| `MODERATION_FLAG_THRESHOLD` | `50.0` | soft flag → stored + emailed |
| `OPERATOR_EMAIL` | unset | **unset ⇒ flags are logged and nobody is told** |

Thresholds are tunable without a redeploy.

## Known gaps / TODOs

- **The client pre-check is inert on both platforms** — neither the TFLite model
  nor the NSFWJS weights are vendored. Every image reaches the backend scan,
  which is the actual authority, so this is a cost/UX gap rather than a safety
  one. See [backlog.md](../backlog.md).
- **The post-outage re-check does not re-scan images.** An `error_allowed` image
  scan sets `itinerary.moderation_status = 'pending'`, and the sweep's re-check
  then re-scans only the **text** fields of that itinerary. A fail-open image is
  never looked at again.
- `test_image_moderation.py` runs and asserts the disabled-by-default behaviour
  first.

## Related

- [image-pipeline.md](image-pipeline.md) — where the scan sits
- [content-reports.md](content-reports.md) — CSAM takedown, and `rejected_csam`
- [text-moderation.md](text-moderation.md) — the other tier, sharing `moderation_status`
- [admin-and-appeals.md](admin-and-appeals.md) — the `/admin/flagged` lane
- [moderation-sweep is documented in admin-and-appeals.md](admin-and-appeals.md#the-sweep)
- `../../social_api/docs/media_pipeline_spec.md` — the four-layer strategy
- `../../social_api/docs/csam_response_runbook.md` — the operator procedure
