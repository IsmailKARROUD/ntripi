"""
conftest.py — Pytest configuration and shared fixtures.

This file is special: pytest automatically discovers and loads it before
running any tests. Everything defined here is available to all test files
without needing to import it explicitly.

Architecture of the test setup:

  Real FastAPI app
       ↓
  TestClient (httpx)         ← makes HTTP requests in-memory (no network)
       ↓
  SQLAlchemy ORM
       ↓
  SQLite in-memory database  ← isolated, fast, destroyed after each test

Why SQLite instead of PostgreSQL for tests?
  - SQLite runs entirely in RAM, so each test run is fast (< 1 second setup).
  - Each test gets a completely fresh database — no data leaks between tests.
  - No PostgreSQL server required to run tests in CI/CD.
  - The downside: SQLite doesn't support every PostgreSQL feature. If you
    ever use PostgreSQL-specific types (like JSONB or ARRAY), you'd need to
    run tests against a real PostgreSQL instance. For now, SQLite is perfect.

Why 'function' scope for fixtures?
  Fixtures with scope='function' (the default) are created fresh for each
  individual test function. This means every test starts with an empty
  database and a clean state — tests can't interfere with each other.
"""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.main import app

# ---------------------------------------------------------------------------
# Database setup
# ---------------------------------------------------------------------------

# SQLite in-memory database URL.
# 'check_same_thread=False' is required for SQLite when used with FastAPI
# because requests may be handled on different threads.
SQLITE_URL = "sqlite://"

# StaticPool ensures all connections share the same in-memory database.
# Without this, each connection would get its own isolated SQLite instance,
# and your tables would appear to be empty after creation.
engine = create_engine(
    SQLITE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)


# SQLite does not enforce foreign key constraints by default.
# This event listener enables FK enforcement (including ON DELETE CASCADE)
# for every connection, matching PostgreSQL's behaviour in production.
@event.listens_for(engine, "connect")
def set_sqlite_pragma(dbapi_connection, connection_record):
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()

TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def override_get_db():
    """
    A replacement for the real get_db() dependency.
    FastAPI's dependency injection system lets us swap this in during tests
    so the app uses our SQLite test database instead of the real PostgreSQL.
    """
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def reset_rate_limiter():
    """Reset slowapi's in-memory storage before each test.

    Without this, rate limit counters accumulate across the test session.
    All TestClient requests share the same IP (testserver), so the 5/hour
    register limit is exhausted after just a few tests, causing unrelated
    tests to receive 429 instead of 201/200.
    """
    from app.limiter import limiter
    limiter._storage.reset()
    yield


@pytest.fixture(autouse=True)
def no_outbound_email(monkeypatch):
    """Stub the email backend for every test.

    The local .env points EMAIL_BACKEND at Resend with a live API key, so any
    flow that sends mail (registration, moderation warnings, appeal outcomes)
    would otherwise fire real HTTP requests during the suite. Tests that assert
    on email content patch their own module-level reference on top of this.
    """
    monkeypatch.setattr(
        "app.services.email_service.send_email",
        lambda to, subject, html: None,
    )
    yield


@pytest.fixture()
def client():
    """
    The main test fixture — provides a TestClient connected to a fresh database.

    The sequence is:
    1. Create all tables in the SQLite in-memory database.
    2. Override FastAPI's get_db dependency to use the test database.
    3. Yield the TestClient for the test to use.
    4. After the test completes, drop all tables and restore the original dependency.

    This 'setup → yield → teardown' pattern is the standard pytest fixture structure.
    Everything before yield runs before the test; everything after yield is cleanup.
    """
    # Create all tables fresh for this test
    Base.metadata.create_all(bind=engine)

    # Override the database dependency
    app.dependency_overrides[get_db] = override_get_db

    # Use ntripi.app as the base URL so the Host header matches ALLOWED_HOSTS
    # and TrustedHostMiddleware does not reject all test requests.
    with TestClient(app, base_url="http://ntripi.app") as test_client:
        yield test_client

    # Teardown: drop all tables so the next test starts clean
    Base.metadata.drop_all(bind=engine)

    # Restore original dependency
    app.dependency_overrides.clear()


