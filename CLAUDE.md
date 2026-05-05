# Ntripi — Architectural Rules for Claude

This file is automatically read by Claude Code at the start of every
session. It contains project conventions, portability rules, and
architectural decisions that apply to every change.

For new conversations on Claude.ai, paste this file into the chat
or upload it to a Claude Project for persistent context.

---

## Project Overview

Ntripi is a full-stack social media app for sharing travel itineraries.
Live in production at **https://ntripi.app**.

Monorepo at `/Users/ismac/project/Ntripi/`:
- `social_api/` — FastAPI + PostgreSQL backend
- `social_flutter/` — Flutter frontend (iOS, Android, Web)

The two communicate **only** via HTTP/JSON. No shared code.

A single Dockerfile at the repo root handles the production build
of both as a multi-stage image (Flutter web compiled in stage 1,
Python runtime + compiled web bundle in stage 2).

---

## Tech Stack

**Backend:** FastAPI 0.135+ · PostgreSQL via SQLAlchemy 2.0 ·
Alembic · JWT (HS256) via python-jose + bcrypt direct ·
Pydantic v2 + pydantic-settings · Jinja2 · Pillow (image processing) ·
Uvicorn · pytest + httpx + SQLite in-memory for tests

**Frontend:** Flutter (Dart SDK ≥ 3.3) · Riverpod 2 (AsyncNotifier,
no codegen) · Dio 5 · go_router 13 · flutter_secure_storage ·
flutter_map + OpenStreetMap · share_plus · image_picker

---

## Live URLs
ntripi.app/                    Marketing homepage (Jinja2 HTML)
ntripi.app/login, /register    Web auth forms
ntripi.app/privacy, /terms     Legal pages
ntripi.app/app/                Flutter web app
ntripi.app/app/itineraries/X   Flutter SPA routes (html=True fallback)
ntripi.app/share/i/X           Public itinerary landing pages
ntripi.app/uploads/...         User-uploaded files (cover images)
ntripi.app/static/...          App assets
ntripi.app/docs                Swagger UI
ntripi.app/health              Health check (Railway)

---

## Portability Rules (CRITICAL)

### Rule 1 — Everything configurable is an environment variable
- Backend reads via `app/config.py` (pydantic-settings)
- Flutter reads via `--dart-define` build flags
- `.env.example` documents every variable

### Rule 2 — Single Dockerfile at repo root
- Multi-stage: Flutter web (stage 1) → Python runtime (stage 2)
- Railway Root Directory is empty (NOT `social_api/`)

### Rule 3 — No platform-specific features
- Standard PostgreSQL, env vars, HTTP only
- No Railway private networking, no Heroku-style addons
- Persistent volumes treated as swappable

### Rule 4 — User uploads through storage abstraction
- `app/storage/base.py` defines the Storage interface
- `FilesystemStorage` is current implementation
- R2/S3 can swap in via single config change (separate Jira ticket)
- Calling code uses `storage().save()` and `.delete()` only

### Rule 5 — Backend ↔ Frontend fully separated
- Zero shared code, no symlinks, HTTP/JSON only
- snake_case in JSON; Flutter converts to camelCase in fromJson
- Types duplicated across languages by design

---

## Architectural Patterns

### Backend
- Single source of truth for access control:
  `can_view_itinerary()` in `app/services/itinerary_access.py`
- Denormalized counters updated in same transaction as source
- Recalculation helpers use SQL `AVG()`, write NULL not 0.0 when count=0
- Every endpoint returns Pydantic schema, never raw ORM
- Direct bcrypt (passlib removed for Python 3.13+ compatibility)
- Timing attack prevention on login (always verify_password, even when no user)
- Auth service pattern: `auth_service.py` shared by web (`/web/login`)
  and API (`/auth/login`). Web sets cookies, API returns JWTs.
- Image processing: `app/services/image_service.py` does Pillow
  resize + EXIF strip + 1200x630 cover-fit crop + JPEG re-encode

### Frontend
- Feature-first: `features/<feature>/{data,domain,presentation,providers}`
- Manual fromJson/toJson — no build_runner/json_serializable
- Three async states always: loading, error, data (and empty)
- Never ListView inside Column — use CustomScrollView + Slivers
- Owner UI elements via explicit `currentUser?.id == itinerary.ownerId`

---

## Data Conventions

### User Identity (case-insensitive uniqueness, display preserved)
- **Username:** a-z A-Z 0-9 period underscore. NO hyphens, spaces,
  Unicode. 4-30 chars. Starts with letter, ends letter/number.
  No consecutive special chars.
