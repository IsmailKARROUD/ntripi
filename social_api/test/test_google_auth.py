"""
test_google_auth.py — Tests for "Sign in with Google" + the verified-email gate.

We never call Google: verify_google_id_token is monkeypatched to return canned
claims. It's imported into app.routers.auth via `from ... import`, so we patch
the name on that module.
"""

import conftest
from conftest import register_user, auth_headers, mark_email_verified
from sqlalchemy import select

from app.models.user import User


def _patch_google(monkeypatch, *, sub, email, email_verified=True,
                  name=None, picture=None):
    """Patch the verifier to return the given claims for any id_token."""
    import app.routers.auth as auth_router
    monkeypatch.setattr(
        auth_router,
        "verify_google_id_token",
        lambda token: {
            "sub": sub,
            "email": email,
            "email_verified": email_verified,
            "name": name,
            "picture": picture,
        },
    )


def _google(client, tos_accepted=True):
    return client.post(
        "/auth/google", json={"id_token": "fake", "tos_accepted": tos_accepted}
    )


def _get_user(email: str) -> User:
    db = conftest.TestingSessionLocal()
    try:
        return db.execute(
            select(User).where(User.email == email.strip().lower())
        ).scalar_one()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Sign-up / sign-in
# ---------------------------------------------------------------------------

def test_new_google_user_is_created_verified(client, monkeypatch):
    _patch_google(monkeypatch, sub="g-1", email="New.User@gmail.com",
                  name="New User", picture="https://lh3.example/p.png")
    r = _google(client)
    assert r.status_code == 200, r.json()
    body = r.json()
    assert body["access_token"] and body["refresh_token"]
    assert body["user_id"] and body["username"]

    user = _get_user("new.user@gmail.com")
    assert user.google_sub == "g-1"
    assert user.email_verified is True
    assert user.password_hash is None          # Google-only account, no password
    assert user.display_name == "New User"
    assert user.avatar_url == "https://lh3.example/p.png"
    assert user.username.lower() == "new.user"  # derived from the email local-part


def test_repeat_google_signin_returns_same_user(client, monkeypatch):
    _patch_google(monkeypatch, sub="g-2", email="repeat@gmail.com")
    first = _google(client).json()
    second = _google(client).json()
    assert first["user_id"] == second["user_id"]

    # No duplicate row.
    db = conftest.TestingSessionLocal()
    try:
        count = len(db.execute(
            select(User).where(User.email == "repeat@gmail.com")
        ).scalars().all())
    finally:
        db.close()
    assert count == 1


def test_missing_email_in_claims_returns_400(client, monkeypatch):
    _patch_google(monkeypatch, sub="g-noemail", email="")
    r = _google(client)
    assert r.status_code == 400


def test_invalid_token_returns_401(client, monkeypatch):
    import app.routers.auth as auth_router

    def _raise(token):
        raise ValueError("bad signature")

    monkeypatch.setattr(auth_router, "verify_google_id_token", _raise)
    r = _google(client)
    assert r.status_code == 401


# ---------------------------------------------------------------------------
# Account linking
# ---------------------------------------------------------------------------

def test_links_to_existing_password_account_when_verified(client, monkeypatch):
    # Unverified password account first.
    existing = register_user(client, "linkme", "link@example.com", verified=False)

    _patch_google(monkeypatch, sub="g-link", email="link@example.com",
                  email_verified=True, name="Linked")
    r = _google(client)
    assert r.status_code == 200, r.json()
    assert r.json()["user_id"] == existing["user_id"]  # same account, not a new one

    user = _get_user("link@example.com")
    assert user.google_sub == "g-link"
    assert user.email_verified is True
    assert user.password_hash is not None  # password kept — both methods work

    # Password login still works after linking.
    login = client.post("/auth/login",
                        json={"identifier": "link@example.com", "password": "test1234"})
    assert login.status_code == 200


def test_unverified_google_email_does_not_claim_existing_account(client, monkeypatch):
    register_user(client, "owner", "owned@example.com", verified=False)
    _patch_google(monkeypatch, sub="g-evil", email="owned@example.com",
                  email_verified=False)
    r = _google(client)
    assert r.status_code == 409

    user = _get_user("owned@example.com")
    assert user.google_sub is None  # not linked


# ---------------------------------------------------------------------------
# Username generation
# ---------------------------------------------------------------------------

def test_username_collision_gets_suffix(client, monkeypatch):
    register_user(client, "john", "john@other.com")  # occupies username "john"
    _patch_google(monkeypatch, sub="g-john", email="john@gmail.com")
    r = _google(client)
    assert r.status_code == 200
    assert r.json()["username"] != "john"
    assert r.json()["username"].startswith("john")


# ---------------------------------------------------------------------------
# Password login against a Google-only account
# ---------------------------------------------------------------------------

def test_password_login_against_google_only_account_fails(client, monkeypatch):
    _patch_google(monkeypatch, sub="g-only", email="googleonly@gmail.com")
    _google(client)  # creates a Google-only account (no password)

    r = client.post("/auth/login",
                    json={"identifier": "googleonly@gmail.com", "password": "whatever1"})
    assert r.status_code == 401  # must not reveal it's a Google account


# ---------------------------------------------------------------------------
# Verified-email gate
# ---------------------------------------------------------------------------

def test_unverified_user_blocked_from_creating_itinerary(client):
    u = register_user(client, "newbie", "newbie@example.com", verified=False)
    r = client.post("/itineraries/", json={"title": "Trip", "visibility": "public"},
                    headers=auth_headers(u["access_token"]))
    assert r.status_code == 403


def test_unverified_user_blocked_from_following(client):
    a = register_user(client, "follower", "f@example.com", verified=False)
    b = register_user(client, "followee", "fe@example.com")
    r = client.post(f"/users/{b['user_id']}/follow", headers=auth_headers(a["access_token"]))
    assert r.status_code == 403


def test_verifying_via_google_unlocks_gated_actions(client, monkeypatch):
    u = register_user(client, "upgrader", "up@example.com", verified=False)
    # Blocked before verification.
    blocked = client.post("/itineraries/", json={"title": "Trip", "visibility": "public"},
                          headers=auth_headers(u["access_token"]))
    assert blocked.status_code == 403

    # Verify by signing in with Google on the same email (links + verifies).
    _patch_google(monkeypatch, sub="g-up", email="up@example.com", email_verified=True)
    g = _google(client)
    assert g.status_code == 200
    new_token = g.json()["access_token"]

    ok = client.post("/itineraries/", json={"title": "Trip", "visibility": "public"},
                     headers=auth_headers(new_token))
    assert ok.status_code == 201


def test_open_actions_work_while_unverified(client):
    u = register_user(client, "browser", "browser@example.com", verified=False)
    headers = auth_headers(u["access_token"])

    # Reading own profile is open and reports the unverified status.
    me = client.get("/users/me", headers=headers)
    assert me.status_code == 200
    assert me.json()["email_verified"] is False

    # Editing own profile is not gated.
    patch = client.patch("/users/me", json={"display_name": "Just Browsing"}, headers=headers)
    assert patch.status_code == 200
