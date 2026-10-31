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

## Documentation (`docs/`) — READ FIRST

`docs/` is the single source of truth for **what this project does**. This file is
the rules; `docs/` is the reference. Read it before writing code, update it after.

**Before any feature work:**
1. Read `docs/README.md` — the index, and how the folder is meant to be used.
2. Read `docs/constraints.md` — the project-wide rules a new feature must not
   violate. They are cross-cutting, so a feature that breaks one is wrong before
   it is written.
3. Read the relevant `docs/features/<feature>.md` **and the "Related" links at its
   foot** — that is where you find what your change would conflict with.
4. Read `docs/decisions.md` before reversing anything: the reasoning is usually
   recorded, including the alternatives already rejected.

**Finishing a change is not just the code.** A change is done when:
- The relevant `docs/features/<feature>.md` reflects the new behaviour — Rules,
  Data model, API surface, Flutter surface, Known gaps.
- A new capability has its own `docs/features/<name>.md`, linked from
  `docs/README.md` and from the "Related" section of every doc it touches.
- Any architectural decision is appended to `docs/decisions.md` as a new dated
  entry (Context / Decision / Consequences / Alternatives rejected). **Append
  only.**
- Anything deferred is in `docs/backlog.md`, marked idea / planned / in-progress.
- A new table or column is in `docs/reference/data-model.md`; a new error code is
  in `docs/reference/error-codes.md`.
- A cross-cutting rule is in `docs/constraints.md`.

Only what the code actually does gets documented. Anything ambiguous goes under an
**OPEN QUESTIONS** heading at the foot of the file it belongs to, never guessed at.

A refactor, an index or a migration with no user-visible surface needs none of
this — the test is whether a reader could notice. This is the same standard the
help centre is held to below: **docs describing last month's behaviour are worse
than no docs, because the reader follows them.**

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
  - `delete_follow(db, follow, follower, followed, *, only_if=None)` — the only way to delete a follow row: unfollow, remove-follower, decline and the block sever all end here. A `DELETE … RETURNING status` statement that decrements only if *this* call removed the row **and the row was accepted when it went**; `only_if=` makes it conditional on a status (decline passes `pending`). Never `db.delete()` a Follow — the ORM only warns on a 0-row DELETE, so two racing deletes both decremented.
  - `follow_counts(db, me, them_id)` — the only source of a follow write's `counts` (`FollowCounts {me, them}`): both counters read back after the commit, never computed. `them` is None wherever `GET /users/{id}` would 404 for `me` — unknown, suspended, or a block either way — so remove follower, which answers even when there was nothing to remove, never tells a blocked user the account exists. The answer for the 204 routes is `routers/follows.py` `counts_answer`, which the block route shares.
  - `bump_follow_counters(db, follower, followed, delta)` — the only way to touch `followers_count`/`following_count` (None-skip, clamped at 0). Exception: `delete_my_account`'s bulk UPDATEs. **The arithmetic is an atomic SQL `UPDATE`, never Python**: `count = count + delta` read into an int and written back is a lost update under READ COMMITTED, so two people following one account in the same moment both read N and both write N+1 and the count drifts low forever. The clamp is a `case()` expression, not `GREATEST()` — the suite runs on SQLite, which has no `GREATEST`. It sets `synchronize_session=False` — the default `'auto'` would reconcile the identity map only by re-SELECTing the row it just wrote — and then `db.expire()`s the attribute itself, which is why the loaded object still reads correctly afterwards.
- **`app/dependencies.py` `return_requested(*representations)`** — the one `?return=` opt-in factory: the representation asked for or None, any other value a 422. Every answer that replaces a GET after a write is opted into through it (`wants_itinerary`, `wants_ratings_page`, `wants_rating_answer`, `wants_counts`, `wants_violations`), so a build that never asks gets byte for byte what it always got.
- **`app/services/token_util.py`** — `hash_token` / `as_aware_utc` / `new_raw_token` for every opaque-token service (refresh, email). New token types must use these.
- **`app/services/image_service.py`** — `process_and_store(raw, key, processor, *, cache_bust)` for all image uploads. `cache_bust=True` for user avatar/cover (stable keys need `?v=`), `False` for itinerary covers (never carried `?v=`).
- **`app/services/share_service.py`** — `build_share_url(itinerary, settings)` for the public share URL; never rebuild the f-string. Also `absolute_storage_url(key, settings)` — the only way to turn a storage key into a URL fit to leave the site (emails, Jira tickets, OG crawlers). Filesystem storage returns a relative `/uploads/…`; R2 is already absolute and passes through. And `default_preview_image_url(settings)` — the default OG card, and the only image a private trip's share page may carry.
- **`app/services/app_links.py`** — `cta_context(share_url, settings)` is the only source of a share page's way in (the **See the full trip** web-app link, store URLs with the waitlist fallback and their `*_live` flags, the Android intent URL, the Smart App Banner); `store_links(settings)` its download half. Render it through the `templates/_app_links.html` macros (`teaser_gate`, `store_badges`), imported `with context`, inside `templates/_share_layout.html`. `platform_head()` in the same file is the one place the visitor's platform is decided — in `<head>`, onto `<html data-platform>` — so a phone is shown its own store only; `app_links_head` calls it, and so must any other page with `data-store` buttons (`home.html` does). `reader_head()`, also called by `app_links_head`, is the one place a share page decides where the reader already is: signed in on the web (the web app's localStorage entry `WEB_SESSION_HINT_KEY`, `ntripi_web_session_until`) → `location.replace` into the web app; Android with the app installed (Chrome's `getInstalledRelatedApps`, through `/manifest.webmanifest`) → **Open in Ntripi** first.
- **`lib/features/itineraries/presentation/widgets/share_link_action.dart` `shareLink(anchor, ref, link)`** — the one way a Share button shares. Phones: the phone's own share popup with a **Copy link** row, through the `ntripi/share` channel (`ShareLinkChooser.kt`, `AppDelegate.swift`) — share_plus alone cannot add the row; the web: a two-item menu, or the link copied at once where the browser has no share popup. `ShareService.itineraryLink` / `profileLink` build the `ShareLink`.
- **`lib/core/storage/secure_storage.dart` `hasLiveRefreshToken()`** — the one "is somebody signed in" check (router redirect, splash, `hasSessionProvider`, the link guard); never re-inline the refresh-token-and-expiry read.
- **`lib/core/cache/image_cache.dart` `ImageCacheEviction`** (`imageCacheEvictionProvider`) — the one way an itinerary cover is cleared from the image cache, disk and memory: before the trip page's and the Itineraries tab's pull, and after a form save that changed the cover. A cover keeps its storage key when replaced, so this is how a new one shows. Best-effort: a cache that cannot be cleared costs a stale cover, never the reload or the save, and its error never escapes into a RefreshIndicator. Never call `CachedNetworkImage.evictFromCache` for a cover directly.
- **`lib/core/providers/reload_keeps_content.dart` `ReloadKeepsContent`** — the one way a notifier fetches again what a screen shows: `reloadKeepingContent(fetch, onApply:)`, behind every `refresh()` and `_adopt`'s GET. Its screen half is `shared/widgets/reload_report.dart` `reportReloads(context, [...])`, the one way a pull-to-refresh or Retry reports a failure; `refusesContent(error)` in `core/api/api_client.dart` decides which answers replace the content. Rules under **Frontend**.
- **`lib/core/ui/app_radii.dart` `NtripiRadius`** — the one source of every corner radius in the app, one token per job (values under **UX Conventions → Surfaces and Chrome**). The web pages mirror it as CSS variables in `social_api/app/templates/_radius_tokens.html` (`var(--radius-card)` …), which all four layouts include (`_base.html`, `_share_layout.html`, `home.html`, `admin/_base.html`) ahead of their own styles. `test/radius_scale_guard_test.dart` fails on a typed radius, a per-call sheet or dialog `shape:` and an `OutlineInputBorder` without `borderRadius:`; `social_api/test/test_radius_scale.py` reads the Dart file and fails when the partial disagrees with it, when a template types a `border-radius`, and when the email button (`auth_service.py`, a literal — email clients drop CSS variables) is not `button`. Artwork drawn to scale is the only exception: `loaders.dart` by name, the homepage's phone mockup and inline code by selector.
- **`app/middleware/__init__.py`** — `STATIC_PREFIXES` shared by the ETag, security-headers and request-timing middleware; add new static mounts there, not in each middleware, and test a path with `is_static_path()` (segment boundary) — a bare `startswith("/app")` also matched `/appeal` and `/appeals` and stripped their security headers.
- **`app/database.py`** — `upsert_insert(db, model)` for any check-then-insert that can race (a dialect `INSERT` with `on_conflict_do_nothing` / `_do_update`, same API on Postgres and the SQLite suite). Used by device registration, the text-moderation cache and the first edit-lock claim — each was a 500 when two requests both saw "no row".
- **`app/services/translation_service.py`** — `REGISTRY` is the one list of translatable fields (itinerary title/description/period note, both annotation tables, stop notes, review notes, leg notes — never place names). **Every write of translatable text calls `sync_translations(db, row, changed=...)` before the commit** (re-detects `source_lang`, drops translations whose source hash moved); **every delete below the itinerary calls `purge_orphans(db, itinerary.id)` after the flush** — a stop delete cascades annotations and legs out of the app's sight. Trip and account deletes need neither: `content_translations.itinerary_id` cascades. A new write or delete path that skips these leaves a copy of rewritten or deleted text behind.
- **`app/routers/itineraries.py` router-private helpers** (keep router-private; don't re-inline):
  - `_etag_json_response(schema_cls, obj, itinerary, status_code)` — every response that carries the concurrency ETag. A response carrying the trip is built from the freshly reloaded detail, never the stale itinerary.
  - `_viewer_detail(itinerary, viewer_id, db)` — **the one builder of the trip as a GET shows it to a viewer** (sets their `can_edit`). `get_itinerary`, the bare reorder answer and every trip edit's answer use it, so a save's answer and a GET can never describe the trip differently.
  - `_trip_edit_answer(itinerary_id, viewer, db, created_id=, status_code=)` + the `wants_itinerary` dependency (`?return=itinerary`) — the full-trip answer every `EDIT_GUARDED` route and both creates give when asked: `ItineraryEditResponse {itinerary, created_id}`, read back after the route's **last** commit. A new trip edit depends on `wants_itinerary` and ends with it, or `test_trip_edit_answers.py` fails.
  - `_ratings_page(itinerary, viewer_id, db)` — the one builder of the ratings page: `GET /ratings` and both rating writes' `?return=ratings_page` answers.
  - `_require_viewable(itinerary, viewer_id, db, detail=…)` — the only 403 access gate (wraps `can_view_itinerary`). `get_itinerary` passes its historical divergent wording explicitly — do not "fix" it.
  - `_two_phase_renumber(rows, db)` — the only way to rewrite a full rank set (`!`-prefixed temp ranks dodge the UNIQUE constraint). Callers validate ownership first.
  - `_validate_layout` + `_apply_layout` — the only way to rewrite a trip's whole structure in one request (`POST /reorder` `layout`, arrange mode's save): everything validated before a write, only what moved written, emptied tracks deleted — their `stops` expired first — before the track renumber.
  - `_require_stops_in_itinerary(...)` — segment stop-membership check.
  - Annotation CRUD: `_get_itinerary_annotation_or_404` / `_get_stop_annotation_or_404` (joins Stop — the IDOR guard) / `_apply_annotation_fields` / `_save_annotation` / `_delete_annotation`.
  - `_moderate_itinerary_text` = `_scan_itinerary_text` + `_stamp_itinerary_text`. Call the halves apart only when something else is checked between them — the form routes scan the cover there, and a refused image commits the session, so the itinerary must still be clean. A `hide_escalate` verdict whose cover is then refused goes through `_escalate_text_left_unsaved` (against the author).
  - The itinerary header's shared steps: `_require_visibility_owner`, `_itinerary_text_fields`, `_apply_itinerary_update`, `_new_itinerary` + `_insert_new_itinerary` (both creates). Covers: `_cover_key`, `_cover_refusal` (the 400/422 mapping), `_apply_cover_status`, `_store_cover` (the form routes' sync call into `process_and_store`), `_delete_cover_object` (best-effort, from a sync route).