- Stored as both `username` (display) and `username_lower` (lookup key)
- All queries use `username_lower`. NEVER `username == ...`.
- **Display name:** Free Unicode (50 char max). Optional. Falls back
  to `@{username}` when empty.
- **Email:** Always lowercased before storage and comparison.

### Stop Place Types
11 purpose-based categories stored as camelCase strings in `place_type` (String, nullable):
`eatDrink` · `sleep` · `pray` · `learnSee` · `buy` · `playWatch` ·
`nature` · `travel` · `healBathe` · `entertainment` · `sight`

Flutter: `PlaceType` enum in `features/itineraries/domain/stop.dart`.
Use `PlaceType.fromString()` for deserialization — handles legacy DB values
(restaurant→eatDrink, hotel→sleep, museum→learnSee, etc.) and returns null
for unknowns instead of throwing.
Backend: validated by regex in `StopCreate`/`StopUpdate` in `schemas/itinerary.py`.
Do NOT use `PlaceType.values.byName()` directly — always go through `fromString()`.

### Itinerary Visibility
Four levels: `public`, `followers`, `restricted`, `only_me`.
Default `only_me`. Single source of truth: `can_view_itinerary()`.
Allowlist for restricted in `itinerary_allowed_users` table.

### Multi-Dimensional Ratings
Required: `score` (1-5).
Optional: `score_safety`, `score_experience`, `score_accessibility`,
`score_family_friendly`. NULL = "didn't rate this dimension."
Cached aggregates: `rating_avg_*` (NULL when count=0), `rating_count_*`.
Show dimension averages only when count >= 3.

### Annotations
Two separate annotation systems — same four types (advice/caution/avoid/info),
different parent FK:

**Stop-level** (`annotations` table, `stop_id → stops.id`)
- Notes about a specific stop ("closes at 5pm", "avoid the souvenir shops")
- Endpoints: `POST/PATCH/DELETE /itineraries/{id}/stops/{stopId}/annotations`
- Managed from the stop form screen AND inline in detail screen edit mode

**Itinerary-level** (`itinerary_annotations` table, `itinerary_id → itineraries.id`)
- Notes about the trip as a whole ("best in summer", "book 2 months ahead")
- Endpoints: `POST/PATCH/DELETE /itineraries/{id}/annotations`
- Shown in a "Notes" section on the detail screen (between description and rating)

Both: editable via PATCH (type and/or content). `updated_at` with `onupdate=func.now()`.
Flutter: both use `AnnotationChip` for display. `ItineraryAnnotation` domain model
is separate from `Annotation` (different `itineraryId` vs `stopId` field).

### Itinerary Images
One optional cover image per itinerary. Stored at
`/app/uploads/itineraries/{id}.jpg` via storage abstraction.
Image priority chain on share landing page:
1. user-uploaded `image_url` (current)
2. auto-generated map image (deferred — Jira ticket)
3. default `/static/ntripi-og-default.png`

### Account Deletion
`ON DELETE SET NULL` on `itinerary_ratings.user_id` preserves
community data as anonymized scores. Requires password re-entry
plus type-to-confirm "DELETE MY ACCOUNT".

---

## UX Conventions

### Destructive Actions — 3 Tiers

**Tier 1 — Undo Snackbar (cheap, reversible)**
Used for: unfollow, remove from allowlist
Implementation: `showUndoableActionSnackbar()` in
`lib/core/ui/destructive_actions.dart`

**Tier 2 — Simple Confirmation Dialog**
Used for: delete annotation, stop, rating, transit segment
Implementation: `confirmDestructiveAction()`

**Tier 3 — Type-to-Confirm Dialog**
Used for: delete itinerary (type the title), delete account (type
"DELETE MY ACCOUNT" + password re-entry)
Implementation: `confirmTypedDestructiveAction()`

NEVER write inline `showDialog` for destructive actions.

### Cookie / Session
Web uses `ntripi_session` HTTP-only cookie (Secure when DEBUG=False,
SameSite=Lax). API uses Authorization header Bearer token.
Both produce identical JWTs from `auth_service`.

### Maps
flutter_map + OpenStreetMap tiles. Attribution always visible
("OpenStreetMap contributors", ODbL requirement).

---

## Legal / Compliance

- **Google Maps:** Places API for autocomplete UX only. Never store
  Places data (ToS 3.2.3(a)(iii)). Geocoding via Nominatim (ODbL OK).
