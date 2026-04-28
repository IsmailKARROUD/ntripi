# Ntripi — Architectural Rules for Claude

This file is automatically read by Claude Code at the start of every
session. It contains project conventions, portability rules, and
architectural decisions that apply to every change.

---

## Project Overview

Ntripi is a full-stack social media app for sharing travel itineraries.
Live in production at **https://ntripi.app**.

Monorepo at `/Users/ismac/project/Ntripi/` with two services:

- `social_api/` — FastAPI + PostgreSQL backend
- `social_flutter/` — Flutter frontend (iOS, Android, Web)

The two communicate **only** via HTTP/JSON. No shared code. No shared
types. The API boundary is the contract.

A single Dockerfile at the repo root handles the production build
of both services as a multi-stage image (Flutter web compiled in
stage 1, Python runtime + compiled web bundle in stage 2).

---

## Tech Stack (do not change without explicit request)

**Backend:**
- FastAPI 0.135+
- PostgreSQL via SQLAlchemy 2.0
- Alembic for migrations
- JWT (HS256) via python-jose + bcrypt direct (not passlib)
- Pydantic v2 + pydantic-settings
- Jinja2 for HTML templates (homepage, share landing pages)
- Uvicorn (ASGI)
- pytest + httpx + SQLite in-memory for tests

**Frontend:**
- Flutter (Dart SDK ≥ 3.3)
- Riverpod 2 (AsyncNotifier pattern — no code generation)
- Dio 5 (with auth + 401 interceptors)
- go_router 13
- flutter_secure_storage
- flutter_map + OpenStreetMap (no Google Maps for storage)
- share_plus for native share sheets

---

## Live URLs

```
ntripi.app/                    Marketing homepage (Jinja2 HTML)
ntripi.app/login               Web login form
ntripi.app/register            Web register form
ntripi.app/privacy             Privacy policy
ntripi.app/terms               Terms of service
ntripi.app/app/                Flutter web app (the actual product)
ntripi.app/app/itineraries/X   Flutter routes via SPA fallback
ntripi.app/share/i/X           Public itinerary landing page
ntripi.app/docs                Swagger UI for developers
ntripi.app/health              Health check (used by Railway)
```

---

## Portability Rules (CRITICAL — follow always)

These rules keep the project hostable anywhere without rewrites.

### Rule 1 — Everything configurable is an environment variable
- Never hardcode URLs, secrets, database connections, or feature flags
- Backend reads all config through `app/config.py` (pydantic-settings)
- Flutter reads all config through `--dart-define` build flags
- The `.env.example` file documents every variable the backend needs

### Rule 2 — Single Dockerfile at the repo root
- Multi-stage build: Flutter web compiled in stage 1, Python runtime in stage 2
- The Dockerfile is the universal contract for running the app
- Any hosting platform runs the same image identically
- Railway's Root Directory is the repo root (NOT `social_api/`)
- Never rely on platform auto-detection for builds

### Rule 3 — No platform-specific features

Allowed (portable everywhere):
- Standard PostgreSQL
- Standard environment variables
- Standard HTTP endpoints
- Persistent volumes (treat as swappable)

Avoid:
- Railway-specific private networking
- Heroku-style add-ons
- Proprietary build caches that affect runtime behavior

### Rule 4 — User uploads go through a storage abstraction
When adding file uploads (photos, avatars, etc.):
- Never write directly to the local filesystem from route handlers
- Create a `storage` service with a `save(bytes, path)` interface
- Implementation starts as local filesystem, swappable to S3 / R2 later
- Abstract the URL generation so it works for both local and remote

### Rule 5 — Backend and frontend are fully separated
- Zero shared code between the two sides
- No symlinks, no cross-imports, no path references across the boundary
- All communication through HTTP/JSON only
- Types are duplicated across languages intentionally — that's the contract
- Field naming uses snake_case in JSON; Flutter models convert to camelCase in fromJson

---

## Architectural Patterns (already established)

### Backend patterns

**Single source of truth for access control.**
`can_view_itinerary()` in `app/services/itinerary_access.py` is called
by every read endpoint. Never duplicated.

**Denormalized counters.**
Follower counts, rating averages, etc. are cached on parent rows.
Updated atomically in the same transaction as the source of truth.

**Recalculation helpers.**
For aggregates like rating averages, write helpers like
`recalculate_rating(itinerary_id)` that use `SELECT AVG(...)` and
write back to cached columns. Use NULL not 0.0 when count is zero.

**Pydantic schemas for every response.**
Endpoints never return raw ORM objects. Define Response schemas
explicitly so the API contract is visible.

**Direct bcrypt for passwords.**
We removed passlib due to Python 3.13+ incompatibility.
`bcrypt.hashpw()` and `bcrypt.checkpw()` directly.

**Timing attack prevention on login.**
Always call verify_password even when user not found (using a
dummy hash), so attackers can't infer email existence from
response timing.

