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
- **`app/services/share_service.py`** — `build_share_url(itinerary, settings)` for the public share URL; never rebuild the f-string. Also `absolute_storage_url(key, settings)` — the only way to turn a storage key into a URL fit to leave the site (emails, Jira tickets, OG crawlers). Filesystem storage returns a relative `/uploads/…`; R2 is already absolute and passes through.
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
- **Never touch `ref` in `State.dispose()`** — `ref` resolves through `BuildContext`, which is already deactivated by then, so `ref.read(...)` throws `StateError: Using "ref" when a widget is about to or has been unmounted is unsafe`. To call a notifier on the way out, hold it in a field: `NotifierType? _notifier;` assigned in `build` via `ref.watch(someProvider.notifier)` (watched, not read once in `initState` — an invalidation swaps the instance and `dispose` must reach the live one), then call `_notifier?.method()` in `dispose`. Safe only because the provider is not `autoDispose`, so the notifier's own `ref` outlives the screen; an `autoDispose` provider needs `ref.keepAlive()` or the work moved into the notifier's `ref.onDispose`. Live example: `notifications_screen.dart` flushing the deferred-delete queue.

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

Optional (bug reports): `BUG_REPORT_RATE_LIMIT=5/hour` · `BUG_REPORT_RETENTION_DAYS=180`. Both have working defaults — shipping the feature needs no deploy change. `OPERATOR_EMAIL` is what turns the notification email on.

Optional (Jira hand-off): `JIRA_BASE_URL` · `JIRA_EMAIL` · `JIRA_API_TOKEN` · `JIRA_PROJECT_KEY` · `JIRA_ISSUE_TYPE=Bug` · `JIRA_TIMEOUT_SECONDS=10`. Any of the first four unset ⇒ the "Create Jira issue" button is not rendered (a partially-set config logs which vars are missing). Free — the Jira Cloud REST API carries no per-call charge; the token comes from id.atlassian.com. `JIRA_PROJECT_KEY` is the board key (`NTRIPI`), not a numeric id, and `JIRA_ISSUE_TYPE` must name a type that exists in that project.

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
- **Coverage is every stored user string except the moderator-facing ones.** Itinerary title/description, stop name/address/notes, both annotation tables, transport-leg line/direction/notes, rating notes, profile display_name/bio, and the `username` + `display_name` chosen at registration. Deliberately NOT moderated: `content_reports.notes`, `appeals.user_reason`, `bug_reports.message`, and admin action reasons — a 422 there would block someone reporting hate speech who quotes it, which is a safety regression, not an improvement.
- **Account creation scans before it writes.** `create_user` commits, so a rejection found afterwards could not undo the account — `moderate_or_422` runs first, with `author=None`. `POST /auth/google` scans the Google profile name but **never rejects it**: the name is Google's, not something the user typed, so a 422 would lock a real person out with no recourse. A reject there drops the name (as `validate_display_name` already does) and stores `approved` — nothing offensive was persisted.
- **A `hide_escalate` verdict must open a `legal_escalations` row, on every path.** Callers pass `ctx.escalate` to `moderation_actions.escalate_if_flagged` after their flush — the caller is the only party holding the row to point at. The one exception is a *rejected* minors verdict, escalated from `_finalize` against the **author**: nothing was stored, so there is no content row, exactly as a CSAM hash match escalates against the uploader.
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

## Bug Reports (shake to report)

Shaking the phone captures the screen, lets the user draw on it, and files a support ticket. Deliberately **not** part of the moderation stack: `content_reports` is evidence about content someone else published, with hide thresholds and escalation paths; `bug_reports` is a ticket about our own app, reviewed at `/admin/bugs` and purged once closed and stale.

