# Ntripi API — Backend

FastAPI + PostgreSQL backend for the Ntripi social media application.

## Project Structure

```
social_api/
├── app/
│   ├── main.py              ← FastAPI app, CORS, router registration
│   ├── config.py            ← pydantic-settings config (reads .env)
│   ├── database.py          ← SQLAlchemy engine + session factory
│   ├── dependencies.py      ← get_current_user (JWT auth dependency)
│   ├── models/
│   │   ├── user.py          ← users table ORM model
│   │   └── follow.py        ← follows table ORM model + FollowStatus enum
│   ├── schemas/
│   │   ├── auth.py          ← Register/Login request + Token response
│   │   ├── user.py          ← User profile schemas (public/private/update)
│   │   └── follow.py        ← Follow response + request list schemas
│   ├── routers/
│   │   ├── auth.py          ← POST /auth/register, POST /auth/login
│   │   ├── users.py         ← GET/PATCH /users/me, GET /users/search, GET /users/{id}
│   │   └── follows.py       ← All follow/unfollow endpoints
│   └── services/
│       └── auth.py          ← bcrypt hashing + JWT create/decode
├── alembic/
│   ├── env.py               ← Alembic config (reads DATABASE_URL from settings)
│   └── versions/            ← Generated migration scripts go here
├── alembic.ini              ← Alembic CLI config
├── requirements.txt
├── .env.example
├── Procfile                 ← Railway/Render deployment
└── README.md
```

## Database Schema

### Table: users

| Column           | Type         | Notes                                              |
|------------------|--------------|----------------------------------------------------|
| id               | UUID         | Primary key, auto-generated                        |
| username         | VARCHAR(30)  | Unique, indexed, lowercase/digits/underscores only |
| email            | VARCHAR(255) | Unique, indexed                                    |
| password_hash    | VARCHAR(255) | bcrypt hash only — plain password never stored     |
| display_name     | VARCHAR(100) | Nullable                                           |
| bio              | TEXT         | Nullable                                           |
| avatar_url       | TEXT         | Nullable                                           |
| is_private       | BOOLEAN      | Default False — drives entire follow flow          |
| followers_count  | INTEGER      | Denormalized counter, default 0                    |
| following_count  | INTEGER      | Denormalized counter, default 0                    |
| is_active        | BOOLEAN      | Default True — soft delete/suspension flag         |
| created_at       | TIMESTAMP    | Auto-set on insert                                 |
| updated_at       | TIMESTAMP    | Auto-updated on every change                       |

### Table: follows

| Column       | Type     | Notes                                             |
|--------------|----------|---------------------------------------------------|
| id           | UUID     | Primary key                                       |
| follower_id  | UUID     | FK → users.id, ON DELETE CASCADE                  |
| following_id | UUID     | FK → users.id, ON DELETE CASCADE                  |
| status       | ENUM     | 'pending' or 'accepted'                           |
| created_at   | TIMESTAMP| Auto-set on insert                                |
| updated_at   | TIMESTAMP| Auto-updated on every change                      |

Constraints:
- UNIQUE (follower_id, following_id) — no duplicate follows
- CHECK follower_id != following_id — no self-follows

## Follow Logic Flowchart

```
User A clicks Follow on User B
         │
         ▼
  Does a follow record already exist?
         │
    YES ─┼─► 409 Conflict
         │
    NO   ▼
  Is User B private?
         │
   NO ───┼──────────────────────────────────────────────────────────────┐
         │                                                              │
  YES    ▼                                                              ▼
  Create Follow{status=pending}                           Create Follow{status=accepted}
  (do NOT update counters)                                A.following_count += 1
         │                                                B.followers_count += 1
         │                                                              │
         ▼                                                              ▼
  User B reviews request                                   ✓ Follow complete
         │
    ┌────┴────┐
    │         │
  ACCEPT    REJECT
    │         │
    ▼         ▼
  status=   DELETE record
  accepted  (allows retry)
  A.following_count += 1
  B.followers_count += 1


User A unfollows User B:
  DELETE the Follow record
  If status was 'accepted' → decrement both counters
  If status was 'pending'  → counters unchanged (were never incremented)

User B switches private → public:
  All pending follows targeting B → status=accepted
  Update counters for each newly accepted follower
```

## API Endpoints

### Authentication

| Method | Path            | Auth | Description                          |
|--------|-----------------|------|--------------------------------------|
| POST   | /auth/register  | No   | Create account, returns JWT          |
| POST   | /auth/login     | No   | Login, returns JWT                   |

### Users

| Method | Path              | Auth | Description                                     |
|--------|-------------------|------|-------------------------------------------------|
| GET    | /users/me         | Yes  | Own full profile (includes email)               |
| PATCH  | /users/me         | Yes  | Partial update own profile                      |
| GET    | /users/search     | Yes  | Search by username/display_name (ILIKE)         |
| GET    | /users/{user_id}  | Yes  | Public profile + is_following, follow_is_pending|

### Follows

| Method | Path                                          | Auth | Description                        |
|--------|-----------------------------------------------|------|------------------------------------|
| POST   | /users/{user_id}/follow                       | Yes  | Follow a user (hybrid logic)       |
| DELETE | /users/{user_id}/follow                       | Yes  | Unfollow or cancel pending request |
| GET    | /users/me/follow-requests                     | Yes  | List incoming pending requests     |
| POST   | /users/me/follow-requests/{follow_id}/accept  | Yes  | Accept a follow request            |
| DELETE | /users/me/follow-requests/{follow_id}         | Yes  | Reject a follow request            |
| GET    | /users/{user_id}/followers                    | Yes  | List accepted followers            |
| GET    | /users/{user_id}/following                    | Yes  | List who the user follows          |

### Health

| Method | Path | Auth | Description                |
|--------|------|------|----------------------------|
| GET    | /    | No   | Returns {"status": "ok"}  |

## Local Setup

### Prerequisites
- Python 3.11+
- PostgreSQL running locally
- `pip` or a virtual environment tool

### Steps

```bash
# 1. Clone the repo and enter the backend directory
cd social_api

# 2. Create and activate a virtual environment
python -m venv venv
source venv/bin/activate   # Windows: venv\Scripts\activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Configure environment
cp .env.example .env
# Edit .env and set DATABASE_URL, SECRET_KEY, etc.

# 5. Create the database (if it doesn't exist)
createdb ntripi_db

# 6. Run database migrations
alembic revision --autogenerate -m "initial schema"
alembic upgrade head

# 7. Start the development server
uvicorn app.main:app --reload
```

The API will be available at http://localhost:8000
Interactive docs: http://localhost:8000/docs

## Deployment (Railway / Render)

1. Set environment variables in the platform dashboard:
   - `DATABASE_URL` (the managed PostgreSQL URL)
   - `SECRET_KEY` (generate with `openssl rand -hex 32`)
   - `DEBUG=False`
   - `ALLOWED_ORIGINS=https://your-frontend-domain.com`

2. The `Procfile` tells the platform how to start the app:
   ```
   web: uvicorn app.main:app --host 0.0.0.0 --port $PORT
   ```

3. Run migrations as a release command (Railway: Settings → Deploy → Release Command):
   ```
   alembic upgrade head
   ```

## Security Notes

- Passwords are hashed with bcrypt (never stored in plain text).
- Login uses constant-time comparison to prevent timing attacks.
- JWT tokens are signed with HS256 and expire after 24 hours (configurable).
- The `is_active` flag is checked on every authenticated request.
- CORS is restricted to the configured frontend domain in production.
- Self-follow is prevented at both the application and database level.
- Duplicate follows are prevented at both the application and database level.
