# Ntripi — Architectural Rules for Claude

Read this fully before writing any code. These rules override default behavior.

---

## Project Overview

Ntripi is a full-stack social media app for sharing travel itineraries.
Live at **https://ntripi.app**.

Monorepo at `/Users/ismac/project/Ntripi/`:
- `social_api/` — FastAPI + PostgreSQL backend
- `social_flutter/` — Flutter frontend (iOS, Android, Web)

---

## Tech Stack

**Backend:** FastAPI · PostgreSQL via SQLAlchemy 2 · Alembic · JWT HS256 (python-jose + bcrypt direct) · Pydantic v2 + pydantic-settings · Jinja2 · Pillow · Uvicorn · pytest + SQLite in-memory

**Frontend:** Flutter (Dart ≥ 3.3) · Riverpod 2 (AsyncNotifier, no codegen) · Dio 5 · go_router 13 · flutter_secure_storage · flutter_map + OpenStreetMap · share_plus · image_picker

---

## Portability Rules (CRITICAL)

1. Everything configurable is an env var (`app/config.py` / `--dart-define`)
2. Single Dockerfile at repo root — Railway Root Directory is empty
3. No platform-specific features — standard PostgreSQL + HTTP only
4. Storage via abstraction (`app/storage/base.py`) — calling code uses `storage().save()` / `.delete()` only
5. Backend ↔ Frontend separated — HTTP/JSON only, no shared code

---

## Architectural Patterns

### Backend
- Access control single source of truth: `can_view_itinerary()` in `app/services/itinerary_access.py`
- Denormalized counters updated in same transaction as source
- Every endpoint returns Pydantic schema, never raw ORM
- Direct bcrypt (no passlib) — Python 3.13+ compatible
- Timing-safe login: always call `verify_password` even when user not found
- Auth service: `auth_service.py` shared by web (`/web/login`) and API (`/auth/login`)
- Image processing: `app/services/image_service.py` — Pillow resize + EXIF strip + 1200×630 cover-fit + JPEG

### Shared Helpers (DRY — reuse these, never re-inline the logic)

Extracted in the 2026-07 dedup refactor. Before writing a query/response block in a router, check here first; if a block appears a second time anywhere, extract it instead of copying.

- **`app/services/user_service.py`** — cross-router user/follow helpers:
  - `get_active_user_or_404(db, user_id)` / `get_active_user_by_username_or_404(db, username)` — the only way to fetch-or-404 a user (enforces `is_active` + `username_lower`).
  - `get_follow(db, follower_id, following_id)` · `is_accepted_follower(...)` — never write inline Follow queries.
  - `bump_follow_counters(follower, followed, delta)` — the only way to touch `followers_count`/`following_count` (None-skip, `max(0, …)`). Exception: `delete_my_account`'s bulk UPDATEs.
