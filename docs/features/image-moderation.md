# Image moderation

**Status:** shipped (**off by default**)
**Tables:** `image_moderation_logs`, writes `itineraries.moderation_status`
**Config:** `MODERATION_ENABLED`, `MODERATION_PROVIDER`, `MODERATION_AWS_*`, `MODERATION_REJECT_THRESHOLD`, `MODERATION_FLAG_THRESHOLD`, `MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON`, `MODERATION_GOOGLE_REJECT_LIKELIHOOD`, `MODERATION_GOOGLE_FLAG_LIKELIHOOD`, `OPERATOR_EMAIL`

## Purpose

Scans uploaded images for sexual content, violence and gore before they are
stored. Two providers can do it, and `MODERATION_PROVIDER` picks one: AWS
Rekognition `DetectModerationLabels` (`rekognition`, the default) or Google
Cloud Vision SafeSearch (`google_vision`), called in the EU. Switching is a
variable change, never a code change. Four layers exist in the overall design;
this document covers layer 2. Layer 3 (known-CSAM hash matching) happens at the
Cloudflare edge and has **no app config** — see
[content-reports.md](content-reports.md) and
`../../social_api/docs/media_pipeline_spec.md`.

## Rules

- **Disabled by default.** `MODERATION_ENABLED=False`, or **any** setting the
  selected provider needs being unset, means uploads are stored unscanned
  exactly as before (`is_enabled`, `moderation_service.py:135`). Rekognition
  needs the three `MODERATION_AWS_*`; Cloud Vision needs
  `MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON`. The two differ only in what the
  operator hears: switched off is a choice and stays silent; switched on with a
  setting missing is a misconfiguration and emails the operator, naming only the
  selected provider's missing settings, at most once an hour
  ([Outage alerts](#outage-alerts)).
- **`MODERATION_PROVIDER` is `rekognition` (default) or `google_vision`**; any
  other value refuses startup (`_validate_image_moderation`, `config.py:403`).
  `MODERATION_ENABLED` is the master switch for both. There is **no fallback**
  from one provider to the other.
- **One seam per provider.** `_PROVIDERS` (`moderation_service.py:336`) holds,
  for each provider, the settings it needs and its scan, which returns a verdict
  (reject / flag / approve, with its labels) or raises. Everything after the call
  — the audit row, the 422, the flag email, the `moderation_status` write, the
  fail-open branch — is shared, so the two providers differ only in how they
  reach a verdict.
- **The scan runs after Pillow processing and before storage**, so rejected bytes
  are never written. It is passed to `process_and_store` as a
  `ModerationContext`; omitting it skips the scan.
- **Three outcomes**, the same for both providers:
  | Outcome | Effect |
  |---|---|
  | **hard reject** | `ModerationRejectedError` → **422 `image_moderation_rejected`**; nothing stored |
  | **soft flag** | stored, logged, operator emailed |
  | **fail-open** | a failed scan: **stored**, logged as `error_allowed`, status set `pending`, operator emailed at most once an hour |

### Rekognition (`rekognition`)

- **By confidence threshold (0–100).** Reject when a label in
  `REJECT_CATEGORIES` (`moderation_service.py:75`) — `Explicit Nudity`,
  `Explicit`, `Violence`, `Graphic Violence`, `Visually Disturbing` — or a child
  of one reaches `MODERATION_REJECT_THRESHOLD` (default 80); flag when any label
  reaches `MODERATION_FLAG_THRESHOLD` (default 50). Both the pre-v7 and v7
  Rekognition top-level names are listed so a model upgrade does not silently
  stop rejecting.
- A failed scan is any exception from the call or from reading its answer.
- The boto3 client allows 3 s to connect, 3 s to read and one attempt. **IAM
  needs only `rekognition:DetectModerationLabels`.** Set an AWS Budgets $50/mo
  alert.

### Google Cloud Vision (`google_vision`)

- **One `requests.post`** to `https://eu-vision.googleapis.com/v1/images:annotate`
  with `parent: projects/{project_id}/locations/eu`, the project id read from
  the key's own `project_id`, so Google stores and processes the image only in
  the EU. The body is the image (`image.content`, the base64 of the processed
  JPEG), `features: [{"type": "SAFE_SEARCH_DETECTION"}]` and `parent` —
  **nothing else**: no user id, email, storage key or URL, the text providers'
  rule.
- **No SDK.** `google-cloud-vision` is gRPC and a large dependency, and it would
  bypass the outbound timing hook on `requests.Session.send`. A slow scan shows
  in the slow-request log as `ext=eu-vision.googleapis.com`.
- **Its own key.** The bearer is minted by google-auth from
  `MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON` — never FCM's key, so revoking one
  never stops the other — with the `cloud-vision` scope, and reused until it
  expires (`google_service_account.access_token`, shared with push). The call
  has Rekognition's budget, 3 s to connect, 3 s to read, one attempt, and the
  token request it makes about once an hour gets the same timeouts.
- **The verdict is read on Google's own levels** (`VERY_UNLIKELY` …
  `VERY_LIKELY`), **never mapped onto percentages**: the audit row would claim a
  confidence Google never gave (`_google_vision_verdict`,
  `moderation_service.py:293`).

  | Outcome | Google answer |
  |---|---|
  | reject | `adult` or `violence` at or above `MODERATION_GOOGLE_REJECT_LIKELIHOOD` (default `VERY_LIKELY`) |
  | flag | `adult`, `violence`, `racy` or `medical` at or above `MODERATION_GOOGLE_FLAG_LIKELIHOOD` (default `LIKELY`) |
  | approve | everything below |

  `spoof` is ignored: it detects edited images and memes, not harm. Each level
  must be `POSSIBLE`, `LIKELY` or `VERY_LIKELY`, and the reject level may not be
  below the flag level; startup refuses either mistake
  (`_validate_image_moderation`).
- **A failed scan, never an approval**, is any of: an exception (a timeout, a
  connection error, a token that cannot be minted, a key with no
  `project_id`); a non-2xx status; a body that is not JSON; a
  `responses[0].error`; no `responses[0]` or no `safeSearchAnnotation`;
  `UNKNOWN` for `adult` or `violence` (`_vision_safe_search`,
  `moderation_service.py:248`).
  - **An absent category counts as `UNKNOWN`.** proto3 JSON omits an enum left
    at zero, and Google's zero is `UNKNOWN`, so a missing `adult` was never
    classified and must not read as unlikely. An `UNKNOWN` `racy` or `medical`
    is simply no signal.
  - A `responses[0].error` fails the scan even though Google documents that
    annotations filled in beside it are still correct.
- **Project setup:** the Cloud Vision API enabled and billing on in the key's
  project. Google documents no IAM role for images sent inline; a refusal shows
  in the alert as `PERMISSION_DENIED` and its reason.
- **Startup checks the key** (`moderation_service.validate_credentials`)
  whenever `google_vision` is selected and the key is set, whether or not
  `MODERATION_ENABLED` is on yet: bad JSON, a missing field (`project_id`
  included) or a single-line PEM logs an ERROR naming
  `MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON`, and never raises — the same stance
  as push's check.

### Both providers

- **Fail-open is deliberate**: a provider outage must not block every upload. The
  upload joins `/admin/flagged` as "Not scanned" (`QUEUE_IMAGE_ACTIONS`), and the
  itinerary stays `pending` — the sweep's text re-check will not approve it while
  that review is outstanding. Until 2026-09-28 nothing reviewed these at all.
  **It is not silent**: the operator is emailed, at most once an hour. Until
  2026-10-25 a failed scan only logged, and a closed AWS account failed every
  scan for days with nobody told.
- **The cover endpoints never lower `itineraries.moderation_status`.** The column
  also carries text-tier flags and a moderator's `rejected`, and the owner's
  request cannot tell which tier raised it. So `upload_itinerary_image` writes the
  scan result through `apply_moderation_status` (escalate-only), and
  `delete_itinerary_image` leaves the status alone — removing a flagged cover
  keeps the itinerary in the moderator queue until someone reviews it. Before
  2026-09-26 an upload assigned the verdict and a delete reset it to `approved`,
  which cleared text flags and let an owner undo `remove_flagged_image`'s
  `rejected`.
- **The form routes write the scan result the same way** (`_apply_cover_status`,
  escalate-only), and scan only once the text check has passed and before the
  itinerary is touched: the reject path commits the session to keep its audit
  row, so nothing of the itinerary may be pending in it by then.
- **A create's scan is linked to its trip afterwards.** `POST /itineraries/form`
  scans the cover before the trip's row exists, and `target_itinerary_id` is a
  real foreign key — an audit row naming the new id would fail the reject's own
  commit. So that scan's context carries `itinerary_pending=True`, the row is
  written unlinked, and `moderation_service.attach_itinerary(ctx)` — the image
  twin of text's `attach_target` — links it after the caller's flush.
  `/admin/flagged` finds a cover's trip only through that column. A rejected
  create keeps its row unlinked: there is no trip. The flag email names the id
  either way.
- The provider call is offloaded with `asyncio.to_thread`, like the Pillow work
  and the storage I/O.
- **A bug-report screenshot is never scanned** — it is never served to another
  user, so a hard reject could only drop a real bug report because our own UI
  tripped a classifier.

### Outage alerts

When uploads are being stored unscanned, the operator is told — at most one
email an hour per situation:

| Situation | When | Subject |
|---|---|---|
| `scan_failed` | the scan failed — an exception from the provider call, or an answer that is not a verdict; the fail-open branch | `[Ntripi] Image moderation unavailable — uploads stored unscanned` |
| `not_configured` | `MODERATION_ENABLED=True` with a setting of the selected provider missing | `[Ntripi] Image moderation not configured — uploads stored unscanned` |

- **Hooked where `moderate_or_raise` decides the outcome, not in a provider
  client** (`_notify_unscanned`, `moderation_service.py:546`), so both providers
  share it. `MODERATION_ENABLED=False` sends nothing — a choice, not a failure.
- **The throttle is `operator_alerts.notify_operator`**, shared with text
  moderation's degradation notices: one email per key per hour, in memory (one
  uvicorn process), so a restart or deploy re-arms it and the first failure
  after each deploy emails again. With `OPERATOR_EMAIL` unset it logs a WARNING
  instead, once an hour. A mail failure is logged and never fails the upload.