**Auth service pattern.**
Web routes (`/web/login`, `/web/register`) and API routes
(`/auth/login`, `/auth/register`) share business logic via
`app/services/auth_service.py`. Web sets HTTP-only cookies;
API returns JSON tokens.

### Storage abstraction

User-uploaded files (currently itinerary cover images) go through
`app/storage/`. Never reference the filesystem directly from routes.

- `app/storage/base.py` — `Storage` ABC (`save`, `delete`, `public_url`, `exists`)
- `app/storage/filesystem.py` — `FilesystemStorage` (Phase 1, current production)
- `app/storage/factory.py` — `storage()` lru-cached singleton; set `STORAGE_BACKEND`
  env var to swap implementations without touching call sites
- Future: add `R2Storage` / `S3Storage` in `factory.py` — zero call-site changes

Image processing (resize to 1200×630, EXIF strip, JPEG re-encode) lives in
`app/services/image_service.py` → `process_cover_image(raw_bytes) → bytes`.

**Production requirement:** Railway must mount a persistent volume at
`STORAGE_FILESYSTEM_PATH` (`/app/uploads` by default) so uploaded images survive
deploys. Without it, every redeploy wipes all user cover images.

### Frontend patterns

**Feature-first folder structure.**
`features/<feature>/{data,domain,presentation,providers}`. Each
feature has its repository (Dio calls), notifier (Riverpod state),
and screens.

**Manual fromJson/toJson — no code generation.**
build_runner is not used. Models are written by hand. This is
deliberate — we trade some boilerplate for full control.

**Three async states always handled.**
`loading`, `error`, `data` (and `empty` where relevant). Use
`AsyncValue.when()` or pattern matching on the Riverpod state.

**Never put ListView inside Column.**
Use CustomScrollView + Slivers when content is mixed.

**Owner-only UI elements via explicit checks.**
Always `if (currentUser?.id == itinerary.ownerId)`. Never
infer ownership from the current route.

---

## Data Conventions

### User Identity

**Username (the @ handle):**
- Allowed: a-z, A-Z, 0-9, period (.), underscore (_)
- NOT allowed: hyphens, spaces, Unicode, emoji
- Length: 4–30 characters
- Must start with a letter, end with letter or number
- No consecutive special chars (.., __, ._, _.)
- Display preserved; case-insensitive lookup via `username_lower` column

**Display name:**
- Free Unicode (international, emoji, spaces)
- Length: 1–50 characters
- Optional, falls back to `@{username}` when empty

**Email:**
- Always lowercased before storage and comparison

### Itinerary Visibility

Four levels: `public`, `followers`, `restricted`, `only_me`.
Default is `only_me`. Single source of truth in `can_view_itinerary()`.
Allowlist for `restricted` is in `itinerary_allowed_users` table —
records persist across visibility changes.

### Multi-Dimensional Ratings

Required: `score` (overall, 1–5).
Optional: `score_safety`, `score_experience`, `score_accessibility`,
`score_family_friendly`. NULL means "user didn't rate this dimension."

Cached aggregates on `itineraries` table: `rating_avg_*` (DECIMAL,
NULL when count = 0) and `rating_count_*` (INTEGER, default 0).

Dimension averages displayed only when count >= 3 (avoid noisy
single-rating averages).

### Annotations

Editable. PATCH endpoint accepts text and/or type. `updated_at`
column added with `onupdate=func.now()`.

### Account Deletion

`ON DELETE SET NULL` on `itinerary_ratings.user_id` preserves
community data as anonymized scores. Account deletion requires
password re-entry plus type-to-confirm ("DELETE MY ACCOUNT").

---

## UX Conventions

### Destructive Actions — Three Tiers

**Tier 1 — Undo Snackbar (cheap, reversible).**
Used for: unfollow, remove from allowlist.
Action happens immediately. Snackbar offers UNDO for 5 seconds.
Undo creates the inverse action.

**Tier 2 — Simple Confirmation Dialog.**
Used for: delete annotation, delete stop, delete rating, delete
transit segment.
AlertDialog with title, message, Cancel + Delete buttons. Delete
button styled with error color. Cancel has default focus.

**Tier 3 — Type-to-Confirm Dialog.**
Used for: delete itinerary, delete account.
User must type a phrase (itinerary title, or "DELETE MY ACCOUNT")
before the confirm button enables.

Implementation lives in `lib/core/ui/destructive_actions.dart`:
- `confirmDestructiveAction()` for Tier 2
- `confirmTypedDestructiveAction()` for Tier 3
- `showUndoableActionSnackbar()` for Tier 1

Never write inline `showDialog` for destructive actions.

### Cookie / Session Management

Web auth flow uses `ntripi_session` HTTP-only cookie:
- Secure flag in production (DEBUG=False)
- SameSite=Lax (allows nav from other sites, blocks CSRF)
- Max-Age matches JWT expiry