- **Two packages, one custom sheet.** `shake` (accelerometer, pulls `sensors_plus`) and `feedback` (screenshot + draw layer). The compose UI is ours via `feedbackBuilder` — `lib/features/bug_report/presentation/bug_report_sheet.dart`, mirroring `report_content_sheet.dart`.
- **`BetterFeedback` must wrap `MaterialApp`, not sit inside `MaterialApp.builder`.** Its bottom sheet builds a bare `Navigator`; inside MaterialApp that Navigator inherits the app's `HeroController` and Flutter asserts ("a HeroController can not be shared by multiple Navigators"). The consequence is that the sheet renders **outside** MaterialApp, so it gets l10n from the delegates passed to `BetterFeedback` (the app's own are listed there) and its `ThemeData` from `ntripiFeedbackAppTheme` in the `feedbackBuilder`. `localeOverride` is required too — that scope otherwise resolves the *platform* locale and ignores the in-app language picker, and it is what drives `Directionality` for Arabic.
- `ShakeToReport` stays *inside* `MaterialApp.builder` so the handler has a `ScaffoldMessenger` for the confirmation snackbar; `BetterFeedback.of()` still finds the controller above.
- **`BetterFeedback` owning the outermost `Overlay` redefines what `rootOverlay: true` means app-wide.** The package hosts the entire app in one `OverlayEntry` with `maintainState: false`, so `Overlay.of(context, rootOverlay: true)` now resolves *outside* MaterialApp: an entry inserted there gets no app `Theme` and no app `Localizations`, and an `opaque: true` one drops the app's own entry from the element tree — unmounting every route, disposing them, and then throwing from `LocalHistoryEntry.remove()` on the dead route so the overlay can never close itself. Anything wanting a full-window layer above the app wants `Navigator.of(context, rootNavigator: true).overlay` instead (`openImageCropOverlay` in `cover_image_field.dart`; regression test `test/widgets/cover_crop_overlay_test.dart`). `field_help.dart` still uses `rootOverlay` — it is safe only because it is non-opaque and captures its colors from the caller's context.
- **The gesture is opt-out-able** (`shakeReportEnabledProvider`, secure storage, default on) and guarded: `minimumShakeCount: 2`, paused whenever the app is not `resumed`, a 3 s cooldown, and skipped on `/splash`. No-op on web (`kIsWeb`) — the Settings ▸ Support row is the entry point there.
- **`POST /bug-reports` is one multipart request** carrying the fields and the screenshot. Two requests would orphan the object in R2 whenever the second failed. Auth-optional — someone stuck on the login screen is exactly who needs to report.
- **Screenshots use `process_screenshot_image`**, not the cover/avatar processors: those cover-crop (destroying a portrait capture) and reject anything under `MIN_DIMENSION=600`. It preserves aspect, downscales to a 1600 px long side, and relaxes the minimum via `_decode_and_validate(min_dimension=…)`.
- **No Rekognition scan on the screenshot** — it is never served to another user, so a hard-reject could only drop a real bug report because our own UI tripped a classifier. `process_and_store` still strips EXIF.
- `screenshot_key` stores the **storage key, not a URL**: the retention purge needs it, and it keeps bug screenshots outside `admin_service.parse_storage_key`, whose whole job is refusing to guess.
- **Retention is a privacy duty**, not housekeeping — a screenshot can contain a third party's data. `bug_report_service.purge_expired` runs from `sweep_service`, deletes the object before the row (so a storage failure retries next sweep), and only ever touches **closed** reports.

---

## In-App Notifications

A bell beside the profile settings gear opens `/notifications`; three of the six types can be switched off in `/settings/notifications`. **In-app only** — there is no FCM/APNs, no notification plugin, and no OS permission prompt. Operators keep their `OPERATOR_EMAIL` mail and additionally get badge counts in the `/admin` nav.

| type | trigger | mutable |
|---|---|---|
| `follow_request` / `new_follower` | `follow_user` — branches on `is_private` | no |
| `moderation_action` | `moderation_actions.auto_hide` + `admin_service.hide_itinerary` / `soft_delete_itinerary` / `warn_user` | no |
| `follow_accepted` | `accept_follow_request` + the bulk auto-accept in `update_me` | **yes** |
| `itinerary_rated` | `upsert_rating`, **insert branch only** | **yes** |
| `itinerary_saved` | `save_itinerary`, **below the idempotent early-return** | **yes** |