- **What the email carries**: what is happening — a failed scan's uploads wait
  in `/admin/flagged` as "Not scanned", an unconfigured tier's uploads leave no
  row at all — that nothing is rejected automatically, the UTC time, and either
  the exception's class name plus the provider's error code when it gives one,
  or the names of the selected provider's missing settings. The error code
  (`_provider_error_code`, `moderation_service.py:612`) is botocore's
  `response["Error"]["Code"]` for Rekognition (e.g.
  `UnrecognizedClientException`), and for Cloud Vision Google's `error.status`
  plus the first `details[].reason` (e.g. `PERMISSION_DENIED/SERVICE_DISABLED`,
  `PERMISSION_DENIED/BILLING_DISABLED`).
- **What it never carries**: the exception message or traceback — a provider's
  HTTP client can put the request URL, key included, in its message, and
  Google's names the project and links to its console — nor the image, its URL
  or storage key, the uploader, or any content.
- **Every operator email leaves the event loop.** `moderate_or_raise` runs on
  the loop and `send_email` is a blocking `requests.post` with a 10 s timeout,
  so the flag email and the alert are built on the loop (the flag email reads
  the uploader's row) and only the send goes to `asyncio.to_thread`. The upload
  that triggers one still waits for its own send; no other request does.

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

- **`LOG_RETENTION = 90 days`, for reviewed rows only.** An unreviewed
  `flagged` / `error_allowed` row is the moderator queue; purging it (as happened
  until 2026-09-28) left the image live and quietly out of review — the text purge
  already kept unreviewed decisions for the same reason.
- **`PRESERVED_ACTION = "rejected_csam"` rows** are **never purged, downgraded, or
  touched**. On a CSAM takedown the object is
  deleted in the same action, so the row and its SHA-256 are the only surviving
  evidence and their retention is a legal duty.
- Automated rows carry no raw text, email or display name.

## Data model

`image_moderation_logs` — `image_hash` VARCHAR(64) (SHA-256), `target_kind`
(`itinerary_cover` / `avatar` / `user_cover`), `target_itinerary_id` FK SET NULL,
`uploader_user_id` FK SET NULL, `action`, `provider`, `labels` JSON,
`reviewed_at`.

- **`provider`** — the `MODERATION_PROVIDER` that scanned (`rekognition` /
  `google_vision`), on every row a scan writes; NULL on a takedown's
  `rejected_csam` row, which no scan wrote. Rows from before `a989b5ce5994`
  were backfilled `rekognition`, the only scanner until then.
- **`labels`** — only what reached the flag level, in the provider's own terms:
  Rekognition `{"name", "confidence"}`, Cloud Vision `{"name", "likelihood"}`.
  `moderation_service.label_text` (`moderation_service.py:471`) renders both — a
  level for Google, a percentage for Rekognition, the bare name for a takedown's
  evidence label — in the flag email and, as the `scan_label` filter, on
  `/admin/flagged` and the admin itinerary page.
- CHECK `ck_moderation_action`: `approved, flagged, rejected, error_allowed,
  rejected_csam`
- CHECK `ck_moderation_target_kind`
- CHECK `ck_moderation_provider`: `rekognition, google_vision` (NULL passes)

Full columns:
[reference/data-model.md](../reference/data-model.md#image_moderation_logs).
Migrations: `b858424a1092` created it; `7f6e757d452c` added the CSAM hash-match
tier; `a989b5ce5994` added `provider`.

## API surface

No endpoints of its own. It is a step inside the upload paths listed in
[image-pipeline.md](image-pipeline.md#api-surface), and it surfaces on two admin
lanes: `GET /admin/flagged` and `POST /admin/flagged/{log_id}/action`.

`remove_flagged_image` **deletes the actual file** — unlike content soft-delete —
and leaves the scan record as evidence.

## Config

| Var | Default | Effect |
|---|---|---|
| `MODERATION_ENABLED` | `False` | master switch, for both providers |
| `MODERATION_PROVIDER` | `rekognition` | `rekognition` or `google_vision`; any other value refuses startup |
| `MODERATION_AWS_ACCESS_KEY_ID` / `_SECRET_ACCESS_KEY` / `_REGION` | unset | Rekognition only; any missing ⇒ not configured |
| `MODERATION_REJECT_THRESHOLD` | `80.0` | Rekognition only: the confidence % for a hard reject → 422 |
| `MODERATION_FLAG_THRESHOLD` | `50.0` | Rekognition only: the confidence % for a soft flag → stored + emailed |
| `MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON` | unset | Cloud Vision only: the whole service-account JSON, **not a path**, and its own key, never FCM's. A real secret. Unset ⇒ not configured |
| `MODERATION_GOOGLE_REJECT_LIKELIHOOD` | `VERY_LIKELY` | Cloud Vision only: the `adult` / `violence` level for a hard reject |
| `MODERATION_GOOGLE_FLAG_LIKELIHOOD` | `LIKELY` | Cloud Vision only: the `adult` / `violence` / `racy` / `medical` level for a soft flag. Both levels: `POSSIBLE`, `LIKELY` or `VERY_LIKELY`, reject never below flag |
| `OPERATOR_EMAIL` | unset | flag emails, and the [outage alerts](#outage-alerts) — at most one per situation per hour. **Unset ⇒ both are only logged, and nobody is told** |

The provider, the thresholds and the levels change with a variable, never with
code.

## Known gaps / TODOs

- **The client pre-check is inert on both platforms** — neither the TFLite model
  nor the NSFWJS weights are vendored. Every image reaches the backend scan,
  which is the actual authority, so this is a cost/UX gap rather than a safety
  one. See [backlog.md](../backlog.md).
- **The post-outage re-check does not re-scan images.** An `error_allowed` image
  scan sets `itinerary.moderation_status = 'pending'`, and the sweep's re-check
  then re-scans only the **text** fields of that itinerary. A fail-open image is
  never looked at again.
- **An upload stored while scanning is switched on but not configured leaves no
  audit row**, so it never reaches `/admin/flagged` and nothing can review it
  later. The hourly `not_configured` alert is the only trace.
- **SafeSearch has five categories** — `adult`, `spoof`, `medical`, `violence`
  (which Google describes as death, serious harm or injury) and `racy` — and no
  self-harm or gore class of its own. Rekognition's `Visually Disturbing` has no
  direct counterpart.
- **No admin page shows `provider`.** It is recorded for the audit trail; the
  pages tell the two apart only by the shape of the labels.
- `test_image_moderation.py` asserts the disabled-by-default behaviour first,
  then both providers through the same upload endpoints.

## Related

- [image-pipeline.md](image-pipeline.md) — where the scan sits
- [content-reports.md](content-reports.md) — CSAM takedown, and `rejected_csam`
- [text-moderation.md](text-moderation.md) — the other tier, sharing `moderation_status` and the operator-alert throttle
- [admin-and-appeals.md](admin-and-appeals.md) — the `/admin/flagged` lane
- [moderation-sweep is documented in admin-and-appeals.md](admin-and-appeals.md#the-sweep)
- [notifications.md](notifications.md) — FCM push, which shares `google_service_account` (a different key)
- [legal-and-age-gate.md](legal-and-age-gate.md) — Privacy §4 and §5 name both providers
- `../../social_api/docs/media_pipeline_spec.md` — the four-layer strategy
- `../../social_api/docs/csam_response_runbook.md` — the operator procedure
