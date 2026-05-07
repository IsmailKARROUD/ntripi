# Ntripi API — Backend

FastAPI + PostgreSQL backend for the Ntripi social travel application.

## Project Structure

```
social_api/
├── app/
│   ├── main.py              ← FastAPI app, CORS, router registration
│   ├── config.py            ← pydantic-settings config (reads .env)
│   ├── database.py          ← SQLAlchemy engine + session factory
│   ├── dependencies.py      ← get_current_user (JWT auth dependency)
│   ├── models/
│   │   ├── user.py                    ← users table
│   │   ├── follow.py                  ← follows table + FollowStatus enum
│   │   ├── itinerary.py               ← itineraries table
│   │   ├── track.py                   ← tracks table (groups parallel stops, ordered by rank)
│   │   ├── stop.py                    ← stops table (track_id + rank, no position)
│   │   ├── annotation.py              ← annotations table (per stop)
│   │   ├── itinerary_annotation.py    ← itinerary_annotations table (trip-level notes)
│   │   ├── transit_segment.py         ← transit_segments table
│   │   ├── transport_leg.py           ← transport_legs table
│   │   ├── itinerary_rating.py        ← itinerary_ratings table (5 dimensions)
│   │   └── itinerary_allowed_user.py  ← itinerary_allowed_users table
│   ├── schemas/
│   │   ├── auth.py          ← Register/Login request + Token response
│   │   ├── user.py          ← User profile schemas
│   │   ├── follow.py        ← Follow response + request list schemas
│   │   └── itinerary.py     ← All itinerary/stop/segment/leg/rating/annotation schemas
│   ├── routers/
│   │   ├── auth.py          ← POST /auth/register, POST /auth/login
│   │   ├── users.py         ← GET/PATCH /users/me, search, public profile
│   │   ├── follows.py       ← All follow/unfollow endpoints
│   │   ├── itineraries.py   ← All itinerary, stop, segment, leg, rating, image endpoints
│   │   ├── share.py         ← GET /share/i/{id} public share landing page
│   │   └── web.py           ← Web HTML routes (login, register, marketing pages)
│   └── services/
│       ├── auth.py               ← bcrypt hashing + JWT create/decode
│       ├── auth_service.py       ← Shared login/session logic for web + API
│       ├── itinerary_access.py   ← Visibility logic + rating recalculation
│       ├── image_service.py      ← Pillow: resize + EXIF strip + 1200×630 crop + JPEG
│       ├── ordering.py           ← Fractional indexing: key_between / n_keys_between
│       └── share_service.py      ← OG metadata builder for share pages
├── alembic/
│   ├── env.py               ← Alembic config (reads DATABASE_URL from settings)
│   └── versions/            ← Generated migration scripts go here
├── alembic.ini              ← Alembic CLI config
├── requirements.txt
├── .env.example
└── README.md
```

---

## Database Schema

### Table: users

| Column          | Type         | Notes                                                    |
|-----------------|--------------|----------------------------------------------------------|
| id              | UUID         | Primary key, auto-generated                              |
| username        | VARCHAR(30)  | Display form — a-z A-Z 0-9 period underscore             |
| username_lower  | VARCHAR(30)  | Unique, indexed — always used for lookups                |
| email           | VARCHAR(255) | Unique, indexed, lowercased before storage               |
| password_hash   | VARCHAR(255) | bcrypt hash only — plain password never stored           |
| display_name    | VARCHAR(50)  | Nullable — free Unicode                                  |
| bio             | TEXT         | Nullable                                                 |
| avatar_url      | TEXT         | Nullable                                                 |
| is_private      | BOOLEAN      | Default false — drives follow flow                       |
| followers_count | INTEGER      | Denormalized counter, default 0                          |
| following_count | INTEGER      | Denormalized counter, default 0                          |
| is_active       | BOOLEAN      | Default true — soft delete/suspension flag               |
| tos_accepted_at | TIMESTAMP    | Captured at registration (GDPR)                          |
| created_at      | TIMESTAMP    | Auto-set on insert                                       |
| updated_at      | TIMESTAMP    | Auto-updated on every change                             |

### Table: follows