# ---------------------------------------------------------------------------
# Helper factories — reusable functions for creating test data
# ---------------------------------------------------------------------------

# Comfortably over MINIMUM_AGE and not a boundary, so a test that is not about
# the age gate never trips it. test_age_gate.py builds its own dates relative to
# date.today() — a fixed literal there would start failing in 2042.
ADULT_DOB = "2000-01-01"


def register_user(client: TestClient, username: str, email: str,
                  password: str = "test1234", display_name: str | None = None,
                  verified: bool = True, date_of_birth: str = ADULT_DOB) -> dict:
    """
    Registers a user and returns the full response body as a dict.
    This includes the access_token, user_id, and username.

    Having this as a helper avoids repeating the same register code
    across dozens of tests — if the register endpoint changes, you
    only need to update this one function.

    `verified` (default True): password signups are unverified in production
    (high-value actions require verifying via Google — see require_verified_email).
    Most tests want a fully-capable account, so we flip email_verified directly
    in the DB by default. Pass verified=False to exercise the gate itself.
    """
    response = client.post("/auth/register", json={
        "username": username,
        "email": email,
        "password": password,
        "display_name": display_name,
        "tos_accepted": True,
        "date_of_birth": date_of_birth,
    })
    assert response.status_code == 201, (
        f"Registration failed for {username}: {response.json()}"
    )
    if verified:
        mark_email_verified(email)
    return response.json()


def mark_email_verified(email: str) -> None:
    """Flip a user's email_verified flag directly in the test DB (no Google
    round-trip), so gated high-value endpoints accept the account."""
    from sqlalchemy import select
    from app.models.user import User

    db = TestingSessionLocal()
    try:
        user = db.execute(
            select(User).where(User.email == email.strip().lower())
        ).scalar_one()
        user.email_verified = True
        db.commit()
    finally:
        db.close()


def patch_google_verifier(monkeypatch, *, sub, email="gina@x.com") -> None:
    """Patch verify_google_id_token on BOTH router modules — each imported it
    via `from ... import`, so the name must be patched on each importing module
    (auth for /auth/google sign-in, users for DELETE re-auth)."""
    import app.routers.auth as auth_router
    import app.routers.users as users_router

    def _claims(token):
        return {"sub": sub, "email": email, "email_verified": True,
                "name": None, "picture": None}

    monkeypatch.setattr(auth_router, "verify_google_id_token", _claims)
    monkeypatch.setattr(users_router, "verify_google_id_token", _claims)


def auth_headers(token: str) -> dict:
    """
    Returns the Authorization header dict that the TestClient needs
    to make authenticated requests. This mirrors exactly what the
    Flutter app will send on every protected request.
    """
    return {"Authorization": f"Bearer {token}"}


# ---------------------------------------------------------------------------
# Admin dashboard helpers
# ---------------------------------------------------------------------------

# The HTTP Basic credentials the admin_enabled fixture installs.
ADMIN_BASIC = ("ops_admin", "basic-pass-1234")


@pytest.fixture()
def admin_enabled(monkeypatch):
    """Turn the /admin dashboard on for a test.

    With either credential unset the whole router 404s (feature off), so every
    admin test needs this. Mutating the cached Settings singleton is the same
    approach the moderation tests use.
    """
    from app.config import get_settings

    settings = get_settings()
    monkeypatch.setattr(settings, "ADMIN_BASIC_USERNAME", ADMIN_BASIC[0])
    monkeypatch.setattr(settings, "ADMIN_BASIC_PASSWORD", ADMIN_BASIC[1])
    return ADMIN_BASIC


def make_admin(email: str) -> None:
    """Grant admin rights directly in the test DB — production does this with a
    manual SQL UPDATE; there is deliberately no API to promote a user."""
    from sqlalchemy import select
    from app.models.user import User

    db = TestingSessionLocal()
    try:
        user = db.execute(
            select(User).where(User.email == email.strip().lower())
        ).scalar_one()
        user.is_admin = True
        db.commit()
    finally:
        db.close()


