# Ntripi — Architectural Rules for Claude

This file is automatically read by Claude Code at the start of every
session. It contains project-wide conventions, portability rules, and
context that applies to every change.

---

## Project Overview

Ntripi is a full-stack social media app for sharing travel itineraries.
Structured as a monorepo with two independent services:

- `social_api/` — FastAPI + PostgreSQL backend
- `social_flutter/` — Flutter frontend (iOS, Android, Web)

The two communicate **only** via HTTP/JSON. No shared code. No shared
types. The API boundary is the contract.

---

## Tech Stack (do not change without explicit request)

**Backend:**
- FastAPI 0.135+
- PostgreSQL (via SQLAlchemy 2.0)
- Alembic for migrations
- JWT (HS256) via python-jose + bcrypt
- Pydantic v2 + pydantic-settings
- Uvicorn (ASGI)
- pytest + httpx for tests
- SQLite in-memory for test database

**Frontend:**
- Flutter (Dart SDK ≥ 3.3)
- Riverpod 2 (AsyncNotifier pattern — no code generation)
- Dio 5 (with auth + 401 interceptors)
- go_router 13
- flutter_secure_storage
- flutter_map + OpenStreetMap (no Google Maps for storage)

---

## Portability Rules (CRITICAL — follow always)

These rules keep the project hostable anywhere without rewrites.

### Rule 1 — Everything configurable is an environment variable

- Never hardcode URLs, secrets, database connections, or feature flags
- Backend reads all config through `app/config.py` (pydantic-settings)
- Flutter reads all config through `--dart-define` build flags
- The `.env.example` file documents every variable the backend needs

### Rule 2 — Use an explicit Dockerfile

- The backend has a Dockerfile at `social_api/Dockerfile`
- The Dockerfile is the universal contract for running the backend
- Any hosting platform (Railway, Fly.io, DigitalOcean, bare metal)
  runs the same Docker image identically
- Never rely on platform auto-detection for builds

### Rule 3 — No platform-specific features

Do not use Railway-specific, Render-specific, or Heroku-specific features:
- No Railway private networking — use public URLs
- No Heroku-style add-ons — use standard Postgres connection strings
- No proprietary build caches that affect runtime behavior

Allowed platform features (portable everywhere):
- Standard PostgreSQL
- Standard environment variables
- Standard HTTP endpoints
- Persistent volumes (treat as swappable)

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

- Single source of truth functions for access control
  (e.g. `can_view_itinerary()` in `app/services/itinerary_access.py`)
- Access control function called by every read endpoint, never duplicated
- Denormalized counters (follower counts, rating averages) updated
  after every mutation in the same transaction
- Recalculation helpers write to cached aggregate columns atomically
- Every API endpoint returns a Pydantic schema — never raw ORM objects
- Password hashing uses bcrypt directly (not passlib — removed due to
  Python 3.13+ incompatibility)
- Timing attack prevention on login: always call verify_password even
  when user not found (using dummy hash)

### Frontend patterns

- Feature-first folder structure: `features/<feature>/{data,domain,presentation,providers}`
- Each feature has repository (Dio calls) + notifier (Riverpod state) + screens
- Manual fromJson/toJson — no code generation (build_runner not used)
- Three async states always handled: loading, error, data (and empty where relevant)
- Never put ListView inside Column — use CustomScrollView + Slivers
- Owner-only UI elements hidden via explicit `isOwner` checks, not by route

---

## Legal / Compliance Rules

### Google Maps
- Google Places API is used ONLY for autocomplete UX
- Nothing from Google Places is stored in the database permanently
- Per Google ToS 3.2.3(a)(iii), storing business names/addresses is prohibited
- Geocoding happens via Nominatim (OpenStreetMap) — ODbL licensed, storage allowed
- Map tiles always from OpenStreetMap (flutter_map), never Google Maps
- OSM attribution always visible on every map rendering (ODbL requirement)

### GDPR
- Account deletion anonymizes ratings (user_id → NULL) rather than deleting them
- The user_id FK on itinerary_ratings uses ON DELETE SET NULL
- Users consent to this at registration via tos_accepted_at timestamp
- ToS text lives in `app/constants/tos.py` and is served via GET /tos
- Account deletion requires password re-entry

---

## Testing Conventions

### Backend tests
- Use the `client` fixture from `test/conftest.py` (fresh SQLite DB per test)
- Helpers: `register_user()`, `auth_headers()`
- Test class names describe the feature: `TestFollowSystem`, `TestVisibility`
- Test function names: `test_<what>_<expected_outcome>`
- Use the real API endpoints in tests, not direct DB manipulation
- Exception: SQLite FK enforcement is enabled via
  `PRAGMA foreign_keys=ON` in conftest.py

### Flutter tests
- Use `http_mock_adapter` for Dio mocking
- Use `FlutterSecureStorage.setMockInitialValues({})` for auth state
- Model tests (`test/models/`) verify fromJson/toJson round-trips
- Repository tests (`test/repositories/`) verify API call shapes

---

## Hosting (current + planned)

- Development: `localhost:8000` backend, Flutter runs on Chrome / iOS sim
- Production: Railway (FastAPI + Postgres), Cloudflare DNS + HTTPS
- Domain: ntripi.app (Cloudflare Registrar)
- Future option: migrate to self-hosted VPS or own infrastructure
  (rules above make this possible with no code changes)

---

## Deferred Features (tracked in Jira)

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
- Do not write rating averages to Python math — use SQL AVG()
- Do not create new access control logic — reuse `can_view_itinerary()`
- Do not hardcode any URL, secret, or environment-specific value
- Do not skip the `--break-system-packages` flag when installing pip
  packages system-wide (macOS requirement)