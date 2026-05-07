# Ntripi

A social travel app for sharing itineraries. Plan trips, share them
with friends, and discover routes that locals love.

🌐 **Live at [https://ntripi.app](https://ntripi.app)**

---

## What It Does

- Build travel itineraries with stops, transit segments, costs, and notes
- **Parallel stops**: add up to 3 alternative stops at the same position (e.g. "Hotel A or Hotel B")
- Multi-dimensional community ratings: overall, safety, experience, accessibility, family-friendly
- Four levels of itinerary visibility: public, followers, restricted, only-me
- Share itineraries via URL with rich Open Graph previews on WhatsApp / Twitter / iMessage
- Upload a cover image per itinerary (EXIF-stripped, auto-cropped to 1200×630)
- Annotate stops with advice, cautions, avoid, or info notes
- Itinerary-level notes for trip-wide observations ("book 2 months ahead")
- Hybrid follow system: public accounts auto-accept, private accounts require approval

## Tech Stack

**Backend** — FastAPI · PostgreSQL · SQLAlchemy 2 · Alembic · JWT auth · pytest

**Frontend** — Flutter · Riverpod · Dio · go_router · flutter_map (OpenStreetMap)

**Infrastructure** — Single Dockerfile (multi-stage) · Railway · Cloudflare DNS · Let's Encrypt

## Repo Structure

```
Ntripi/
├── Dockerfile              Multi-stage build for production
├── .dockerignore
├── CLAUDE.md               Conventions for AI assistants
├── README.md               This file
│
├── social_api/             FastAPI backend
│   ├── app/
│   │   ├── main.py         App creation, CORS, router registration
│   │   ├── config.py       Environment config (pydantic-settings)
│   │   ├── database.py     SQLAlchemy engine + session factory
│   │   ├── dependencies.py get_current_user JWT dependency
│   │   ├── models/         SQLAlchemy ORM models
│   │   ├── schemas/        Pydantic request/response schemas
│   │   ├── routers/        API endpoints + web HTML routes
│   │   ├── services/       Business logic (auth, access control, image processing)
│   │   ├── validators/     Username and other field validators
│   │   ├── templates/      Jinja2 HTML for landing pages
│   │   └── static/         Static assets (default OG image, etc.)
│   ├── alembic/            Database migrations
│   ├── test/               Backend tests
│   ├── requirements.txt
│   └── .env.example
│
└── social_flutter/         Flutter app (iOS, Android, Web)
    ├── lib/
    │   ├── main.dart
    │   ├── core/           Routing, API client, shared UI
    │   └── features/       Feature-first organization
    │       ├── auth/
    │       ├── users/
    │       └── itineraries/
    ├── test/
    └── pubspec.yaml
```

## Running Locally

### Prerequisites

| Tool        | Version | Notes                     |
|-------------|---------|---------------------------|
| Python      | 3.11+   |                           |
| PostgreSQL  | 14+     |                           |
| Flutter SDK | 3.3+    |                           |
| Docker      | any     | optional, for prod builds |

### Backend

```bash
cd social_api

# Set up venv
python3 -m venv venv
source venv/bin/activate          # macOS / Linux
# venv\Scripts\activate           # Windows

pip install -r requirements.txt

# Configure environment
cp .env.example .env
# Edit .env with your local DATABASE_URL, SECRET_KEY, etc.

# Create the database and run migrations
createdb ntripi_db
PYTHONPATH=. alembic upgrade head

# Start the server
PYTHONPATH=. uvicorn app.main:app --reload
```

The backend runs on `http://localhost:8000`. Visit `/docs` for Swagger.

### Frontend (against local backend)

```bash
cd social_flutter
flutter pub get

flutter run -d chrome \
  --web-port=5555 \
  --dart-define=API_BASE_URL=http://localhost:8000 \
  --dart-define=SHARE_BASE_URL=http://localhost:8000
```

The pinned port 5555 keeps CORS working consistently.
`scripts/dev.sh` does the same.

> **Android emulator note:** the emulator cannot reach `localhost` on
> the host. Use `http://10.0.2.2:8000` as the API base URL instead
> (the emulator's alias for host localhost).

### Frontend (against production backend)

```bash
cd social_flutter
flutter run -d chrome \
  --web-port=5555 \
  --dart-define=API_BASE_URL=https://ntripi.app \
  --dart-define=SHARE_BASE_URL=https://ntripi.app
```

Or use `scripts/prod.sh`.

## Environment Variables

Create `social_api/.env` from `.env.example`:

```env
# PostgreSQL connection string
DATABASE_URL=postgresql://yourname@localhost:5432/ntripi_db

# JWT signing secret — generate with: openssl rand -hex 32
SECRET_KEY=your-super-secret-key-change-this-in-production

ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=1440

# True in development: allows all CORS origins + verbose errors
DEBUG=True

# Production only: comma-separated allowed CORS origins (used when DEBUG=False)
ALLOWED_ORIGINS=https://ntripi.app

# Base URL used in share link generation
SHARE_BASE_URL=http://localhost:8000

# Android download URL (leave empty until APK is hosted)
ANDROID_DOWNLOAD_URL=

# Storage backend (filesystem or s3-compatible)
STORAGE_BACKEND=filesystem
STORAGE_FILESYSTEM_PATH=/app/uploads
STORAGE_PUBLIC_URL_PREFIX=/uploads
```

## Production Build

```bash
docker build -t ntripi .
docker run --rm -p 8000:8000 \
  -e DATABASE_URL=... \
  -e SECRET_KEY=... \
  ntripi
```

This produces a single image containing the FastAPI backend AND the
compiled Flutter web app served at `/app/`.

## Follow System

Ntripi implements a **hybrid follow model** similar to Instagram:

```
User A clicks Follow on User B
         │
         ▼
  Is User B's account private?
         │
   NO ───┼──────────────────────────────────────────────┐
         │                                              │
  YES    ▼                                              ▼
  status = pending                           status = accepted
  counters NOT updated                       A.following_count += 1
         │                                  B.followers_count += 1
         ▼
  User B reviews the request
         │
    ┌────┴────┐
    │         │
  ACCEPT    REJECT
    │         │
    ▼         ▼
  status =  Record DELETED
  accepted  (allows User A to retry)
  A.following_count += 1
  B.followers_count += 1
```

Key rules:
- Rejecting deletes the record (no "rejected" state) so the requester can try again
- Switching a private account to public auto-accepts all pending requests
- Counters are only incremented when a follow reaches `accepted` status

## Running Tests

### Backend

```bash
cd social_api
source venv/bin/activate
PYTHONPATH=. pytest -v
```

Tests run against an in-memory SQLite database — no PostgreSQL required.

### Flutter

```bash
cd social_flutter
flutter test
```

| File | What it tests |
|------|---------------|
| `test/models/user_test.dart` | `User.fromJson`, `toJson`, `copyWith` |
| `test/models/follow_test.dart` | `Follow`, `FollowRequestItem`, `FollowerListItem` |
| `test/repositories/auth_repository_test.dart` | `register`, `login`, `logout` |
| `test/repositories/follow_repository_test.dart` | `followUser`, `unfollowUser`, `getFollowers`, `getFollowing`, etc. |

HTTP calls are intercepted by `http_mock_adapter`. Secure storage is
replaced by an in-memory stub via `FlutterSecureStorage.setMockInitialValues({})`.

## Security Notes

- **Passwords** are hashed with bcrypt (cost factor 12). Plain text is never stored or logged.
- **Timing attack prevention** — bcrypt is called against a dummy hash even when the email doesn't exist, so response time can't reveal whether an account is registered.
- **JWT tokens** are signed with HS256, expire after 24 hours (configurable), and stored in the device's secure enclave (iOS Keychain / Android Keystore).
- **401 auto-logout** — the Dio interceptor clears the stored token and redirects to `/login` on any 401 response.
- **CORS** is restricted to configured origins in production (`DEBUG=False`).
- **EXIF stripping** — all uploaded cover images have EXIF metadata (including GPS) removed before storage.
- **Private by default** — new accounts are private (`is_private = true`).

## Deployment

Deploys to Railway on push to `main`. Railway detects the Dockerfile
at the repo root and runs the multi-stage build. Cloudflare provides
DNS, proxy, and DDoS protection. SSL via Let's Encrypt (auto-managed
by Railway). HTTPS is enforced at the TLD level (`.app` is on the
HSTS preload list).

A persistent volume must be mounted at `/app/uploads` on Railway
or uploaded cover images will be lost on redeploy.

## Status

Active development. Production is live and stable.

- ✓ Authentication with JWT cookies + tokens
- ✓ User profiles, follows, blocks
- ✓ Itineraries with stops (including parallel alternatives), transit segments, annotations
- ✓ Itinerary-level notes (trip-wide annotations)
- ✓ Cover image upload with EXIF stripping and auto-crop
- ✓ Multi-dimensional ratings (overall, safety, experience, accessibility, family-friendly)
- ✓ Visibility system (public, followers, restricted, only-me)
- ✓ Share landing pages with Open Graph previews
- ✓ Marketing homepage at apex domain
- ✓ Flutter web app at `/app/`

Upcoming: posts feature, real-time feed, native app store distribution.

## Architecture Notes

For development conventions and architectural rules that all
contributors (human and AI) must follow, see [CLAUDE.md](./CLAUDE.md).

## License

Personal project — not currently open source.

## Author

Ismail Karroud · [github.com/IsmailKARROUD](https://github.com/IsmailKARROUD)