| Column       | Type      | Notes                                   |
|--------------|-----------|-----------------------------------------|
| id           | UUID      | Primary key                             |
| follower_id  | UUID      | FK → users.id ON DELETE CASCADE         |
| following_id | UUID      | FK → users.id ON DELETE CASCADE         |
| status       | ENUM      | `pending` or `accepted`                 |
| created_at   | TIMESTAMP | Auto-set on insert                      |
| updated_at   | TIMESTAMP | Auto-updated on every change            |

Constraints: UNIQUE(follower_id, following_id), CHECK follower_id != following_id

### Table: itineraries

| Column             | Type          | Notes                                                     |
|--------------------|---------------|-----------------------------------------------------------|
| id                 | UUID          | Primary key                                               |
| user_id            | UUID          | FK → users.id ON DELETE CASCADE, indexed                  |
| title              | VARCHAR(200)  |                                                           |
| description        | TEXT          | Nullable                                                  |
| cover_image_url    | TEXT          | Nullable — path to uploaded cover image                   |
| total_duration_min | INTEGER       | Denormalized sum of stops + segments. Recalculated server-side |
| total_cost         | NUMERIC(10,2) | Denormalized sum of stops + segments. Recalculated server-side |
| currency           | VARCHAR(3)    | ISO 4217 code, default `EUR`                              |
| safety_rating      | SMALLINT      | Nullable, 1–5 (owner's personal route-safety rating)      |
| rating_avg         | NUMERIC(3,2)  | Denormalized community average overall. NULL when count=0 |
| rating_count       | INTEGER       | Count of community overall ratings                        |
| visibility         | VARCHAR(20)   | `public` / `followers` / `restricted` / `only_me`        |
| created_at         | TIMESTAMP     |                                                           |
| updated_at         | TIMESTAMP     |                                                           |

### Table: tracks

A track is a vertical column of parallel stop alternatives at the same point in the journey. Tracks are ordered within an itinerary by `rank` (fractional indexing).

| Column       | Type      | Notes                                                    |
|--------------|-----------|----------------------------------------------------------|
| id           | UUID      | Primary key                                              |
| itinerary_id | UUID      | FK → itineraries.id ON DELETE CASCADE, indexed           |
| rank         | TEXT COLLATE "C" | Fractional-index key — byte-wise sorted            |
| created_at   | TIMESTAMP |                                                          |
| updated_at   | TIMESTAMP |                                                          |

Constraints: UNIQUE(itinerary_id, rank). A track is always non-empty — it is created with its first stop and deleted when its last stop is deleted.

### Table: stops

> **Stop role (origin / waypoint / arrival) is not stored here.** Flutter derives it from track position: first track = origin, last track = arrival, rest = waypoint. Computed in `Itinerary._parseTracks()`. No `type` column exists.

| Column       | Type          | Notes                                                                |
|--------------|---------------|----------------------------------------------------------------------|
| id           | UUID          | Primary key                                                          |
| itinerary_id | UUID          | FK → itineraries.id ON DELETE CASCADE, indexed                       |
| track_id     | UUID          | FK → tracks.id ON DELETE CASCADE, indexed                            |
| rank         | TEXT COLLATE "C" | Fractional-index key within the track                             |
| place_name   | VARCHAR(200)  | Nullable                                                             |
| place_address| TEXT          | Nullable                                                             |
| lat          | NUMERIC(9,6)  | Nullable — ~11cm precision                                           |
| lng          | NUMERIC(9,6)  | Nullable                                                             |
| place_type   | VARCHAR(50)   | Nullable — camelCase: eatDrink/sleep/pray/learnSee/buy/playWatch/nature/travel/healBathe/entertainment/sight |
| duration_min | INTEGER       | Nullable                                                             |
| cost         | NUMERIC(10,2) | Default 0.00                                                         |
| is_free      | BOOLEAN       | Explicitly free (park, beach, etc.)                                  |
| notes        | TEXT          | Nullable                                                             |
| created_at   | TIMESTAMP     |                                                                      |

Constraints: UNIQUE(track_id, rank)

### Table: annotations

Stop-level annotations. Each belongs to a single stop.

| Column     | Type        | Notes                                                  |
|------------|-------------|--------------------------------------------------------|
| id         | UUID        | Primary key                                            |
| stop_id    | UUID        | FK → stops.id ON DELETE CASCADE, indexed               |
| type       | VARCHAR(20) | `advice` / `caution` / `avoid` / `info`                |
| content    | TEXT        | Required                                               |
| created_at | TIMESTAMP   |                                                        |
| updated_at | TIMESTAMP   | Auto-updated on every PATCH                            |

### Table: itinerary_annotations

Trip-level annotations. Each belongs to a single itinerary (not a stop).
Used for general notes about the trip as a whole.

| Column       | Type        | Notes                                                  |
|--------------|-------------|--------------------------------------------------------|
| id           | UUID        | Primary key                                            |
| itinerary_id | UUID        | FK → itineraries.id ON DELETE CASCADE, indexed         |
| type         | VARCHAR(20) | `advice` / `caution` / `avoid` / `info`                |
| content      | TEXT        | Required                                               |
| created_at   | TIMESTAMP   |                                                        |
| updated_at   | TIMESTAMP   | Auto-updated on every PATCH                            |

### Table: transit_segments

| Column             | Type          | Notes                                                        |
|--------------------|---------------|--------------------------------------------------------------|
| id                 | UUID          | Primary key                                                  |
| itinerary_id       | UUID          | FK → itineraries.id ON DELETE CASCADE, indexed               |
| from_stop_id       | UUID          | FK → stops.id ON DELETE CASCADE                              |
| to_stop_id         | UUID          | FK → stops.id ON DELETE CASCADE                              |
| total_duration_min | INTEGER       | Denormalized sum of legs                                     |
| total_cost         | NUMERIC(10,2) | Denormalized sum of non-free legs                            |
| created_at         | TIMESTAMP     |                                                              |

Constraints: UNIQUE(from_stop_id, to_stop_id), CHECK from_stop_id != to_stop_id

### Table: transport_legs

| Column      | Type          | Notes                                                              |
|-------------|---------------|--------------------------------------------------------------------|
| id          | UUID          | Primary key                                                        |
| segment_id  | UUID          | FK → transit_segments.id ON DELETE CASCADE, indexed                |
| position    | SMALLINT      | 1-based order within the segment                                   |
| mode        | VARCHAR(20)   | walk / bus / tram / metro / train / taxi / uber / bike / ferry / car / airplane |
| line        | VARCHAR(30)   | Nullable — e.g. "Line 9", "AF 123"                                 |
| direction   | TEXT          | Nullable — e.g. "Nation", "CDG T2"                                 |
| duration_min| INTEGER       | Nullable                                                           |
| cost        | NUMERIC(10,2) | Default 0.00                                                       |
| is_free     | BOOLEAN       | Default false                                                      |
| notes       | TEXT          | Nullable                                                           |
| created_at  | TIMESTAMP     |                                                                    |

Constraints: UNIQUE(segment_id, position)

### Table: itinerary_ratings

| Column                | Type          | Notes                                                              |
|-----------------------|---------------|--------------------------------------------------------------------|
| id                    | UUID          | Primary key                                                        |
| itinerary_id          | UUID          | FK → itineraries.id ON DELETE CASCADE, indexed                     |
| user_id               | UUID          | FK → users.id ON DELETE **SET NULL** — GDPR: rating kept anonymized|
| stars                 | SMALLINT      | 1–5 (required — overall score)                                     |
| safety_stars          | SMALLINT      | Nullable, 1–5                                                      |
| experience_stars      | SMALLINT      | Nullable, 1–5                                                      |
| accessibility_stars   | SMALLINT      | Nullable, 1–5                                                      |
| family_friendly_stars | SMALLINT      | Nullable, 1–5                                                      |
| created_at            | TIMESTAMP     |                                                                    |
| updated_at            | TIMESTAMP     |                                                                    |

Constraints: UNIQUE(itinerary_id, user_id)

### Table: itinerary_allowed_users

| Column       | Type      | Notes                                              |
|--------------|-----------|----------------------------------------------------|
| itinerary_id | UUID      | PK + FK → itineraries.id ON DELETE CASCADE         |
| user_id      | UUID      | PK + FK → users.id ON DELETE CASCADE               |
| created_at   | TIMESTAMP |                                                    |

Composite primary key (itinerary_id, user_id).

---

## API Endpoints

### Authentication

| Method | Path           | Auth | Description                 |
|--------|----------------|------|-----------------------------|
| POST   | /auth/register | No   | Create account, returns JWT |
| POST   | /auth/login    | No   | Login, returns JWT          |

### Users

| Method | Path             | Auth | Description                                      |
|--------|------------------|------|--------------------------------------------------|
| GET    | /users/me        | Yes  | Own full profile (includes email)                |
| PATCH  | /users/me        | Yes  | Partial update own profile                       |
| GET    | /users/search    | Yes  | Search by username/display_name (ILIKE)          |
| GET    | /users/{id}      | Yes  | Public profile + follow status                   |
| DELETE | /users/me        | Yes  | Delete own account (GDPR)                        |

### Follows

| Method | Path                                         | Auth | Description                        |
|--------|----------------------------------------------|------|------------------------------------|
| POST   | /users/{id}/follow                           | Yes  | Follow a user (hybrid logic)       |
| DELETE | /users/{id}/follow                           | Yes  | Unfollow or cancel pending request |
| GET    | /users/me/follow-requests                    | Yes  | List incoming pending requests     |
| POST   | /users/me/follow-requests/{id}/accept        | Yes  | Accept a follow request            |
| DELETE | /users/me/follow-requests/{id}               | Yes  | Reject a follow request            |
| GET    | /users/{id}/followers                        | Yes  | List accepted followers            |
| GET    | /users/{id}/following                        | Yes  | List who the user follows          |

### Itineraries

| Method | Path                       | Auth | Description                                        |
|--------|----------------------------|------|----------------------------------------------------|
| POST   | /itineraries/              | Yes  | Create a new itinerary                             |
| GET    | /itineraries/me            | Yes  | List own itineraries                               |
| GET    | /itineraries/{id}          | Yes  | Full detail with stops, annotations, segments      |
| PATCH  | /itineraries/{id}          | Yes  | Update title, description, visibility, etc.        |
| DELETE | /itineraries/{id}          | Yes  | Delete itinerary and all its data                  |
| GET    | /users/{id}/itineraries    | Yes  | List another user's itineraries (visibility-filtered) |

### Cover Image

| Method | Path                       | Auth | Description                                              |
|--------|----------------------------|------|----------------------------------------------------------|
| POST   | /itineraries/{id}/image    | Yes  | Upload cover image (multipart/form-data). Processes via Pillow. |
| DELETE | /itineraries/{id}/image    | Yes  | Delete cover image and clear cover_image_url             |

### Stops

All mutation endpoints require an `If-Match` header matching the itinerary's current ETag. Missing header → 428. Stale header → 412. Successful response includes the new `ETag` header.

| Method | Path                             | Auth | Description                                                       |
|--------|----------------------------------|------|-------------------------------------------------------------------|
| POST   | /itineraries/{id}/stops          | Yes  | Add a stop. `track_id=null` creates a new track; otherwise adds to existing track. Anchors: `after_stop_id`, `before_stop_id`, `after_track_id`, `before_track_id`. |
| PATCH  | /itineraries/{id}/stops/{stopId} | Yes  | Partial update. Optional `track_id` change moves the stop across tracks. |
| DELETE | /itineraries/{id}/stops/{stopId} | Yes  | Delete a stop; deletes its track too if it becomes empty.         |

### Stop Annotations

| Method | Path                                                       | Auth | Description                   |
|--------|------------------------------------------------------------|------|-------------------------------|
| POST   | /itineraries/{id}/stops/{stopId}/annotations               | Yes  | Add annotation to stop        |
| PATCH  | /itineraries/{id}/stops/{stopId}/annotations/{annId}       | Yes  | Update type and/or content    |
| DELETE | /itineraries/{id}/stops/{stopId}/annotations/{annId}       | Yes  | Delete annotation             |

### Itinerary Annotations (trip-level notes)

| Method | Path                                          | Auth | Description                         |
|--------|-----------------------------------------------|------|-------------------------------------|
| POST   | /itineraries/{id}/annotations                 | Yes  | Add trip-level annotation           |
| PATCH  | /itineraries/{id}/annotations/{annId}         | Yes  | Update type and/or content          |
| DELETE | /itineraries/{id}/annotations/{annId}         | Yes  | Delete trip-level annotation        |

### Transit Segments

| Method | Path                                    | Auth | Description                                  |
|--------|-----------------------------------------|------|----------------------------------------------|
| POST   | /itineraries/{id}/segments              | Yes  | Create segment with legs between two stops   |
| GET    | /itineraries/{id}/segments              | Yes  | List all segments (ordered by from_stop position) |
| PATCH  | /itineraries/{id}/segments/{segId}      | Yes  | Replace segment stop refs + full leg list    |
| DELETE | /itineraries/{id}/segments/{segId}      | Yes  | Delete segment and all its legs              |

### Transport Legs

> These endpoints are **not called by the Flutter app**. Flutter uses `PATCH /segments/{id}` (full leg replacement) for all leg changes. These endpoints exist for future API consumers.

| Method | Path                                               | Auth | Description                     |
|--------|----------------------------------------------------|------|---------------------------------|
| POST   | /itineraries/{id}/segments/{segId}/legs            | Yes  | Add leg to a segment            |
| PATCH  | /itineraries/{id}/segments/{segId}/legs/{legId}    | Yes  | Partial update a leg            |
| DELETE | /itineraries/{id}/segments/{segId}/legs/{legId}    | Yes  | Delete a leg                    |

### Ratings

| Method | Path                            | Auth | Description                                                          |
|--------|---------------------------------|------|----------------------------------------------------------------------|
| POST   | /itineraries/{id}/ratings       | Yes  | Submit or update rating (overall required + 4 optional dimensions)   |
| GET    | /itineraries/{id}/ratings       | Yes  | Full ratings page (avg, distribution, rater list per dimension)      |
| GET    | /itineraries/{id}/ratings/me    | Yes  | Own rating (404 if not rated)                                        |
| DELETE | /itineraries/{id}/ratings/me    | Yes  | Delete own rating                                                    |

### Allowlist (restricted visibility)

| Method | Path                                    | Auth | Description                          |
|--------|-----------------------------------------|------|--------------------------------------|
| POST   | /itineraries/{id}/allowed-users         | Yes  | Grant a user access                  |
| GET    | /itineraries/{id}/allowed-users         | Yes  | List users in the allowlist          |
| DELETE | /itineraries/{id}/allowed-users/{userId}| Yes  | Revoke a user's access               |

### Health / Share

| Method | Path          | Auth | Description                        |
|--------|---------------|------|------------------------------------|
| GET    | /             | No   | Returns `{"status":"ok"}`          |
| GET    | /share/i/{id} | No   | Public share landing page (HTML)   |

---

## Key Design Decisions

### Visibility system
Four levels enforced by `can_view_itinerary()` in `services/itinerary_access.py` — single source of truth, never duplicated inline:
- `public` — any authenticated user
- `followers` — owner + accepted followers
- `restricted` — owner + explicit allowlist
- `only_me` — owner only (default)

### Tracks and fractional indexing
Stops are grouped into **tracks**. A track is a column of parallel alternative stops at the same point in the journey (e.g. two hotel options for the same night). Tracks and stops within a track are ordered by `rank` — a lexicographic string key produced by the fractional-indexing algorithm (`services/ordering.py`). Both columns use `TEXT COLLATE "C"` so PostgreSQL sorts by raw byte value, identical to Python's default string comparison. Inserting between two existing items never requires touching other rows — only the new rank needs to be computed.

### ETag / If-Match concurrency control
Every GET on an itinerary returns an `ETag` header equal to the itinerary's `updated_at` ISO string (quoted per RFC 7232). Every mutation (stop, annotation, segment) requires a matching `If-Match` header. Missing → 428. Stale → 412. This prevents silent overwrites when two sessions edit the same itinerary concurrently. Implemented in `app/dependencies.py` via the `require_etag` dependency (SELECT FOR UPDATE).

### Track lifecycle
A track is always non-empty. Creating a stop with `track_id=null` creates a new track + stop atomically. Deleting the last stop in a track also deletes the track. This invariant is enforced in application code (`_delete_track_if_empty`), not by a DB trigger, so it is auditable.

### Rank collision retry
On `IntegrityError` (UNIQUE constraint on rank), the endpoint retries up to 3 times with freshly computed ranks before returning 409. This handles the rare case of two concurrent inserts at the same anchor pair.

### Cover image processing
`services/image_service.py` uses Pillow to: strip all EXIF metadata (privacy / GPS), resize to fit within 1200×630, and JPEG re-encode at 85% quality. This happens synchronously before the file is written via the storage abstraction.

### Denormalized totals
`total_duration_min` and `total_cost` on itineraries, and on transit segments, are recalculated by `_recalculate_totals()` / `_recalculate_segment_totals()` after every stop/leg mutation — never updated directly by callers.

### Multi-dimensional ratings
`stars` (overall) is always required. `safety_stars`, `experience_stars`, `accessibility_stars`, and `family_friendly_stars` are all nullable — `NULL` means the rater didn't score that dimension. Aggregate averages are computed in SQL (`AVG()`), never in Python. Averages are returned as `NULL` (not `0.0`) when count = 0. The Flutter client hides dimension averages when fewer than 3 users have rated that dimension.

### GDPR: rating anonymization
`itinerary_ratings.user_id` is `ON DELETE SET NULL`. When a user deletes their account, their star scores are preserved as anonymous community data. The `RaterInfo` schema handles nullable user fields.

### is_free vs cost=0
Both stops and legs distinguish between *explicitly free* (`is_free=True`) and *cost unknown* (`is_free=False, cost=0.00`). Only non-free rows are summed into totals.

### Two annotation systems
`annotations` (FK: `stop_id`) and `itinerary_annotations` (FK: `itinerary_id`) are separate tables with the same four type values. Stop annotations are shown inline per stop; itinerary annotations are shown in a "Notes" section on the detail screen. Both support PATCH for updating type and/or content.

---

## Follow Logic

```
User A clicks Follow on User B
         │
         ▼
  Does a follow record already exist?  ──YES──► 409 Conflict
         │NO
         ▼
  Is User B private?
   NO ───────────────────────────────────────────────────────┐
         │YES                                                 ▼
         ▼                                    Create Follow{status=accepted}
  Create Follow{status=pending}               A.following_count += 1
  (counters unchanged)                        B.followers_count += 1
         │
  User B reviews request
    ACCEPT → status=accepted, update counters
    REJECT → DELETE record (allows retry)

User A unfollows:
  DELETE Follow record
  If accepted → decrement both counters
  If pending  → counters unchanged

User B switches private → public:
  All pending follows targeting B → status=accepted
  Update counters for each newly accepted follow
```

---

## Local Setup

### Prerequisites
- Python 3.11+
- PostgreSQL running locally

### Steps

```bash
# 1. Enter the backend directory
cd social_api

# 2. Create and activate a virtual environment
python -m venv venv
source venv/bin/activate   # Windows: venv\Scripts\activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Configure environment
cp .env.example .env
# Edit .env — set DATABASE_URL, SECRET_KEY, etc.

# 5. Create the database
createdb ntripi_db

# 6. Run migrations
alembic upgrade head

# 7. Start the dev server
PYTHONPATH=. uvicorn app.main:app --reload
```

API: http://localhost:8000  
Docs: http://localhost:8000/docs

---

## Deployment (Railway)

1. Set environment variables:
   - `DATABASE_URL` — private PostgreSQL URL (`${{Postgres.DATABASE_URL}}`)
   - `SECRET_KEY` — generate with `openssl rand -hex 32`
   - `DEBUG=False`
   - `ALLOWED_ORIGINS=https://ntripi.app`
   - `STORAGE_BACKEND=filesystem`
   - `STORAGE_FILESYSTEM_PATH=/app/uploads`
   - `STORAGE_PUBLIC_URL_PREFIX=/uploads`

2. Persistent volume must be mounted at `/app/uploads` — cover images will be lost on redeploy without it.

3. Build triggered automatically on push to `main` via the repo-root Dockerfile.

---

## Security Notes

- Passwords hashed with bcrypt — plain text never stored or logged.
- Login uses constant-time comparison to prevent timing attacks.
- JWT HS256, 24h expiry, stored in flutter_secure_storage on the client.
- `is_active` is checked on every authenticated request.
- CORS restricted to configured frontend origin in production.
- Self-follow prevented at both application and database level.
- Duplicate follows prevented at both application and database level.
- All mutating itinerary endpoints verify ownership before proceeding.
- EXIF metadata (including GPS coordinates) stripped from all uploaded images.
- Web sessions use `ntripi_session` HTTP-only cookie (Secure when `DEBUG=False`, SameSite=Lax).
