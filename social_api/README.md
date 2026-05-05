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
│   │   ├── stop.py                    ← stops table
│   │   ├── annotation.py              ← annotations table (per stop)
│   │   ├── transit_segment.py         ← transit_segments table
│   │   ├── transport_leg.py           ← transport_legs table
│   │   ├── itinerary_rating.py        ← itinerary_ratings table
│   │   └── itinerary_allowed_user.py  ← itinerary_allowed_users table
│   ├── schemas/
│   │   ├── auth.py          ← Register/Login request + Token response
│   │   ├── user.py          ← User profile schemas
│   │   ├── follow.py        ← Follow response + request list schemas
│   │   └── itinerary.py     ← All itinerary/stop/segment/leg/rating schemas
│   ├── routers/
│   │   ├── auth.py          ← POST /auth/register, POST /auth/login
│   │   ├── users.py         ← GET/PATCH /users/me, search, public profile
│   │   ├── follows.py       ← All follow/unfollow endpoints
│   │   └── itineraries.py   ← All itinerary, stop, segment, leg, rating endpoints
│   └── services/
│       ├── auth.py               ← bcrypt hashing + JWT create/decode
│       └── itinerary_access.py   ← Visibility logic + rating recalculation
├── alembic/
│   ├── env.py               ← Alembic config (reads DATABASE_URL from settings)
│   └── versions/            ← Generated migration scripts go here
├── alembic.ini              ← Alembic CLI config
├── requirements.txt
├── .env.example
├── Procfile                 ← Railway/Render deployment
└── README.md
```

---

## Database Schema

### Table: users

| Column          | Type         | Notes                                              |
|-----------------|--------------|----------------------------------------------------|
| id              | UUID         | Primary key, auto-generated                        |
| username        | VARCHAR(30)  | Unique, indexed, lowercase/digits/underscores only |
| email           | VARCHAR(255) | Unique, indexed                                    |
| password_hash   | VARCHAR(255) | bcrypt hash only — plain password never stored     |
| display_name    | VARCHAR(100) | Nullable                                           |
| bio             | TEXT         | Nullable                                           |
| avatar_url      | TEXT         | Nullable                                           |
| is_private      | BOOLEAN      | Default false — drives follow flow                 |
| followers_count | INTEGER      | Denormalized counter, default 0                    |
| following_count | INTEGER      | Denormalized counter, default 0                    |
| is_active       | BOOLEAN      | Default true — soft delete/suspension flag         |
| created_at      | TIMESTAMP    | Auto-set on insert                                 |
| updated_at      | TIMESTAMP    | Auto-updated on every change                       |

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

| Column            | Type          | Notes                                                     |
|-------------------|---------------|-----------------------------------------------------------|
| id                | UUID          | Primary key                                               |
| user_id           | UUID          | FK → users.id ON DELETE CASCADE, indexed                  |
| title             | VARCHAR(200)  |                                                           |
| description       | TEXT          | Nullable                                                  |
| cover_image_url   | TEXT          | Nullable                                                  |
| total_duration_min| INTEGER       | Denormalized sum of stops + segments. Recalculated server-side |
| total_cost        | NUMERIC(10,2) | Denormalized sum of stops + segments. Recalculated server-side |
| currency          | VARCHAR(3)    | ISO 4217 code, default `EUR`                              |
| safety_rating     | SMALLINT      | Nullable, 1–5 (owner's own rating of the route)           |
| rating_avg        | NUMERIC(3,2)  | Denormalized community average. Recalculated after every rating |
| rating_count      | INTEGER       | Denormalized count of community ratings                   |
| visibility        | VARCHAR(20)   | `public` / `followers` / `restricted` / `only_me`        |
| created_at        | TIMESTAMP     |                                                           |
| updated_at        | TIMESTAMP     |                                                           |

### Table: stops

> **Stop role (origin / waypoint / arrival) is not stored here.** Flutter derives it
> from sorted position at read time: first stop = origin, last = arrival, rest = waypoint.

| Column       | Type          | Notes                                                            |
|--------------|---------------|------------------------------------------------------------------|
| id           | UUID          | Primary key                                                      |
| itinerary_id | UUID          | FK → itineraries.id ON DELETE CASCADE, indexed                   |
| position     | SMALLINT      | 1-based order within the itinerary                               |
| place_name   | VARCHAR(200)  | Nullable                                                         |
| place_address| TEXT          | Nullable                                                         |
| lat          | NUMERIC(9,6)  | Nullable — ~11cm precision                                       |
| lng          | NUMERIC(9,6)  | Nullable                                                         |
| place_type   | VARCHAR(50)   | Nullable — restaurant/cafe/museum/hotel/park/station/airport/beach/landmark/other |
| duration_min | INTEGER       | Nullable — time spent at this stop                               |
| cost         | NUMERIC(10,2) | Default 0.00                                                     |
| is_free      | BOOLEAN       | Explicitly free (park, beach, etc.)                              |
| notes        | TEXT          | Nullable                                                         |
| created_at   | TIMESTAMP     |                                                                  |

Constraints: UNIQUE(itinerary_id, position)

### Table: annotations

| Column     | Type        | Notes                                                  |
|------------|-------------|--------------------------------------------------------|
| id         | UUID        | Primary key                                            |
| stop_id    | UUID        | FK → stops.id ON DELETE CASCADE, indexed               |
| type       | VARCHAR(20) | `advice` / `caution` / `avoid` / `info`                |
| content    | TEXT        | Required                                               |
| created_at | TIMESTAMP   |                                                        |

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

| Column       | Type      | Notes                                                                 |
|--------------|-----------|-----------------------------------------------------------------------|
| id           | UUID      | Primary key                                                           |
| itinerary_id | UUID      | FK → itineraries.id ON DELETE CASCADE, indexed                        |
| user_id      | UUID      | FK → users.id ON DELETE **SET NULL** — GDPR: rating kept anonymized   |
| stars        | SMALLINT  | 1–5                                                                   |
| created_at   | TIMESTAMP |                                                                       |
| updated_at   | TIMESTAMP |                                                                       |

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

### Stops

| Method | Path                                   | Auth | Description                              |
|--------|----------------------------------------|------|------------------------------------------|
| POST   | /itineraries/{id}/stops                | Yes  | Add a stop (inserts at position, shifts others up) |
| PATCH  | /itineraries/{id}/stops/reorder        | Yes  | Reorder all stops by providing ordered ID list |
| PATCH  | /itineraries/{id}/stops/{stopId}       | Yes  | Partial update a stop                    |
| DELETE | /itineraries/{id}/stops/{stopId}       | Yes  | Delete a stop and its annotations        |

### Annotations

| Method | Path                                                   | Auth | Description             |
|--------|--------------------------------------------------------|------|-------------------------|
| POST   | /itineraries/{id}/stops/{stopId}/annotations           | Yes  | Add annotation to stop  |
| DELETE | /itineraries/{id}/stops/{stopId}/annotations/{annId}   | Yes  | Delete annotation       |

### Transit Segments

| Method | Path                                    | Auth | Description                                  |
|--------|-----------------------------------------|------|----------------------------------------------|
| POST   | /itineraries/{id}/segments              | Yes  | Create segment with legs between two stops   |
| GET    | /itineraries/{id}/segments              | Yes  | List all segments (ordered by from_stop position) |
| PATCH  | /itineraries/{id}/segments/{segId}      | Yes  | Replace segment stop refs + full leg list    |
| DELETE | /itineraries/{id}/segments/{segId}      | Yes  | Delete segment and all its legs              |

### Transport Legs

> These endpoints are **not called by the Flutter app**. Flutter uses `PATCH /segments/{id}` (full leg replacement) for all leg changes. These endpoints are available for future API consumers (web client, third-party integrations).

| Method | Path                                               | Auth | Description                     |
|--------|----------------------------------------------------|------|---------------------------------|
| POST   | /itineraries/{id}/segments/{segId}/legs            | Yes  | Add leg to a segment            |
| PATCH  | /itineraries/{id}/segments/{segId}/legs/{legId}    | Yes  | Partial update a leg            |
| DELETE | /itineraries/{id}/segments/{segId}/legs/{legId}    | Yes  | Delete a leg                    |

### Ratings

| Method | Path                            | Auth | Description                               |
|--------|---------------------------------|------|-------------------------------------------|
| POST   | /itineraries/{id}/ratings       | Yes  | Submit or update a 1–5 star rating        |
| GET    | /itineraries/{id}/ratings       | Yes  | Full ratings page (avg, distribution, list) |
| GET    | /itineraries/{id}/ratings/me    | Yes  | Own rating (404 if not rated)             |
| DELETE | /itineraries/{id}/ratings/me    | Yes  | Delete own rating                         |

### Allowlist (restricted visibility)

| Method | Path                                    | Auth | Description                          |
|--------|-----------------------------------------|------|--------------------------------------|
| POST   | /itineraries/{id}/allowed-users         | Yes  | Grant a user access                  |
| GET    | /itineraries/{id}/allowed-users         | Yes  | List users in the allowlist          |
| DELETE | /itineraries/{id}/allowed-users/{userId}| Yes  | Revoke a user's access               |

### Health

| Method | Path | Auth | Description               |
|--------|------|------|---------------------------|
| GET    | /    | No   | Returns `{"status":"ok"}` |

---

## Key Design Decisions

### Visibility system
Four levels enforced by `can_view_itinerary()` in `services/itinerary_access.py` — the single source of truth, never duplicated inline:
- `public` — any authenticated user
- `followers` — owner + accepted followers
- `restricted` — owner + explicit allowlist
- `only_me` — owner only (default)

### Denormalized totals
`total_duration_min` and `total_cost` on itineraries, and `total_duration_min` / `total_cost` on transit segments are computed aggregates. They are recalculated by `_recalculate_totals()` / `_recalculate_segment_totals()` after every stop/leg mutation — never updated directly by callers.

### Two-phase position shifting
Inserting a stop at an occupied position uses a two-phase UPDATE to avoid UNIQUE(itinerary_id, position) violations:
1. Park conflicting stops at high temporary positions (offset = max + 1)
2. Write the final 1-based positions

The same pattern is used in the reorder endpoint.

### GDPR: rating anonymization
`itinerary_ratings.user_id` is `ON DELETE SET NULL`. When a user deletes their account, their star scores are preserved as anonymous community data (ratings are not personal data once detached from an identity). The `RaterInfo` schema handles nullable user fields.

### is_free vs cost=0
Both stops and legs distinguish between *explicitly free* (`is_free=True`) and *cost unknown* (`is_free=False, cost=0.00`). Only non-free rows are summed into totals.

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
uvicorn app.main:app --reload
```

API: http://localhost:8000  
Docs: http://localhost:8000/docs

---

## Deployment (Railway / Render)

1. Set environment variables in the platform dashboard:
   - `DATABASE_URL` — managed PostgreSQL URL
   - `SECRET_KEY` — generate with `openssl rand -hex 32`
   - `DEBUG=False`
   - `ALLOWED_ORIGINS=https://your-frontend-domain.com`

2. `Procfile` starts the server:
   ```
   web: uvicorn app.main:app --host 0.0.0.0 --port $PORT
   ```

3. Release command (runs before each deploy):
   ```
   alembic upgrade head
   ```

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