- **Rows are structured references, never rendered sentences.** `(type, subtype, actor_id, entity_type, entity_id)`; the text is built client-side in `AppNotification.title()` from `AppLocalizations`. A stored English string would be wrong in the other five locales, would freeze a display name moderation later hides, and would need a backfill to reword. The read path resolves the actor through `user_service.public_profile_text`.
- **`notification_service.notify` is the only writer.** Its three suppression rules — self, muted, blocked — only hold because there is one door. It does `db.add()` and **nothing else**: no commit, no flush. This is the opposite of the email senders' post-commit-and-swallow, deliberately — a mail outage must not fail a user's write, but a notification belongs in the same transaction as the event that caused it.
- **`moderation_action` carries the action name in `subtype`**, aligned with `ViolationItem.action`, so a new moderation action needs no new notification type. `actor_id` stays null — naming the reporter to the author would out them. Tapping routes to `/settings/account-status`, where the appeal button already lives; appeals must not get a second home.
- **Preferences are three boolean columns on `users`**, checked at write time, exposed through the existing `PATCH /users/me` and `UserPrivateProfile`. A separate table buys nothing: adding a type alters the `type` CheckConstraint regardless.
- `moderation_actions.auto_hide` returns `None` when the content was already hidden, so hanging the notify off a non-`None` return makes a repeat sweep idempotent for free. **`warn_user` is the deliberate exception** — a second warning writes a second row, because escalation is the mechanism and collapsing it would hide that this has happened before. Warnings carry `entity_type="user"` and no title (the penalty is against the person), and `_moderationTitle` must branch on `subtype == 'warn'` **before** the hide fallthrough or a warning renders as "your itinerary was hidden". They wear `cautionBg`/`cautionFg`, not `dangerTint` — nothing was taken down.
- **`ban_user` writes no notification and must not.** `deactivate_account` sets `is_active=False`, which 403s every authenticated request, so a banned account can never load `/notifications`. Suspended users get the email and the public token appeal form in `web.py`.
- Retention (purged by `sweep_service._purge`) has two cutoffs: `NOTIFICATION_RETENTION_DAYS=90` takes **read** rows, and `NOTIFICATION_MAX_AGE_DAYS=365` is a hard cap that takes any row regardless of read state. An unread notice outlives the first because it is the recipient's only record that something happened to them; it does not outlive the second, because a year-old unread row is not something anyone can still act on and the feed would otherwise grow forever. Startup refuses a cap below the read window — it would silently shorten it.
- **Users delete their own rows.** `DELETE /notifications/{id}` and `DELETE /notifications` (clear all), both **idempotent and never 404**: the client removes the row on screen and sends the request only after a five-second undo window, so a retry or a row the sweep already took must not raise. Ownership lives in the `WHERE`, same IDOR guard as mark-read, which also means another user's id is indistinguishable from a missing one. Deletion is hard — a notification is a nudge, not evidence, and a moderation notice it pointed at survives on `/settings/account-status`.
- Client-side the delete is **deferred, not optimistic-with-rollback**: `NotificationsNotifier.dismiss` takes the row out of state and queues a `Timer`; only `_commit` sends. Undo is therefore real, where a server-first delete could only be "undone" by re-creating a row the API has no endpoint for. `flushPending()` runs from the screen's `dispose` so leaving settles the queue; `_commit` never rethrows (it runs from a timer, usually after the screen is gone — the row reappearing is the failure signal).
- **Both refs outlive their owner here, and Riverpod 3 throws for it.** The widget `ref` is backed by `BuildContext`, so `dispose()` must use a notifier captured while still mounted — seeded in `didChangeDependencies` (a teardown can beat the first build) and kept current by a `ref.watch(…notifier)` in `build`, because an invalidation swaps the instance and `dispose` must reach the live one — never `ref.read` from `dispose` itself. The notifier's own `ref` is separate but just as fragile: every `state =` or `ref.invalidate` that follows an `await` needs an `if (!ref.mounted) return` guard, because logout invalidates the provider mid-flight and a disposed `Ref` throws rather than no-opping. Regression test: `test/widgets/notifications_screen_teardown_test.dart`.
- Admin badges come from `admin_service.nav_counts` (a narrow slice of `overview_counts`), injected once in `admin.py::_page` off the `"admin"` context key and the session stashed by `_stash_session`. Only queues are badged; Hidden/Removed/Suspended/Log are outcomes and would light permanently.
- Frontend: `NotificationType.fromString` degrades unknown values to a generic renderable row (same rule as `ModerationStatus.fromString`). Opening the screen clears the badge but **does not** flip the local rows — erasing the unread tint in the frame the user arrived to read it defeats the point.

