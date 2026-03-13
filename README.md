# Ntripi — Social Media App

A full-stack social media application with a **FastAPI** backend and a **Flutter** frontend.

> **Version:** 0.1 — covers authentication, user profiles, and a hybrid follow system (public / private accounts).

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Tech Stack](#tech-stack)
3. [Project Structure](#project-structure)
4. [Architecture Overview](#architecture-overview)
5. [Quick Start](#quick-start)
   - [Prerequisites](#prerequisites)
   - [1. Start the Backend](#1-start-the-backend)
   - [2. Start the Flutter App](#2-start-the-flutter-app)
6. [Environment Variables](#environment-variables)
7. [API Reference](#api-reference)
8. [Follow System](#follow-system)
9. [Database Schema](#database-schema)
10. [Security Notes](#security-notes)

---

## Project Overview

Ntripi is a social platform where users can:

- Register and log in with email + password
- View and edit their own profile (display name, bio, avatar, privacy)
- Search for other users by username or display name
- Follow / unfollow other users
- Switch between **public** accounts (follows are accepted instantly) and **private** accounts (follows require approval)
- Manage incoming follow requests (accept / reject)

---

## Tech Stack

### Backend (`social_api/`)

| Layer       | Technology                                  |
|-------------|---------------------------------------------|
| Framework   | FastAPI 0.135                               |
| Database    | PostgreSQL (via SQLAlchemy 2.0)             |
| Migrations  | Alembic                                     |
| Auth        | JWT (HS256) via `python-jose` + bcrypt      |
| Validation  | Pydantic v2 + pydantic-settings             |
| Server      | Uvicorn (ASGI)                              |

### Frontend (`social_flutter/`)

| Layer            | Technology                             |
|------------------|----------------------------------------|
| Framework        | Flutter (Dart SDK ≥ 3.3)              |
| State management | Riverpod 2 (AsyncNotifier)             |
| HTTP client      | Dio 5 (with auth interceptor)          |
| Navigation       | go_router 13                           |
| Secure storage   | flutter_secure_storage (Keychain / Keystore) |

---

## Project Structure

```
Ntripi/
├── social_api/                  ← FastAPI backend
│   ├── app/
│   │   ├── main.py              ← App creation, CORS, router registration
│   │   ├── config.py            ← Environment config (pydantic-settings)
│   │   ├── database.py          ← SQLAlchemy engine + session factory
│   │   ├── dependencies.py      ← get_current_user JWT dependency
│   │   ├── models/
│   │   │   ├── user.py          ← users table ORM model
│   │   │   └── follow.py        ← follows table ORM model
│   │   ├── schemas/
│   │   │   ├── auth.py          ← Register/Login/Token Pydantic schemas
│   │   │   ├── user.py          ← User profile schemas
│   │   │   └── follow.py        ← Follow response schemas
│   │   ├── routers/
│   │   │   ├── auth.py          ← POST /auth/register, POST /auth/login
│   │   │   ├── users.py         ← GET/PATCH /users/me, search, public profile
│   │   │   └── follows.py       ← Follow/unfollow + request management
│   │   └── services/
│   │       └── auth.py          ← bcrypt hashing + JWT create/decode
│   ├── alembic/                 ← Database migration scripts
│   ├── alembic.ini
│   ├── requirements.txt
│   ├── .env.example
│   └── README.md                ← Detailed backend docs
│
└── social_flutter/              ← Flutter frontend
    └── lib/
        ├── main.dart            ← App entry point
        ├── core/
        │   ├── api/
        │   │   ├── api_client.dart      ← Dio client + AuthInterceptor
        │   │   └── api_endpoints.dart   ← All URL constants
        │   ├── router/
        │   │   └── app_router.dart      ← go_router + auth guard + ShellRoute
        │   └── storage/
        │       └── secure_storage.dart  ← JWT token read/write/delete
        ├── shared/
        │   ├── models/
        │   │   ├── user.dart            ← User Dart model
        │   │   └── follow.dart          ← Follow + FollowRequestItem models
        │   └── widgets/
        │       ├── follow_button.dart   ← 3-state Follow/Following/Requested button
        │       └── user_avatar.dart     ← Circular avatar with placeholder
        └── features/
            ├── auth/                    ← Login & Register screens + providers
            ├── profile/                 ← My Profile + User Profile screens
            ├── search/                  ← Search screen + debounced provider
            └── follows/                 ← Follow Requests screen + provider
```

---

## Architecture Overview

```
Flutter App
    │
    │  HTTP (Dio + Bearer token)
    ▼
FastAPI Backend
    │
    ├── JWT validation (every protected route)
    │
    ├── Pydantic validation (request bodies)
    │
    └── SQLAlchemy ORM
            │
            ▼
        PostgreSQL
```

**State management pattern (Flutter):**
- Each feature has a `Repository` (HTTP calls) and a `Notifier` (Riverpod state).
- Screens `watch` providers — they rebuild automatically when state changes.
- Optimistic UI updates are applied locally; the server is the source of truth on refresh.

---

## Quick Start

### Prerequisites

| Tool            | Version    | Install                              |
|-----------------|------------|--------------------------------------|
| Python          | 3.11+      | https://python.org                   |
| PostgreSQL      | 13+        | https://postgresql.org               |
| Flutter SDK     | 3.3+       | https://flutter.dev/docs/get-started |
| Dart SDK        | 3.3+       | Bundled with Flutter                 |

---

### 1. Start the Backend

```bash
# Navigate to the backend directory
cd social_api

# Create a virtual environment
python -m venv venv

# Activate it
source venv/bin/activate          # macOS / Linux
# venv\Scripts\activate           # Windows

# Install dependencies
pip install -r requirements.txt

# Set up environment variables
cp .env.example .env
# Open .env and set DATABASE_URL and SECRET_KEY (see Environment Variables below)

# Create the PostgreSQL database
createdb ntripi_db

# Run database migrations (creates the tables)
alembic upgrade head

# Start the development server
uvicorn app.main:app --reload
```

The API is now running at:
- **Base URL:** `http://localhost:8000`
- **Interactive docs (Swagger):** `http://localhost:8000/docs`
- **Alternative docs (ReDoc):** `http://localhost:8000/redoc`
- **Health check:** `http://localhost:8000/`

> **Tip:** `--reload` automatically restarts the server when you save a file. Remove it in production.

---

### 2. Start the Flutter App

```bash
# Navigate to the Flutter directory
cd social_flutter

# Install Flutter dependencies
flutter pub get

# Check your connected devices
flutter devices

# Run on a device / emulator
flutter run

# Or target a specific platform
flutter run -d chrome        # Web browser
flutter run -d macos         # macOS desktop
flutter run -d ios           # iOS simulator
flutter run -d android       # Android emulator
```

> **Android emulator note:** The emulator cannot reach `localhost` on the host machine.
> Open `lib/core/api/api_endpoints.dart` and change:
> ```dart
> const kApiBaseUrl = 'http://10.0.2.2:8000'; // Android emulator alias for host localhost
> ```

> **iOS simulator / macOS:** `http://localhost:8000` works as-is.

---

## Environment Variables

Create `social_api/.env` (copy from `.env.example`):

```env
# PostgreSQL connection URL
# Format: postgresql://user:password@host:port/dbname
DATABASE_URL=postgresql://postgres:password@localhost:5432/ntripi_db

# JWT signing secret — generate a strong one with:
#   openssl rand -hex 32
SECRET_KEY=your-super-secret-key-change-this-in-production

# JWT algorithm — HS256 is standard for a single-service setup
ALGORITHM=HS256

# Token expiry in minutes (1440 = 24 hours)
ACCESS_TOKEN_EXPIRE_MINUTES=1440

# Set True in development — allows all CORS origins and enables verbose errors
DEBUG=True

# Production only: the frontend domain allowed to make cross-origin requests
# Only used when DEBUG=False
ALLOWED_ORIGINS=https://your-frontend-domain.com
```

---

## API Reference

All protected routes require the header:
```
Authorization: Bearer <access_token>
```

### Authentication

| Method | Endpoint         | Auth | Description                              |
|--------|------------------|------|------------------------------------------|
| POST   | `/auth/register` | No   | Create account → returns JWT + user info |
| POST   | `/auth/login`    | No   | Login → returns JWT + user info          |

**Register / Login response:**
```json
{
  "access_token": "eyJ...",
  "token_type": "bearer",
  "user_id": "uuid-string",
  "username": "john_doe"
}
```

---

### Users

| Method | Endpoint             | Auth | Description                                        |
|--------|----------------------|------|----------------------------------------------------|
| GET    | `/users/me`          | Yes  | Own full profile (includes email)                  |
| PATCH  | `/users/me`          | Yes  | Partial update (display_name, bio, avatar, privacy)|
| GET    | `/users/search?q=`   | Yes  | Search users by username or display name           |
| GET    | `/users/{user_id}`   | Yes  | Public profile + follow status                     |

---

### Follows

| Method | Endpoint                                         | Auth | Description                          |
|--------|--------------------------------------------------|------|--------------------------------------|
| POST   | `/users/{user_id}/follow`                        | Yes  | Follow a user (hybrid logic)         |
| DELETE | `/users/{user_id}/follow`                        | Yes  | Unfollow or cancel pending request   |
| GET    | `/users/me/follow-requests`                      | Yes  | List my incoming pending requests    |
| POST   | `/users/me/follow-requests/{follow_id}/accept`   | Yes  | Accept a follow request              |
| DELETE | `/users/me/follow-requests/{follow_id}`          | Yes  | Reject a follow request              |
| GET    | `/users/{user_id}/followers`                     | Yes  | List accepted followers              |
| GET    | `/users/{user_id}/following`                     | Yes  | List who the user follows            |

---

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

**Key rules:**
- Rejecting a request **deletes** the record (no "rejected" state) so the requester can try again.
- Switching a private account to **public** automatically accepts all pending requests.
- `followers_count` and `following_count` are only updated when a follow reaches `accepted` status.
- Unfollowing an accepted follow decrements both counters. Cancelling a pending request does not.

---

## Database Schema

### `users`

| Column          | Type         | Notes                                         |
|-----------------|--------------|-----------------------------------------------|
| id              | UUID         | Primary key, auto-generated                   |
| username        | VARCHAR(30)  | Unique · indexed · `[a-z0-9_]` only           |
| email           | VARCHAR(255) | Unique · indexed                              |
| password_hash   | VARCHAR(255) | bcrypt hash only — plain password never stored|
| display_name    | VARCHAR(100) | Nullable                                      |
| bio             | TEXT         | Nullable                                      |
| avatar_url      | TEXT         | Nullable                                      |
| is_private      | BOOLEAN      | Default false                                 |
| followers_count | INTEGER      | Denormalized counter (default 0)              |
| following_count | INTEGER      | Denormalized counter (default 0)              |
| is_active       | BOOLEAN      | Default true — soft delete / suspension flag  |
| created_at      | TIMESTAMPTZ  | Set on insert                                 |
| updated_at      | TIMESTAMPTZ  | Auto-updated on every change                  |

### `follows`

| Column      | Type        | Notes                                   |
|-------------|-------------|-----------------------------------------|
| id          | UUID        | Primary key                             |
| follower_id | UUID        | FK → users.id · ON DELETE CASCADE       |
| following_id| UUID        | FK → users.id · ON DELETE CASCADE       |
| status      | ENUM        | `pending` or `accepted`                 |
| created_at  | TIMESTAMPTZ | Set on insert                           |
| updated_at  | TIMESTAMPTZ | Auto-updated on every change            |

**Constraints:**
- `UNIQUE(follower_id, following_id)` — prevents duplicate follow records
- `CHECK(follower_id != following_id)` — prevents self-follows

---

## Security Notes

- **Passwords** are hashed with bcrypt (cost factor 12). The plain-text password is never stored or logged.
- **Login timing attack** — even when the email does not exist, bcrypt is called against a dummy hash so response time is identical whether the email or password is wrong.
- **JWT tokens** are signed with HS256, expire after 24 hours (configurable), and are stored in the device's secure storage (iOS Keychain / Android Keystore).
- **401 auto-logout** — the Dio interceptor clears the stored token and redirects to `/login` on any 401 response.
- **Follow request ownership** — accept/reject endpoints verify the `following_id` equals the current user, returning 404 (not 403) to avoid leaking other users' request IDs.
- **CORS** is restricted to the configured frontend domain in production (`DEBUG=False`).