def admin_session(client: TestClient, identifier: str, password: str = "test1234") -> str:
    """Sign in at /admin/login and attach the session cookie to the client.

    The cookie is read out of the Set-Cookie header and set on the jar
    explicitly: when DEBUG is False it carries Secure, and httpx will not
    replay a Secure cookie over the http:// test base URL.
    """
    from app.routers.admin import ADMIN_COOKIE

    response = client.post(
        "/admin/login",
        data={"identifier": identifier, "password": password},
        auth=ADMIN_BASIC,
        follow_redirects=False,
    )
    assert response.status_code == 303, response.text
    raw = response.headers["set-cookie"]
    token = raw.split(f"{ADMIN_COOKIE}=", 1)[1].split(";", 1)[0]
    client.cookies.set(ADMIN_COOKIE, token)
    return token


# ---------------------------------------------------------------------------
# Collaborative-editing helpers
# ---------------------------------------------------------------------------

def acquire_edit_lock(client: TestClient, itinerary_id: str, headers: dict,
                      *, takeover: bool = False) -> str:
    """Claim the edit lock and return the raw token.

    Every itinerary-content mutation requires one, so any test that writes to an
    itinerary starts here. `takeover=True` is needed to displace an existing
    claim — including the caller's own claim from another "device".
    """
    response = client.post(
        f"/itineraries/{itinerary_id}/lock",
        json={"takeover": takeover}, headers=headers,
    )
    assert response.status_code == 200, response.text
    return response.json()["token"]


def edit_headers(headers: dict, etag: str, token: str) -> dict:
    """Auth + the two preconditions every content mutation carries."""
    return {**headers, "If-Match": etag, "X-Edit-Lock": token}


def locked_headers(client: TestClient, itinerary_id: str, headers: dict,
                   etag: str) -> dict:
    """Auth + If-Match + a freshly claimed X-Edit-Lock, in one call.

    For the many tests that mutate an itinerary while testing something else
    entirely. It claims with takeover=True so repeated calls — and calls from a
    second account — just work, rather than making every unrelated test thread
    a token through its own helpers. Claiming does not touch updated_at, so an
    ETag captured beforehand stays valid.

    Tests that are ABOUT the lock use acquire_edit_lock and hold their token:
    that is the whole point there.
    """
    token = acquire_edit_lock(client, itinerary_id, headers, takeover=True)
    return edit_headers(headers, etag, token)


def edit_now(client: TestClient, itinerary_id: str, headers: dict) -> dict:
    """locked_headers, but it fetches the current ETag for you too.

    For tests that only need to write something on the way to testing something
    else. Anything actually exercising If-Match must hold its own ETag — reading
    a fresh one here is exactly what those tests must not do.
    """
    response = client.get(f"/itineraries/{itinerary_id}", headers=headers)
    assert response.status_code == 200, response.text
    return locked_headers(client, itinerary_id, headers, response.headers["etag"])


def backdate_lock_heartbeat(itinerary_id: str, seconds: int) -> None:
    """Age a claim by `seconds`, straight through the DB.

    There is no way to make a claim go stale through the API, and sleeping for
    five minutes is not a test. Mirrors _age_report in test_moderation_sweep.py.
    """
    import uuid as _uuid
    from datetime import datetime, timedelta, timezone
    from app.models.itinerary_edit_lock import ItineraryEditLock

    db = TestingSessionLocal()
    try:
        lock = db.get(ItineraryEditLock, _uuid.UUID(itinerary_id))
        assert lock is not None, "no edit lock to backdate"
        lock.last_heartbeat_at = (
            datetime.now(timezone.utc) - timedelta(seconds=seconds)
        )
        db.commit()
    finally:
        db.close()


def etag_from_updated_at(updated_at_iso: str) -> str:
    """
    Derive the wire ETag the server emits for a given `updated_at`.

    The concurrency ETag is just the quoted ISO datetime; the server's
    `_normalize_etag` collapses `Z` ↔ `+00:00` so either form works. We
    return the form the server actually emits (Python's `isoformat()`,
    which uses `+00:00`) so tests can also compare to response headers.
    """
    from types import SimpleNamespace
    from datetime import datetime
    from app.dependencies import _etag_value

    ts = datetime.fromisoformat(updated_at_iso.replace("Z", "+00:00"))
    return _etag_value(SimpleNamespace(updated_at=ts))
