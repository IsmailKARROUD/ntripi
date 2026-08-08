"""
Tests for Terms of Service acceptance on every account-creation path, and for
the re-acceptance gate that catches accounts stamped with an older revision.

The Google path is the one that was broken: GoogleAuthRequest.tos_accepted
defaulted True, so an account could be created without the user ever having
been shown, let alone having agreed to, anything.
"""

from fastapi.testclient import TestClient
from sqlalchemy import select

from app.constants.tos import TOS_VERSION
from app.models.user import User
from conftest import (
    TestingSessionLocal,
    auth_headers,
    patch_google_verifier,
    register_user,
)


def _google(client: TestClient, body: dict):
    return client.post("/auth/google", json=body)


def _find_user(email: str) -> User | None:
    db = TestingSessionLocal()
    try:
        return db.execute(
            select(User).where(User.email == email)
        ).scalar_one_or_none()
    finally:
        db.close()


def _set_tos_version(email: str, version: str | None) -> None:
    """Rewind a user's accepted revision — what a real ToS bump looks like."""
    db = TestingSessionLocal()
    try:
        user = db.execute(select(User).where(User.email == email)).scalar_one()
        user.tos_accepted_version = version
        user.tos_accepted_at = None
        db.commit()
    finally:
        db.close()


class TestGoogleSignupRequiresAcceptance:
    def test_new_account_without_the_flag_is_refused(self, client, monkeypatch):
        patch_google_verifier(monkeypatch, sub="g-new", email="new@x.com")

        r = _google(client, {"id_token": "fake"})

        assert r.status_code == 400
        assert r.json()["code"] == "tos_required"

    def test_refusal_creates_no_account(self, client, monkeypatch):
        patch_google_verifier(monkeypatch, sub="g-new", email="new@x.com")

        _google(client, {"id_token": "fake"})

        assert _find_user("new@x.com") is None

    def test_accepting_then_retrying_the_same_token_succeeds(
        self, client, monkeypatch
    ):
        # The client's flow: 400 → show the consent sheet → re-post the same
        # ID token with the flag set. Verification is stateless, so the token
        # is still good.
        patch_google_verifier(monkeypatch, sub="g-new", email="new@x.com")
        assert _google(client, {"id_token": "fake"}).status_code == 400

        r = _google(client, {"id_token": "fake", "tos_accepted": True, "date_of_birth": "2000-01-01"})

        assert r.status_code == 200
        user = _find_user("new@x.com")
        assert user.tos_accepted_version == TOS_VERSION
        assert user.tos_accepted_at is not None

    def test_existing_account_signs_in_without_the_flag(self, client, monkeypatch):
        # Returning users must never be re-prompted at sign-in — only the
        # create-a-new-account branch consults tos_accepted.
        patch_google_verifier(monkeypatch, sub="g-back", email="back@x.com")
        assert _google(
            client, {"id_token": "fake", "tos_accepted": True, "date_of_birth": "2000-01-01"}
        ).status_code == 200

        r = _google(client, {"id_token": "fake"})

        assert r.status_code == 200

    def test_linking_google_to_a_password_account_needs_no_flag(
        self, client, monkeypatch
    ):
        register_user(client, "linker", "linker@x.com")
        patch_google_verifier(monkeypatch, sub="g-link", email="linker@x.com")

        r = _google(client, {"id_token": "fake"})

        assert r.status_code == 200


class TestPasswordSignupRequiresAcceptance:
    def test_false_is_refused_with_a_stable_code(self, client):
        r = client.post("/auth/register", json={
            "username": "refused", "email": "refused@x.com",
            "password": "test1234", "tos_accepted": False,
            "date_of_birth": "2000-01-01",
        })

        assert r.status_code == 400
        assert r.json()["code"] == "tos_required"

    def test_acceptance_records_the_current_revision(self, client):
        register_user(client, "accepter", "accepter@x.com")

        assert _find_user("accepter@x.com").tos_accepted_version == TOS_VERSION


class TestReacceptanceGate:
    def test_fresh_signup_is_already_current(self, client):
        token = register_user(client, "fresh", "fresh@x.com")["access_token"]

        me = client.get("/users/me", headers=auth_headers(token)).json()

        assert me["tos_current"] is True

    def test_an_older_revision_is_not_current(self, client):
        token = register_user(client, "stale", "stale@x.com")["access_token"]
        _set_tos_version("stale@x.com", "1.0")

        me = client.get("/users/me", headers=auth_headers(token)).json()

        assert me["tos_current"] is False

    def test_a_never_stamped_account_is_not_current(self, client):
        # Accounts that predate the column read NULL, not an old version.
        token = register_user(client, "nulled", "nulled@x.com")["access_token"]
        _set_tos_version("nulled@x.com", None)

        me = client.get("/users/me", headers=auth_headers(token)).json()

        assert me["tos_current"] is False

    def test_accepting_clears_the_gate(self, client):
        token = register_user(client, "gated", "gated@x.com")["access_token"]
        _set_tos_version("gated@x.com", "1.0")

        r = client.post("/auth/accept-tos", headers=auth_headers(token))

        assert r.status_code == 200
        assert r.json()["tos_current"] is True
        user = _find_user("gated@x.com")
        assert user.tos_accepted_version == TOS_VERSION
        assert user.tos_accepted_at is not None

    def test_acceptance_requires_authentication(self, client):
        assert client.post("/auth/accept-tos").status_code == 403

    def test_the_version_recorded_is_the_servers_not_the_clients(self, client):
        # A client must not be able to claim acceptance of a revision it never
        # rendered. The body carries a date of birth and nothing else — any
        # `version` in it is ignored outright.
        token = register_user(client, "liar", "liar@x.com")["access_token"]
        _set_tos_version("liar@x.com", "1.0")

        client.post(
            "/auth/accept-tos",
            headers=auth_headers(token),
            json={"version": "99.0"},
        )

        assert _find_user("liar@x.com").tos_accepted_version == TOS_VERSION