- **GDPR:** Account deletion anonymizes ratings. ToS in
  `app/constants/tos.py`, served via `GET /tos`. `tos_accepted_at`
  timestamp captured at registration.
- **Privacy policy:** Placeholder at `app/constants/privacy.py`.
  Needs real content before public launch.
- **EXIF stripping:** Mandatory on uploaded images for GPS privacy.

---

## Testing

### Backend
- `client` fixture in `test/conftest.py` (fresh SQLite per test)
- Helpers: `register_user()`, `auth_headers()`
- SQLite FK enforcement: `PRAGMA foreign_keys=ON` in conftest
- Use real API endpoints, not direct DB manipulation

### Flutter
- `http_mock_adapter` for Dio mocking
- `FlutterSecureStorage.setMockInitialValues({})` for auth state
- Manual fromJson/toJson round-trip tests

---

## Hosting / Deployment

**Production:** Railway (single Dockerfile, multi-stage build) +
Cloudflare Registrar/DNS (proxied) + Let's Encrypt SSL via Railway.

**Build flow on every git push:**
1. Railway pulls latest commit
2. Stage 1: cirruslabs/flutter compiles web bundle with
   `--base-href=/app/`
3. Stage 2: python:3.11-slim runs backend, copies Flutter bundle
4. Container: `alembic upgrade head` then `uvicorn`

**Railway env vars:**
DATABASE_URL=${{Postgres.DATABASE_URL}}  ← private, NOT public
SECRET_KEY=<production JWT key>
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=1440
DEBUG=False
SHARE_BASE_URL=https://ntripi.app
ALLOWED_ORIGINS=https://ntripi.app,http://localhost:5555
ANDROID_DOWNLOAD_URL=  (empty until APK ready)
STORAGE_BACKEND=filesystem
STORAGE_FILESYSTEM_PATH=/app/uploads
STORAGE_PUBLIC_URL_PREFIX=/uploads

**Railway volume requirement:** Persistent volume must be mounted
at `/app/uploads` or images vanish on redeploy.

**Local dev:**
- Backend: `PYTHONPATH=. uvicorn app.main:app --reload` from `social_api/`
- Flutter: `flutter run -d chrome --web-port=5555 --dart-define=...`
  (port pinned for stable CORS)
- Scripts: `social_flutter/scripts/dev.sh` and `prod.sh`

---

## Active Backlog (Jira)

### Trust & Safety — Content Moderation Epic
- Phase 1: User Reporting (HIGH, ready)
- Phase 2: AI Image Scanning (HIGH, blocks public launch)
- Phase 5: CSAM Detection (CRITICAL, legal requirement)
- Phase 3: Operator Dashboard
- Phase 4: User Appeals
- Phase 6: Text Moderation (with posts)
- Phase 7: Profile Photo Moderation (with avatars)
- Phase 8: Trust Signals (at scale)

### Production Hardening Epic
- Universal Links / App Links (deep linking)
- Server-side map images (share preview Phase 2)
- Production monitoring (Sentry, health checks, backups)
- Email verification + password reset
- Username change UX (rate limiting + reservation period)
- Migrate image storage to Cloudflare R2 / S3

### Future Features
- Posts feature (text + photos)
- Reactions on posts (LinkedIn-style: salute, wow, love, bookmark)
- Home feed
- Android APK distribution
- iOS App Store launch

---

## What NOT To Do

- Do NOT introduce code generation (build_runner, json_serializable)
- Do NOT add a new state management library — Riverpod only
- Do NOT use Google Maps SDK anywhere — OSM only
- Do NOT compute rating averages in Python — use SQL `AVG()`
- Do NOT create new access control logic — reuse `can_view_itinerary()`
- Do NOT hardcode URLs, secrets, or environment values
- Do NOT skip `--break-system-packages` for system pip on macOS
- Do NOT write inline `showDialog` for destructive actions
- Do NOT use `allow_origin_regex=".*"` in CORS — use explicit list
- Do NOT query `User.username == something` — always `username_lower`
- Do NOT use `--web-renderer` flag in Flutter web (removed in 3.29)
- Do NOT reference `DATABASE_PUBLIC_URL` from the backend (egress fees) —
  always `${{Postgres.DATABASE_URL}}` (private network)
- Do NOT bypass the storage abstraction — use `storage().save()`
- Do NOT skip EXIF stripping on uploaded images (privacy risk)
