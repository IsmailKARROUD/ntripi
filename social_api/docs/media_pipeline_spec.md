# Media Upload Pipeline — Technical Specification

**Status:** implemented in code; awaiting the operator steps in §5.
**Storage:** Cloudflare R2 behind a proxied custom domain.
**Child-safety layer:** Cloudflare CSAM Scanning Tool (serve-time) + AWS Rekognition (upload-time) + user reports.

---

## 0. The one correction to read before anything else

Cloudflare's CSAM Scanning Tool **does not file NCMEC reports on your behalf, and it does not scan uploads.** It hash-matches content **as Cloudflare serves it**, tries to block matched URLs at the edge, and emails you a **daily digest** of matched file paths. What it removed was the *NCMEC credential requirement to enable the tool* — not your own reporting duty.

Concretely, three things remain yours:

| | Cloudflare | You |
|---|---|---|
| Hash-match against known-CSAM lists | ✅ at the edge, on served content | — |
| Block the matched URL | ✅ best-effort, reported in the digest | — |
| Delete the object + suspend the account | ❌ | ✅ `/admin/legal` → Takedown |
| File the CyberTipline report | ❌ | ✅ within 24h of the notice |
| Preserve evidence | ❌ | ✅ automatic (`rejected_csam` rows) |

**Accepted risk this design takes on:** because detection is serve-time and the digest is daily, a matched image *will* have been stored and possibly served before you learn of it. Upload-time hash matching (PhotoDNA) is the only thing that prevents that, and it was consciously traded away for operational simplicity. Rekognition still rejects overtly explicit uploads before storage; it is a guessing classifier, not a hash match.

---

## 1. Pipeline architecture

```
┌────────┐  multipart   ┌──────────────────────────────┐   PUT    ┌──────────┐
│ Client │─────────────▶│  FastAPI  (Railway)          │─────────▶│ R2 bucket│
└────────┘   ≤10 MB     │  1 validate: format/size/dim │  boto3   └────┬─────┘
     ▲                  │  2 Pillow: crop + resize     │               │
     │                  │     re-encode JPEG q85       │               │
     │                  │     → strips EXIF/GPS        │               │
     │                  │  3 Rekognition scan          │               │
     │                  │     reject ⇒ 422, not stored │               │
     │                  │  4 storage().save(key)       │               │
     │                  │  5 persist public URL in DB  │               │
     │                  └──────────────────────────────┘               │
     │                                                                 ▼
     │   image bytes                                    ┌──────────────────────────┐
     └──────────────────────────────────────────────────│ images.ntripi.app        │
                                                        │ (PROXIED custom domain)  │
                                                        │  • Cloudflare CDN cache  │
                                                        │  • CSAM edge hash match  │
                                                        └──────────────────────────┘
```

**Upload (write path)** — `POST /users/me/avatar`, `POST /users/me/cover-image`, `POST /itineraries/{id}/image`, all funnelling through `image_service.process_and_store`:

1. `_decode_and_validate` — ≤10 MB, JPEG/PNG/WEBP only, ≥600×600, convert to RGB.
2. `process_cover_image` (1200×630) or `process_avatar_image` (800×800) — cover-crop, LANCZOS resize, re-encode as JPEG q85. **Re-encoding is how EXIF and GPS coordinates are stripped**; the bytes that reach storage are a new image built in memory.
3. `moderation_service.moderate_or_raise` — Rekognition `DetectModerationLabels` on the processed bytes. Hard reject ⇒ `ModerationRejectedError` ⇒ 422, nothing written. Soft flag ⇒ stored, logged, operator emailed. AWS error ⇒ stored as `pending` (fail-open).
4. `storage().save(key, bytes, "image/jpeg")` — R2 `put_object` with `ContentType: image/jpeg` and `CacheControl: public, max-age=3600`.
5. The returned public URL is persisted (`users.avatar_url`, `users.cover_image_url`, `itineraries.cover_image_url`). Avatar and user-cover URLs get a `?v=<ms>` suffix because their keys are stable per user.

**Serve (read path)** — the client requests the stored URL directly from `images.ntripi.app`. Cloudflare serves from cache or fetches from R2. The API is not in the read path at all.

**Storage keys are deterministic**, which is what makes a Cloudflare notice actionable:

| Kind | Key | Cache-bust |
|---|---|---|
| Avatar | `avatars/{user_id}.jpg` | `?v=` |
| Profile cover | `covers/{user_id}.jpg` | `?v=` |
| Itinerary cover | `itineraries/{itinerary_id}.jpg` | none |

### Why not presigned direct-to-R2 uploads

Presigned URLs would move the upload off the API — and take four guarantees with it. EXIF/GPS stripping, format and dimension validation, the pre-storage Rekognition scan, and the guarantee that only well-formed JPEGs ever enter the bucket all live in the API path. Restoring them behind presigned uploads means R2 event notifications → a queue → a worker that re-processes and re-uploads, with a window where the original unscanned bytes are live and publicly addressable. That is strictly more infrastructure for a solo operator, and strictly weaker safety. Images are capped at 10 MB, so the API round-trip is not a bottleneck worth that trade.

---

## 2. Safety & compliance strategy

### Layer 1 — client pre-check (UX only)
NSFWJS (web) / TFLite (mobile) in `lib/core/moderation/`. Advisory; fails open; never authoritative.

### Layer 2 — upload-time classifier (AWS Rekognition)
`app/services/moderation_service.py`. Runs before storage, so a hard reject is never written to R2. Catches **new** explicit material a hash list has never seen — but it guesses, so it never acts on an account by itself. `MODERATION_ENABLED=False` by default.