### Delivery: foreground polling

There is no push channel, so nothing reaches a client that does not ask. Both notifiers are keep-alive and would otherwise `build()` once per launch — a hot restart was the only way to see a new row.

- **`NotificationPoller`** (`presentation/widgets/notification_poller.dart`, mounted in `main.dart`'s `MaterialApp.builder` beside `ShakeToReport`) polls `GET /notifications/unread-count` every `kNotificationPollInterval` (60 s), and immediately on launch, on resume, on reconnect, and on login. The interval only bounds the worst case; the edges are what the user actually sees. On web the same `didChangeAppLifecycleState` hook is driven by the browser's `visibilitychange`, so tab blur/focus needs no separate path and the poller does **not** early-return on `kIsWeb` the way `ShakeToReport` does.
- **The gate is foregrounded + online + a settled `hasSessionProvider`** — `authNotifierProvider` would miss every session restored by splash, and an invalidated `FutureProvider` keeps serving its previous value while it reloads, so `isLoading` has to be refused separately or the frame after logout still polls.
- **The feed has a loud read and a quiet one — `refresh()` and `silentRefresh()`.** Nobody asked for the quiet one, so it may not show a spinner and may not write `AsyncError`: a failed `silentRefresh` keeps the loaded feed, exactly as a failed `poll` keeps the last good badge. `refresh()` only swaps in the skeleton when `!state.hasValue`, so pull-to-refresh keeps the list under the user's finger (`AsyncValue.copyWithPrevious` is package-internal in Riverpod 3 and is not the way to say this).
- **The badge has only `poll()`** — no forced variant. The three user actions that change it (`markAllRead`, `clearAll`, a committed delete) invalidate the provider outright, and a feed load hands its badge over via `setBadge`. `poll()`'s first call lands while `build()` is still in flight, so it awaits `future` rather than racing a second request for the same value.
- **`latest_at` is the arrival signal, not the count.** `GET /notifications/unread-count` answers `{unread_count, latest_at}` (`notification_service.badge_state`, one query, `MAX(created_at)` off `ix_notifications_user_created`), and `NotificationBadge.arrivedSince` — the single comparison the cue and the screen both use — tests that timestamp advancing. A count rise looks like the same thing and is not: reading one notification on another device while another arrives leaves the count untouched, so the arrival would be swallowed. The count is only ever the number on the bell. `arrivedSince` still returns false without a baseline, which is what stops every cold launch sounding like an arrival.
- **`silentRefresh()` refuses to run while a delete is queued.** Reloading inside the undo window puts the dismissed row back under the user's finger, and flushing the queue first would destroy the undo they were just offered. Like `poll()`, it awaits `future` instead of racing an in-flight `build()`.
- The badge already rides along with every feed page, so `refresh()`/`silentRefresh()` push it via `setBadge` instead of spending a second request. Pushing the page's `latestAt` is what stops the next poll announcing a row the user is already looking at. Never from `build()` — writing another provider mid-build is what Riverpod forbids outright.
- **Both screens refetch on open, before acting on what they loaded.** `notificationsProvider` and `followRequestsProvider` are keep-alive, so a second visit renders the first visit's data. On the notification feed the order is load-bearing: `markAllRead` on a *cached* feed marks a row the user has never been shown read on the server — badge cleared, cue already played, row never surfaced anywhere again. `_pullInArrivals` is `silentRefresh()` **then** `markAllRead()`, and `markAllRead`'s null-value early return is what keeps a failed load from clearing the badge anyway.
- **The refetch is unconditional.** `GET /notifications` carries the rows *and* the badge and goes through `ETagMiddleware`, so the conditional GET answers 304 with an empty body when nothing changed — it is already conditional where the comparison is exact. Gating it on the badge would skip when the badge is merely stale (up to a full interval), and skip forever after a read on another device drove `unread` to 0.
- `RefreshableCenter` (`shared/widgets/editorial_widgets.dart`) is how an empty or errored list stays pullable. A `RefreshIndicator` wrapped around the populated list sits behind the `isEmpty` early return, which strands the exact two states where the user most wants to ask again.
- **`EditorialDivider(loading:)` is the on-open refetch's only visible sign.** The reload deliberately leaves the previous rows on screen, so without it the screen just sits there until content changes under the user — and a `RefreshIndicator` cannot fill in, because it only draws for a real drag. Its 2 px box is fixed with the idle hairline top-aligned inside, so toggling never nudges the content. The screens raise it with `setState` from a **post-frame callback**, since `didChangeDependencies` runs inside the build pipeline.

---

## Legal Documents and ToS Acceptance

Three documents — Terms of Service, Privacy Policy, Community Guidelines — in six languages, served through one pipeline to both the website and the app.

- **Bodies live in `app/constants/legal/<lang>.py`**, one module per *language* (not per document), each exporting `TOS` / `PRIVACY` / `GUIDELINES` as **plain text**. Plain text, never HTML: the same string renders on the web page (`white-space: pre-wrap`) and in the Flutter sheet, which is a bare `Text`. HTML would need a renderer package on the client or a second copy of every document.
- `app/constants/{tos,privacy,guidelines}.py` keep the version/date constants and expose `get_tos(lang)` / `get_privacy(lang)` / `get_guidelines(lang)`, all through `legal.document()`, which falls back to English twice over — unknown language code, and a language module missing that document.
- **English is authoritative.** Every other language carries a prevailing-language clause from `i18n.py` (`legal_notice_terms` / `_privacy` / `_guidelines`, empty for `en`) — one key per document, not one with a `{document}` placeholder, because Arabic and Chinese put the noun where interpolation cannot reach it.
- **One template, `legal.html`**, for all three routes. They were three near-identical files, so `dir="{{ dir }}"` (Arabic bodies need RTL — the old `dir="ltr"` predates translation), the translated `<h1>`, and the "Last updated"/"Version" labels each had to be fixed three times.
- `i18n.py` `SUPPORTED` must stay in step with the app's `kAppLocaleCodes`: the app appends `?lang=<its locale>` when it opens a legal page in the browser, and a code missing there silently serves English.
- **`GET /auth/tos?lang=` returns all three documents plus their notices** in one response. Three consumers share it — the signup agreement, the Google consent sheet, and the re-acceptance gate.

### Acceptance

- `TOS_VERSION` is written verbatim into `users.tos_accepted_version` at signup, on **both** paths. Bumping it is what makes "which document did this person agree to" answerable; rows are never backfilled.
- **`GoogleAuthRequest.tos_accepted` defaults `False`.** Only the create-a-new-account branch reads it, answering 400 `tos_required`; sign-in and account-linking never consult it. The client's move is **consent-on-demand**: post the token, and on `tos_required` show the sheet and re-post the *same* ID token with `True` (Google ID tokens live ~1h, verification is stateless). Asking before the picker would re-prompt every returning Google user at every sign-in.
- **The re-acceptance gate is client-side** — `UserPrivateProfile.tos_current` (reads `User.tos_current`) plus `TosGate` in `main.dart`'s `MaterialApp.router` builder. It sits there, not in `_AppShell`, because many routes are declared at the router's root level and would slip past a shell-mounted gate. It is inert unless `hasSessionProvider` **and** a loaded profile **and** `tos_current == false`, so `/splash` `/login` `/register` `/suspended` need no allowlist. Loading and error fall through — a profile we could not read is not evidence of a stale agreement.
- `hasSessionProvider` (not `authNotifierProvider`) is the "is somebody signed in?" signal outside the router: splash restores a session without calling `setAuthenticated`, so the notifier is null for exactly the returning users the gate exists for.
- `POST /auth/accept-tos` never takes a **version** — it stamps the server's own `TOS_VERSION`, so a client cannot claim acceptance of a document it never rendered. Its body (`AcceptTosRequest`) carries a date of birth and nothing else, and is itself optional so a client deployed before the age gate still works.
- `AcceptTermsScreen` always carries a sign-out action. A gate with no exit is a lockout, and signing out is also how someone reaches account deletion.
- **The document sheet subscribes to `legalDocumentsProvider` from inside its own route.** `showModalBottomSheet` builds on a separate route, so a parent `setState` never reaches it — capturing the body at call time is what left it on "Loading…" forever. Three async states: spinner, body, and error with Retry + open-in-browser.

---

## Age Gate (16+)

The ToS asserted a minimum age for a release before anything asked for one. `users.date_of_birth` + `users.dob_source` now back it on all three write paths.

- **`app/services/age_service.py` is the single source of truth** — `MINIMUM_AGE`, `calculate_age`, `is_old_enough`, `is_plausible`. No router re-implements the arithmetic. 16 clears GDPR Art. 8 in every member state, so no parental-consent path is ever needed; it does **not** imply contract capacity, which is why the ToS keeps its separate age-of-majority / guardian clause.
- The age comparison is a tuple compare (`(today.month, today.day) < (dob.month, dob.day)`), which is what makes a 29 Feb birth turn 16 on 1 March. `DateOfBirthField.isOldEnough` mirrors it on the client and the two must stay in step.
- **Shape errors are 422, policy refusals are 400.** A future or >120-year date fails `_dob_must_be_plausible` in the schema; a real date under 16 answers 400 `underage` from the router. The client renders a field error for one and a message for the other. New codes: `underage`, `dob_required`.
- **The age check runs before `moderate_or_422`**, exactly like the `tos_accepted` gate above it — an underage signup must not spend a paid provider call to earn its 400. `create_user` re-checks (it commits, so a later failure could not undo the account).
- **Only the Google create-a-new-account branch reads `date_of_birth` / `google_access_token`**, the same rule that already governs `tos_accepted`. Sign-in and account-linking must never consult them or every returning user is re-prompted forever.
- **Google supplies the date when it can; the consent sheet is the guaranteed fallback.** Google ID tokens carry **no birthdate claim** — it needs the People API, the `user.birthday.read` **sensitive scope** (Google verification review before non-test users can grant it), and an access token rather than the ID token. Many accounts have no birthday, many more hide the **year** (`{month, day}` cannot answer an age question), and the scope is refusable. `dob_source` records which source stood behind the account.
- **`google_people.fetch_birthdate` verifies `resourceName == "people/{sub}"`.** The access token is a separate credential from the ID token, so without this check a caller could pair their own ID token with an access token minted for a different Google account and inherit that account's birthday. It returns `None` for every unusable answer and never raises — the caller falls through to asking.
- **The client requests the birthday scope only after the server answers `tos_required`.** That 400 is the only signal the token means signup rather than sign-in; prompting before the picker would nag every returning Google user at every login. The client's People API read is a **prefill hint only** — the server re-reads it and its answer is what gets stored.
- **Existing accounts backfill at the re-acceptance gate.** `date_of_birth` is nullable and never backfilled with a date nobody gave us. `AcceptTermsScreen` shows the field exactly when `UserPrivateProfile.date_of_birth` is null, and `accept-tos` 400s `dob_required` until one arrives. An existing date is **never overwritten** — it is a declaration of record, and re-declaring on demand would defeat the gate.
- `date_of_birth` is on **`UserPrivateProfile` only** — never a profile another user can read.
- **Deploy note:** the Google-sourced half is blocked on OAuth verification for `user.birthday.read` (100-test-user cap and an "unverified app" warning until it clears). The sheet fallback means everything else ships without waiting. App Store privacy nutrition label and Play Data safety both need the DOB declared.

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
- Do NOT scan account text *after* `create_user` — it commits, so the 422 could not undo the account
- Do NOT let a moderation verdict reject a Google-supplied profile name — drop the name instead; the user cannot edit what Google sent
- Do NOT consume `ctx.escalate` without calling `escalate_if_flagged` — hiding without the `legal_escalations` row keeps a CSAM signal out of `/admin/legal`
- Do NOT moderate report notes, appeal reasons, bug-report messages, or admin action reasons — rejecting a report that quotes the abuse it reports is a safety regression
- Do NOT move `BetterFeedback` inside `MaterialApp` — its bottom sheet's Navigator would inherit the app's HeroController and assert on every shake
- Do NOT insert an app-level layer into `Overlay.of(context, rootOverlay: true)` — that is `BetterFeedback`'s overlay, outside MaterialApp; use `Navigator.of(context, rootNavigator: true).overlay`
- Do NOT mark such an overlay entry `opaque: true` — the app's own entry does not `maintainState`, so it would unmount the whole app underneath
- Do NOT drop `localeOverride` or the app's own delegates from `BetterFeedback` — the compose sheet renders outside MaterialApp and would fall back to the platform locale, LTR, and Material default styling
- Do NOT run a bug-report screenshot through the cover/avatar processors — they cover-crop a portrait capture and reject anything under 600 px
- Do NOT purge an **open** bug report — nobody has read it yet; retention only applies once it is closed
- Do NOT call Jira before checking `bug_reports.jira_issue_key` — its presence IS the duplicate guard; two operators working the queue would otherwise file the same bug twice
- Do NOT convert `jira_service.create_issue` or its route to `async def` — same threadpool reasoning as the text-moderation providers; the blocking `requests.post` is correct in a sync endpoint
- Do NOT make the Jira hand-off fail open like email or image moderation — the operator is waiting on the key, so a swallowed error is worse than a red flash
- Do NOT put the reporter's email in the Jira payload, or log `JIRA_API_TOKEN` — the operator inbox is one person, a Jira project is a whole team
- Do NOT send a plain string as a Jira `description` — REST v3 requires ADF (`{"type":"doc","version":1,…}`) and rejects anything else
- Do NOT put raw content text, emails, or display names in an automated `moderation_log` row
- Do NOT store rendered notification text — it is wrong in five of six locales and freezes a display name moderation may later hide
- Do NOT construct a `Notification` directly or call `notify()` after commit — one writer, one transaction, or the suppression rules and atomicity both break
- Do NOT notify an actor about their own action, or across a block in either direction
- Do NOT purge unread notifications inside the read-retention window — an unread notice is the recipient's only record that something happened to them; only the hard age cap may take one
- Do NOT set `NOTIFICATION_MAX_AGE_DAYS` below `NOTIFICATION_RETENTION_DAYS` — it would silently shorten the read window, and startup refuses it for that reason
- Do NOT make a notification DELETE answer 404 — the client sends it after the row has already left the screen, so a retry must not surface an error for something the user watched disappear
- Do NOT send the DELETE before the undo window closes — undo only works because nothing was sent, and no endpoint can re-create a notification
- Do NOT let `_commit` rethrow — it runs from a `Timer` after the screen may be gone, so the restored row is the failure signal and a rethrow is just an unhandled async error
- Do NOT touch the widget `ref` in `State.dispose()` — it is backed by `BuildContext`; capture the notifier while mounted (`didChangeDependencies` + a watch in `build`) and call that
- Do NOT let the notification poll run while backgrounded, offline, or signed out — the timer is cancelled on every non-`resumed` lifecycle state, and `hasSessionProvider` must be settled as well as true, or the frame after logout still fires a 401
- Do NOT let a background read write `AsyncLoading` or `AsyncError` — nobody asked for it, and blanking a correct badge or a loaded feed over one dead-tunnel request is worse than a value that is a minute stale
- Do NOT `silentRefresh()` inside an undo window — it resurrects the row the user just dismissed, and flushing the queue first destroys the undo they were offered
- Do NOT ring the new-notification cue without a previous `AsyncData` to compare against — a first poll has no baseline, and every cold launch would sound like an arrival
- Do NOT use a count rise as the arrival signal — a read on another device cancels out an arrival and masks it; compare `latest_at` via `NotificationBadge.arrivedSince`, which is the only place that comparison is written
- Do NOT mark notifications read from a feed that has not been refreshed since the screen opened — the server is the authority on read state, so a row that was never rendered would be marked read and never surface as new again
- Do NOT gate the on-open refetch on the badge count — the badge is up to a poll interval stale, and after a read on another device it is 0 while the feed is not
- Do NOT put a list's only `RefreshIndicator` behind an `isEmpty` early return — an empty list and a failed load are the two states most in need of a pull; use `RefreshableCenter`
- Do NOT set `state` or call `ref.invalidate` after an `await` in a notifier without checking `ref.mounted` — logout disposes the provider mid-flight and a disposed `Ref` throws
- Do NOT give `moderation_action` an actor or an inline appeal button — it would out the reporter and give appeals a second home away from `/settings/account-status`
- Do NOT add a switch for follow requests or moderation notices — an unseen request cannot be answered and an unseen takedown cannot be appealed in time
- Do NOT make `warn_user` notifications idempotent, and do NOT notify on `ban_user` — a repeat warning is the escalation, and a banned account is 403'd out of the feed entirely
- Do NOT purge, downgrade, or otherwise touch `rejected_csam` rows in `image_moderation_logs` — the object is deleted in the same action, so the row and its hash are the only evidence and their retention is a legal duty
- Do NOT delete the object before hashing it in `csam_takedown` — the order is the evidence
- Do NOT email the uploader or surface a CSAM-specific message on a takedown — it tells someone whose upload matched a law-enforcement corpus exactly what was detected
- Do NOT point `R2_PUBLIC_URL` at a `pub-*.r2.dev` domain in production — it bypasses the Cloudflare zone and silently disables CSAM scanning entirely
- Do NOT re-implement the age arithmetic anywhere but `age_service.py` — three write paths enforce it and a second copy will drift on the leap-year boundary
- Do NOT run the age check after `moderate_or_422` — an underage signup must not spend a paid provider call to earn its 400
- Do NOT turn an underage date into a 422 or a malformed date into a 400 — the client shows a field error for one and a message for the other
- Do NOT read `date_of_birth` or `google_access_token` on the Google sign-in or account-linking branches — same rule as `tos_accepted`, or every returning user is re-prompted forever
- Do NOT request the `user.birthday.read` scope before the server answers `tos_required` — that 400 is the only signal the token means signup, and prompting earlier nags every returning Google user at every sign-in
- Do NOT trust a People API result without checking `resourceName == "people/{sub}"` — the access token is a separate credential and could belong to another Google account
- Do NOT treat a birthday with no `year` as usable, or let a People API failure raise — both must fall through to asking the user
- Do NOT trust the client's People API read — it is a prefill hint; the server re-reads and stores its own answer
- Do NOT overwrite an existing `date_of_birth`, and do NOT backfill the column — it is a declaration of record, and inventing one fakes the evidence the gate exists to produce
- Do NOT put `date_of_birth` on `UserBase` or `UserPublicProfile` — it is owner-only
- Do NOT make the `accept-tos` body required — clients deployed before the age gate post none and would be locked behind a gate they cannot satisfy
- Do NOT default `tos_accepted` to `True` anywhere — an account created without an explicit acceptance is the App Store 1.2 / Play UGC violation this was all built to close
- Do NOT ask for ToS consent *before* the Google picker — only the server knows whether a token means sign-in or signup, and a consent-first sheet re-prompts every returning user forever
- Do NOT let `POST /auth/accept-tos` take a version from the client — it must stamp the server's `TOS_VERSION`
- Do NOT hand a legal document body to `showModalBottomSheet` at call time — the sheet is a separate route that no parent `setState` reaches, and a null capture is a permanent "Loading…"
- Do NOT swallow a failed `/auth/tos` fetch — silence is how the sheet broke; surface it with a retry
- Do NOT gate on `authNotifierProvider` for "is somebody signed in?" — splash restores sessions without setting it; use `hasSessionProvider`
- Do NOT ship a legal document in HTML — plain text is what lets one string serve the web page and the in-app sheet without a renderer package
- Do NOT add a language to the app's locales without adding it to `i18n.py` `SUPPORTED` — the app's `?lang=` would silently fall back to English
- Do NOT pin a legal page's body to `dir="ltr"` — the bodies are translated now, and Arabic needs RTL
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
- Do NOT call `ref.read` / `ref.watch` / `ref.invalidate` inside `State.dispose()` — it throws at runtime; capture the notifier in a field from `build` and call it from there