API auth uses Authorization header with Bearer token.
Both flows produce the same JWT format from `auth_service`.

### Maps and Attribution

Map tiles via OpenStreetMap (flutter_map). OSM attribution always
visible on every map ("OpenStreetMap contributors", ODbL requirement).

---

## Legal / Compliance Rules

### Google Maps
Google Places API is used ONLY for autocomplete UX. Nothing from
Google Places is stored permanently (per Google ToS 3.2.3(a)(iii)).
Geocoding via Nominatim (OpenStreetMap) — ODbL allows storage.
Map tiles always from OpenStreetMap (flutter_map), never Google Maps SDK.

### GDPR
Account deletion anonymizes ratings (user_id → NULL) rather than
deleting them. The `user_id` FK on `itinerary_ratings` uses
`ON DELETE SET NULL`. Users consent via `tos_accepted_at` at
registration. ToS text in `app/constants/tos.py`, served via `GET /tos`.

### Privacy Policy
Placeholder at `app/constants/privacy.py`. Needs real content
before public launch.

---

## Testing Conventions

### Backend tests
- `client` fixture from `test/conftest.py` (fresh SQLite per test)
- Helpers: `register_user()`, `auth_headers()`
- Test class names describe the feature: `TestFollowSystem`, `TestVisibility`
- Test function names: `test_<what>_<expected_outcome>`
- Use real API endpoints, not direct DB manipulation
- SQLite FK enforcement via `PRAGMA foreign_keys=ON` in conftest

### Flutter tests
- `http_mock_adapter` for Dio mocking
- `FlutterSecureStorage.setMockInitialValues({})` for auth state
- Model tests: fromJson/toJson round-trips
- Repository tests: API call shapes

---

## Hosting (current)

**Production:**
- Single Docker image at the monorepo root
- Hosted on Railway with managed PostgreSQL
- Multi-stage build: `ghcr.io/cirruslabs/flutter:stable` (stage 1) + `python:3.11-slim` (stage 2)
- Cloudflare Registrar + Cloudflare DNS (proxied)
- Let's Encrypt SSL via Railway

**Build flow on every git push:**
1. Railway pulls latest commit
2. Multi-stage Docker build:
   - Stage 1: Flutter web compiled with `--base-href=/app/`
   - Stage 2: Python runtime, copies the Flutter bundle in
3. Container starts: `alembic upgrade head` then `uvicorn`

**Build time:** ~5–8 min first build (Flutter SDK download); ~2–3 min cached.
**Final image size:** ~250 MB (Flutter SDK discarded after Stage 1).

**Environment variables (Railway):**
```
DATABASE_URL                  (auto, references Postgres addon)
SECRET_KEY                    (production JWT signing key)
ALGORITHM                     HS256
ACCESS_TOKEN_EXPIRE_MINUTES   1440
DEBUG                         False
SHARE_BASE_URL                https://ntripi.app
ALLOWED_ORIGINS               https://ntripi.app,http://localhost:5555
ANDROID_DOWNLOAD_URL          (empty until Android APK is hosted)
STORAGE_BACKEND               filesystem
STORAGE_FILESYSTEM_PATH       /app/uploads
STORAGE_PUBLIC_URL_PREFIX     /uploads
```

**Persistent volume (required):** Mount a Railway volume at `/app/uploads` so
user-uploaded cover images survive deploys. Without it every redeploy wipes all images.

### Routes served by the single container

| Path prefix           | Handler                                      |
|-----------------------|----------------------------------------------|
| `/`                   | Jinja2 marketing homepage                    |
| `/login`, `/register` | Web auth forms                               |
| `/privacy`, `/terms`  | Legal pages                                  |
| `/share/i/{id}`       | Public itinerary landing pages               |
| `/app/`               | Flutter web app (StaticFiles, `html=True`)   |
| `/static/`            | Backend static assets (OG image, etc.)       |
| `/docs`               | Swagger UI                                   |
| `/health`             | Health check                                 |
| Everything else       | JSON API endpoints                           |

In **local dev**, `/app/` returns 404 (no Flutter build present — intended).

---

## Deferred Features

- Universal Links (iOS) / App Links (Android) — requires App Store/Play Store
- Dynamic Open Graph preview images — needs server rendering setup
- Post/reactions feature — deferred in favor of sharing
- Home feed algorithm — deferred until posts exist

---

## What NOT To Do

- Do not introduce code generation (build_runner, json_serializable)
  without explicit discussion — manual models are deliberate
- Do not add a new state management library — Riverpod is the choice
- Do not use Google Maps SDK anywhere — OpenStreetMap only
- Do not write rating averages in Python math — use SQL AVG()
- Do not create new access control logic — reuse `can_view_itinerary()`
- Do not hardcode any URL, secret, or environment-specific value
- Do not write inline `showDialog` for destructive actions — use `destructive_actions.dart`
- Do not skip the `--break-system-packages` flag when installing pip
  packages system-wide (macOS requirement)