- **`app/services/moderation_service.py` `attach_itinerary(ctx)`** — links a create-time cover scan's audit row to its trip after the flush (the image twin of text's `attach_target`). A create scans before its row exists, `target_itinerary_id` is a real FK and a reject commits the row, so the context says `itinerary_pending=True` and the row is linked afterwards — `/admin/flagged` finds a cover's trip only through that column.
- **`app/services/google_service_account.py`** — the one home of a Google service-account key read from an env var: `parse` (`json.loads(..., strict=False)` — an env-var paste can turn the key's `\n` escapes into real line breaks), `validate(var_name, raw, *, consequence, log, required=)` (the startup check: logs an ERROR, never raises) and `access_token(var_name, raw, scope, *, timeout=)` (the token cache, keyed by variable and scope, one lock per key; a failure drops the credentials and raises). FCM push (`FCM_SERVICE_ACCOUNT_JSON`) and Cloud Vision (`MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON`) each hold their own key through it — never re-inline the parse, the PEM check or the cache.
- **`app/services/moderation_service.py` `_PROVIDERS`** — the one seam between `moderate_or_raise` and an image scanner: per `MODERATION_PROVIDER` name, the settings it needs (what the "not configured" alert names) and its scan, which returns a verdict or raises. A new provider is an entry here plus a name in `config.IMAGE_MODERATION_PROVIDERS` — never a second reject / flag / fail-open path. `label_text(label)` beside it is the one rendering of a stored scan label (a level for Cloud Vision, a percentage for Rekognition): the flag email, and both admin pages as the `scan_label` filter.
- **`app/services/operator_alerts.py` `notify_operator(settings, key, *, subject, body, log_line)`** — the one throttled operator alert: at most one email per `key` per hour (an in-memory map under a lock — one uvicorn process, so a deploy re-arms it), `log_line` logged at WARNING when the hour's slot is taken, the `OPERATOR_EMAIL` guard, mail errors swallowed. Text moderation's degradation notices (`text_moderation:<level>`) and image moderation's outage alerts (`image_moderation:scan_failed` / `:not_configured`) go through it, and so does any new "this tier is down" alert — never re-inline a cooldown dict. It blocks on `send_email`, so an `async` caller builds the body on its own thread (no ORM read in the worker) and sends with `asyncio.to_thread`. A per-event email (a flagged image, a report, a bug report) is not an alert and is never throttled. conftest's autouse `reset_operator_alerts` clears it between tests.
- **`app/schemas/itinerary.py`** — reuse `_NOTE_TYPE_PATTERN`, `_PLACE_TYPE_PATTERN`, `_VISIBILITY`; annotation request schemas subclass `_AnnotationCreateBase`/`_AnnotationUpdateBase`. The two annotation **Response** classes stay separate on purpose — a shared base would reorder JSON keys (base-class fields serialize first). Same rule for any future Response dedup: JSON key order = Pydantic field-definition order = part of the API contract.
- Keep validation-error shapes stable: constrained string fields stay `pattern=` regex, not `Literal` — switching changes the 422 body.
- **`app/services/stop_location.py` `normalize(fields, existing, now)`** — the one place a stop write becomes a location the rules allow (`docs/features/places-and-maps.md`): from Google only a place ID and the user's own search text; never coordinates beside a link or a Google place (`extract_place_id` reads a `ChIJ…` out of a link's text, no fetch); a body without `place_source` (installed builds) read from what it sends; the refresh stamps move only when the ID changes. `add_stop` and `update_stop` run it before their moderation scan; a new stop write path must too.
- **`app/database.py` `reserve_within_limit(db, model, keys, column, amount, limit)`** — the one conditional-upsert counter (spend counted only if it fits; nothing on refusal). The translation budgets and `place_search_usage` use it; a new per-user or per-day budget is one call, never a read-then-write.
- **`app/services/google_places.py`** — the only caller of Google Places (Autocomplete for the form's fallback, the free IDs-only Details call for the yearly refresh). Fails quiet, logs status codes and exception classes only — never a body, a search text or a suggestion. No Place Details on the search path, ever (a suggestion carries its place ID; a session would only add cost).
- **`lib/features/itineraries/data/google_embed_urls.dart` `GoogleEmbed`** — the only builder of a Google map's address: a page on our server (`/embed/place|point|search|directions`, `routers/embed.py`) that frames Google's Maps Embed API with the backend's key. Shown through `widgets/google_map_embed.dart` (`GoogleMapEmbed`: WebView on phones, iframe on web, display-only). `test/google_embed_source_guard_test.dart` fails on a `maps/embed/v1` URL or an Embed key anywhere in `lib/`, the Dockerfile or the scripts.
- **`lib/features/itineraries/presentation/widgets/place_search_box.dart` `PlaceSearchBox`** — the stop form's one search box: OSM on submit (never as the user types), and in the Google Maps segment the Google fallback (a "Search on Google Maps" row, the switch on an empty submitted OSM search, suggestions that follow the typing) with each source's attribution. `domain/search_bias.dart` is where it looks first; `domain/trip_route.dart` `tripRoute` is the one "trip as a route" (route link and Map view).

### Security Middleware Stack

`add_middleware` is **LIFO** — the last `add_middleware` call is the outermost layer (receives requests first, responses last). The correct code order to achieve the desired runtime order is:

```
Code order (first added → innermost):     Runtime request order (outermost first):
  RequestTimingMiddleware           →        ProxyHeadersMiddleware
  OpenHostMiddleware                →        ClientIPHeaderMiddleware
  LanguageCookieMiddleware          →        TrustedHostMiddleware
  ETagMiddleware                    →        ContentSizeLimitMiddleware
  CORSMiddleware                    →        SecurityHeadersMiddleware
  SecurityHeadersMiddleware         →        CORSMiddleware
  ContentSizeLimitMiddleware        →        ETagMiddleware
  TrustedHostMiddleware             →        LanguageCookieMiddleware
  ClientIPHeaderMiddleware          →        OpenHostMiddleware
  ProxyHeadersMiddleware            →        RequestTimingMiddleware
```

Key rules:
- **`ProxyHeadersMiddleware`** (`uvicorn.middleware.proxy_headers`) is outermost — it rewrites `X-Forwarded-Proto` into the scheme (HSTS needs it) and `X-Forwarded-For` into `request.client.host`. With `trusted_hosts="*"` uvicorn 0.41 takes the **leftmost** X-Forwarded-For entry, and Cloudflare *appends* to a client-supplied header, so on its own that IP is caller-chosen.
- **`ClientIPHeaderMiddleware`** (`app/middleware/client_ip.py`), just inside ProxyHeaders, has the last word on `request.client`: it takes `CLIENT_IP_HEADER` (default `cf-connecting-ip`, which Cloudflare overwrites) and falls back to the X-Forwarded-For answer when the header is absent (local dev). Every `slowapi` limit keys on this — before 2026-09-28 any caller could forge its IP past login/register/report/appeal limits. A request that reaches Railway directly can still forge either header; closing that is edge config.
- **`RequestTimingMiddleware`** is added first, so it is innermost; it rewrites nothing. **`OpenHostMiddleware`** (`app/middleware/open_host.py`) comes next: on `APP_OPEN_HOST` it serves `/.well-known/*` as the main host does and redirects everything else to `SHARE_BASE_URL` (a share path with `?app=missing`); inside `SecurityHeadersMiddleware`, so its redirects carry HSTS; unset, it does nothing. **`LanguageCookieMiddleware`** touches only `text/html` responses. None of the three affects the security ordering.
- **Request timing is a log line, never a response header** (`app/middleware/request_timing.py`). A request slower than `SLOW_REQUEST_LOG_MS` (default 1000, `0` = every request) logs one WARNING line — the only level Railway shows: `slow request: POST /itineraries/{itinerary_id}/stops status=201 total=812ms db=45ms/14q ext=api.openai.com:610ms/1 other=157ms`. It logs the **route template, never the path** (no id or username), and a `Server-Timing` header is forbidden: a query count or a duration tells any caller whether an account or a trip exists, undoing the timing-safe login and the identical 404s. Database time comes from class-level `Engine` cursor listeners; outbound time from wrapping the two seams every integration passes through, `requests.Session.send` and botocore's `URLLib3Session.send` (`install_outbound_hooks`) — a new HTTP client library needs a hook there. The record rides a `ContextVar` that anyio copies into the endpoint's worker thread; the clock stops at the last body chunk, so background tasks are not counted.
- **`TrustedHostMiddleware`** reads `ALLOWED_HOSTS` from settings (comma-separated). The apex domain and wildcard must both be listed separately (`ntripi.app,*.ntripi.app`) — Starlette's wildcard does not match the bare apex.
- **`SecurityHeadersMiddleware`** (`app/middleware/security_headers.py`) applies `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Content-Security-Policy: frame-ancestors 'none'`, and (HTTPS only) `Strict-Transport-Security: max-age=31536000`. CSP uses only `frame-ancestors` — `default-src 'self'` is meaningless for a JSON API.
- **`CORSMiddleware`** must use explicit method and header lists — never `["*"]`. Current whitelist: methods `GET POST PATCH DELETE OPTIONS`; headers `Content-Type Authorization If-Match If-None-Match`.
- **Rate limiting** (`slowapi`) — the limiter singleton lives in `app/limiter.py` to avoid circular imports (main.py imports routers; routers cannot import from main.py). Import `limiter` in router files; call `app.state.limiter = limiter` in `main.py`. Current limits: register 5/hour, login 10/minute, search 30/minute, `POST /translations` 60/minute. In-memory store — sufficient for single-instance Railway; needs Redis if horizontally scaled.
- **Generic exception handler** must re-raise `asyncio.CancelledError`, `KeyboardInterrupt`, and `SystemExit` — intercepting these breaks Starlette's lifespan and async request lifecycle.

### Config Invariants
- `SECRET_KEY` is validated at startup with `Field(min_length=32)` — anything shorter raises a `ValidationError` before the server accepts traffic. Generate with `openssl rand -hex 32`.
- `ALLOWED_HOSTS` (comma-separated) drives `TrustedHostMiddleware`. Default: `ntripi.app,*.ntripi.app`.
- `DEBUG=False` disables `/docs`, `/redoc` and `/openapi.json` (`docs_url` / `redoc_url` / `openapi_url=None`). Never set `True` on Railway.

### Database Invariants
- Pool: `pool_size=10`, `max_overflow=20`, `pool_pre_ping=True`.
- Statement timeout: 30 s via `connect_args={"options": "-c statement_timeout=30000"}`. Alembic uses its own `NullPool` engine and is not affected by this timeout.
- **Every FK column needs an explicit index** (`index=True`, or an entry in `__table_args__`). PostgreSQL creates one for the *referenced* key, never for the referencing column: without it the join seq-scans, and a DELETE on the parent locks the child table and scans it whole — which is what a CASCADE to `users.id` does on every account deletion. A column that is the **trailing** half of a composite PK is not covered either: `saved_itineraries` and `itinerary_allowed_users` are keyed `(itinerary_id, user_id)`, so `WHERE user_id = ?` cannot use the PK index. `ix_itinerary_editors_user` is the precedent. The eight remaining unindexed FKs are all `SET NULL` admin/audit columns with no hot read and no cascade scan — deliberately left alone.

### Stop / Track Ordering (fractional indexing)
- **Tracks** are a first-class table (`tracks`). A track is a vertical column of parallel stop alternatives.
- `tracks.rank` and `stops.rank` are lexicographic string keys — `TEXT COLLATE "C"` in PostgreSQL.
- Ordering helper: `app/services/ordering.py` — `key_between(a, b)` and `n_keys_between(a, b, n)`.
- `stops` table has `track_id` (FK) + `rank`. No `position` or `parallel_position` columns exist.
- Track lifecycle: a track only exists when it has ≥ 1 stop. Creating a stop with `track_id=null` creates a new track + stop atomically. Deleting the last stop in a track also deletes the track (app-level, not DB cascade).
- **Arrange mode is the one place a trip's structure changes** (`ArrangeTripView`, `TripArrangement`): track order, alternative order and which track a stop is in, all local until Save sends one `layout` (`docs/features/tracks-and-stops.md`).

### ETag / If-Match (optimistic concurrency)
- Scope: whole-itinerary. Any mutation bumps `itinerary.updated_at`.
- ETag value = quoted ISO datetime of `updated_at`: `"2026-05-11T14:18:05.079393+00:00"`. The Flutter client emits the same field as `…Z` (Dart's `toIso8601String()`); the server's `_normalize_etag()` collapses both forms before byte-compare.
- Every GET returns `ETag` header. Every mutation requires `If-Match` header.
- Only the owner's editing session may move `updated_at`: moderation writes, lock heartbeats and the rating aggregate (`recalculate_rating`) all go through `set_preserving_etag` or leave it alone, or a stranger's action 412s the owner's open editor. Granting or revoking edit rights and the allowlist leave it alone too — they change what some viewer's GET shows, which the body-hash validator already refreshes.
- Missing `If-Match` → 428. Mismatch → 412 `{"detail":"itinerary modified, please reload"}`.
- `_normalize_etag()` strips three intermediary mutations: whitespace, `W/` weak prefix (added by Cloudflare when it recompresses), and `Z` ↔ `+00:00` timezone serialization. **`require_etag` then compares instants, not strings** (`_concurrency_token`, `datetime.fromisoformat` on both sides): Dart drops the sub-millisecond digits when they are zero (`.123Z` vs Python's `.123000+00:00`), and a byte compare left ~1 in 1000 itineraries permanently unsaveable. Anything after `;` (the GET's body-hash suffix, below) is ignored.
- Dependency: `require_etag` in `app/dependencies.py` (SELECT FOR UPDATE + ownership + ETag compare).
- **A trip edit answers with the whole trip when asked** (`?return=itinerary`, every `EDIT_GUARDED` route and both creates): `ItineraryEditResponse {itinerary, created_id}` — exactly the body `GET /itineraries/{id}` would give that caller right after the save, plus the new concurrency ETag. `itinerary` is null only when the save took the caller's view away (moderation hiding an editor's text on the spot). Asked nothing, every route answers byte for byte as before — installed builds depend on it. Ratings: `POST /ratings` appends `rating_avg`/`rating_count` (and `ratings_page` with `?return=ratings_page`); `DELETE /ratings/me` answers them with `?return=aggregate`, or the whole page with `?return=ratings_page`.

### ETag / If-None-Match (cache validation, bandwidth-saving)
- `ETagMiddleware` in `app/middleware/etag.py` hashes every GET JSON response body to a 16-char opaque ETag and sets `Cache-Control: private, no-cache`. When the client returns the value via `If-None-Match`, the middleware replies `304 Not Modified` with an empty body.
- The middleware skips non-GET, non-JSON, non-2xx responses, and the `/uploads`, `/static`, `/app` static mounts.
- If an endpoint sets its own `ETag` header (e.g. `GET /itineraries/{id}` reusing the concurrency token), the middleware emits **`"<that token>;<body hash>"`** and 304s against the composite. The token alone could not validate a cache: the rating aggregate and moderator hides change the body without moving `updated_at`, so viewers kept stale averages and a stale `hidden` flag indefinitely. `require_etag` reads only the part before `;`, so the header still works as an `If-Match`; tests compare it with `conftest.concurrency_part()`.
- The middleware uses `_normalize_etag` on both sides of the comparison, so Cloudflare's `W/` weak downgrade still matches.
- Flutter side: `CachePolicy.request` in `lib/core/api/api_client.dart` honors `Cache-Control` + `ETag` automatically — no per-call changes. A reload (`forceRefreshOptions()`) skips the validator and never takes the stale-on-error copy; a first load still falls back to it.

### Frontend
- Feature-first: `features/<feature>/{data,domain,presentation,providers}`
- Manual `fromJson`/`toJson` — no build_runner/json_serializable
- Three async states always: loading, error, data (and empty)
- **A reload never blanks content already on screen** (since 2026-10-25). Riverpod 3 carries the previous value into every `AsyncLoading` / `AsyncError` a notifier writes, and `when()` still draws them as the loader and the error view — so every `refresh()` goes through `ReloadKeepsContent.reloadKeepingContent`, the only place those two states are written:
  - **Nothing on screen** (first load, Retry from the error view): the loader, then the answer or the error.
  - **Content on screen**: it stays mounted, every opened "view more" with it. An answer replaces it in place — unless a save, a dismissal or a removal wrote the state while the reload was in flight, and then that newer state stands. A refusal (`refusesContent`: 401/403/404/410 — gone, blocked, no longer yours) replaces it with the error view. Any other failure (timeout, offline, 5xx) leaves it and comes back as a `ReloadFailure`.
  - A screen reports a user-started reload with `reportReloads` (a SnackBar — full-screen routes only); a reload the app starts ignores the result. Paging bookkeeping goes in `onApply`, and a `loadMore` page requested before a reload landed is dropped.
  - Reloads are forced and never answered from the HTTP cache's stale copy (`forceRefreshOptions()`); first loads still are.
  - `test/reload_keeps_content_guard_test.dart` fails on a loading/error write, an `AsyncValue.guard` or a `refresh()` outside the mechanism (allowlisted: `PlaceSearchNotifier`, where a new query must not keep showing the last one's results), and on a `.refresh()` in `presentation/` outside `reportReloads(...)` or `unawaited(...)` — a reload is reported or dropped on purpose, never by accident.
  - Whatever a pull does before its reload (clearing covers) is best-effort and cannot stop it: `ImageCacheEviction`.
- Never `ListView` inside `Column` — use `CustomScrollView` + Slivers
- **"View more" is one widget** — `ExpandableText` (`shared/widgets/expandable_text.dart`), used by stop-card notes, review notes and a leg's thoughts. Its overflow check measures with everything `Text` renders with (inherited style, text scaler, bold text, direction); the two private copies it replaced measured with less and left long notes unreachable under large accessibility text. Its `LayoutBuilder` throws on an intrinsic query, so never under `IntrinsicHeight`.
- Grounds, chrome widgets and color tokens: **UX Conventions → Surfaces and Chrome**
- **Keyboard avoidance is one contract** (`shared/widgets/keyboard_avoidance.dart`, held by `test/keyboard_avoidance_guard_test.dart`):
  1. **Whoever lifts content above the keyboard removes the inset from what it passes down.** Scaffold does; the bottom-nav shell does — it rebuilds its tabs' MediaQuery from a context *above* its Scaffold, so it calls `.removeViewInsets` itself (until 2026-10-01 it did not: every tab lifted twice, and 18 screens hid that with `resizeToAvoidBottomInset: false`, which left the root-navigator screens with no avoidance at all); `AboveKeyboard` does.
  2. **Screens keep the default `resizeToAvoidBottomInset`.** `false` only for a page that must not reflow — the map picker (live map) and the cover crop overlay — allowlisted with the reason.
  3. **A sheet with a field lifts its body with `KeyboardSafeSheetBody`** (inset outside the scroll view, cap on the content; show it `isScrollControlled` + `useSafeArea`) **and pins its buttons in `actions:`** — a `SheetActionBar` below the scroll view, never the body's last child (the guard test fails on a call without it). A dialog with a field must shrink: `scrollable: true`, or a `Flexible` list.
  4. **A field and the text that belongs to it are revealed as one unit** with `RevealTogether` — a render object widening the field's own `showOnScreen` request, standing aside when the group is taller than the viewport. `ModerationHint` already wraps every prose field in one.
- Owner UI elements via explicit `currentUser?.id == itinerary.ownerId`
- **A screen opened from outside the app always has a way back** — enter through `GoRouter.pushOverHome` / `openFromOutside`, leave through `popOr`, all in `core/router/navigation_ext.dart` (details under Push Notifications)
- **On the web the address bar shows the screen on top** (`GoRouter.optionURLReflectsImperativeAPIs = true` in `main.dart`), so every route is a URL the app can start on. Two rules hold it, both in the router's redirect and in `core/router/app_links.dart`: **the app never starts on an editing form** (`editingRouteLaunchRedirect` lands the edit forms, the add-stop form and the map picker on what they edit — they save only under a claim the trip page took), and **a trip or profile URL opened signed out is parked through the sign-in** (`signInRedirect`). `test/core/router/landing_routes_test.dart` classifies every route as landable or editing and fails on a new one. A page load of `/app/<path>` is redirected to `/app/#/<path>` (`_SPAStaticFiles`)
- `ItineraryStaleException` thrown by repository on 412 — presentation catches and shows reload dialog
- **A write answers with what the screen shows next, and the app never re-downloads after its own write** (project-wide since 2026-10-22). Named exceptions only: content an answer cannot carry (someone's trips or followers after an unfollow or removal, the feed after a block or unblock, a new row in a list); pull-to-refresh and Retry; sign-in, sign-out and token exchanges; invalidating data no open screen shows. Its applications:
  - **Trip saves**: every trip edit and both creates in `ItineraryRepository` go through `_tripEdit`, which sends `?return=itinerary`; all 15 saves in `ItineraryDetailNotifier` are one call to `_save` / `_saveTrip`, which runs `_write`, `_adopt` (the answered trip becomes the state — the next `If-Match` comes from its `updated_at`, and `addStop` returns the stop the answer's `createdId` names) and `_syncListRows` (the trip's row in Mine / Shared with me becomes `Itinerary.summary` of the answer). A create's trip waits in `tripSeedsProvider` and `build()` takes it, so the new trip opens with no GET. `refresh()` is for pull-to-refresh and Retry; the first load is `build()`.
  - **Editors**: a grant or revoke downloads nothing; `EditorsNotifier.leave` sets `can_edit` false through `editRightsEnded` and drops the Shared row.
  - **Follows and blocks** adopt the `counts` their answer carries — `adoptMyCounts` / `adoptTheirFollowState`, only onto a profile already loaded (reading one that is not builds it, which is a GET).
  - **Accepting the terms** adopts the answered profile (`MyProfileNotifier.adopt`); **an appeal** the answered violations list (`MyViolationsNotifier.adopt`); **a rating** the aggregate (`adoptRatingAggregate`), and the ratings page when it is loaded (`RatingsPageNotifier.adopt`).
  - An answer that replaces a whole GET body — the trip, the profile, the violations list, the ratings page — is also written into the HTTP cache as that GET's entry (`cacheAsGet`): the copy shown offline, which the old reload kept current.
- **Every request to the API travels on one connection pool** — `apiConnectionPool` (`core/api/api_connection_pool_io.dart`), installed by `createDioClient` and `createBareDio`, the only two Dio clients for `kApiBaseUrl` (`api_connection_pool_test.dart` fails on a third). Its `HttpClient` keeps an unused connection for `kApiConnectionIdleTimeout` (120 s): Dio's own adapter closes it after 3 s, and a new connection costs a TCP and TLS handshake (about 50 ms on Wi-Fi from Belgium, more on mobile data). 120 s is above the 30 s lock heartbeat and the 60 s poll, so either keeps the connection warm, and below Cloudflare's 400 s HTTP/1.1 keep-alive, so the app always closes first. dart:io never checks a pooled connection before reusing it and never retries, so `main.dart` **retires** the pool when the app is hidden and when `networkChanges()` (`core/connectivity/connectivity_service.dart`) reports another network: later requests open a new connection, requests under way finish on theirs. Retiring sets the old client's `idleTimeout` to zero, because `close()` would also cancel a request still connecting. On the web the browser keeps its own connections and the pool only delegates. The third-party clients (geocoding, People API, link previews) keep Dio's default — their servers' idle limits are unknown.
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
11 camelCase strings in `place_type` (nullable): `eatDrink` · `sleep` · `pray` · `learnSee` · `buy` · `playWatch` · `nature` · `transport` · `healBathe` · `entertainment` · `sight`
Flutter: always use `PlaceType.fromString()` — handles legacy values (`travel` is the pre-rename spelling of `transport`; the backend rejects it), returns null for unknowns. The other server enums follow the same rule: `AnnotationType.fromString` degrades an unknown value to `info` and `TransportMode.fromString` to `car` — never `values.byName` on a server string, which would fail the whole itinerary parse.

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

### Surfaces and Chrome

One ground, one card, one set of chrome widgets. `0d3b3d0` aligned the form screens; the sheet pass that followed collapsed the last split.

- **Everything paints `nt.surface`** — full-screen routes, modal sheets, dialogs. `bottomSheetTheme.modalBackgroundColor` and `dialogTheme.backgroundColor` both say so, so a `showModalBottomSheet` / `AlertDialog` that passes no `backgroundColor` is already correct; passing one is what breaks the rule. There is no second ground: a sheet is meant to read like the route behind it, white card off a `nt.border` hairline, and in dark mode `nt.surface` is pure black so the hairline is the *only* edge a card gets.
- **`nt.sand` is a warm accent fill, never a background** — `ConfirmDialog`'s cancel pill, avatar and cover placeholders, the arrange-mode drag proxy (`arrange_trip_view`), the bug-report backdrop. Its job is to make one element stand out *against* the surface; using it as a ground is what made sheets read as a different app.
- **Chrome comes from `shared/widgets/editorial_widgets.dart`, never re-inlined**: `EditorialTopBar` (replaces `AppBar` — 17/w700/`-0.2`) · `EditorialDivider` · `SectionLabel` (uppercased internally; do not call `.toUpperCase()` at the call site) · `SectionCard` (`nt.surface`, radius 18, `nt.border`, margin h16) · `FieldDivider` (leading inset only, full-bleed trailing) · `EditorialRow` · `RefreshableCenter` · `AvatarInitials` · `OwnerAttributionRow` · `SheetErrorRow` · `SheetActionBar`. Six private clones of the middle three had already drifted apart before they were extracted.
- **A sheet's buttons never scroll with its content.** They sit in a `SheetActionBar` pinned below the scroll view — `KeyboardSafeSheetBody(actions:)` on a modal sheet, under its own list in the bug reporter — with a top hairline, the bottom safe area, and the sheet's error above them (`error:`). As the body's last child they sat under the keyboard while a field was in use and below the fold once the body outgrew its cap; in the bug reporter, out of sight from the moment it opened.
- **A sheet leads with a title and uses the native handle** — `showDragHandle: true` (48 px tap target and a `Semantics` label a hand-rolled 36×4 box does not have), then a title at 18/w800/`nt.bark`/`-0.3` in `fromLTRB(22, 6, 22, 14)`. Section headers sit at inset 22, cards at 16 — two insets, not three.
- **Every corner is a token of `NtripiRadius`** (`core/ui/app_radii.dart`, re-exported by `app_theme.dart`), one per job: card 18 · field 14 · button 14 · tile 12 · icon 10 · toggle 12 · inset 8 · pill 999 · modal 28 · checkbox 4. A corner takes the token of what it rounds — a ripple the token of the box it highlights, a borderless row's ripple `tile` — never a number. Sheet tops and dialogs are `modal`, set once in `bottomSheetTheme` / `dialogTheme` (and `datePickerTheme`); popup menus `tile` and `SegmentedButton` `toggle`, through the theme. Spacing: card margin 16 · label inset 22.
- **Colors come from `context.nt` only.** `app_theme.dart` is the single source of truth and there is not one `Color` literal outside it (`Colors.transparent` excepted) — keep it that way. `nt.danger` is the destructive color, not `nt.ratingRed` and not `colorScheme.error`; reach for `colorScheme` only for on-colors (`onPrimary`, `onError`) that have no `nt` token. Note `Theme.of(context).dividerColor` is **not** `nt.border` — the theme sets `dividerTheme.color` but never `dividerColor`, so that getter falls through to M3's `outlineVariant` grey.
- **A sheet that fails must say so inline.** `ScaffoldMessenger` snackbars render behind the modal barrier and are never seen, so a sheet that stays open on failure carries its own `String? _error` state rendered with `SheetErrorRow` (`Icon(Icons.error_outline, 18, nt.danger)` + 13/`nt.danger`) — handed to its `SheetActionBar`'s `error:`, so it shows above the pinned buttons wherever the body is scrolled; a sheet without buttons places it itself. That includes a validation refusal like the language picker's cap, not just a failed save.

### Destructive Actions
- **Tier 1** — undo snackbar: `showUndoableActionSnackbar()`
- **Tier 2** — confirm dialog: `confirmDestructiveAction()`
- **Tier 3** — type-to-confirm: `confirmTypedDestructiveAction()`
NEVER write inline `showDialog` for destructive actions.

### Segment orphan warning
When inserting a new track between two adjacent tracks that have a segment connecting them, show a confirmation dialog. The segment becomes invisible once the tracks are no longer adjacent. If confirmed, delete the segment(s) before navigating to the stop form.

---

## Testing

**Backend:** `client` fixture in `test/conftest.py` (fresh SQLite per test). conftest forces `EMAIL_BACKEND=console` before the app loads — a developer `.env` with `resend` otherwise mails every test address (some are real `@gmail.com` domains, and `OPERATOR_EMAIL` is the live ops inbox). Every itinerary write needs `If-Match` + `X-Edit-Lock` — use conftest's `edit_now` / `locked_headers`, never bare `auth_headers`. **SQLite stamps `updated_at` in whole seconds** (`func.now()` → `CURRENT_TIMESTAMP`), so two writes in one second leave the ETag where it was and a stale `If-Match` passes; a test about the ETag moving backdates the row first (`_backdate` in `test_itinerary_form.py`). The six files once parked under `pytest.mark.skip("rewriting after fractional-indexing refactor")` run again (2026-09-26); new itinerary/ordering tests go in `test/test_fractional_indexing_smoke.py`.

**Flutter:** `http_mock_adapter` for Dio mocking. `FlutterSecureStorage.setMockInitialValues({})` for auth state. Shared support lives in `test/support/` — `RecordingDio` (a mocked Dio that logs every request, so "no GET after the write" is an exact assertion, and whose `hold(path)` keeps a request off the wire until the test lets it through — how a test looks at the screen while a reply has not landed), `HeldClaim` (an edit claim this device holds), the trip JSON builders (`tripJson`, `stopJson`, `tripAnswer`…) and `kZeroCounts`; reuse them, never copy them into a test.

---

## Hosting / Deployment

Railway (single Dockerfile) + Cloudflare DNS + Let's Encrypt SSL.

**Postgres must run in the same Railway region as the API (EU West, Amsterdam).** A region is set per service, so moving the API never moves the database. Until 2026-10-20 Postgres sat in a US region: a save makes 8–20 database round trips one after another, each crossed the Atlantic (~120 ms), and saves took 4–6 s. Check without signing in: `https://ntripi.app/share/i/not-a-uuid` (refused before any query) and `https://ntripi.app/share/i/<random uuid>` (one query) must answer in the same time.

Railway env vars: `DATABASE_URL=${{Postgres.DATABASE_URL}}` · `SECRET_KEY` · `ALGORITHM=HS256` · `ACCESS_TOKEN_EXPIRE_MINUTES=1440` · `DEBUG=False` · `SHARE_BASE_URL=https://ntripi.app` · `ALLOWED_ORIGINS=https://ntripi.app` · `STORAGE_BACKEND=r2` · `R2_ACCESS_KEY_ID` · `R2_SECRET_ACCESS_KEY` · `R2_BUCKET` · `R2_ENDPOINT` · `R2_PUBLIC_URL=https://images.ntripi.app` (proxied custom domain — never `pub-*.r2.dev`) · `STORAGE_PUBLIC_URL_PREFIX=/uploads` (keep set: legacy relative URLs still validate against it) · `CLIENT_IP_HEADER=cf-connecting-ip` (the default; the header every rate limit keys on — keep it while the app sits behind Cloudflare). Filesystem fallback for local dev only: `STORAGE_BACKEND=filesystem` + `STORAGE_FILESYSTEM_PATH=/app/uploads`.

Optional: `FEED_TOP_MIN_RATINGS=3` — minimum rating count for an itinerary to appear in the "Top" discovery feed (defaults to 3; lower it while the catalogue is young).

Optional (image moderation — the backend tier): `MODERATION_ENABLED=True` is the master switch, and `MODERATION_PROVIDER` picks the scanner — `rekognition` (default) or `google_vision`; any other value refuses startup. One provider at a time, no fallback chain. Rekognition: `MODERATION_AWS_ACCESS_KEY_ID` · `MODERATION_AWS_SECRET_ACCESS_KEY` · `MODERATION_AWS_REGION` (e.g. `eu-west-1`) · `MODERATION_REJECT_THRESHOLD=80` · `MODERATION_FLAG_THRESHOLD=50` (confidence %, Rekognition only); IAM policy needs only `rekognition:DetectModerationLabels`; set an AWS Budgets $50/mo alert on Rekognition. Google Cloud Vision: `MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON` (the whole service-account JSON, not a path — its own key, never `FCM_SERVICE_ACCOUNT_JSON`'s, so revoking one never stops the other; a real secret) · `MODERATION_GOOGLE_REJECT_LIKELIHOOD=VERY_LIKELY` · `MODERATION_GOOGLE_FLAG_LIKELIHOOD=LIKELY` (SafeSearch levels `POSSIBLE` / `LIKELY` / `VERY_LIKELY`, never percentages; a reject level below the flag level refuses startup). It calls `eu-vision.googleapis.com` with `parent=projects/{project_id}/locations/eu` (the key's own `project_id`), so images are checked in the EU; the project needs the Cloud Vision API enabled and billing on, and Google documents no IAM role for images sent inline. Disabled (default) or a setting of the selected provider missing = uploads stored unscanned, exactly as before — but a missing setting while `MODERATION_ENABLED=True` also emails the operator, naming only that provider's settings, at most once an hour. Scan runs after Pillow processing, before storage: hard-reject (Rekognition: explicit nudity / violence / gore ≥ reject threshold; Cloud Vision: `adult` or `violence` at the reject level) → 422, nothing stored; soft-flag (any Rekognition label ≥ flag threshold; Cloud Vision `adult` / `violence` / `racy` / `medical` at the flag level, `spoof` ignored) → stored + logged + operator-emailed (`OPERATOR_EMAIL`); a failed scan (a provider error, or an answer that is not a verdict) → stored as `pending` (fail-open), and the operator is emailed, at most once an hour. Client-side pre-check (NSFWJS web / TFLite mobile) is a UX/cost optimization only — the backend is the authority; its model files are not vendored (see `social_flutter/{assets/models,web/nsfw}/README.md`).

CSAM hash matching has **no app config** — Cloudflare's CSAM Scanning Tool does it at the edge (dashboard toggle: Caching → CSAM Scanning Tool, notification address = `OPERATOR_EMAIL`). It requires `STORAGE_BACKEND=r2` served from a **proxied custom domain**; a `pub-*.r2.dev` `R2_PUBLIC_URL` bypasses the zone and silently disables the whole layer (the storage factory logs a warning). It scans **serve-time, not upload-time**, blocks matched URLs at the edge, and emails a **daily digest** — it does **NOT** file with NCMEC on our behalf. Removal, the CyberTipline filing (24h from the notice), and preservation are ours: `social_api/docs/media_pipeline_spec.md` + `csam_response_runbook.md`.

`STORAGE_BACKEND=r2` with any `R2_*` var missing now **raises at startup** — silently writing to a filesystem path production no longer serves (the `/uploads` mount is filesystem-only) would strand every upload and take images out from behind Cloudflare. Filesystem backend still needs a persistent volume at `/app/uploads` or images vanish on redeploy.

Optional (text moderation): `TEXT_MODERATION_PROVIDER=openai|local|disabled` (default `disabled`) · `OPENAI_API_KEY` · `TEXT_MODERATION_MODEL=omni-moderation-latest` · `TEXT_MODERATION_TIMEOUT_SECONDS=5.0` · `TEXT_MODERATION_CACHE_TTL_DAYS=30` · `TEXT_MODERATION_LOG_RETENTION_DAYS=90`. Startup **fails** if `openai` is selected without a key — a silent downgrade to the wordlist is worse than not booting.

Moderation sweep — **one of the two drivers is required**, or SLA auto-hide and post-outage re-checks never run: `SWEEP_IN_PROCESS=True` (timer in the app process; no token, no scheduler — the single-instance default) **or** an external scheduler running `curl -X POST -H "Authorization: Bearer $SWEEP_TOKEN" https://ntripi.app/internal/moderation-sweep` hourly (keeps a wall-clock schedule across deploys, which restart the in-process timer). Both at once is safe — the advisory lock makes the duplicate a no-op. Also: `MODERATION_SLA_HOURS=20` (≤22, validated) · `SWEEP_TOKEN` (unset ⇒ `/internal/moderation-sweep` 404s) · `SWEEP_INTERVAL_MINUTES=30` (in-process only; floored at 60s).

Optional (collaborative editing): `EDIT_LOCK_HEARTBEAT_SECONDS=30` / `EDIT_LOCK_IDLE_SECONDS=90` / `EDIT_LOCK_TTL_SECONDS=300`. All have working defaults — the feature ships with no deploy change. Startup refuses `TTL <= IDLE` or `IDLE < 2 x HEARTBEAT`: a claim that becomes takeable before it even reads as inactive would be stolen out from under someone the UI still shows as editing.

Optional (reports/safety): `REPORT_HIDE_THRESHOLDS` (comma `category:count`) · `REPORT_RATE_LIMIT=10/hour` · `ABUSE_CONTACT_EMAIL=abuse@ntripi.app` (must match the in-app address AND the store listing).

**Mailboxes** (Google Workspace on the root MX; Resend sends from the `send.ntripi.app` subdomain, so sending and receiving never collide): `OPERATOR_EMAIL=ops@ntripi.app` is the one to actually set — unset, four alert paths (`report_service`, `moderation_service`, `bug_report_service`, `operator_alerts` — text and image moderation outages) guard on it and skip the email, so the queues fill with nobody told. `abuse@` is published in-app and on the store listing, `privacy@` is hardcoded in all six `app/constants/legal/*.py` bodies as the GDPR controller contact, `support@` and `contact@` are the Flutter `kSupportContactEmail` / `kGeneralContactEmail` defaults, and `noreply@` (the `EMAIL_FROM` sender) must stay a real routed address — users reply to password resets.

Optional (share pages): `SHARE_RATE_LIMIT=120/minute` — per-IP limit on `/share/*`, answered with an HTML 429; the default needs no deploy change.

Optional (request timing): `SLOW_REQUEST_LOG_MS=1000` — a request slower than this is logged at WARNING with its database, outbound-HTTP and remaining time. `0` logs every request: set it for an investigation, then put it back, because Railway keeps every WARNING line. The default needs no deploy change.

Optional (bug reports): `BUG_REPORT_RATE_LIMIT=5/hour` · `BUG_REPORT_RETENTION_DAYS=180`. Both have working defaults — shipping the feature needs no deploy change. `OPERATOR_EMAIL` is what turns the notification email on.

Optional (push notifications): `FCM_PROJECT_ID` · `FCM_SERVICE_ACCOUNT_JSON` (the whole service-account JSON, not a path — Railway has no filesystem for a key file; this one is a real secret) · `FCM_TIMEOUT_SECONDS=10` · `DEVICE_TOKEN_RETENTION_DAYS=180`. Either unset ⇒ push is off and the client's 60 s poll is the only channel, exactly as before. Free — FCM carries no per-message charge — and needs no new Python package, since `google-auth` already mints the bearer. Client side needs `flutterfire configure` to have written `firebase_options.dart` + `google-services.json` + `GoogleService-Info.plist` (the Android build fails loudly without the JSON, deliberately), and iOS needs an APNs `.p8` uploaded to Firebase. Attach Firebase to the **existing** Google Cloud project that holds the Sign-In OAuth clients.

Optional (app links — shared links open the installed app): `IOS_APP_IDS=K8G92959RF.com.ismailkarroud.ntripi` · `ANDROID_APP_PACKAGE=com.ismailkarroud.ntripi` · `ANDROID_CERT_SHA256` (comma-separated SHA-256 of **every** certificate a shipped build is signed with: the Play app-signing key — every Play install, internal testing included — and the upload key) · `IOS_APP_STORE_ID` (numeric; turns on Safari's Smart App Banner, which Safari draws only once the app is live in the store) · `APP_STORE_URL` · `PLAY_STORE_URL` (the share pages' download buttons; unset = the homepage waitlist; paste them without a country or language — no `/us/`, no `&hl=` — or the store opens in that one for everyone) · `APP_OPEN_HOST=open.ntripi.app` (the iPhone **Open in Ntripi**; needs `IOS_APP_IDS`; set it only after the host is a Railway custom domain behind a proxied Cloudflare CNAME, Apple's CDN serves its AASA — `app-site-association.cdn-apple.com/a/v1/open.ntripi.app` — and a build with the second `applinks:` entry is installed). Unset ids ⇒ `/.well-known/apple-app-site-association` and `assetlinks.json` 404 and every link opens the web page, as before. **Deploy the backend with the ids before installing a build that claims the domain** — devices fetch the files at install (iOS through Apple's CDN, which can lag hours). Both files must answer 200 `application/json` with no redirect and no bot challenge: if Cloudflare Bot Fight Mode challenges `/.well-known/*`, add a skip rule. Check with Google's `digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://ntripi.app&relation=delegate_permission/common.handle_all_urls`, Apple's `app-site-association.cdn-apple.com/a/v1/ntripi.app`, and on a device `adb shell pm get-app-links com.ismailkarroud.ntripi`.

Optional (Google Maps Platform — place search and every Google map): `GOOGLE_PLACES_API_KEY` (server only; restrict it to Places API (New)) · `GOOGLE_MAPS_EMBED_API_KEY` (a **new** key restricted to the Maps Embed API and the website referrers `https://ntripi.app/*` plus the dev API host — it is written into `/embed/*` pages browsers load; never the old build-time key) · `GOOGLE_PLACES_USER_HOURLY_LIMIT=60` · `GOOGLE_PLACES_TIMEOUT_SECONDS=5` · `GOOGLE_PLACE_REFRESH_DAYS=365` · `GOOGLE_PLACE_REFRESH_BATCH=100` · `PLACE_SEARCH_RATE_LIMIT=60/minute` · `EMBED_RATE_LIMIT=240/minute` · `EMBED_FRAME_ANCESTORS=self` (add a local web build's origin, e.g. `self http://localhost:5555`; a bare `self` is quoted for CSP). Each key unset ⇒ that half is invisible (no Google row, no Google map, the List/Map toggle hidden). Autocomplete is billed per request — 10,000 free a month, then about $2.83 per 1,000, **with no hard stop by the user's choice** — so set a Google Cloud budget alert on the project. The Embed API and the yearly IDs-only refresh are free. Deploy the backend (with Terms 3.2, which re-prompts every user once) before shipping app builds; keep the old build-time Embed key alive until builds older than 2026-10-31 have aged out.

Optional (Jira hand-off): `JIRA_BASE_URL` · `JIRA_EMAIL` · `JIRA_API_TOKEN` · `JIRA_PROJECT_KEY` · `JIRA_ISSUE_TYPE=Bug` · `JIRA_TIMEOUT_SECONDS=10`. Any of the first four unset ⇒ the "Create Jira issue" button is not rendered (a partially-set config logs which vars are missing). Free — the Jira Cloud REST API carries no per-call charge; the token comes from id.atlassian.com. `JIRA_PROJECT_KEY` is the board key (`NTRIPI`), not a numeric id, and `JIRA_ISSUE_TYPE` must name a type that exists in that project.

The issue's **Reporter is the admin who clicked**, not the service account. Jira Cloud dropped username/email as user identifiers in the 2019 GDPR change, so `jira_service.find_account_id` resolves `admin.email` to an `accountId` first via `GET /rest/api/3/user/assignable/search?project=…` — project-scoped, because "is this person on *this* board" is the actual question. It matches on **exact `emailAddress` only**: `query` also matches displayName, and a loose hit would file the ticket under a colleague's name. Attribution is strictly best-effort — a failed lookup, an unknown admin, or a Jira 400 naming `reporter` all drop the field, file the ticket anyway, and return a `JiraResult.warning` the dashboard shows as a yellow flash beside the green one. Three Jira-side prerequisites, each of which merely degrades to that warning: the service account needs **Browse users and groups** (global) and **Modify Reporter** (project), and **Reporter must be on the create screen** for the issue type.

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
- **An author's rewrite of a profile or review goes through `apply_author_edit_status`**: a whole-text rescan replaces an automated flag, but a takedown (`hidden`/`rejected`) is lifted only by a moderator or an appeal, and a partial profile edit only escalates. The cover endpoints never lower the status either.
- **Any moderation write to an itinerary from outside the owner's own request MUST go through `admin_service.set_preserving_etag` / `moderation_actions.set_status`.** `updated_at` IS the concurrency ETag; moving it 412s the author's open editor over a change they cannot see.
- **Coverage is every stored user string except the moderator-facing ones.** Itinerary title/description, stop name/address/notes, both annotation tables, transport-leg line/direction/notes, rating notes, profile display_name/bio, and the `username` + `display_name` chosen at registration. Deliberately NOT moderated: `content_reports.notes`, `appeals.user_reason`, `bug_reports.message`, and admin action reasons — a 422 there would block someone reporting hate speech who quotes it, which is a safety regression, not an improvement.
- **Account creation scans before it writes.** `create_user` commits, so a rejection found afterwards could not undo the account — `moderate_or_422` runs first, with `author=None`. `POST /auth/google` scans the Google profile name but **never rejects it**: the name is Google's, not something the user typed, so a 422 would lock a real person out with no recourse. A reject there drops the name (as `validate_display_name` already does) and stores `approved` — nothing offensive was persisted.
- **A `hide_escalate` verdict must open a `legal_escalations` row, on every path.** Callers pass `ctx.escalate` to `moderation_actions.escalate_if_flagged` after their flush — the caller is the only party holding the row to point at. The one exception is a *rejected* minors verdict, escalated from `_finalize` against the **author**: nothing was stored, so there is no content row, exactly as a CSAM hash match escalates against the uploader.
- Operator gets an email when the provider chain degrades (fallback, or all-down), throttled to one per hour per level by `operator_alerts.notify_operator` (Shared Helpers) — the helper image moderation's outage alerts use too.

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

## Translation ("See translation")

Readers translate trips, stop notes and annotations, and reviews into their app language — server-side, cached per source hash, one tap per content group. **OFF unless `TRANSLATION_PROVIDERS` is set**: unset, `POST /translations` 404s, `GET /translations/config` answers `enabled: false`, the feed carries no title translations, and the app draws no button. Reference: `docs/features/translations.md`.

- **The client names content and never sends text.** The body is `{target_lang, items: [{content_type, content_id, fields}]}`; the server loads the text itself, so the access check is on exactly what gets translated.
- **Access is the viewer ladder, plus takedown.** `translate_items` checks `can_view_itinerary` once per trip and `can_view_rating` per review. Hidden, rejected or soft-deleted content answers `not_found` **even to its author** — a takedown is never handed to a third party. Missing, forbidden and taken-down are indistinguishable.
- **Engines run in `TRANSLATION_PROVIDERS` order** (`openai,azure`): OpenAI's Responses API with a strict schema, opaque keys and `store: false`; Azure v3 (`zh` is sent as `zh-Hans`). Every output passes `translation_validation` and, with moderation on, output moderation, which fails closed. A failed field falls to the next engine; a field every engine fails is `unavailable` and never cached.
- **The request's transaction ends before any engine call** (`db.commit()` in `translate_items`) — no pooled connection waits on a provider.
- **Cost is capped in Postgres** (`translation_usage.py`): fields per user per clock hour (cache misses only) and characters per engine per UTC day, each an atomic conditional upsert committed on its own.
- **Public titles are translated ahead of time** by a `BackgroundTasks` job (`pretranslate_title`, its own session via `_session_factory`) on a public create, a publish, or a public title change — nothing else schedules it.
- **The feed's language rides in the query** (`?lang=`), never in `Accept-Language`: the client's HTTP cache keys on the URL.
- **Client** (`lib/features/translation/`): one `TranslationToggle` per group — a trip's header with its trip-wide notes and every leg's thoughts, a stop with its notes, annotations and the thoughts on its inbound and outbound legs, one review — and every `TranslatableText` in the group watches the same `contentTranslationProvider((type, id, lang))`. Read mode only. The notifier keeps only final answers, each with the text it was made from; a 404/400 re-reads `translationConfigProvider`. Both providers are in `_userScopedProviders`.
- **A leg's thoughts never bring a toggle of their own** — `legThoughtsMembers` (`widgets/leg_thoughts.dart`) adds them to the trip's group on the trip page and the stop's on a stop page. `TranslatableText` returns one tree shape (a `Directionality` around the builder) for the original and the translation, so a swap keeps the builder's state — an unfolded "view more" stays unfolded.
- **Feed titles** (`FeedTitle`): a title in one of the reader's profile `languages` shows as written with a toggle; any other shows translated with a lit marker. Neither is a request.
- **Every engine is named in Privacy §4 and §5, in all six languages** — `test_privacy_names_every_translation_engine`.

## Bug Reports (shake to report)

Shaking the phone captures the screen, lets the user draw on it, and files a support ticket. Deliberately **not** part of the moderation stack: `content_reports` is evidence about content someone else published, with hide thresholds and escalation paths; `bug_reports` is a ticket about our own app, reviewed at `/admin/bugs` and purged once closed and stale.

- **Two packages, one custom sheet.** `shake` (accelerometer, pulls `sensors_plus`) and `feedback` (screenshot + draw layer). The compose UI is ours via `feedbackBuilder` — `lib/features/bug_report/presentation/bug_report_sheet.dart`, mirroring `report_content_sheet.dart`.
- **The compose sheet pins Cancel / Send report in a `SheetActionBar` below its list, and asks for the message before the optional category.** The package opens the sheet at `feedbackSheetHeight` (0.45 of the screen) — shorter than the form — so a Send inside the list started out of sight on every phone; the package's own `StringFeedback` pins its button the same way. Send stays disabled until a message is typed, so the field comes first, where the collapsed sheet shows it beside Send. Regression tests: `test/features/bug_report/bug_report_sheet_test.dart` ("on a phone").
- **`BetterFeedback` must wrap `MaterialApp`, not sit inside `MaterialApp.builder`.** Its bottom sheet builds a bare `Navigator`; inside MaterialApp that Navigator inherits the app's `HeroController` and Flutter asserts ("a HeroController can not be shared by multiple Navigators"). The consequence is that the sheet renders **outside** MaterialApp, so it gets l10n from the delegates passed to `BetterFeedback` (the app's own are listed there) and its `ThemeData` from `ntripiFeedbackAppTheme` in the `feedbackBuilder`. `localeOverride` is required too — that scope otherwise resolves the *platform* locale and ignores the in-app language picker, and it is what drives `Directionality` for Arabic.
- `ShakeToReport` stays *inside* `MaterialApp.builder` so the handler has a `ScaffoldMessenger` for the confirmation snackbar; `BetterFeedback.of()` still finds the controller above.
- **`BetterFeedback` owning the outermost `Overlay` redefines what `rootOverlay: true` means app-wide.** The package hosts the entire app in one `OverlayEntry` with `maintainState: false`, so `Overlay.of(context, rootOverlay: true)` now resolves *outside* MaterialApp: an entry inserted there gets no app `Theme` and no app `Localizations`, and an `opaque: true` one drops the app's own entry from the element tree — unmounting every route, disposing them, and then throwing from `LocalHistoryEntry.remove()` on the dead route so the overlay can never close itself. Anything wanting a full-window layer above the app wants `Navigator.of(context, rootNavigator: true).overlay` instead (`openImageCropOverlay` in `cover_image_field.dart`; regression test `test/widgets/cover_crop_overlay_test.dart`). `field_help.dart` still uses `rootOverlay` — it is safe only because it is non-opaque and captures its colors from the caller's context.
- **The gesture is opt-out-able** (`shakeReportEnabledProvider`, secure storage, default on) and guarded: `minimumShakeCount: 2`, paused whenever the app is not `resumed`, a 3 s cooldown, and skipped on `/splash`. No-op on web (`kIsWeb`) — the Settings ▸ Support row is the entry point there.
- **`POST /bug-reports` is one multipart request** carrying the fields and the screenshot. Two requests would orphan the object in R2 whenever the second failed. Auth-optional — someone stuck on the login screen is exactly who needs to report.
- **Screenshots use `process_screenshot_image`**, not the cover/avatar processors: those cover-crop (destroying a portrait capture) and reject anything under `MIN_DIMENSION=600`. It preserves aspect, downscales to a 1600 px long side, and relaxes the minimum via `_decode_and_validate(min_dimension=…)`.
- **No image scan on the screenshot** — it is never served to another user, so a hard-reject could only drop a real bug report because our own UI tripped a classifier. `process_and_store` still strips EXIF.
- `screenshot_key` stores the **storage key, not a URL**: the retention purge needs it, and it keeps bug screenshots outside `admin_service.parse_storage_key`, whose whole job is refusing to guess.
- **Retention is a privacy duty**, not housekeeping — a screenshot can contain a third party's data. `bug_report_service.purge_expired` runs from `sweep_service`, deletes the object before the row (so a storage failure retries next sweep), and only ever touches **closed** reports.

---

## In-App Notifications

A bell beside the profile settings gear opens `/notifications`; three of the eight types can be switched off in `/settings/notifications`. Delivery is a foreground poll plus **FCM push on iOS and Android** (see Push Notifications below); web is poll-only. Operators keep their `OPERATOR_EMAIL` mail and additionally get badge counts in the `/admin` nav.

| type | trigger | mutable |
|---|---|---|
| `follow_request` / `new_follower` | `follow_user` — branches on `is_private` | no |
| `moderation_action` | `moderation_actions.auto_hide` + `admin_service.hide_itinerary` / `soft_delete_itinerary` / `warn_user` | no |
| `follow_accepted` | `accept_follow_request` + the bulk auto-accept in `update_me` | **yes** |
| `itinerary_rated` | `upsert_rating`, **insert branch only** | **yes** |
| `itinerary_saved` | `save_itinerary`, **below the idempotent early-return** | **yes** |
| `itinerary_editor_added` | `add_editor` | no |
| `itinerary_viewer_added` | `add_allowed_user` | no |

- **The two access grants name the itinerary in the sentence itself**, not in the subtitle: a restricted trip is in no feed and no search, so "you were added as an editor" leaves the reader with nothing to act on until they know which one. `entityTitle` is already on every row, and the subtitle is spent on what the access allows instead (edit vs view) — the one thing the two rows do not share. Naming someone else's itinerary is safe here and only here: the grant being announced is what confers the right to see it. `add_editor`'s `grant_view` writes its allowlist row inline and sends **only** the editor notice — two rows for one action would be noise.
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
- **The feed has a loud read and a quiet one — `refresh()` and `silentRefresh()`.** Nobody asked for the quiet one, so it may not show a spinner and may not write `AsyncError`: a failed `silentRefresh` keeps the loaded feed, exactly as a failed `poll` keeps the last good badge. `refresh()` reloads through `ReloadKeepsContent` like every other: the list stays under the user's finger through the pull, and a failed pull keeps it and says so in a SnackBar (`reportReloads`).
- **The badge has only `poll()`** — no forced variant. The three user actions that change it (`markAllRead`, `clearAll`, a committed delete) invalidate the provider outright, and a feed load hands its badge over via `setBadge`. `poll()`'s first call lands while `build()` is still in flight, so it awaits `future` rather than racing a second request for the same value.
- **`latest_at` is the arrival signal, not the count.** `GET /notifications/unread-count` answers `{unread_count, latest_at}` (`notification_service.badge_state`, one query, `MAX(created_at)` off `ix_notifications_user_created`), and `NotificationBadge.arrivedSince` — the single comparison the cue and the screen both use — tests that timestamp advancing. A count rise looks like the same thing and is not: reading one notification on another device while another arrives leaves the count untouched, so the arrival would be swallowed. The count is only ever the number on the bell. `arrivedSince` still returns false without a baseline, which is what stops every cold launch sounding like an arrival.
- **`silentRefresh()` refuses to run while a delete is queued.** Reloading inside the undo window puts the dismissed row back under the user's finger, and flushing the queue first would destroy the undo they were just offered. Like `poll()`, it awaits `future` instead of racing an in-flight `build()`.
- The badge already rides along with every feed page, so `refresh()`/`silentRefresh()` push it via `setBadge` instead of spending a second request. Pushing the page's `latestAt` is what stops the next poll announcing a row the user is already looking at. Never from `build()` — writing another provider mid-build is what Riverpod forbids outright.
- **Both screens refetch on open, before acting on what they loaded.** `notificationsProvider` and `followRequestsProvider` are keep-alive, so a second visit renders the first visit's data. On the notification feed the order is load-bearing: `markAllRead` on a *cached* feed marks a row the user has never been shown read on the server — badge cleared, cue already played, row never surfaced anywhere again. `_pullInArrivals` is `silentRefresh()` **then** `markAllRead()`, and `markAllRead`'s null-value early return is what keeps a failed load from clearing the badge anyway.
- **The refetch is unconditional.** `GET /notifications` carries the rows *and* the badge and goes through `ETagMiddleware`, so the conditional GET answers 304 with an empty body when nothing changed — it is already conditional where the comparison is exact. Gating it on the badge would skip when the badge is merely stale (up to a full interval), and skip forever after a read on another device drove `unread` to 0.
- `RefreshableCenter` (`shared/widgets/editorial_widgets.dart`) is how an empty or errored list stays pullable. A `RefreshIndicator` wrapped around the populated list sits behind the `isEmpty` early return, which strands the exact two states where the user most wants to ask again.
- **`EditorialDivider(loading:)` is the on-open refetch's only visible sign.** The reload deliberately leaves the previous rows on screen, so without it the screen just sits there until content changes under the user — and a `RefreshIndicator` cannot fill in, because it only draws for a real drag. Its 2 px box is fixed with the idle hairline top-aligned inside, so toggling never nudges the content. The screens raise it with `setState` from a **post-frame callback**, since `didChangeDependencies` runs inside the build pipeline.

---

## Push Notifications (FCM)

Delivery for the notification feed above, on iOS and Android. **OFF unless `FCM_PROJECT_ID` and `FCM_SERVICE_ACCOUNT_JSON` are both set** — the same "unset = invisible" rule as `JIRA_*`; unset, nothing is sent, nothing raises, and the poll is the only channel exactly as before.

- **Push is a latency improvement over the poll, never a replacement.** FCM delivery is best-effort: OEM battery managers kill background processes, iOS throttles, a token goes stale silently, permission can be denied. `NotificationPoller` stays, and stays unconditional — gating it on push would inherit push's failure modes. Nothing may be load-bearing on a push arriving.
- **Zero new backend dependencies.** FCM HTTP v1 wants an OAuth2 bearer from a service account, which is what `google-auth` (already installed for Sign-In) mints — through `google_service_account` (Shared Helpers), which Cloud Vision image moderation shares with a key of its own. So `push_service.py` is a `requests.post`, shaped like `jira_service.py`, not an SDK. It **fails open** like `email_service` and unlike `jira_service`: nobody is waiting on it, and a Google outage must not 500 a follow.
- **Push is queued `after_commit` and NEVER sent from inside `notify()`.** `notify()` adds its row to the caller's open transaction, so sending there would push for transactions that later roll back — and a push cannot be un-sent. `notify()` appends a `PendingPush` snapshot to `Session.info["pending_pushes"]`; the `after_commit` listener in `push_service.py` drains it. An `after_soft_rollback` listener clears the queue, or a rolled-back event would ride out on whatever commits next.
- **One background worker sends it, never the request** (since 2026-10-22). The listener hands the batch to `_submit` — a module-level `ThreadPoolExecutor(max_workers=1)`, run in an empty `contextvars.Context` — so no write waits on FCM and the request-timing line never counts it. Tests run it inline by patching `_submit`.
- **The worker uses its OWN session** (`_session_factory`), never the request's. Pruning a dead token needs a commit, and the request's session is not the worker's to use.
- **`PendingPush` is a snapshot, not the ORM row.** After commit the row's attributes are expired and touching one fires a lazy reload on a session between transactions. Resolving actor name and itinerary title inside `notify()` also means the dispatcher queries nothing but `device_tokens`.
- **Suppression is inherited, not reimplemented.** Because push hangs off `notify()`, the self / muted / blocked rules and the three `notify_*` columns govern it for free. There is no fourth preference column — the OS permission is the master switch, and an in-app toggle would just create a state where the OS says yes and the app says no.
- **Server-rendered push text does not violate the "no stored rendered text" rule.** The OS draws the tray entry before our code runs, so client-side rendering is impossible; but the payload is transient and the `notifications` table still stores only the structured reference. `app/constants/push_i18n.py` holds the strings, copied **verbatim** from the app's `.arb` files so a tray entry and its feed row read identically — reword one, reword the other in the same commit.
- **Locale lives on `device_tokens`, not on `users`** — one account can be a phone in French and a tablet in English, and it costs no new user column. Normalised on the way in (`fr-CA` → `fr`, junk → `en`), never 422.
- **The actor falls back to `@username`, not to "Someone".** Same as the feed. `push_i18n`'s localised "Someone" is only for rows with no actor at all; using it for a user who never set a display name would make an ordinary person anonymous.
- **`device_tokens.token` is UNIQUE, not `(user_id, token)`.** FCM reassigns a token to whichever account is signed in on that install, so registering is an upsert that MOVES the row. Otherwise two people sharing a phone leave the first still receiving the second's notifications.
- **Sign-out must `DELETE /devices/{token}`**, before the repository call that discards the access token. A token that outlives the session delivers the previous user's notifications — including moderation notices — to whoever signs in next. `_registeredToken` is memory-only, so on launch `attachPushListeners` **re-adopts** the registration when the OS already granted permission and a session exists (`getNotificationSettings()` never prompts), and `unregisterForPush` falls back to `getToken()` — after a restart it used to unregister nothing. **Sign-in re-adopts as well** (`setAuthenticated` → `readoptPushRegistration`): sign-out deleted the row, so the next account got no push until a cold start. **Every POST goes through `RegistrationGate`**, which refuses a registration whose session has ended and makes sign-out wait for one already on the wire — a POST landing after the DELETE re-creates the row for the account that left (`test/core/push/registration_gate_test.dart`).
- **Dead tokens are pruned on `UNREGISTERED`, and on `INVALID_ARGUMENT` only when the error names the token** (a `message.token` field violation or "registration token" in the message) — FCM also answers `INVALID_ARGUMENT` for a malformed *payload*. A 500, a 503, or a 401 from a misconfigured key is transient and must never cost a working device its registration — that is unrecoverable without a reinstall. The sweep additionally purges rows idle past `DEVICE_TOKEN_RETENTION_DAYS` (an uninstall never tells us).
- **Client is mobile-only and fails silent.** Every entry point in `lib/core/push/` is `kIsWeb`-guarded, and `initFirebase()` swallows a missing `google-services.json` so the app still launches without push. `PushGateway` (in `MaterialApp.router`'s builder, beside `NotificationPoller`) owns the router and locale; `push_service.dart` owns the FCM plumbing.
- **Never call `getToken()` directly — `_fetchToken` waits for the APNs token first.** On iOS the FCM token is minted from it, Apple delivers it asynchronously after launch, and a `getToken()` that wins the race throws `apns-token-not-set` — which every caller swallowed, so the iPhone silently never registered. `test/core/push/apns_token_wait_test.dart` fails on a bare call.
- **The permission prompt is asked on `/notifications` and nowhere else.** iOS allows exactly one per install and a denial is only reversible in Settings, so it lands when the user has just shown they want notifications — not at launch, in front of an app they have not seen.
- **A cold start's tap is routed by the splash screen.** `getInitialMessage()`'s answer is kept as a future; splash awaits `takeInitialPushRoute()` after its brand flash and opens the route over home in **one** navigation — `GoRouter.pushOverHome` (`core/router/navigation_ext.dart`). A post-frame drain lost every such tap — the platform reply lands after the first frame, and splash's own `go('/profile/me')` overrode it — and `go(home)` then `push(route)` raced the redirect: `push()` builds on the stack as it stands at the call, `go()` lands only after the async redirect, and splash's loader keeps frames coming, so the tap could end up stacked on splash. This is the most common real-world path and the easiest to lose.
- **A warm tap opens over the screen the user left** — `openTappedRoute` (`push_gateway.dart`) → `GoRouter.openFromOutside`, never `go()`, which replaced the stack and left the tapped screen alone on its navigator: a back arrow that did nothing, an Android back that closed the app, and the user's own screen destroyed. A root-level destination is pushed over the current screen; one inside the tab shell (`/follow-requests`, `/settings/account-status`) opens over home, because pushed over a root-level page go_router appends a second shell whose navigator keys collide. A tap while splash still owns the first navigation goes to `deferTapToSplash`; one on a `kPublicRoutes` screen is dropped. `test/core/push/tap_routing_test.dart` runs every notification type through both paths — the cold one on the real `SplashScreen` at 60 Hz, since `pumpAndSettle`'s 100 ms steps hide the race.
- **Every screen a notification can open leaves through `popOr`, in every state** — the other-user profile (hero, error, account unavailable), the trip (hero, error), its ratings, Follow requests, Account status — so it has a way out even alone on its navigator. `test/widgets/notification_destinations_exit_test.dart` fails until a new `notificationRoute` destination has a case.
- **Tap routing reuses `notificationRoute()`** (`app_notification.dart`), a free function precisely because a push arrives as a bare `data` map with no `AppNotification`. A tray tap and a feed tap must never disagree.
- Foreground messages are deliberately unhandled: Android suppresses the tray entry while the app is open, and the poller's badge + `Sfx.newNotification` already announce the arrival.

---

## App Links (shared links open the app)

A tap on `https://ntripi.app/share/i/{id}` or `/share/u/{username}` opens the app when it is installed (iOS Universal Links, Android App Links); in a browser signed in to Ntripi it opens the web app at once; otherwise the share page shows a teaser and one way in, **See the full trip**, into the web app — and **Open in Ntripi** on a phone. A typed or pasted link never opens an app, and neither does an `/app/#/…` address. Reference: `docs/features/app-links.md`, `docs/features/sharing.md`.

- **Share links only.** The claim is `/share/i/*` and `/share/u/*` — never `/*`: emailed reset, verification and appeal links are web forms. It is one contract across four places, changed together: `services/app_links.py` `APP_LINK_PATHS` (the AASA), the manifest's `autoVerify` intent filter, `Runner.entitlements` (`applinks:` hosts only — the share host and `open.` + it, which `APP_OPEN_HOST` must name), and `appLinkLocation` in `lib/core/router/app_links.dart`. `test/app_links_native_config_test.dart` holds the client's three to the release `SHARE_BASE_URL`; `test_app_links.py` holds the server's to the real `/share` routes.
- **Open in Ntripi, one tap from the page** — no page can open an app by itself. Android: the `intent://` button, led when Chrome says the app is installed (`asset_statements` in the app ↔ `/manifest.webmanifest` on the site) and hidden when it says it is not. iPhone: a link to the same path on `APP_OPEN_HOST` — iOS hands only a cross-host tap to an app; without the app Safari loads it, and `OpenHostMiddleware` sends it back with `?app=missing`, which the page reports. That host serves nothing but `/.well-known/*`.
- **A reader signed in on the web goes straight in.** The web app keeps `ntripi_web_session_until` in localStorage (`web_session_hint.dart`: written by `saveTokens`, removed by `clearAllTokens`, synced at launch); `reader_head` reads it before the body is drawn and leaves with `location.replace`. An installed Android app wins over it; iOS cannot tell, so a signed-in iPhone goes to the web app.
- **Flutter's own deep linking, no plugin** (`FlutterDeepLinkingEnabled` / `flutter_deeplinking_enabled`, stated explicitly). A plugin such as `app_links` would need it turned off.
- **A link never lands as it arrives.** Cold start: `appLinkLaunchRedirect` (the redirect's first step) parks it and goes to `/splash`, which opens it over home through `landHome`. Running: `appLinkOnEnter` (the router's `onEnter`) opens it over the current screen with `openFromOutside`, reading the visible page from `current` — `currentConfiguration.uri` stays at the route pushes sit on. During splash, or signed out: parked, and the next `landHome` — splash, password login, Google login, registration — opens it. **A link is parked while signed out; a tray tap is dropped** — a link belongs to no session.
- **Two answers when a link can't be opened, neither saying why and neither with a Retry**: no access (the API's one 403 `itinerary_access_denied`, which a block shares) and not available (404, or a link `appLinkLocation` cannot read — checked before anything is fetched, so `/share/i/new` never opens the create-trip form). Offline and server errors keep Retry.
- **`MainActivity` is `launchMode="singleTask"`.** `singleTop` + `taskAffinity=""` started a second copy of the app in the caller's task for a link tapped in Gmail.
- **A private trip's share page names nothing about it** — no title, owner or cover, on the page or in its preview card, and the router passes `share_private.html` no trip to leak. Each **Open in Ntripi** is revealed on its own platform only — Android's `intent://` link, the iPhone's link to `APP_OPEN_HOST` (a same-domain link never opens an app on iOS) — and the `[hidden]` rule in `app_links_head` is load-bearing.
- **A reader without an account gets the teaser and nothing else** — a public trip's title, cover, rating and description; a profile's display name, @username and avatar — the same for a person, a chat crawler and a search engine, and the chat card says what the page says. `prepare_share_context` / `prepare_profile_share_context` pass the templates those fields, never the row. `test_public_surface.py` classifies every route reachable without sign-in and seeds a marker into every non-teaser field; a new open route fails the suite until classified.
- **The way in is the web app first** (`/app/#/share/…`, which parks the link through sign-in — `ParkedLinkNotice` says so above the form); a phone whose store is live gets that store first, with "tap the link again once installed". `/share/*` is rate-limited per IP (`SHARE_RATE_LIMIT`, HTML 429).
- **A phone is offered only its own store** — Google Play on Android, the App Store on an iPhone or iPad (iPadOS Safari reports a Mac; its touch points give it away). `platform_head` decides once, in `<head>` so the other badge never flashes, and `app_links_script` reads its answer; a laptop, an unknown device and a browser without JavaScript get both, which stay in the HTML. `test_app_links.py` pins the templates that render store buttons and checks each one's `<head>`. The page's language is the reader's own (`resolve_lang`; share links carry no `?lang=`), and the app's first launch walks the device's language list the same way (`firstSupportedLocale`).

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

## Collaborative Editing (editors + edit lock)

An itinerary has one owner and any number of **editors**, plus a server-enforced
**edit lock** so two people never write at once. Everything is decided
server-side; the client renders state and may be stale or hostile.

### Editors

- **`itinerary_editors`** mirrors `itinerary_allowed_users` exactly — composite PK
  `(itinerary_id, user_id)`, both FKs CASCADE, presence means granted, revoke by
  deleting the row. It adds `granted_by` (SET NULL, audit only) and an
  `ix_itinerary_editors_user` index, which the allowlist does not need: this table
  *is* queried by the trailing column ("itineraries I can edit").
- **`can_edit_itinerary()` in `itinerary_access.py` is the single source of truth**,
  and it *delegates to `can_view_itinerary()` first*. That is what makes edit
  rights re-derived rather than stored: a block, a visibility change, a moderator
  hide, a banned owner or a soft delete revokes editing the moment it revokes
  viewing, with no rows to clean up and no sweep. There is one access ladder,
  never two.
- **Only the owner grants or revokes.** An editor cannot recruit more editors —
  the grant is the owner's trust decision and does not carry the power to
  delegate it. `GET /editors` is readable by editors too (someone sharing a
  document should see who else holds a pen).
- **Granting to someone who cannot view answers 409 `editor_cannot_view`** with
  `{visibility, can_fix_with_allowlist}`. That is a question, not an error: the
  client asks the owner and re-posts with `grant_view: true`. `grant_view` only
  ever inserts an `ItineraryAllowedUser` row and only for `restricted` — it must
  never change `visibility`, because `followers` -> `restricted` silently cuts off
  every follower and `only_me` -> anything is a privacy decision the owner has to
  make deliberately on the visibility screen.
- Revoking **also deletes that user's lock row**, in the same transaction —
  otherwise a removed editor's claim blocks everyone until the TTL runs out.
  Removing a follower and a block (both directions) can end edit rights on all
  of an owner's trips at once, so they call
  `edit_lock_service.release_claims_lost_by(db, owner_id, user_id)`, which
  drops only the claims the person can no longer edit.
- The editor endpoints leave `updated_at` alone, like the allowlist (since
  2026-10-22; they used to call `_touch_itinerary`). `ItineraryDetail.can_edit`
  rides in the detail, but its cache validator is `"<updated_at>;<body hash>"`,
  so a changed `can_edit` already fails a cached copy's 304; the bump only made
  the owner reload to learn the new stamp. The guard re-derives the right on
  every save.
- New notification type **`itinerary_editor_added`**, mandatory (not in
  `MUTABLE_TYPES`, so no new boolean column on `users`) — edit rights nobody
  knows they hold are edit rights nobody uses.

### Finding a shared trip again — `GET /itineraries/shared-with-me`

- The grant notification cannot be the only way back to a shared trip: a
  `restricted` itinerary is in no feed and no search, and notifications are
  purged (90 days read / 365 hard cap). This is the durable surface, and it is
  the only query that reads `itinerary_editors` by its trailing column — what
  `ix_itinerary_editors_user` was created for.
- **Reuses `ItineraryFeedItem` and `_to_feed_item`**, not a new schema: summary
  + `owner: RaterInfo` is exactly this payload, and `_to_feed_item` already
  routes the display name through `public_profile_text`. `ItinerarySummary`
  gains **no** `can_edit` — that would churn the key order of `/me`, `/saved`
  and `/feed` for a flag only this list needs.
- Two filters, like `/saved`: `public_listing_criteria` in SQL (deleted /
  hidden / banned owner / blocked, and it needs the `join(User)` the attribution
  wants anyway), then **`can_edit_itinerary` per row** — the SQL half does not
  cover the visibility ladder and a granted editor's access is usually
  `restricted` or `followers`. Its re-lookup of the editor row the join already
  proved is deliberate: one access ladder beats saving a query.
- Mine and Shared are **disjoint by construction** (`add_editor` 400s on the
  owner), so the merged view needs no de-duplication.
- A read, so `test_edit_guard_coverage.py` neither covers nor wants it —
  adding it to any of those four sets fails the suite on `classified - live`.
- Frontend: `sharedWithMeProvider` stays a **separate provider** from
  `myItinerariesProvider` — two endpoints that fail independently, and the
  active segment decides which must be settled, so a dead `shared-with-me` can
  never blank the Mine segment. The scope selector, the loader and the error
  therefore all live **inside** the list: replacing the screen wholesale would
  take the control away with it and strand the user on a scope they cannot
  leave. Client-side filter only — flipping segments must not refetch.
- **A row's provenance, not an id comparison, gates the owner-only chrome.**
  `/itineraries/me` is owner-only by construction, so a null `owner` is a
  stronger signal than `currentUser?.id == itinerary.userId` and needs no
  profile load. Shared rows get `SharedItineraryCard` (attribution + an Editor
  badge, no share action) and never the long-press delete.
- `OwnerAttributionRow` (`shared/widgets/editorial_widgets.dart`) is the row
  `FeedCard` and `SharedItineraryCard` share. It takes plain nullable strings
  rather than a `FeedOwner` so `shared/` never imports a feature's domain layer.

### Edit lock

- **`itinerary_edit_locks` has `itinerary_id` as its PRIMARY KEY**, so "at most
  one holder" is a database invariant rather than something app code remembers.
- **The claim is identified by a rotating opaque token, never by `user_id`.**
  `token_hash` stores only the SHA-256 (`token_util`, same treatment as refresh
  and email tokens); the raw token is returned exactly once, by the claim
  endpoint. Every takeover mints a fresh one, and *that rotation is the entire
  mechanism* behind "the displaced device cannot save": it still holds the old
  token, still believes it is editing, and fails closed on its next write. A
  `user_id` comparison could not express this (the same person on a second device
  looks identical) and a check at acquire time could not express it at all.
- **No `expires_at` column.** Staleness is derived from `last_heartbeat_at`
  against the config windows at read time, so raising the TTL takes effect on
  claims that already exist.
- **`state` is computed server-side and shipped as a word** — `active` (heartbeat
  current) / `idle` (quiet, claim still stands, presentational only) / `takeable`
  (past the TTL, any editor may take it). The client renders it and counts down
  against absolute timestamps; it never derives it. The GET body carries
  **absolute timestamps and no remaining-seconds field**, so it stays
  byte-identical between polls and `ETagMiddleware` answers 304.
- **`takeover` defaults `false` on every displacing path** — a takeable claim,
  your own other device, and the owner's immediate reclaim all need the explicit
  flag, so a steal is always a deliberate second call the UI confirmed.
- `DELETE /lock` is **idempotent and never 404s** (same rule as the notification
  DELETE — the client fires it from teardown). The owner may release without a
  token: that is the "unlock it from my other device" path. **A token, when
  sent, ends only the claim it names — the owner's included**: the client hands
  journalled claims back late, and by then the owner may hold a newer claim on
  another device.
- Config: `EDIT_LOCK_HEARTBEAT_SECONDS=30` / `EDIT_LOCK_IDLE_SECONDS=90` /
  `EDIT_LOCK_TTL_SECONDS=300`. A startup validator refuses `TTL <= IDLE` or
  `IDLE < 2 x HEARTBEAT`. `sweep_service._purge` deletes long-dead rows
  (`edit_locks_purged`) — housekeeping only; a surviving row still reads
  `takeable`.

### The guard

`require_edit_access` in `app/dependencies.py` — the same object as
`require_etag`, which keeps its name for the ten endpoints and the docs that
already use it. Order is load-bearing:

```
1. 404  missing OR deleted_at is not None   (require_etag never checked this)
2. 403  itinerary_not_owner   - can_edit_itinerary() false
3. 428  edit_lock_required    - no X-Edit-Lock header
4. 409  edit_lock_lost        - no lock row, or the token does not match
5. 428 if_match_required / 412 itinerary_stale
6. refresh the claim's heartbeat - saving is activity
```

- **Step 4 sits above step 5** deliberately: after a takeover the ETag has usually
  moved too, and 412 would send the user to reload into a screen they still
  cannot save from. "You lost the claim" is the more specific truth and the only
  actionable one.
- **409, not 423, on the write path.** 423 means "you asked to claim and cannot"
  (answerable by waiting or taking over); 409 means "you believed you held it and
  do not" (protect the unsaved input). The client reacts differently to each.
- **A matching token past its TTL is honoured** and its heartbeat refreshed —
  nobody took the claim, so refusing would discard real work to enforce a
  deadline that was not holding anyone up.
- **Editor rights are content only.** Owner-only: delete the itinerary,
  `visibility` (rejected in `update_itinerary`'s body — the guard admits editors,
  the body does not), the allowlist, the editor list, and the **cover image**
  (the trip's public face, and every upload spends a paid image scan).
  The Edit itinerary form saves through `PATCH /itineraries/{id}/form`, which
  the guard admits editors to for the fields; an `image` or `remove_cover` part
  from an editor is a 403 for the whole request, nothing saved.
- **One user action is one guarded write.** The form used to send its cover
  through `POST`/`DELETE /image` (`OWNER_ONLY`, outside the guard) and then
  PATCH the fields with the `If-Match` read before — every cover write that
  changed the row 412'd the PATCH. Never split a save into a lock-free write
  and a guarded one again; the `/image` pair stays only for installed builds.
- `X-Edit-Lock` must stay in `main.py`'s CORS `allow_headers` or the browser
  preflight fails before the request is sent.

### `test_edit_guard_coverage.py` — the structural proof

Introspects `app.main.app.routes` and asserts every mutating route under
`/itineraries/{itinerary_id}` is in **exactly one** of `EDIT_GUARDED` /
`OWNER_ONLY` / `LOCK_ENDPOINTS` / `VIEWER_WRITE`, that every `EDIT_GUARDED` one
depends on `require_edit_access`, and that none of the others do. A new endpoint
fails the suite until somebody classifies it — that is what keeps "no exceptions"
true for code nobody has written yet. `VIEWER_WRITE` (ratings, saves) is exempt
because those write sibling tables, never itinerary content.

### Frontend

- `EditLockNotifier` (`providers/edit_lock_provider.dart`, family by itinerary
  id, **not autoDispose**) owns the token and the heartbeat. It lives in a
  provider because the claim must survive the detail screen being covered by the
  stop form. Saves and heartbeats use **only the token in memory**. It is also
  written to `EditClaimJournal` (`data/edit_claim_journal.dart`) until its
  release lands — secure storage on a device, the tab's `sessionStorage` on the
  web — and `peek()`/`acquire()` first hand back any journalled claim that is
  not the live one. Memory dies with the app: before the journal, a claim the
  app was closed holding read as "you're editing this on another device" from
  the very device that left it.
- **The claim follows the screens editing under it.** The detail screen and the
  stop page `attach()` in `initState` and `detach()` in `dispose` (notifier held
  in a field); when the last screen detaches the claim is released after
  `kEditLockDetachGrace` unless one re-attaches — a `router.go()` rebuild does.
  A claim that lands after every screen has gone starts the same grace.
  **Edit mode IS this device holding the claim, wherever it was taken**: a
  rebuilt detail screen resumes a claim it already holds, `_enterEditMode` never
  re-acquires a held one, and a claim taken while the detail screen is covered
  (from the stop page) flips it into edit mode via `ref.listen` on the acquire
  edge. The heartbeat stops for good on 403 (rights
  revoked → lost) and 404 (itinerary gone), and skips while the app is
  backgrounded. Sign-out calls `releaseAllEditClaims` before the tokens go.
- **The claim is never handed back under a running save.** Every write that
  carries it goes through `ItineraryDetailNotifier._write`, which hands it the
  token (readable nowhere else) and counts it until its answer is adopted — a
  save answers with the whole trip, so no refresh follows it.
  ✓ and Back call `_requestExitEditMode`: nothing running → leave at once;
  otherwise `SavingOverlay` with `editModeLeaveAfterSave`, no new edit, and leave
  once `writesSettled()` answers — a failed write keeps edit mode and the claim,
  under its own error, then `editModeStayedAfterFailedSave` (the only word on it
  when the save came from a stop page that has already gone). Released first, the write was refused after the card that
  would show its error had gone. Regression test:
  `test/widgets/edit_mode_exit_while_saving_test.dart`.
- `mayEdit = isOwner || itinerary.canEdit`. Ownership is OR-ed in because it is
  the one case the client can derive itself, and a summary payload (no `can_edit`
  key) must not take the owner's own pencil away.
- **`long_press_to_edit.dart`'s "role-disjoint" invariant is now can-edit vs
  report**, not owner vs report — an editor gets the pencil and never the flag.
  `_CoverHero.canEdit` (renamed from `isOwner`) is what picks that chrome.
- **`itinerary_form_screen.dart` in edit mode ("Edit Itinerary") opens on
  `mayEdit`; each owner-only CONTROL inside it gates on `isOwner`.** The screen
  is not one permission — `title`, `currency` and the recommended period are an
  editor's to change, while cover, visibility, the editor list and delete are
  not. So the owner-only rows are hidden rather than offered and left to 403,
  and an editor's `else` branch of the danger zone is `EditorAccessRow`
  (removing themselves — the way out that *is* theirs). `_CannotEditNotice`
  refuses only someone who can neither own nor edit, and fires **only on
  evidence** — a profile or detail still loading falls through to the form, or a
  cold deep link would lock the owner out of their own trip.
  **`visibility` must be absent from the PATCH body for a non-owner**: the
  server refuses the key, not the value, so `visibility: null` 403s exactly as a
  real one does (`_ownsItinerary(watch: false)` — `ref.watch` is build-only, and
  `_save` runs from a callback). Regression test:
  `test/widgets/itinerary_edit_form_access_test.dart`.
- **Any surface that pushes an itinerary editing route claims the lock first.**
  `require_edit_access` demands `X-Edit-Lock` from the owner too, and no form
  claims one for itself, so a route pushed without a claim looks editable and
  then 428s on Save. `_openStopForm` and `_openDetailsForm` both do the round
  trip before pushing and abandon the push if the claim is refused — the
  "someone else is editing" banner is the honest answer at that point, not an
  error after the user has typed. The read-mode long-presses (description,
  itinerary note, a stop) claim — and await the claim — the same way.
  **Editing from the stop page enters the trip's edit mode.** Its pencil and
  long-presses gate on `mayEdit` (not ownership) in both modes and run through
  `_inEditMode`: acquire when this device holds no claim, never with `takeover`,
  and **keep** it — the user leaves edit mode with ✓ on the trip page. A refused
  claim is a pop-up in the banner's words (`editLockCopy`) offering the takeover
  the banner would (owner always, own other device always, an editor only when
  `takeable`); confirming takes over and opens nothing, and a disallowed takeover
  is `ConfirmDialog.inform`. While the claim is held the page shows originals.
  Regression test: `test/widgets/stop_detail_edit_lock_test.dart`.
  Self-removal (`EditorsNotifier.leave`) sets `can_edit` false on the
  loaded trip and drops its Shared row; the form pops `true` so the detail
  screen leaves edit mode, and nothing is downloaded.
- **A lock loss must never pop a route or clear a controller.** The ejected user
  is mid-edit and their unsaved text is now the only copy: `EditLockLostNotice`
  is a persistent banner (not a snackbar — it has to still be visible two minutes
  later), Save is disabled, every field stays populated and editable, and there
  are two ways out that both preserve the work — reclaim, or copy.
- `extractErrorMessage` maps the three typed lock exceptions, so every compose
  surface explains itself without its own branch. The forms that must *also*
  protect unsaved input catch the type instead.
- `EditLockState.fromString` degrades unknown values to **`active`** — the
  conservative direction, so a newer backend never makes an older client offer a
  takeover it does not understand.

---

## Help Centre (`/help`) and sitewide SEO

Public documentation at `/help`, written once and rendered five ways: HTML for
people, Markdown for AI assistants, JSON-LD for search engines, a search index,
and the sitemap. Nothing is authored twice.

- **`app/constants/help/en.py` is the route table.** The router, `sitemap.xml`,
  `llms.txt` and the search index all read the same tuple, so they cannot
  disagree about which pages exist. A slug that is not there does not exist.
- **Content is Python string constants, never `.md` files on disk.**
  `.dockerignore` strips `**/*.md`, so on-disk Markdown would build an image with
  an empty help centre and nothing would fail until production served a blank
  page. Same one-module-per-language shape as `constants/legal/`.
- **The dataclasses live in `constants/help/models.py`, not `__init__.py`** — the
  language modules import them and `__init__.py` imports the language modules.
  `constants/legal/` dodges this only because its modules export bare strings.
- **Structure in dataclasses, prose in Markdown.** A `Block` carries its
  `anchor`, `heading` and `kind` as fields, and its `body` **must contain no
  headings**. `FAQPage.mainEntity` and `HowTo.step` are built from `kind`, so
  deriving them by scanning rendered HTML for `<h2>` would let a translator
  writing `###` silently empty the structured data while the page still looked
  perfect. Pinned by `test_help_content.py`.
- **`articles(lang)` falls back per *slug*, not per module** — a half-finished
  translation ships what it has beside English for the rest, the same way
  `translator()` falls back per key. This is also what makes hreflang and the
  sitemap honest: every alternate they advertise resolves. `en.ARTICLES` stays
  the spine, so a slug present only in a translated module is dropped.
- **All six languages are translated** (`en` `fr` `es` `de` `ar` `zh`), and a
  module is registered in `_MODULES` only once **every** slug in it is
  translated. Registration is what puts a language into
  `seo.HELP_CONTENT_LANGS`, and therefore into hreflang, the sitemap and
  `llms.txt` — advertising a language whose articles are still English is a
  duplicate-content signal, not a localisation one.
  `test_help_content.py::test_a_registered_module_translates_every_article`
  makes a half-finished registration fail the suite.
- **Structure is identical across languages, by construction.** `slug`,
  `category`, `schema`, `related`, `updated`, `Category.id`/`icon`,
  `Release.version`/`date` and every `Block.anchor`/`kind` are copied from
  `en.py`; only the prose fields are translated. The anchor is both the in-page
  fragment and the `HowToStep.url`, and `kind` is what `FAQPage.mainEntity` and
  `HowTo.step` are built from, so a translator who renumbers one empties the
  structured data and breaks the table of contents while the page still renders
  perfectly. Pinned by `test_structure_is_identical_across_languages`.
- **`keywords` are the one field that is NOT translated — they are re-chosen.**
  They are search synonyms, so they have to be the words someone types in *that*
  language. This matters most for Chinese, where the substring tier is what
  carries a query: short 2-character terms in `keywords` are what make the
  keyword tier fire at all.
- **Every prose invariant runs per language**: `summary` ≤ 160 characters (German
  needs real rewrites here, not translations), no `#` heading inside a
  `Block.body`, `mailto:` limited to the four real mailboxes, external links
  host-allowlisted.
- **`/help/app-map`'s diagram labels are `help_diag_*` i18n keys**, and
  `article.html` imports the macro `{% from "help/_diagrams.html" import diagram
  with context %}`. `_` is a context-processor value (`templating.py`), not
  `env.globals`, so a plain `import` leaves it undefined and every `_()` in the
  macro raises. The SVG geometry stays left-to-right in every language including
  Arabic — the diagram is decoration, the legend beneath it is the content.
- **`fold()` normalises Arabic and falls back to bigrams for CJK.** Both are
  recall fixes, not polish. `_score_token` asks whether the token is *in* the
  field, so a search for `المسار` scores zero against a title carrying `مسار`
  — containment runs the wrong way — hence the alef/taa-marbuta/alef-maksura
  table and the stripped `ال`. And CJK has no spaces, so a Chinese question
  folds to one long token that appears verbatim nowhere: `_score_token` scores
  it by its character bigrams, but only when a **majority** of them are present,
  so sharing one character is not a match. The `_search_js.html` mirror carries
  both rules, and its punctuation class must be `\p{L}\p{N}` with the `u` flag
  — JavaScript's `\w` is ASCII-only and would erase every Arabic and Chinese
  character.
- **The CTA and the contact strip are included by `_layout.html`, not by each
  page**, so they reach the hub, every article, the search page and the 404 —
  the last two being exactly where a reader is most likely to leave. A page that
  also includes one renders it twice; `test_furniture_is_not_duplicated` pins it.
- **The CTA's download button points at `/#get-the-app`, never a store URL.**
  The app is pre-launch, so the homepage's own download buttons open the
  waitlist; `home.html` has a `location.hash` handler so a cross-page link can
  do the same. A hardcoded store link would ship dead.
- **The contact strip prints each address as text beside its `mailto:`.** A
  `mailto:` with no registered handler does nothing at all — the common case on
  desktop — which silently turned all four support routes into dead ends. The
  copy button falls back to a `<textarea>` + `execCommand`, because
  `navigator.clipboard` is undefined on plain http.
- **Only `a.hc-card` gets the hover lift.** A category card is a `<section>`
  with nowhere to go; the unscoped `.hc-card:hover` rule lifted it anyway, which
  made the blurb read as the card's first link and earned a click that could
  never do anything. The article links inside a card carry a standing underline
  for the same reason: blurb and links sit at the same size in two shades of the
  same green, and an underline is direction-neutral where a chevron is not.
- **`llms.txt` is per-language and its links carry `?lang=`.** The index is the
  first thing an assistant reads; English titles under `?lang=de` would advertise
  a corpus that does not match the pages behind it, and a bare link would index
  German then fetch English.
- **`MarkdownIt` stays `html=False`.** The content is ours, so this is not
  defence against a hostile author — it is defence against the flag being
  flipped for a one-off embed, which would turn every article into an injection
  point. The site's CSP is `frame-ancestors` only and would not catch it.
- **Titles are problem-shaped, not feature-shaped.** Someone who has never heard
  of Ntripi searches for "plan two options for the same day", not for our word
  for it. The feature name lives in a block heading and in `keywords`. `intro`
  is the direct answer in 40–60 words — what a search engine lifts into a
  featured snippet and what an assistant quotes, so it must stand alone.
- **Declaration order in `routers/help.py` is load-bearing.** `/help/{slug}`
  matches any single segment, so every literal path must be declared above it and
  `{slug}.md` above `{slug}`. The failure is silent: `/help/search` simply starts
  rendering "page not found".
- **Cloudflare honours `Vary` only on `Accept-Encoding`.** So help HTML — whose
  language can come from a cookie or `Accept-Language` — must never carry
  `Cache-Control: public`, or one visitor's language is served to everyone. The
  machine surfaces (`.md`, `search-index.json`, `llms-full.txt`) read `?lang=`
  **only**, ignoring the cookie, which is what makes the URL the whole cache key
  and public caching safe there. `ETagMiddleware` now preserves an
  endpoint-set `Cache-Control`, the same way it already preserved a set `ETag`.
- **`.md` is served as `text/plain`, not `text/markdown`** — browsers download
  the latter, and a link an assistant is meant to follow should render.
- **No named crawler groups in `robots.txt`.** A named user-agent group
  *replaces* the `*` group rather than adding to it, so an `Allow: /` block
  written to welcome an AI crawler would also hand it `/admin`.
- **Diagrams are inline SVG in the template, never `/static/*.svg`.** An
  `<img src="…svg">` is opaque to a screen reader and to the crawlers this
  section exists to serve, and cannot inherit `currentColor`. Every diagram is
  followed by a text legend — the diagram is decoration, the legend is content.
- **Deep links into the app use the hash form** (`/app/#/settings/help`). Flutter
  web has no `usePathUrlStrategy()` call, so the path form lands on the app's
  home screen instead.
- **`services/seo.py` owns canonical, hreflang and the sitemap sitewide** — the
  homepage and legal pages need them too. `templating.py`'s context processor
  injects `canonical_url`, `alternates` and `switch_lang` into every render,
  because Starlette applies context processors *after* the caller's context, so
  a route cannot override what the processor sets. `alternates_for()` therefore
  makes the per-path decision: help articles advertise only the languages whose
  prose is translated; everything else advertises all six.
- **The language switcher uses `switch_lang(code)`, not a bare `?lang=`** — the
  bare form replaces the whole query string, which drops `q` on `/help/search`.
- The in-app FAQ in `social_flutter/lib/features/help/` stays as it is and is
  *not* replaced by this. Its eight answers ship with the binary so they cannot
  describe a version the reader is not holding; the web centre is the fuller,
  deploy-updated resource, reached from one row in `HelpCenterScreen`.
- The "Do NOT ship a legal document in HTML" rule below is specific to *legal*
  documents, whose strings must also render in a bare Flutter `Text` widget.
  Help articles have no such consumer, which is why Markdown is free here.

### Every user-facing change updates the help centre (CRITICAL)

The help centre is the record of how the app works **today**, so keeping it true
is part of the change, not follow-up work. **A commit that alters what a user
sees or does — a new feature, a moved control, reworded copy, a changed limit, a
removed screen — is not finished until `app/constants/help/` says so.** An
article describing last month's UI is worse than no article: the reader follows
it, the step is not where it says, and they conclude the app is broken. A
refactor, an index or a migration with no visible surface needs none of this —
the test is whether a reader could notice.

For each article the change touches:

- **Edit the prose in all six languages, not just `en.py`.** `articles()` falls
  back per *slug*, not per field, so a translated module goes on serving its own
  stale text forever — the page still renders perfectly and nothing fails. Only
  a wholly missing slug is caught
  (`test_a_registered_module_translates_every_article`).
- **Bump `updated`, in all six.** `test_structure_is_identical_across_languages`
  asserts it matches `en.py` exactly, so the date bump is what makes the suite
  refuse a change that touched one language and forgot the other five. It is
  also `dateModified` in the JSON-LD.
- **Re-check `summary` (≤160 chars), `keywords` and `related`.** If the change
  renamed something, the old word is what people still type — keywords are
  re-chosen per language, never translated. A new article also needs `related`
  links *from* its neighbours; a page nothing points at is reachable only by
  search.
- **A new capability needs a new `Article` in `en.py` and in every registered
  language, in the same commit.** `en.ARTICLES` is the route table, and a
  module in `_MODULES` is expected to translate every slug — landing
  English-only either fails the suite or advertises a language whose new page
  is not in it.
- **Add a `Release` to `RELEASES` for `/help/whats-new` — in all six modules.**
  `releases()` falls back *whole*, not per entry, and each translated module
  carries its own list, so an entry added only to `en.py` leaves the other five
  showing an outdated What's New — `test_every_language_lists_every_release`
  fails the suite for it.
- **Fix the in-app FAQ when the change contradicts one of its eight answers.**
  It is built from `AppLocalizations` (`faq*Q` / `faq*A` in the `.arb` files),
  ships with the binary and cannot be corrected by a deploy — which is exactly
  why a wrong answer there outlives the release that broke it.
- **Renamed routes and screens count too.** `/help/app-map`'s labels are
  `help_diag_*` i18n keys, and every deep link is `/app/#/…`; a route renamed
  without them lands the reader on the app's home screen with nothing to explain
  it.

---

## Alembic Migration Rules (CRITICAL)

- **Never hand-write a revision ID** — always generate one with `venv/bin/alembic revision -m "description"` (or `--autogenerate` if a DB is reachable). Hand-written placeholder IDs (e.g. `a1b2c3d4e5f6`) silently collide with existing migrations, fork the chain, and crash Railway on `alembic upgrade head`.
- **Always verify a single head before committing** — run `venv/bin/alembic heads` from `social_api/`. If it lists more than one `(head)`, stop and fix the branch (create a merge migration or remove a duplicate stub) before adding a new migration.
- **Never keep two files with the same revision ID** — if a stub (`*_stub_*.py`) and the original file both exist for the same revision, delete the stub; the original is authoritative.
- **`down_revision` must point to the current single head** — read `venv/bin/alembic heads` to get the exact revision string; do not guess from file names or dates.
- **Adding an index to a populated table needs `CREATE INDEX CONCURRENTLY`** — a plain `CREATE INDEX` holds a write lock for the length of the build, and migrations run at deploy on Railway. It cannot execute inside a transaction, so it is not a flag flip: wrap it in `with op.get_context().autocommit_block():` and pass `postgresql_concurrently=True`. Guard the block on `op.get_context().dialect.name == "postgresql"` and keep a plain branch for anything else. The trade-off is that autocommit forfeits the migration's atomicity — a failed concurrent build leaves an `INVALID` index to drop by hand (`SELECT * FROM pg_index WHERE NOT indisvalid`). `a681984a1a04` is the reference implementation.

---

## What NOT To Do

- Do NOT start feature work without reading `docs/README.md` and
  `docs/constraints.md` — the constraints are cross-cutting, and a feature that
  violates one is wrong before it is written
- Do NOT ship a change without updating the matching `docs/features/<feature>.md`
  and appending to `docs/decisions.md` — a doc describing last month's behaviour
  is worse than none, because the reader follows it
- Do NOT edit or delete an existing `docs/decisions.md` entry — the log is
  append-only; a reversed decision gets a NEW entry that supersedes the old one
  and links to it
- Do NOT add `type`, `position`, or `parallel_position` columns to `stops`
- Do NOT send or return `position` / `parallel_position` in any API payload
- Do NOT skip `If-Match` on any mutation endpoint
- Do NOT split one save into a lock-free write and a guarded one — the first moves `updated_at` and the second's `If-Match` is stale; the itinerary form's cover went through `POST`/`DELETE /image` first and 412'd every PATCH behind it. Carry both in one request, as `PATCH /itineraries/{id}/form` does
- Do NOT scan a cover for an itinerary whose row is not inserted yet without `itinerary_pending=True` and an `attach_itinerary` after the flush — the audit row's `target_itinerary_id` is a real FK, and a reject commits it on the spot
- Do NOT use locale-aware collation on `rank` columns — must be `COLLATE "C"`
- Do NOT put a reorder or move control back on a stop card, or save a change to a trip's structure outside arrange mode — three mechanisms (a reorder pill, a move pill, a reorder-tracks sheet) each saving on its own is what confused users and the owner; arrange mode saves one `layout`, all or nothing
- Do NOT end a drag on `onDragEnd` — Flutter skips it once the dragged widget is rebuilt away, and a row's hover tint (a `Container` gaining a box) did exactly that: arrange mode stayed stuck mid-drag, its stop highlighted and every target open. End drags through `onDragCompleted` + `onDraggableCanceled`, and never let a highlight add or remove a widget above a draggable
- Do NOT let lifting a stop or track change the arrange view's layout — targets open only once the drag has travelled past the slop (`_dragTravelled`), and the faded copy keeps the chip's size; opened at the lift, they pushed the rows down under a finger held still, and the next tremble dropped the stop wherever that landed
- Do NOT make a tap on a stop place the picked one — with a stop picked, a tap on another stop picks that one instead: people read a second tap as "move this one instead", and placing before it either changed nothing and seemed only to unselect, or moved a stop they had stopped thinking about. A tap places only on a gap or a track; only a drag drops a stop in front of another
- Do NOT delete a track in a session where its stops just moved without expiring its `stops` collection first — `Track.stops` cascades delete-orphan, so a collection loaded before the move deletes the moved stops with it (`_apply_layout`)
- Do NOT introduce build_runner / json_serializable / freezed
- Do NOT add a state management library — Riverpod only
- Do NOT use the Google Maps SDK — maps we draw are flutter_map + OSM; a Google map appears only through the `/embed/*` page (`GoogleEmbed` + `GoogleMapEmbed`)
- Do NOT store any Google content but a place ID — not a suggestion's name or address, not coordinates read from a Google link (`stop_location.normalize`, `ck_stops_link_no_coords`, `ck_stops_place_id_no_coords`); and do NOT put a Google place on an OSM map
- Do NOT prefill a stop's name from a Google suggestion or a pasted link — the user types it; an OSM pick fills it only when the field is empty
- Do NOT fetch a pasted link from the stop form, or import `link_preview_service.dart` there — read links with `google_maps_links.dart` (`stop_form_link_fetch_guard_test.dart`)
- Do NOT search Nominatim as the user types — every OSM search box searches on submit; the policy forbids autocomplete and caps the whole app at one request a second
- Do NOT call Google Places from the app, or call Place Details on the search path — the server proxies Autocomplete with its own key and budget, and a suggestion already carries its place ID
- Do NOT log, cache or store Google's autocomplete answer — `google_places.py` logs status codes only, the route answers `no-store`, and it is a POST so the app's HTTP cache never keeps it
- Do NOT send a user, stop or trip identifier to Google, or an unrounded device position — the text, the language and a bias rounded to 0.1° on the server
- Do NOT build a `google.com/maps/embed` URL in the app or pass `GOOGLE_MAPS_EMBED_API_KEY` to a build — the server's `/embed/*` page holds the key (`google_embed_source_guard_test.dart`)
- Do NOT name the embed page's language parameter `lang` — `LanguageCookieMiddleware` writes the site cookie from `?lang=`
- Do NOT let any path but `/embed/*` be framed — `is_embed_path` is the only exception to `X-Frame-Options: DENY`
- Do NOT send `place_source` or the Google fields from the stop form unless the location changed this session — an untouched Google stop must not write back an ID the yearly refresh replaced
- Do NOT re-find a lost Google place automatically — a dead ID is marked and an editor searches again; the first Text Search match can be a different place
- Do NOT compute rating averages in Python — use SQL `AVG()`
- Do NOT create new access control logic — reuse `can_view_itinerary()`
- Do NOT call `moderate_or_422` as a `Depends` — endpoint body only, or a 412 spends a paid moderation call
- Do NOT convert text write endpoints to `async def` — sync SQLAlchemy on the event loop is the real hazard; the threadpool already keeps blocking provider calls off it
- Do NOT convert the ten `async def` endpoints to sync as a drive-by — the image uploads, the deletes that remove a stored image (an itinerary's included), both admin form posts and the bug-report intake await the async image pipeline and storage directly, and they work. The old reason given here was wrong: a sync `def` CAN take a multipart upload. FastAPI parses the body before calling the endpoint, so a sync `def` reads `UploadFile.file` on its worker thread and reaches `process_and_store` through `anyio.from_thread.run(functools.partial(...))` — the two itinerary form routes do exactly that; only a handler that calls `await request.form()` itself needs `async`. The ten are the known exception to the rule above: they do run sync SQLAlchemy on the loop, for a local round trip — and so does the image scan's audit row on every path, sync routes included. What must stay off the loop there is the **CPU** work — `process_and_store` hands Pillow to `asyncio.to_thread`, exactly as `r2_storage` and the image scan's provider call already do; never call a `process_*_image` function directly from an `async def`
- Do NOT send anything but the text to a moderation provider — no user id, email, or content id
- Do NOT send Cloud Vision anything but the image, the SafeSearch feature and `parent` — no user id, email, storage key or URL, the same rule as the text providers
- Do NOT read an absent SafeSearch category as unlikely — proto3 JSON omits an enum left at zero, and Google's zero is `UNKNOWN`; an `UNKNOWN` `adult` or `violence` is a failed scan, never an approval
- Do NOT map Cloud Vision's likelihoods onto Rekognition's percentages — the audit row would claim a confidence Google never gave; its labels are `{name, likelihood}`
- Do NOT give Cloud Vision FCM's service-account key, or push the moderation one — one key per job, so revoking either never stops the other
- Do NOT add the `google-cloud-vision` SDK — it is gRPC and bypasses `requests.Session.send`, so a slow scan would vanish from the slow-request log
- Do NOT add a second reject / flag / fail-open path for a new image provider — it is an entry in `moderation_service._PROVIDERS`, whose scan returns a verdict or raises
- Do NOT send a content id, a field name or a user reference to a translation engine — OpenAI gets the texts under opaque keys (`t0`…) with `store: false`, Azure a bare array; and never log a text, in or out
- Do NOT cache a translation that skipped `translation_validation` or, with moderation on, output moderation — it is machine output served to every later reader; a failed check falls to the next engine, never into the cache
- Do NOT accept text from the client for translation — name the content and load it server-side, or the access check is on something other than what is sent
- Do NOT translate content under a takedown, even for its author — `translate_items` answers `not_found`; translating it hands taken-down text to a third party
- Do NOT hold a database transaction open across an engine call — `translate_items` commits before `run_chain`
- Do NOT count translation usage in Python or in slowapi — the conditional upserts in `translation_usage.py` are the only counters, and a refused reservation counts nothing
- Do NOT schedule title pre-translation from any path but a public create, a publish or a public title change — drafts are `only_me`, and collaborative saves are frequent
- Do NOT put the feed's language in `Accept-Language` — the client cache keys on the URL, so `?lang=` must be part of it
- Do NOT keep an `unavailable` or `rate_limited` answer in the client's translation state — the next tap must ask again, or one dropped request hides the button until sign-out
- Do NOT show a translation in edit mode — `TranslatableText(enabled: !_editMode)`; whoever edits reads the original
- Do NOT give a transit card its own "See translation" — a leg's thoughts join the group already on screen, the trip's or the stop's
- Do NOT add a translation engine without naming it in Privacy §4 and §5, in all six languages, in the same commit — an undisclosed processor is a GDPR breach
- Do NOT write an itinerary's moderation state from outside the owner's request without `set_preserving_etag` — it 412s their open editor
- Do NOT assign a text verdict on an author's edit — `apply_author_edit_status`; assigning let any edit un-hide a taken-down profile or review
- Do NOT write `rating_count` / `rating_avg` directly — `recalculate_rating` preserves the ETag; a raw write 412s the owner every time someone rates
- Do NOT page a list with `limit`/`offset` without a total `ORDER BY` — Postgres may repeat or skip rows between pages; and a client list that sends no `limit` silently stops at the server default
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
- Do NOT put the **bug reporter's** email in the Jira payload, or log `JIRA_API_TOKEN` — the operator inbox is one person, a Jira project is a whole team. The acting **admin's** email is a different matter and does go to Jira, as a `user/assignable/search` query term only — an operator's Jira identity is already visible to that team, and it never reaches the ticket body
- Do NOT let `find_account_id` raise, or let a missing Reporter block the filing — the operator is waiting on a ticket, not on attribution; every lookup failure degrades to a warning. This is the one deliberate exception to the fail-closed rule above, which still governs `create_issue` itself
- Do NOT take the first `user/assignable/search` hit — `query` matches displayName too, so only an exact `emailAddress` match may set the Reporter; anything looser files the bug under the wrong person
- Do NOT send a plain string as a Jira `description` — REST v3 requires ADF (`{"type":"doc","version":1,…}`) and rejects anything else
- Do NOT put raw content text, emails, or display names in an automated `moderation_log` row
- Do NOT store rendered notification text — it is wrong in five of six locales and freezes a display name moderation may later hide
- Do NOT let an access grant (editor or allowlist) render as a generic row — a restricted itinerary is in no feed, so a notice that does not name it cannot be acted on; add the type to `NotificationType.fromString` and `push_i18n.render` in the same commit as the backend type
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
- Do NOT write `AsyncLoading` or `AsyncError` into a notifier's state, or assign it an `AsyncValue.guard` result, outside `ReloadKeepsContent` — `when()` draws both over the content even while they carry its value; reload through `reloadKeepingContent`, and `reload_keeps_content_guard_test.dart` fails until you do
- Do NOT pull-to-refresh with `ref.invalidate` — it returns at once, so the spinner ends before the data comes back, and a failed rebuild replaces the content with the error view; give the notifier a `refresh()` through `ReloadKeepsContent`
- Do NOT put anything that can throw or hang ahead of a pull's reload — clearing covers goes through `ImageCacheEviction`, which swallows a cache failure; `CachedNetworkImage.evictFromCache` called directly let a throw skip the reload and escape into the RefreshIndicator, and turned a saved itinerary form into a reported failure
- Do NOT let a reload be answered from the HTTP cache's stale copy — it comes back as a success, so the failure is never reported, and it can be older than the screen (rows and counts adopted from write answers are never stored); `forceRefreshOptions()` turns the fallback off, first loads keep it
- Do NOT `silentRefresh()` inside an undo window — it resurrects the row the user just dismissed, and flushing the queue first destroys the undo they were offered
- Do NOT ring the new-notification cue without a previous `AsyncData` to compare against — a first poll has no baseline, and every cold launch would sound like an arrival
- Do NOT use a count rise as the arrival signal — a read on another device cancels out an arrival and masks it; compare `latest_at` via `NotificationBadge.arrivedSince`, which is the only place that comparison is written
- Do NOT mark notifications read from a feed that has not been refreshed since the screen opened — the server is the authority on read state, so a row that was never rendered would be marked read and never surface as new again
- Do NOT gate the on-open refetch on the badge count — the badge is up to a poll interval stale, and after a read on another device it is 0 while the feed is not
- Do NOT put a list's only `RefreshIndicator` behind an `isEmpty` early return — an empty list and a failed load are the two states most in need of a pull; use `RefreshableCenter`
- Do NOT set `state` or call `ref.invalidate` after an `await` in a notifier without checking `ref.mounted` — logout disposes the provider mid-flight and a disposed `Ref` throws
- Do NOT send a push from inside `notify()` — it adds to an open transaction, and a push sent for a rollback cannot be un-sent; queue on `Session.info` and let the `after_commit` listener hand it to the push worker
- Do NOT send a push on the request's thread — the `after_commit` listener only drains the queue and calls `_submit`; FCM time belongs to the worker, never to a user's write
- Do NOT let the push worker use the request's session — pruning a dead token commits, and the request's session is not the worker's to use
- Do NOT drop the `after_soft_rollback` listener — a stale queued push would ride out on whatever commits next, announcing an event that never happened
- Do NOT hold an ORM row in a `PendingPush` — its attributes are expired after commit and reading one lazy-loads on a session between transactions; snapshot inside `notify()`
- Do NOT reimplement the suppression rules for push, and do NOT add a fourth `notify_*` column — push hangs off `notify()` and the OS permission is the master switch
- Do NOT delete a device token on a 500, a 503, or a 401 — only `UNREGISTERED`/`INVALID_ARGUMENT` mean the token is dead; anything else is transient and dropping it needs a reinstall to undo
- Do NOT skip `DELETE /devices/{token}` on sign-out, or send it after the access token is discarded — the next user on that phone inherits this user's notifications
- Do NOT make `device_tokens.token` unique per user — FCM reassigns a token across accounts, and a per-user constraint turns that into a duplicate that misdelivers
- Do NOT store the push locale on `users` — it is per-device, and one account can be a phone in French and a tablet in English
- Do NOT reword a `push_i18n` string without rewording its `.arb` twin — a tray entry and its feed row are the same sentence
- Do NOT name a reporter, a reason, or a report count in push text — the tray entry is visible on a lock screen
- Do NOT ask for notification permission at launch — iOS grants exactly one prompt per install and a denial is only undoable in Settings
- Do NOT navigate from `getInitialMessage()`, and do NOT drain it from a post-frame callback — the reply lands after the first frame and splash navigates anyway; splash awaits `takeInitialPushRoute()`
- Do NOT open a tray tap with `go()` — it replaces the stack and leaves the tapped screen alone on its navigator, where Back does nothing and Android's back closes the app; warm taps go through `openTappedRoute`, cold ones through `pushOverHome`
- Do NOT build a stack with `go()` and then `push()` — `push()` builds on the stack as it stands at the call and `go()` lands only after the async redirect, so the push can stack onto the page `go()` was replacing; make it one navigation with an explicit base (`pushOverHome`)
- Do NOT push a route inside the tab shell over a root-level page — go_router appends a second shell whose navigator keys collide (an assertion, then a wedged navigator); `openFromOutside` opens such a route over home
- Do NOT give a screen a notification can open a back control that only pops — leave through `popOr` in every state, and add the screen's case to `notification_destinations_exit_test.dart`
- Do NOT open an app from a page's script — an intent or a cross-host navigation without a tap is refused; the page offers **Open in Ntripi** and the reader taps it
- Do NOT put anything but the session's end time in the web session hint (`ntripi_web_session_until`) — every script on the origin can read it; and change its key on both sides (`web_session_hint.dart`, `app_links.WEB_SESSION_HINT_KEY`) in one commit
- Do NOT leave a share page with `location.assign` — `replace`, or Back returns to a page that redirects forward again
- Do NOT serve anything on `APP_OPEN_HOST` but `/.well-known/*` — a second copy of the site has its own localStorage, where the share pages cannot see the reader's session
- Do NOT let the app start on an editing form, and do NOT add a route without classifying it in `landing_routes_test.dart` — on the web every screen is a URL, and a form opened by a reload holds no edit claim
- Do NOT share a link through share_plus directly — `shareLink` is what adds the popup's **Copy link** row (the `ntripi/share` channel) and the web's menu
- Do NOT claim more than `/share/i/*` and `/share/u/*` for the app — `/*` would capture emailed reset, verification and appeal links, which are web forms; and change a claimed path in all four places at once (AASA paths, manifest, entitlements, `appLinkLocation`)
- Do NOT add a custom URL scheme (`ntripi://`) or a deep-link plugin — any app can register a scheme, and a plugin needs Flutter's built-in deep linking off
- Do NOT let a shared link land as it arrives — a cold start must go through splash (`appLinkLaunchRedirect`), a warm one opens over the current screen (`appLinkOnEnter` → `openFromOutside`), and every landing after splash or a sign-in goes through `landHome`
- Do NOT drop a link tapped while signed out — park it for the sign-in; only a tray tap, which belongs to an ended session, is dropped
- Do NOT pass `itinerary`, `owner` or a cover to `share_private.html` — its preview card reaches everyone in the chat, mostly people who cannot open the trip
- Do NOT hand a share template the ORM row, or render anything on a share page beyond the teaser fields — a person, a chat crawler and a search engine read the same page, and nothing below the teaser is theirs without an account
- Do NOT add a route reachable without sign-in without classifying it in `test_public_surface.py` — the test fails until you do, deliberately, and its sentinel half checks the new route leaks nothing
- Do NOT give the "can't open" screens a reason or a Retry — the API's one 403 covers a block too, and an answer does not change by asking again
- Do NOT test `navigator.userAgent` in a template anywhere but `platform_head` — the store row, **Open in app** and **Get the app** all read `<html data-platform>`; the second copy that used to live in `app_links_script` had already drifted (it missed iPads)
- Do NOT pick a store on the server from the User-Agent — the HTML would vary by User-Agent, and an iPad can only be told apart in the browser
- Do NOT put `singleTop` back on `MainActivity` — a link from another app started a second copy of the app in the caller's task
- Do NOT let push failures surface to the user or block a write — it fails open like `email_service`, and the poll still corrects the badge within a minute
- Do NOT make `NotificationPoller` conditional on push — best-effort delivery is exactly why the backstop exists
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
- Do NOT move help content into `.md` files on disk — `.dockerignore` strips `**/*.md`, so the image would ship an empty help centre and nothing would fail until production served a blank page
- Do NOT declare the help dataclasses in `constants/help/__init__.py` — the language modules import them and `__init__.py` imports the language modules; that is an import cycle at boot
- Do NOT put a heading inside a `Block.body` — the anchor, the table of contents and the JSON-LD all key off `Block.heading`, so a stray `##` is invisible to every one of them while the page still looks right
- Do NOT derive `FAQPage` questions or `HowTo` steps by scanning rendered HTML — a translator writing `###` would empty the structured data silently; `Block.kind` is the contract
- Do NOT set `MarkdownIt(html=True)` for a one-off embed — it turns every article into an injection point, and `frame-ancestors`-only CSP would not catch it
- Do NOT declare a literal `/help/*` route below `/help/{slug}`, or `{slug}` above `{slug}.md` — the catch-all swallows them and the page still renders, just the wrong one
- Do NOT put `Cache-Control: public` on help HTML — its language can come from a cookie, and Cloudflare honours `Vary` only on `Accept-Encoding`, so one visitor's language would be served to everyone
- Do NOT read the language cookie on `.md`, `search-index.json` or `llms-full.txt` — `?lang=` alone is what makes the URL the whole cache key and public caching safe
- Do NOT serve `/help/{slug}.md` as `text/markdown` — browsers download it instead of rendering it
- Do NOT add a named `GPTBot` / `ClaudeBot` group to `robots.txt` — a named group replaces the `*` group wholesale, so an `Allow: /` written to welcome a crawler also hands it `/admin`
- Do NOT put a help diagram in `/static` as an `<img>` — inline SVG text nodes translate, reach the accessibility tree, and are extractable by the crawlers this section exists for; always pair a diagram with a text legend
- Do NOT link into the app with a path deep link — Flutter web is on the hash strategy, so `/app/#/…` is the only form that arrives
- Do NOT advertise an hreflang alternate for a language whose *content* is not translated — six alternates all serving English is a duplicate-content signal, not a localisation one
- Do NOT pass `alternates` or `canonical_url` from a route — Starlette applies context processors after the caller's context, so the processor always wins; make the decision in `seo.alternates_for()`
- Do NOT use a bare `?lang=` for the language switcher — it replaces the whole query string and drops `q` on `/help/search`
- Do NOT add a "was this helpful" form — free text from the public site drags in `moderate_or_422`, rate limits, a retention policy and a new table, for a signal nothing consumes; a `mailto:` with the slug in the subject costs nothing
- Do NOT rate-limit `/help/search` — the limiter is in-memory and single-instance, the endpoint touches no DB, and a 429 on a crawler-facing page is a self-inflicted SEO wound
- Do NOT replace the in-app FAQ with the web one — its answers ship with the binary so they cannot describe a version the reader is not holding
- Do NOT include `_cta.html` or `_contact_strip.html` from a help page — `_layout.html` includes both, so a page that adds one renders it twice
- Do NOT put a store URL in the help CTA — the app is pre-launch, so `/#get-the-app` (the homepage waitlist) is what a "download" button can honestly do
- Do NOT offer a support address as a bare `mailto:` — with no registered mail handler it does nothing at all, so the address must also be on screen as selectable text
- Do NOT give a hover lift to a `.hc-card` that is not a link — a category card has no destination, and the affordance makes its blurb read as a link that cannot be clicked
- Do NOT register a `constants/help/<lang>.py` in `_MODULES` until every slug in it is translated — registration is what advertises the language in hreflang, the sitemap and `llms.txt`, so a partial module claims a localisation that is mostly English
- Do NOT change a `Block.anchor`, a `kind`, a `slug`, a `category`, a `schema`, a `related` list or an `updated` date when translating — the anchor is the in-page fragment *and* the `HowToStep.url`, and `kind` is what the structured data is built from; the page still renders perfectly, which is why only a test catches it
- Do NOT translate `keywords` word for word — they are search synonyms and have to be what someone types in that language; in Chinese they are what makes the keyword tier fire at all
- Do NOT let a translated `summary` exceed 160 characters — German runs ~20% longer, so several of them are rewrites rather than translations
- Do NOT import the diagram macro without `with context` — `_` comes from a context processor, not `env.globals`, so every label inside it would raise
- Do NOT hardcode a label inside `_diagrams.html` — inline SVG text is translatable text, which is the entire reason the diagrams are not `<img>`
- Do NOT use `\w` in the search JS — JavaScript's is ASCII-only, so `[^\w\s]` erases every Arabic and Chinese character rather than the punctuation; use `\p{L}\p{N}` with the `u` flag
- Do NOT drop the Arabic normalisation from `fold()` — `_score_token` tests containment in one direction only, so a query carrying `ال` can never match a title without it
- Do NOT relax the CJK bigram rule to "any gram hits" — one shared character would match a large share of the corpus, which is worse than the empty result the fallback exists to fix
- Do NOT serve `llms.txt` in English under another `?lang=` — the index is what an assistant reads first, and its links must carry the language they name
- Do NOT name internal state (`edit_lock_lost`, a status code) in a troubleshooting article — describe the message the user saw and what to do; the internal name goes stale on the next refactor
- Do NOT ship a user-facing change without updating `app/constants/help/` in the same commit — an article describing last month's UI is worse than none, because the reader follows it, finds the step missing, and concludes the app is broken
- Do NOT edit help prose in `en.py` alone — `articles()` falls back per slug, so each translated module keeps serving its own stale text and only a *missing* slug fails the suite
- Do NOT leave `updated` untouched after editing an article — bumping it in all six is what makes the structure test catch a one-language edit, and it is `dateModified` in the JSON-LD
- Do NOT add a `Release` entry to `en.py` only — `releases()` falls back whole rather than per entry, so the other five languages go on showing an outdated What's New; `test_every_language_lists_every_release` now fails for it
- Do NOT leave a contradicted in-app FAQ answer to the next release — it ships with the binary, so unlike the web centre a deploy cannot correct it
- Do NOT apply the client text filter to titles or place names — European place names false-positive
- Do NOT let a client-side filter block submission, mutate text, or clear a compose field
- Do NOT create a second access ladder for editing — `can_edit_itinerary` must keep delegating to `can_view_itinerary`, or edit rights outlive view rights
- Do NOT identify an edit claim by `user_id` — the rotating token is the only thing that can tell a displaced device from the same person on a new one
- Do NOT check the claim only at acquire time — every mutating request re-checks it, which is the whole point
- Do NOT put the lock check after the If-Match check — a taken-over client would be told to reload into a screen it still cannot save from
- Do NOT collapse 409 `edit_lock_lost` and 423 `itinerary_locked` — one says protect unsaved input, the other says offer to wait
- Do NOT let a heartbeat or a takeover touch `itinerary.updated_at` — that column IS the concurrency ETag and would 412 every open client once a minute
- Do NOT put lock state on `ItineraryDetail` — it changes every heartbeat while that response's ETag does not
- Do NOT put a remaining-seconds field in the lock GET body — it would change on every poll and defeat the 304
- Do NOT let `grant_view` change `visibility` — it may only add an allowlist row, and only for `restricted`
- Do NOT let an editor grant edit rights, change visibility, delete the itinerary, or replace the cover
- Do NOT gate the whole "Edit Itinerary" form on `isOwner` — it opens on `mayEdit` and hides the owner-only controls individually; refusing the screen would also refuse the title, currency and period an editor may already change
- Do NOT send `visibility` from a non-owner — the server rejects the key's presence, so an explicit null 403s just like a real value
- Do NOT push an itinerary editing route without claiming the edit lock first — no form claims one for itself, and the owner needs it as much as an editor does, so the screen looks editable and 428s on Save
- Do NOT release a claim the stop page took after its edit — a claim is the trip's edit mode, and claim-per-edit is how a stop got edited while the trip sat in read mode
- Do NOT take over from the stop page without its pop-up's confirmation, or offer the takeover to an editor before the server says `takeable` — the same rule as the trip page's banner, worded by the same `editLockCopy`
- Do NOT leave a revoked editor's claim standing — it blocks everyone until the TTL for someone who can no longer use it
- Do NOT add a mutating itinerary endpoint without classifying it in `test_edit_guard_coverage.py` — the test fails until you do, deliberately
- Do NOT add a READ route to any `test_edit_guard_coverage.py` set — `classified - live` is asserted empty, so a GET listed there fails the suite
- Do NOT add `can_edit` to `ItinerarySummary` — it would reorder the JSON keys of `/me`, `/saved` and `/feed` for a flag only the shared list needs; reuse `ItineraryFeedItem`
- Do NOT filter `shared-with-me` with `public_listing_criteria` alone — it does not cover the visibility ladder, and a granted editor's access is usually `restricted` or `followers`
- Do NOT merge `sharedWithMeProvider` into `myItinerariesProvider` — two endpoints that fail independently, and one combined AsyncValue lets a dead shared call blank the Mine segment
- Do NOT put the scope selector, the loader, or the error outside the list — replacing the screen wholesale removes the control and strands the user on a scope they cannot leave
- Do NOT decide a list row's owner-only chrome by comparing ids — provenance is the stronger signal, since `/itineraries/me` is owner-only by construction and needs no profile load
- Do NOT offer the long-press delete on a shared row — an editor cannot delete, so the confirm dialog could only earn a 403 after they typed the trip's title into it
- Do NOT make `DELETE /lock` 404 — it is called from teardown, same rule as the notification DELETE
- Do NOT pop a route or clear a field when a save returns `edit_lock_lost` — the user's unsaved text is the only copy of it at that moment
- Do NOT leave edit mode with `_exitEditMode()` from a user action — ✓ and Back go through `_requestExitEditMode`, which waits for `writesSettled()`; releasing the claim under a running write loses that write without a word
- Do NOT read the edit-lock token outside `ItineraryDetailNotifier._write` — the wrapper is what counts a write as running, and leaving edit mode waits on that count
- Do NOT re-download after the app's own write — a write answers with what the screen shows next and the app adopts it; only the named exceptions (content no answer carries, pull-to-refresh and Retry, sign-in/out and token exchanges, data no open screen shows) may invalidate. A new write that leaves a screen stale gets an answer (`return_requested`), not a refetch
- Do NOT call `refresh()`, invalidate the detail, or otherwise GET the trip after a trip save — the save's answer is the whole trip; adopt it through `_save`. The reload was a second request every form waited on, and its loading state rebuilt the whole trip view behind the full-screen loader
- Do NOT write a trip save that skips `_save` — it is what adopts the answer, counts the write for `writesSettled()`, and keeps the Itineraries tab's row in step; `_listsChanged()` placed by hand is how segment saves left stale totals
- Do NOT read a provider's `.notifier` to adopt an answer into a profile, a ratings page or a violations list that may not be loaded — reading it builds it, which is the GET; check `exists` first (`adoptMyCounts`, `adoptTheirFollowState`)
- Do NOT add a trip edit route without the full-trip answer — depend on `wants_itinerary` and return `_trip_edit_answer` after the last commit; `test_trip_edit_answers.py` fails until the route has a case
- Do NOT change a trip edit's answer when `?return=itinerary` is absent — that answer is what installed builds parse, byte for byte
- Do NOT attach `X-Edit-Lock` from a Dio interceptor — a blanket one would send a dead token onto requests that must not carry one
- Do NOT adopt a journalled claim token for a save or a heartbeat — `EditClaimJournal` keeps it only so `DELETE /lock` can hand back a claim the app was closed holding; and do NOT journal it in web `localStorage`, which every tab shares, so a second tab would hand back the first one's live claim
- Do NOT drop `X-Edit-Lock` from CORS `allow_headers` — the browser preflight fails before the request is sent
- Do NOT hardcode URLs, secrets, or environment values
- Do NOT use `passlib` — bcrypt direct only
- Do NOT use `allow_origin_regex=".*"` in CORS — explicit list only
- Do NOT use `allow_methods=["*"]` or `allow_headers=["*"]` in CORS — explicit lists only
- Do NOT query `User.username == something` — always `username_lower`
- Do NOT write inline fetch-user-or-404, Follow queries, or follower-counter math — use `app/services/user_service.py` helpers
- Do NOT delete a Follow row any way but `delete_follow` — it decides the decrement from the row as it was deleted, which is what keeps a cancel racing an accept, or an unfollow racing a block, from leaving the counters wrong for good
- Do NOT notify a removed follower, or let Remove follower touch a pending request — removal is as silent as a decline or a block, and refusing a request is Decline's job (a stale Remove must never refuse one the owner has not seen)
- Do NOT subtract one from a follower/following count on the client after a row action, and do NOT refetch the profile for it either — adopt the `counts` the write's answer carries; a local ±1 from a stale row would count twice
- Do NOT answer a follow write's `counts.them` where `GET /users/{id}` would 404 for the caller — a count would tell a blocked user that the account behind the block exists
- Do NOT compute a denormalized counter in Python — read-then-write loses concurrent updates under READ COMMITTED; the increment belongs in the `UPDATE` statement, where Postgres re-evaluates it against the latest committed row
- Do NOT duplicate a helper that already exists in the Shared Helpers section — extract on second occurrence instead of copying
- Do NOT merge Pydantic Response classes into a shared base if it reorders JSON keys — field-definition order is part of the API contract
- Do NOT use `--web-renderer` flag in Flutter (removed in 3.29)
- Do NOT reference `DATABASE_PUBLIC_URL` from the backend — use `${{Postgres.DATABASE_URL}}`
- Do NOT bypass the storage abstraction
- Do NOT skip EXIF stripping on uploaded images
- Do NOT write inline `showDialog` for destructive actions
- Do NOT pass a `backgroundColor` to a sheet or dialog — `bottomSheetTheme` and `dialogTheme` already say `nt.surface`, so the only thing an explicit one can do is break the rule
- Do NOT use `nt.sand` as a ground — it is an accent fill that exists to stand out *against* the surface; a sand sheet is what made sheets read as a different app
- Do NOT re-inline `SectionCard`, `SectionLabel`, `FieldDivider` or `EditorialTopBar` — six private clones had already drifted apart from each other before they were extracted
- Do NOT type a number into `Radius.circular` / `BorderRadius.circular` — take the job's `NtripiRadius` token; 247 typed corners in 18 values is how the trip page's edit-mode boxes kept a 4 copied from a field that had moved to 14 (`radius_scale_guard_test.dart`)
- Do NOT pass `shape:` to a sheet or a dialog — `bottomSheetTheme` and `dialogTheme` give `NtripiRadius.modal` once; per-call shapes are how sheet tops ended up at 20, 24 and 28
- Do NOT write an `OutlineInputBorder` without `borderRadius:` — Material falls back to 4, a square field among the 14s
- Do NOT type a px `border-radius` in a template — take `var(--radius-<token>)` from `_radius_tokens.html`; and do NOT change `NtripiRadius` without the partial, or the partial without `NtripiRadius` — `test_radius_scale.py` fails until both say the same
- Do NOT re-inline a "view more" overflow check — `ExpandableText` measures with the inherited style and text scaler; a bare `TextPainter` says "fits" while the text is ellipsised
- Do NOT render a transport leg's thoughts as markdown — the leg form is a plain field, so a typed `#` or `*` must stay a character
- Do NOT hide a leg's thoughts in the editable transit card — what readers see must not vanish from under the person editing it; there they show as written, and a tap opens the leg (`LegThoughts(expandOnTextTap: false)`)
- Do NOT call `.toUpperCase()` on a `SectionLabel` — it uppercases internally, and the call site's own padding will miss the 22 inset every other header uses
- Do NOT hand-roll a sheet's drag handle — `showDragHandle: true` carries a 48 px tap target and a `Semantics` label that a 36×4 `Container` does not
- Do NOT use `Theme.of(context).dividerColor` for a hairline — the theme sets `dividerTheme.color` but never `dividerColor`, so it falls through to M3's `outlineVariant` grey; use `nt.border`
- Do NOT use `nt.ratingRed` or `colorScheme.error` for a destructive affordance — `nt.danger` is the token; `colorScheme` is only for on-colors that have none
- Do NOT report a sheet's failure with a `ScaffoldMessenger` snackbar — it draws behind the modal barrier and is never seen; use an inline error row
- Do NOT set `resizeToAvoidBottomInset: false` to fix a gap above the keyboard — the gap is a leaked inset, and on the root navigator `false` leaves the keyboard over the screen; only a page that must not reflow may, and `keyboard_avoidance_guard_test.dart` makes it say why
- Do NOT rebuild a MediaQuery from a context above a Scaffold that consumed the keyboard inset without `.removeViewInsets(removeBottom: true)` — `MediaQuery.removePadding(context: outer)` hands the keyboard to every descendant a second time
- Do NOT put a sheet's buttons inside its scroll view — pin them in a `SheetActionBar` (`KeyboardSafeSheetBody(actions:)`); as the body's last child they sat under the keyboard and below the fold, and the bug reporter opened with Send out of sight
- Do NOT pad a sheet by the keyboard inside its scroll view, or cap a field sheet with `showModalBottomSheet(constraints:)` — the cap cancels the padding and the field stays under the keyboard, counted as visible; use `KeyboardSafeSheetBody`
- Do NOT give a field a `scrollPadding` number to show what sits under it — wrap the field and that text in `RevealTogether`
- Do NOT omit `ProxyHeadersMiddleware` when deploying behind Railway/Cloudflare — rate limiting will throttle all users from the same proxy IP without it
- Do NOT remove `ALLOWED_HOSTS` or set it to `*` in production — always whitelist `ntripi.app,*.ntripi.app`
- Do NOT set `SECRET_KEY` shorter than 32 characters — startup will refuse to start
- Do NOT expose `/docs`, `/redoc` or `/openapi.json` in production — `DEBUG=False` disables all three; do not override `docs_url`/`redoc_url`/`openapi_url` unconditionally
- Do NOT catch `asyncio.CancelledError` in exception handlers — re-raise it; intercepting it breaks Starlette's lifespan
- Do NOT add new rate-limited endpoints without importing `limiter` from `app/limiter.py` (not from `app/main.py` — circular import)
- Do NOT run the container as root — the Dockerfile creates `appuser` and must keep `USER appuser`
- Do NOT put request timing in a response header (`Server-Timing` or any other) — a query count or a duration tells any caller whether an account or a trip exists; `RequestTimingMiddleware` logs the route template instead
- Do NOT run Postgres in a different Railway region from the API — a save makes 8–20 database round trips one after another, and across the Atlantic that turned 0.2 s saves into 4–6 s
- Do NOT store tokens or sensitive user data in Riverpod provider state — use `flutter_secure_storage` only
- Do NOT add a keep-alive user-scoped provider without adding it to `_userScopedProviders` in `auth_provider.dart` — that list is reset on sign-in and sign-out, and a provider missing from it shows one account's data to the next person on the device
- Do NOT key the HTTP cache on the URL alone — `ntripiCacheKey` (`core/api/cache_key.dart`) prefixes the JWT `sub`, and every `CacheOptions` (including `forceRefreshOptions()`, whose options replace the interceptor's) and `CacheEvictInterceptor` must use it
- Do NOT build a Dio for the API outside `createDioClient` / `createBareDio` — they install `apiConnectionPool`; any other client opens a new connection after every 3 s pause and keeps a dead one across a sleep or a network change
- Do NOT raise `kApiConnectionIdleTimeout` to 400 s or above — Cloudflare closes an idle HTTP/1.1 connection at 400 s, and a request sent as both ends close fails instead of being slow
- Do NOT retire the API's connections with `HttpClient.close()` — even with `force: false` it cancels a request still opening its connection; set the old client's `idleTimeout` to zero, as `ApiConnectionPool.retire` does
- Do NOT compare an `If-Match` as a string — `_concurrency_token` compares instants; Dart and Python spell the same `updated_at` differently one time in a thousand
- Do NOT key a rate limit on X-Forwarded-For alone behind Cloudflare — its leftmost entry is caller-chosen; `ClientIPHeaderMiddleware` sets the client from `CLIENT_IP_HEADER`
- Do NOT close only the report in hand when content is hidden or restored — `admin_service.resolve_pending_reports` settles the target's other pending reports, or the SLA sweep re-hides what a moderator restored
- Do NOT approve an itinerary's status from an image review or a clean text re-check while another unreviewed signal stands on it — `approve_flagged` lowers only `flagged`, and the re-check leaves `pending` while an unscanned upload waits in `/admin/flagged`
- Do NOT write two audit rows for one operator hide — pass `admin=` to `moderation_actions.auto_hide`
- Do NOT let a background timer (heartbeat, poll) run while the app is not resumed, or outlive every screen that needs it — `EditLockNotifier.attach()`/`detach()`
- Do NOT call `ref.read` / `ref.watch` / `ref.invalidate` inside `State.dispose()` — it throws at runtime; capture the notifier in a field from `build` and call it from there