- **`app/services/token_util.py`** — `hash_token` / `as_aware_utc` / `new_raw_token` for every opaque-token service (refresh, email). New token types must use these.
- **`app/services/image_service.py`** — `process_and_store(raw, key, processor, *, cache_bust)` for all image uploads. `cache_bust=True` for user avatar/cover (stable keys need `?v=`), `False` for itinerary covers (never carried `?v=`).
- **`app/services/share_service.py`** — `build_share_url(itinerary, settings)` for the public share URL; never rebuild the f-string.
- **`app/middleware/__init__.py`** — `STATIC_PREFIXES` shared by ETag + security-headers middleware; add new static mounts there, not in each middleware.
- **`app/routers/itineraries.py` router-private helpers** (keep router-private; don't re-inline):
  - `_etag_json_response(schema_cls, obj, itinerary, status_code)` — every response that carries the concurrency ETag. In `reorder_itinerary`, pass the freshly reloaded detail, not the stale itinerary.
  - `_require_viewable(itinerary, viewer_id, db, detail=…)` — the only 403 access gate (wraps `can_view_itinerary`). `get_itinerary` passes its historical divergent wording explicitly — do not "fix" it.
  - `_two_phase_renumber(rows, db)` — the only way to rewrite a full rank set (`!`-prefixed temp ranks dodge the UNIQUE constraint). Callers validate ownership first.
  - `_require_stops_in_itinerary(...)` — segment stop-membership check.
  - Annotation CRUD: `_get_itinerary_annotation_or_404` / `_get_stop_annotation_or_404` (joins Stop — the IDOR guard) / `_apply_annotation_fields` / `_save_annotation` / `_delete_annotation`.
- **`app/schemas/itinerary.py`** — reuse `_NOTE_TYPE_PATTERN`, `_PLACE_TYPE_PATTERN`, `_VISIBILITY`; annotation request schemas subclass `_AnnotationCreateBase`/`_AnnotationUpdateBase`. The two annotation **Response** classes stay separate on purpose — a shared base would reorder JSON keys (base-class fields serialize first). Same rule for any future Response dedup: JSON key order = Pydantic field-definition order = part of the API contract.
- Keep validation-error shapes stable: constrained string fields stay `pattern=` regex, not `Literal` — switching changes the 422 body.

### Security Middleware Stack

`add_middleware` is **LIFO** — the last `add_middleware` call is the outermost layer (receives requests first, responses last). The correct code order to achieve the desired runtime order is:

```
Code order (first added → innermost):     Runtime request order (outermost first):
  ETagMiddleware                    →        ProxyHeadersMiddleware
  CORSMiddleware                    →        TrustedHostMiddleware
  SecurityHeadersMiddleware         →        ContentSizeLimitMiddleware
  ContentSizeLimitMiddleware        →        SecurityHeadersMiddleware
  TrustedHostMiddleware             →        CORSMiddleware
  ProxyHeadersMiddleware            →        ETagMiddleware
```

Key rules:
- **`ProxyHeadersMiddleware`** (`uvicorn.middleware.proxy_headers`) must be outermost — it rewrites `X-Forwarded-For` into `request.client.host` so rate limiting (`slowapi`) and `TrustedHostMiddleware` see the real client IP, not Railway's internal proxy IP. `trusted_hosts="*"` is safe because Railway does not expose the container to the internet directly.
- **`TrustedHostMiddleware`** reads `ALLOWED_HOSTS` from settings (comma-separated). The apex domain and wildcard must both be listed separately (`ntripi.app,*.ntripi.app`) — Starlette's wildcard does not match the bare apex.
- **`SecurityHeadersMiddleware`** (`app/middleware/security_headers.py`) applies `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Content-Security-Policy: frame-ancestors 'none'`, and (HTTPS only) `Strict-Transport-Security: max-age=31536000`. CSP uses only `frame-ancestors` — `default-src 'self'` is meaningless for a JSON API.
- **`CORSMiddleware`** must use explicit method and header lists — never `["*"]`. Current whitelist: methods `GET POST PATCH DELETE OPTIONS`; headers `Content-Type Authorization If-Match If-None-Match`.
- **Rate limiting** (`slowapi`) — the limiter singleton lives in `app/limiter.py` to avoid circular imports (main.py imports routers; routers cannot import from main.py). Import `limiter` in router files; call `app.state.limiter = limiter` in `main.py`. Current limits: register 5/hour, login 10/minute, search 30/minute. In-memory store — sufficient for single-instance Railway; needs Redis if horizontally scaled.
- **Generic exception handler** must re-raise `asyncio.CancelledError`, `KeyboardInterrupt`, and `SystemExit` — intercepting these breaks Starlette's lifespan and async request lifecycle.

### Config Invariants
- `SECRET_KEY` is validated at startup with `Field(min_length=32)` — anything shorter raises a `ValidationError` before the server accepts traffic. Generate with `openssl rand -hex 32`.
- `ALLOWED_HOSTS` (comma-separated) drives `TrustedHostMiddleware`. Default: `ntripi.app,*.ntripi.app`.
- `DEBUG=False` disables `/docs` and `/redoc` via `docs_url=None`. Never set `True` on Railway.

### Database Invariants
- Pool: `pool_size=10`, `max_overflow=20`, `pool_pre_ping=True`.
- Statement timeout: 30 s via `connect_args={"options": "-c statement_timeout=30000"}`. Alembic uses its own `NullPool` engine and is not affected by this timeout.

### Stop / Track Ordering (fractional indexing)
- **Tracks** are a first-class table (`tracks`). A track is a vertical column of parallel stop alternatives.
- `tracks.rank` and `stops.rank` are lexicographic string keys — `TEXT COLLATE "C"` in PostgreSQL.
- Ordering helper: `app/services/ordering.py` — `key_between(a, b)` and `n_keys_between(a, b, n)`.
- `stops` table has `track_id` (FK) + `rank`. No `position` or `parallel_position` columns exist.
- Track lifecycle: a track only exists when it has ≥ 1 stop. Creating a stop with `track_id=null` creates a new track + stop atomically. Deleting the last stop in a track also deletes the track (app-level, not DB cascade).

### ETag / If-Match (optimistic concurrency)
- Scope: whole-itinerary. Any mutation bumps `itinerary.updated_at`.
- ETag value = quoted ISO datetime of `updated_at`: `"2026-05-11T14:18:05.079393+00:00"`. The Flutter client emits the same field as `…Z` (Dart's `toIso8601String()`); the server's `_normalize_etag()` collapses both forms before byte-compare.
- Every GET returns `ETag` header. Every mutation requires `If-Match` header.
- Missing `If-Match` → 428. Mismatch → 412 `{"detail":"itinerary modified, please reload"}`.
- `_normalize_etag()` handles three intermediary mutations: whitespace, `W/` weak prefix (added by Cloudflare when it recompresses), and `Z` ↔ `+00:00` timezone serialization.
- Dependency: `require_etag` in `app/dependencies.py` (SELECT FOR UPDATE + ownership + ETag compare).

### ETag / If-None-Match (cache validation, bandwidth-saving)
- `ETagMiddleware` in `app/middleware/etag.py` hashes every GET JSON response body to a 16-char opaque ETag and sets `Cache-Control: private, no-cache`. When the client returns the value via `If-None-Match`, the middleware replies `304 Not Modified` with an empty body.
- The middleware skips non-GET, non-JSON, non-2xx responses, and the `/uploads`, `/static`, `/app` static mounts.
- If an endpoint sets its own `ETag` header (e.g. `GET /itineraries/{id}` reusing the concurrency token), the middleware leaves it alone — the 304 round-trip still works against the endpoint-set ISO value via `_normalize_etag`.
- The middleware uses `_normalize_etag` on both sides of the comparison, so Cloudflare's `W/` weak downgrade still matches.
- Flutter side: `CachePolicy.request` in `lib/core/api/api_client.dart` honors `Cache-Control` + `ETag` automatically — no per-call changes.

### Frontend
- Feature-first: `features/<feature>/{data,domain,presentation,providers}`
- Manual `fromJson`/`toJson` — no build_runner/json_serializable
- Three async states always: loading, error, data (and empty)
- Never `ListView` inside `Column` — use `CustomScrollView` + Slivers
- Owner UI elements via explicit `currentUser?.id == itinerary.ownerId`
- `ItineraryStaleException` thrown by repository on 412 — presentation catches and shows reload dialog

---

## Code Comments

Add a short inline comment whenever the **why** behind a line or block is non-obvious to a future reader — hidden constraints, project-specific invariants, workarounds, or architectural decisions that would otherwise require cross-referencing another file to understand.

Rules:
- One line max. If you need more, it's documentation — put it in the PR description.
- Explain the *reason*, not the action (`# always hash even for missing users — timing-safe` not `# hash password`).
- Target: complex or project-specific logic (ETag normalization, fractional-indexing rank generation, bcrypt direct, `COLLATE "C"` on rank columns, access-control single source of truth, etc.).
- Do NOT comment self-evident code, standard library calls, or anything a reader can understand from the identifiers alone.

---

## Data Conventions

### Stop Role (StopType)
Frontend-only — never stored. Derived in `Itinerary._parseTracks()`:
- 1 track → all stops: `origin`
- 2+ tracks → first track: `origin`, last track: `arrival`, rest: `waypoint`

`Stop.fromJson` always sets placeholder `waypoint`; real type assigned after deserialization.
No `type` column on stops. Never send or expect a `type` field in stop API payloads.

### Stop Place Types
11 camelCase strings in `place_type` (nullable): `eatDrink` · `sleep` · `pray` · `learnSee` · `buy` · `playWatch` · `nature` · `travel` · `healBathe` · `entertainment` · `sight`
Flutter: always use `PlaceType.fromString()` — handles legacy values, returns null for unknowns.

### Itinerary Visibility
`public` / `followers` / `restricted` / `only_me` (default). Single source of truth: `can_view_itinerary()`.

### Multi-Dimensional Ratings
Required: `score` (1-5). Optional (columns `*_stars` on `itinerary_ratings`, exposed as `*_score` in `RatingWithUser`): `safety`, `experience`, `accessibility`, `family_friendly`, `crowdedness`. NULL = not rated. All optional dimensions are higher-is-better (crowdedness: 5 = pleasantly uncrowded, 1 = overcrowded) so `ratingColor` green stays meaningful. Show dimension averages only when count ≥ 3.
The rate dialog (`rate_itinerary_dialog.dart`) shows Overall + the review note first, then reveals the optional dimensions once Overall is rated. Crowdedness renders person glyphs instead of stars. Adding a dimension = new nullable `*_stars` column (model + migration + schemas + router mapping) plus a `DimensionKey` enum value (auto-wires the viewer/aggregate screens).

### Annotations
Two systems — same four types (advice/caution/avoid/info):
- **Stop-level** (`annotations` table, FK: `stop_id`) — per-stop notes
- **Itinerary-level** (`itinerary_annotations` table, FK: `itinerary_id`) — trip-wide notes
Both require `If-Match` on mutations.

### User Identity
- `username_lower` is the lookup key. NEVER query `User.username == ...`.
- Email always lowercased before storage/comparison.
- Display name: free Unicode (50 char max), falls back to `@{username}`.

---

## UX Conventions

### Destructive Actions
- **Tier 1** — undo snackbar: `showUndoableActionSnackbar()`
- **Tier 2** — confirm dialog: `confirmDestructiveAction()`
- **Tier 3** — type-to-confirm: `confirmTypedDestructiveAction()`
NEVER write inline `showDialog` for destructive actions.

### Segment orphan warning
When inserting a new track between two adjacent tracks that have a segment connecting them, show a confirmation dialog. The segment becomes invisible once the tracks are no longer adjacent. If confirmed, delete the segment(s) before navigating to the stop form.

---

## Testing

**Backend:** `client` fixture in `test/conftest.py` (fresh SQLite per test). Itinerary/stop tests marked `pytest.mark.skip("rewriting after fractional-indexing refactor")`. New tests go in `test/test_fractional_indexing_smoke.py`.

**Flutter:** `http_mock_adapter` for Dio mocking. `FlutterSecureStorage.setMockInitialValues({})` for auth state.

---

## Hosting / Deployment

Railway (single Dockerfile) + Cloudflare DNS + Let's Encrypt SSL.

Railway env vars: `DATABASE_URL=${{Postgres.DATABASE_URL}}` · `SECRET_KEY` · `ALGORITHM=HS256` · `ACCESS_TOKEN_EXPIRE_MINUTES=1440` · `DEBUG=False` · `SHARE_BASE_URL=https://ntripi.app` · `ALLOWED_ORIGINS=https://ntripi.app` · `STORAGE_BACKEND=r2` · `R2_ACCESS_KEY_ID` · `R2_SECRET_ACCESS_KEY` · `R2_BUCKET` · `R2_ENDPOINT` · `R2_PUBLIC_URL=https://images.ntripi.app` (proxied custom domain — never `pub-*.r2.dev`) · `STORAGE_PUBLIC_URL_PREFIX=/uploads` (keep set: legacy relative URLs still validate against it). Filesystem fallback for local dev only: `STORAGE_BACKEND=filesystem` + `STORAGE_FILESYSTEM_PATH=/app/uploads`.

Optional: `FEED_TOP_MIN_RATINGS=3` — minimum rating count for an itinerary to appear in the "Top" discovery feed (defaults to 3; lower it while the catalogue is young).

Optional (image moderation — AWS Rekognition backend tier): `MODERATION_ENABLED=True` · `MODERATION_AWS_ACCESS_KEY_ID` · `MODERATION_AWS_SECRET_ACCESS_KEY` · `MODERATION_AWS_REGION` (e.g. `eu-west-1`) · `MODERATION_REJECT_THRESHOLD=80` · `MODERATION_FLAG_THRESHOLD=50`. Disabled (default) or any missing cred = uploads stored unscanned, exactly as before. Scan runs after Pillow processing, before storage: hard-reject (explicit nudity / violence / gore ≥ reject threshold) → 422, nothing stored; soft-flag (any label ≥ flag threshold) → stored + logged + operator-emailed (`OPERATOR_EMAIL`); AWS error → stored as `pending` (fail-open). IAM policy needs only `rekognition:DetectModerationLabels`. Set an AWS Budgets $50/mo alert on Rekognition. Client-side pre-check (NSFWJS web / TFLite mobile) is a UX/cost optimization only — the backend is the authority; its model files are not vendored (see `social_flutter/{assets/models,web/nsfw}/README.md`).

CSAM hash matching has **no app config** — Cloudflare's CSAM Scanning Tool does it at the edge (dashboard toggle: Caching → CSAM Scanning Tool, notification address = `OPERATOR_EMAIL`). It requires `STORAGE_BACKEND=r2` served from a **proxied custom domain**; a `pub-*.r2.dev` `R2_PUBLIC_URL` bypasses the zone and silently disables the whole layer (the storage factory logs a warning). It scans **serve-time, not upload-time**, blocks matched URLs at the edge, and emails a **daily digest** — it does **NOT** file with NCMEC on our behalf. Removal, the CyberTipline filing (24h from the notice), and preservation are ours: `social_api/docs/media_pipeline_spec.md` + `csam_response_runbook.md`.

`STORAGE_BACKEND=r2` with any `R2_*` var missing now **raises at startup** — silently writing to a filesystem path production no longer serves (the `/uploads` mount is filesystem-only) would strand every upload and take images out from behind Cloudflare. Filesystem backend still needs a persistent volume at `/app/uploads` or images vanish on redeploy.

Optional (text moderation): `TEXT_MODERATION_PROVIDER=openai|local|disabled` (default `disabled`) · `OPENAI_API_KEY` · `TEXT_MODERATION_MODEL=omni-moderation-latest` · `TEXT_MODERATION_TIMEOUT_SECONDS=5.0` · `TEXT_MODERATION_CACHE_TTL_DAYS=30` · `TEXT_MODERATION_LOG_RETENTION_DAYS=90`. Startup **fails** if `openai` is selected without a key — a silent downgrade to the wordlist is worse than not booting.

Moderation sweep — **one of the two drivers is required**, or SLA auto-hide and post-outage re-checks never run: `SWEEP_IN_PROCESS=True` (timer in the app process; no token, no scheduler — the single-instance default) **or** an external scheduler running `curl -X POST -H "Authorization: Bearer $SWEEP_TOKEN" https://ntripi.app/internal/moderation-sweep` hourly (keeps a wall-clock schedule across deploys, which restart the in-process timer). Both at once is safe — the advisory lock makes the duplicate a no-op. Also: `MODERATION_SLA_HOURS=20` (≤22, validated) · `SWEEP_TOKEN` (unset ⇒ `/internal/moderation-sweep` 404s) · `SWEEP_INTERVAL_MINUTES=30` (in-process only; floored at 60s).

Optional (reports/safety): `REPORT_HIDE_THRESHOLDS` (comma `category:count`) · `REPORT_RATE_LIMIT=10/hour` · `ABUSE_CONTACT_EMAIL=abuse@ntripi.app` (must match the in-app address AND the store listing).

---

## Text Moderation

Provider-agnostic by construction — swapping providers is a config change, never a code edit.

- **Policy is ours, not the provider's.** `app/services/moderation_policy.py` holds the 13 categories with Ntripi's own (review, reject) thresholds; the provider's boolean `flagged` verdict is deliberately ignored. `POLICY_VERSION` is part of the cache key, so bumping it invalidates every cached verdict — **bump it whenever you touch a threshold**.
- **Providers**: `app/services/text_moderation_providers.py`. Chain is `openai → local → pending`. The OpenAI request body carries the text and the model name and **nothing else** — no user id, email, or content id, ever.
- **Blocking calls are correct here.** Every text write path is a sync `def` endpoint, which FastAPI runs in a threadpool, so a blocking `requests.post` with a timeout never touches the event loop. Do NOT convert these endpoints to `async def` — that would put the sync SQLAlchemy session on the loop, which is the actual hazard.
- **Call `moderate_or_422` from the endpoint BODY, never as a `Depends`.** Dependencies resolve before the body, so a `Depends` would spend a paid moderation call before `require_etag` could return its 412.
- **`text_moderation_cache`** holds no raw text and no user reference; `text_moderation_decisions` is the audit trail *and* the moderator queue (`reviewed_at IS NULL` = queued). Retention purges reviewed rows only.
- **Content state** lives on `itineraries.moderation_status` (shared by the image and text tiers), `itinerary_ratings.moderation_status`, and `users.moderation_status`. Stop / annotation / transport-leg text **rolls up to its parent itinerary** — hiding is itinerary-level, so a per-fragment status would have no read path.
- **Automated writes only ever RAISE severity** (`apply_moderation_status`, order `approved < pending < flagged < hidden < rejected`): a clean caption edit must not clear an unresolved image flag. Moderator and appeal paths assign directly to lower it.
- **Any moderation write to an itinerary from outside the owner's own request MUST go through `admin_service.set_preserving_etag` / `moderation_actions.set_status`.** `updated_at` IS the concurrency ETag; moving it 412s the author's open editor over a change they cannot see.
- Operator gets an email when the provider chain degrades (fallback, or all-down), throttled to one per hour per level.

### Reports, thresholds, escalation
- `content_reports` is **polymorphic** (`target_type` + `target_id`, no FK on the id — evidence must survive a hard delete). Canonical reasons: `csam, sexual_content, violence_threat, hate_speech, harassment, other, spam`; legacy wire values (`nsfw`, `violence`, `copyright`) are accepted and normalized by `report_service.normalize_reason` so deployed clients keep working.
- Distinct-reporter counts hide content immediately (`REPORT_HIDE_THRESHOLDS`); the count drops by one (floor 1) when the content is already flagged or a classifier score corroborates the reason. `has_pending_report` idempotency is what makes reporters *distinct*.
- CSAM signals open a `legal_escalations` row, rendered in its own `/admin/legal` lane. The routine dismiss action refuses escalated reports, and closing one demands a written note. **No automated reporting to authorities** — deliberate.
- Automated audit rows (`moderation_log`, `admin_user_id IS NULL`) carry `content_snapshot=None` and no raw text, email, or display name. Operator rows keep their snapshot.

### CSAM takedown (response to a Cloudflare notice)
Detection is Cloudflare's, at serve time; the app's whole job is the response — `admin_service.csam_takedown(db, admin, path)`, driven by the form on `/admin/legal`. `parse_storage_key` normalises whatever the operator pastes (full URL, bare key, `/uploads/` prefix, `?v=` suffix) against the three deterministic key patterns, and **refuses anything it does not recognise** — guessing could suspend an unrelated account. Order is load-bearing: **hash the object before deleting it**, because afterwards the `rejected_csam` row and its SHA-256 are the only evidence (exempt from the 90-day purge via `moderation_service.PRESERVED_ACTION`). Then clear the URL (itineraries via `set_preserving_etag`), `deactivate_account`, one operator `ban` row (so `/admin/log`'s unban still works if a match is ever disputed), `escalate(source='hash_match')` against the **user** (no content row survives to point at), commit — evidence, suspension, and escalation as one transaction — and finally delete the object best-effort. The uploader is never emailed. Procedure and counsel sign-offs: `social_api/docs/csam_response_runbook.md`; pipeline: `media_pipeline_spec.md`.

### Sweep
`app/services/sweep_service.py` — SLA auto-hide, post-outage re-check, cache purge. Idempotent by construction; `pg_try_advisory_lock` makes concurrent runs impossible (skipped on SQLite). Invoked by `POST /internal/moderation-sweep` (bearer token, `secrets.compare_digest`, rate-limited, `include_in_schema=False`) or the in-process timer.

### Appeals
`hide` and every automated action (`auto_hide_reports`, `auto_hide_sla`, `auto_reject`) are **appealable** — an auto-hide is provisional and nobody has judged it. Filing an appeal writes its own `appeal_filed` audit row.

### Blocking
`user_blocks` (both FKs CASCADE — a block is a preference, not evidence). `block_service.is_blocked_either_way` is consulted inside `can_view_itinerary`; `blocked_user_ids` filters list queries. Visibility is cut in **both** directions, and a blocked profile 404s identically to a deleted one so the blocked user is never told.

### Frontend rules
- The client filter (`lib/core/moderation/text_precheck.dart`) **warns, never blocks**: any failure returns "clean", the submit control stays enabled, and text is never mutated or cleared.
- Applied to free prose only — **never to titles or place names**. European place names false-positive on wordlists (Bitche, Condom, Sexbierum, Wank); flagging a real destination teaches users to ignore the warning. The backend still moderates titles, where a context-aware classifier can tell the difference.
- `ModerationStatus.fromString` degrades unknown values to `approved` — a newer backend must never crash a deployed client.
- `pending` and `flagged` are internal and are NOT surfaced to the author. Only `hidden` is, with a reason and a one-tap appeal.

---

## Alembic Migration Rules (CRITICAL)

- **Never hand-write a revision ID** — always generate one with `venv/bin/alembic revision -m "description"` (or `--autogenerate` if a DB is reachable). Hand-written placeholder IDs (e.g. `a1b2c3d4e5f6`) silently collide with existing migrations, fork the chain, and crash Railway on `alembic upgrade head`.
- **Always verify a single head before committing** — run `venv/bin/alembic heads` from `social_api/`. If it lists more than one `(head)`, stop and fix the branch (create a merge migration or remove a duplicate stub) before adding a new migration.
- **Never keep two files with the same revision ID** — if a stub (`*_stub_*.py`) and the original file both exist for the same revision, delete the stub; the original is authoritative.
- **`down_revision` must point to the current single head** — read `venv/bin/alembic heads` to get the exact revision string; do not guess from file names or dates.

---

## What NOT To Do

- Do NOT add `type`, `position`, or `parallel_position` columns to `stops`
- Do NOT send or return `position` / `parallel_position` in any API payload
- Do NOT skip `If-Match` on any mutation endpoint
- Do NOT use locale-aware collation on `rank` columns — must be `COLLATE "C"`
- Do NOT introduce build_runner / json_serializable / freezed
- Do NOT add a state management library — Riverpod only
- Do NOT use Google Maps SDK — OSM via flutter_map only
- Do NOT compute rating averages in Python — use SQL `AVG()`
- Do NOT create new access control logic — reuse `can_view_itinerary()`
- Do NOT call `moderate_or_422` as a `Depends` — endpoint body only, or a 412 spends a paid moderation call
- Do NOT convert text write endpoints to `async def` — sync SQLAlchemy on the event loop is the real hazard; the threadpool already keeps blocking provider calls off it
- Do NOT send anything but the text to a moderation provider — no user id, email, or content id
- Do NOT write an itinerary's moderation state from outside the owner's request without `set_preserving_etag` — it 412s their open editor
- Do NOT change a threshold in `moderation_policy.py` without bumping `POLICY_VERSION` — stale verdicts would survive in the cache
- Do NOT put raw content text, emails, or display names in an automated `moderation_log` row
- Do NOT purge, downgrade, or otherwise touch `rejected_csam` rows in `image_moderation_logs` — the object is deleted in the same action, so the row and its hash are the only evidence and their retention is a legal duty
- Do NOT delete the object before hashing it in `csam_takedown` — the order is the evidence
- Do NOT email the uploader or surface a CSAM-specific message on a takedown — it tells someone whose upload matched a law-enforcement corpus exactly what was detected
- Do NOT point `R2_PUBLIC_URL` at a `pub-*.r2.dev` domain in production — it bypasses the Cloudflare zone and silently disables CSAM scanning entirely
- Do NOT apply the client text filter to titles or place names — European place names false-positive
- Do NOT let a client-side filter block submission, mutate text, or clear a compose field
- Do NOT hardcode URLs, secrets, or environment values
- Do NOT use `passlib` — bcrypt direct only
- Do NOT use `allow_origin_regex=".*"` in CORS — explicit list only
- Do NOT use `allow_methods=["*"]` or `allow_headers=["*"]` in CORS — explicit lists only
- Do NOT query `User.username == something` — always `username_lower`
- Do NOT write inline fetch-user-or-404, Follow queries, or follower-counter math — use `app/services/user_service.py` helpers
- Do NOT duplicate a helper that already exists in the Shared Helpers section — extract on second occurrence instead of copying
- Do NOT merge Pydantic Response classes into a shared base if it reorders JSON keys — field-definition order is part of the API contract
- Do NOT use `--web-renderer` flag in Flutter (removed in 3.29)
- Do NOT reference `DATABASE_PUBLIC_URL` from the backend — use `${{Postgres.DATABASE_URL}}`
- Do NOT bypass the storage abstraction
- Do NOT skip EXIF stripping on uploaded images
- Do NOT write inline `showDialog` for destructive actions
- Do NOT omit `ProxyHeadersMiddleware` when deploying behind Railway/Cloudflare — rate limiting will throttle all users from the same proxy IP without it
- Do NOT remove `ALLOWED_HOSTS` or set it to `*` in production — always whitelist `ntripi.app,*.ntripi.app`
- Do NOT set `SECRET_KEY` shorter than 32 characters — startup will refuse to start
- Do NOT expose `/docs` or `/redoc` in production — `DEBUG=False` disables them; do not override `docs_url`/`redoc_url` unconditionally
- Do NOT catch `asyncio.CancelledError` in exception handlers — re-raise it; intercepting it breaks Starlette's lifespan
- Do NOT add new rate-limited endpoints without importing `limiter` from `app/limiter.py` (not from `app/main.py` — circular import)
- Do NOT run the container as root — the Dockerfile creates `appuser` and must keep `USER appuser`
- Do NOT store tokens or sensitive user data in Riverpod provider state — use `flutter_secure_storage` only; call `ref.invalidate()` on user-specific providers in `AuthNotifier.logout()`