### Layer 3 — serve-time hash matching (Cloudflare CSAM Scanning Tool)
Zero application code. Requirements: `STORAGE_BACKEND=r2`, and `R2_PUBLIC_URL` pointing at a **proxied** custom domain. A `pub-*.r2.dev` URL bypasses the zone entirely and the scanner sees nothing — the storage factory logs a warning if it detects one.

On a match Cloudflare blocks the URL at the edge where it can, and emails the daily digest to the address configured in the dashboard (use the same one as `OPERATOR_EMAIL`).

### Layer 4 — human reports
`POST /reports` with reason `csam` → `legal_escalations` → `/admin/legal`. Unchanged by this migration.

### Our retained legal duties

1. **Remove** the content — the takedown action in §3.
2. **Report** to NCMEC's CyberTipline within 24 hours of the notice, manually. No automated reporting exists in this codebase, by deliberate design (`app/models/legal_escalation.py`).
3. **Preserve** evidence — `image_moderation_logs` rows with `action='rejected_csam'` are exempt from the 90-day purge (`moderation_service.PRESERVED_ACTION`). The object is deleted; its SHA-256 is not.
4. **Suspend** the uploader — automatic within the takedown action.

---

## 3. Backend responsibilities (what our code actually does)

The entire application-side response to a Cloudflare notice is one operator action: `admin_service.csam_takedown(db, admin, path)`, driven by a form on `/admin/legal` (`POST /admin/legal/takedown`).

**Input:** one file path from the digest email. It accepts a full URL, a bare key, a leading slash, a legacy `/uploads/` prefix, or a `?v=` suffix — `parse_storage_key` normalises all of them. A path that does not match one of the three key patterns is **refused**, because guessing could suspend an unrelated account.

**Order of operations** (the order is the point):

1. **Hash before deleting.** `storage().read(key)` → SHA-256 → an `ImageModerationLog` row with `action='rejected_csam'`, `provider: cloudflare`, and the key. Once the object is gone, this row is the only evidence. If the object is already missing (the digest is daily), the hash records the sentinel `"unavailable"` and the rest of the action still proceeds.
2. **Snapshot** the user (`snapshot_user`) plus the hash and key.
3. **Clear the URL** — `itineraries.cover_image_url` via `set_preserving_etag` (moving `updated_at` would 412 the author's open editor), or the user column directly.
4. **Suspend** — `deactivate_account`: `is_active=False` + revoke every refresh token. Effective on the uploader's next request; `get_current_user` re-reads the row each time.
5. **Audit** — one operator `ban` row naming the admin, the key, and the hash. It appears in `/admin/log` with the standard unban control, so a disputed match is reversible.
6. **Escalate** — `moderation_actions.escalate(source="hash_match")` against the **user** (there is no content row left to point at). It lands in `/admin/legal` and cannot be closed without a written note — where the CyberTipline report number goes.
7. **Commit** (evidence, suspension, and escalation land as one transaction), then **delete the object** best-effort — a storage outage must not undo a committed takedown.

**Deliberately absent:** any email to the uploader, and any CSAM-specific error surfaced to a client. A notice would tell someone whose upload matched a law-enforcement corpus exactly what was detected.

---

## 4. Data & configuration

| Setting | Value | Note |
|---|---|---|
| `STORAGE_BACKEND` | `r2` | missing `R2_*` vars now **fail the boot** rather than falling back to a filesystem path production no longer serves |
| `R2_PUBLIC_URL` | `https://images.ntripi.app` | must be proxied; `r2.dev` disables the CSAM layer |
| `R2_ENDPOINT` | `https://<account-id>.r2.cloudflarestorage.com` | S3 API |
| `R2_BUCKET` / `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` | — | token needs Object Read & Write |
| `STORAGE_PUBLIC_URL_PREFIX` | `/uploads` | keep set — legacy relative URLs still validate against it |
| `OPERATOR_EMAIL` | your address | also use it as Cloudflare's notification address |

No application config exists for CSAM scanning; it is entirely a dashboard toggle.

---

## 5. Migration checklist

**Code (done):** storage `read()` added to the abstraction, factory hard-fails on missing R2 vars, `CacheControl` on uploads, `migrate_to_r2.py` fixed to backfill all three URL columns and preserve `?v=`, takedown action + `/admin/legal` form, tests, docs.

**Yours, in order:**

1. **R2 bucket + token** — Cloudflare Dashboard → R2 → create bucket (e.g. `ntripi-media`) and an API token with Object Read & Write. Note the Account ID, Access Key ID, Secret.
2. **Custom domain** — bucket → Settings → Custom Domains → add `images.ntripi.app`. **Verify the DNS record is proxied (orange cloud).** Grey cloud = no CSAM scanning.
3. **Enable CSAM Scanning** — Dashboard → Caching → CSAM Scanning Tool → enable, notification email = your `OPERATOR_EMAIL`, accept the terms.
4. **Railway vars** — `STORAGE_BACKEND=r2` + the five `R2_*` values. Keep `STORAGE_PUBLIC_URL_PREFIX`. Deploy; a typo now fails the boot loudly.
5. **Backfill** — with production `DATABASE_URL` and the R2 vars in the environment: `python scripts/migrate_to_r2.py --dry-run`, review, then run it live.
6. **Verify, then clean up** — avatars, profile covers, itinerary covers, and a public share page must all render from `images.ntripi.app`. Only then detach the Railway volume.
7. **Runbook** — read `csam_response_runbook.md`, fill in the counsel contact block.
8. **Optional** — register with NCMEC as an ESP. Not required to enable the Cloudflare tool, but your own filings (still your obligation on every match) go through a better portal with it.

**Rollback:** set `STORAGE_BACKEND=filesystem` and re-attach the volume. Note this only restores files that were never deleted from it, and stored URLs would need re-pointing back — take the R2 path as one-way once step 6 passes.
