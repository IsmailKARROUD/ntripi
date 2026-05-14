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
Required: `score` (1-5). Optional: `score_safety`, `score_experience`, `score_accessibility`, `score_family_friendly`. NULL = not rated. Show dimension averages only when count ≥ 3.

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

Railway env vars: `DATABASE_URL=${{Postgres.DATABASE_URL}}` · `SECRET_KEY` · `ALGORITHM=HS256` · `ACCESS_TOKEN_EXPIRE_MINUTES=1440` · `DEBUG=False` · `SHARE_BASE_URL=https://ntripi.app` · `ALLOWED_ORIGINS=https://ntripi.app` · `STORAGE_BACKEND=filesystem` · `STORAGE_FILESYSTEM_PATH=/app/uploads` · `STORAGE_PUBLIC_URL_PREFIX=/uploads`

Persistent volume must be mounted at `/app/uploads` or images vanish on redeploy.

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
- Do NOT hardcode URLs, secrets, or environment values
- Do NOT use `passlib` — bcrypt direct only
- Do NOT use `allow_origin_regex=".*"` in CORS — explicit list only
- Do NOT query `User.username == something` — always `username_lower`
- Do NOT use `--web-renderer` flag in Flutter (removed in 3.29)
- Do NOT reference `DATABASE_PUBLIC_URL` from the backend — use `${{Postgres.DATABASE_URL}}`
- Do NOT bypass the storage abstraction
- Do NOT skip EXIF stripping on uploaded images
- Do NOT write inline `showDialog` for destructive actions