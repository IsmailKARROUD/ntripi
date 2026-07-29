"""
test_account_deletion.py — Tests for ToS acceptance, account deletion,
cascade integrity, and rating anonymization.

Three test classes:
  TestRegistrationToS   — ToS enforcement on register + GET /tos endpoint
  TestAccountDeletion   — full deletion flow, wrong password, token invalidation
  TestDeleteCascades    — follow counter integrity, itinerary cascade, allowlists
"""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

from conftest import auth_headers, mark_email_verified, patch_google_verifier


# ---------------------------------------------------------------------------
# Helper — register with ToS (new default)
# ---------------------------------------------------------------------------

def register(client, username, email, password="test1234", tos_accepted=True):
    r = client.post("/auth/register", json={
        "username": username,
        "email": email,
        "password": password,
        "tos_accepted": tos_accepted,
    })
    return r


def register_ok(client, username, email, password="test1234"):
    r = register(client, username, email, password)
    assert r.status_code == 201, r.json()
    # Verify the email so gated high-value actions (create itinerary, follow) work.
    mark_email_verified(email)
    return r.json()


def delete_account(client, token, password):
    # TestClient.delete() does not accept json= in this starlette version;
    # use client.request() instead.
    return client.request(
        "DELETE",
        "/users/me",
        json={"password": password},
        headers=auth_headers(token),
    )


def create_itinerary(client, token, title="Trip", visibility="public"):
    r = client.post(
        "/itineraries/",
        json={"title": title, "visibility": visibility},
        headers=auth_headers(token),
    )
    assert r.status_code == 201, r.json()
    return r.json()


def add_stop(client, token, itinerary_id):
    r = client.post(
        f"/itineraries/{itinerary_id}/stops",
        json={"position": 1, "type": "origin"},
        headers=auth_headers(token),
    )
    assert r.status_code == 201, r.json()
    return r.json()


def follow(client, token, user_id):
    r = client.post(
        f"/users/{user_id}/follow",
        headers=auth_headers(token),
    )
    assert r.status_code in (200, 201), r.json()
    return r.json()


def rate(client, token, itinerary_id, stars):
    r = client.post(
        f"/itineraries/{itinerary_id}/ratings",
        json={"stars": stars},
        headers=auth_headers(token),
    )
    assert r.status_code == 201, r.json()
    return r.json()


# ---------------------------------------------------------------------------
# Class: TestRegistrationToS
# ---------------------------------------------------------------------------

class TestRegistrationToS:
    def test_register_without_tos_fails(self, client):
        r = register(client, "alice", "alice@x.com", tos_accepted=False)
        assert r.status_code == 400
        assert "Terms of Service" in r.json()["detail"]

    def test_register_with_tos_succeeds(self, client):
        r = register(client, "alice", "alice@x.com", tos_accepted=True)
        assert r.status_code == 201
        data = r.json()
        assert "access_token" in data

    def test_tos_endpoint_returns_text(self, client):
        r = client.get("/auth/tos")
        assert r.status_code == 200
        body = r.json()
        assert "version" in body
        assert "date" in body
        assert "summary" in body
        assert len(body["summary"]) > 10


# ---------------------------------------------------------------------------
# Class: TestAccountDeletion
# ---------------------------------------------------------------------------

class TestAccountDeletion:
    def test_delete_account_requires_correct_password(self, client):
        alice = register_ok(client, "alice", "alice@x.com")
        r = delete_account(client, alice["access_token"], "wrongpass9")
        assert r.status_code == 401

    def test_delete_account_succeeds_with_correct_password(self, client):
        alice = register_ok(client, "alice", "alice@x.com")
        r = delete_account(client, alice["access_token"], "test1234")
        assert r.status_code == 204

        # Token is now invalid — get_current_user raises 401.
        r2 = client.get("/users/me", headers=auth_headers(alice["access_token"]))
        assert r2.status_code == 401

    def test_delete_account_removes_user_data(self, client):
        alice = register_ok(client, "alice", "alice@x.com")
        bob = register_ok(client, "bob1", "bob@x.com")

        it = create_itinerary(client, alice["access_token"])
        # Alice follows Bob (public account — accepted immediately)
        client.patch(
            "/users/me",
            json={"is_private": False},
            headers=auth_headers(bob["access_token"]),
        )
        follow(client, alice["access_token"], bob["user_id"])

        delete_account(client, alice["access_token"], "test1234")

        # Alice's itinerary is gone (Bob can't see it either)
        r = client.get(
            f"/itineraries/{it['id']}",
            headers=auth_headers(bob["access_token"]),
        )
        assert r.status_code == 404

    def test_delete_account_anonymizes_ratings_not_deletes(self, client):
        alice = register_ok(client, "alice", "alice@x.com")
        bob = register_ok(client, "bob1", "bob@x.com")

        it = create_itinerary(client, alice["access_token"])
        rate(client, bob["access_token"], it["id"], 4)

        delete_account(client, bob["access_token"], "test1234")

        # Itinerary still has the rating — just anonymous now.
        r = client.get(
            f"/itineraries/{it['id']}",
            headers=auth_headers(alice["access_token"]),
        )
        assert r.status_code == 200
        body = r.json()
        assert body["rating_count"] == 1
        assert abs(body["rating_avg"] - 4.0) < 0.01

    def test_rating_avg_unchanged_after_rater_deletes_account(self, client):
        alice = register_ok(client, "alice", "alice@x.com")
        bob = register_ok(client, "bob1", "bob@x.com")
        charlie = register_ok(client, "charlie", "charlie@x.com")

        it = create_itinerary(client, alice["access_token"])
        rate(client, bob["access_token"], it["id"], 5)
        rate(client, charlie["access_token"], it["id"], 3)

        # Confirm avg = 4.0 before deletion
        r = client.get(
            f"/itineraries/{it['id']}",
            headers=auth_headers(alice["access_token"]),
        )
        assert abs(r.json()["rating_avg"] - 4.0) < 0.01

        delete_account(client, bob["access_token"], "test1234")

        # Avg and count unchanged — Bob's score was preserved anonymously.
        r2 = client.get(
            f"/itineraries/{it['id']}",
            headers=auth_headers(alice["access_token"]),
        )
        body = r2.json()
        assert body["rating_count"] == 2
        assert abs(body["rating_avg"] - 4.0) < 0.01

    def test_deleted_user_cannot_login(self, client):
        alice = register_ok(client, "alice", "alice@x.com")
        delete_account(client, alice["access_token"], "test1234")

        r = client.post("/auth/login", json={
            "identifier": "alice@x.com",
            "password": "test1234",
        })
        assert r.status_code == 401

    def test_deleted_user_token_is_invalid(self, client):
        alice = register_ok(client, "alice", "alice@x.com")
        token = alice["access_token"]
        delete_account(client, token, "test1234")

        r = client.get("/users/me", headers=auth_headers(token))
        assert r.status_code == 401


# ---------------------------------------------------------------------------
# Class: TestDeleteCascades
# ---------------------------------------------------------------------------

class TestDeleteCascades:
    def test_delete_removes_itineraries_and_stops(self, client):
        alice = register_ok(client, "alice", "alice@x.com")
        it = create_itinerary(client, alice["access_token"])
        for i in range(1, 4):
            client.post(
                f"/itineraries/{it['id']}/stops",
                json={"position": i, "type": "waypoint"},
                headers=auth_headers(alice["access_token"]),
            )

        delete_account(client, alice["access_token"], "test1234")

        # Re-register under a different name to get a token to query with
        bob = register_ok(client, "bob1", "bob@x.com")
        r = client.get(
            f"/itineraries/{it['id']}",
            headers=auth_headers(bob["access_token"]),
        )
        assert r.status_code == 404

    def test_delete_removes_follow_relationships(self, client):
        alice = register_ok(client, "alice", "alice@x.com")
        bob = register_ok(client, "bob1", "bob@x.com")

        # Both accounts need to be public for auto-accept
        client.patch("/users/me", json={"is_private": False},
                     headers=auth_headers(alice["access_token"]))
        client.patch("/users/me", json={"is_private": False},
                     headers=auth_headers(bob["access_token"]))

        follow(client, alice["access_token"], bob["user_id"])
        follow(client, bob["access_token"], alice["user_id"])

        # Verify counts before
        bob_before = client.get("/users/me",
                                headers=auth_headers(bob["access_token"])).json()
        assert bob_before["followers_count"] == 1
        assert bob_before["following_count"] == 1

        delete_account(client, alice["access_token"], "test1234")

        # Bob should have 0 followers and 0 following now
        bob_after = client.get("/users/me",
                               headers=auth_headers(bob["access_token"])).json()
        assert bob_after["followers_count"] == 0
        assert bob_after["following_count"] == 0

    def test_delete_removes_from_allowlists(self, client):
        alice = register_ok(client, "alice", "alice@x.com")
        bob = register_ok(client, "bob1", "bob@x.com")

        it = create_itinerary(client, alice["access_token"], visibility="restricted")
        client.post(
            f"/itineraries/{it['id']}/allowed-users",
            json={"user_id": bob["user_id"]},
            headers=auth_headers(alice["access_token"]),
        )

        # Alice deletes her account — itinerary and its allowlist rows cascade
        delete_account(client, alice["access_token"], "test1234")

        # Bob can no longer access the itinerary
        r = client.get(
            f"/itineraries/{it['id']}",
            headers=auth_headers(bob["access_token"]),
        )
        assert r.status_code == 404


# ---------------------------------------------------------------------------
# Class: TestGoogleAccountDeletion — passwordless (SSO) accounts re-auth with
# their provider instead of a password. Google is the only provider today.
# ---------------------------------------------------------------------------

def google_signin(client, sub="g-1", email="gina@x.com"):
    r = client.post(
        "/auth/google", json={"id_token": "fake", "tos_accepted": True}
    )
    assert r.status_code == 200, r.json()
    return r.json()


def delete_account_google(client, token, id_token="fake"):
    return client.request(
        "DELETE", "/users/me",
        json={"google_id_token": id_token},
        headers=auth_headers(token),
    )


class TestGoogleAccountDeletion:
    def test_google_user_deletes_with_matching_token(self, client, monkeypatch):
        patch_google_verifier(monkeypatch, sub="g-1")
        gina = google_signin(client, sub="g-1")
        token = gina["access_token"]

        r = delete_account_google(client, token)
        assert r.status_code == 204, r.text

        # Token is now invalid — the user row is gone.
        assert client.get("/users/me", headers=auth_headers(token)).status_code == 401

    def test_google_delete_rejects_mismatched_sub(self, client, monkeypatch):
        patch_google_verifier(monkeypatch, sub="g-1")
        token = google_signin(client, sub="g-1")["access_token"]

        # The re-auth token belongs to a DIFFERENT Google account.
        import app.routers.users as users_router
        monkeypatch.setattr(
            users_router, "verify_google_id_token",
            lambda t: {"sub": "someone-else"},
        )
        r = delete_account_google(client, token)
        assert r.status_code == 401
        assert r.json()["code"] == "google_account_mismatch"

    def test_google_delete_requires_a_token(self, client, monkeypatch):
        patch_google_verifier(monkeypatch, sub="g-1")
        token = google_signin(client, sub="g-1")["access_token"]

        r = client.request("DELETE", "/users/me", json={},
                           headers=auth_headers(token))
        assert r.status_code == 401
        assert r.json()["code"] == "google_reauth_required"

    def test_google_delete_rejects_invalid_token(self, client, monkeypatch):
        patch_google_verifier(monkeypatch, sub="g-1")
        token = google_signin(client, sub="g-1")["access_token"]

        # Verifier raises → any verification failure is a clean 401 (not a 500).
        import app.routers.users as users_router

        def _raise(t):
            raise ValueError("bad signature")

        monkeypatch.setattr(users_router, "verify_google_id_token", _raise)
        r = delete_account_google(client, token)
        assert r.status_code == 401
        assert r.json()["code"] == "google_token_invalid"

    def test_google_user_sending_password_gets_401_not_500(self, client, monkeypatch):
        # Regression for the original bug: a passwordless account hitting the
        # password branch used to crash with 500 (verify_password(None)).
        # It must now fail cleanly, asking for Google re-auth instead.
        patch_google_verifier(monkeypatch, sub="g-1")
        token = google_signin(client, sub="g-1")["access_token"]

        r = client.request("DELETE", "/users/me",
                           json={"password": "anything"},
                           headers=auth_headers(token))
        assert r.status_code == 401
        assert r.json()["code"] == "google_reauth_required"


# ---------------------------------------------------------------------------
# Class: TestDualMethodDeletion — an account with BOTH a password and a linked
# Google login (a password user who signed in with Google on the same verified
# email). Either credential must be accepted for deletion.
# ---------------------------------------------------------------------------

def link_google(client, monkeypatch, email, sub="g-dual"):
    """Sign in with Google on an EXISTING verified email → links google_sub and
    keeps password_hash, producing a dual-method account. Returns its token."""
    patch_google_verifier(monkeypatch, sub=sub, email=email)
    r = client.post("/auth/google", json={"id_token": "fake", "tos_accepted": True})
    assert r.status_code == 200, r.json()
    return r.json()["access_token"]


class TestDualMethodDeletion:
    def test_dual_method_deletes_with_password(self, client, monkeypatch):
        register_ok(client, "alice", "alice@x.com")
        token = link_google(client, monkeypatch, "alice@x.com")

        r = delete_account(client, token, "test1234")
        assert r.status_code == 204, r.text
        assert client.get("/users/me", headers=auth_headers(token)).status_code == 401

    def test_dual_method_deletes_with_google_token(self, client, monkeypatch):
        register_ok(client, "alice", "alice@x.com")
        token = link_google(client, monkeypatch, "alice@x.com", sub="g-dual")

        # Verifier still returns the linked sub → Google re-auth works too.
        r = delete_account_google(client, token)
        assert r.status_code == 204, r.text
        assert client.get("/users/me", headers=auth_headers(token)).status_code == 401

    def test_dual_method_wrong_password_rejected(self, client, monkeypatch):
        register_ok(client, "alice", "alice@x.com")
        token = link_google(client, monkeypatch, "alice@x.com")

        r = delete_account(client, token, "wrongpass9")
        assert r.status_code == 401
        assert r.json()["code"] == "incorrect_password"

    def test_dual_method_google_mismatch_rejected(self, client, monkeypatch):
        register_ok(client, "alice", "alice@x.com")
        token = link_google(client, monkeypatch, "alice@x.com", sub="g-dual")

        # A Google token for a DIFFERENT account must not delete this one.
        import app.routers.users as users_router
        monkeypatch.setattr(
            users_router, "verify_google_id_token", lambda t: {"sub": "someone-else"},
        )
        r = delete_account_google(client, token)
        assert r.status_code == 401
        assert r.json()["code"] == "google_account_mismatch"


# ---------------------------------------------------------------------------
# Class: TestHasGoogleFlag — GET /users/me exposes has_google so the client can
# offer Google re-auth on dual-method accounts.
# ---------------------------------------------------------------------------

class TestHasGoogleFlag:
    def test_password_only_account_has_no_google(self, client):
        alice = register_ok(client, "alice", "alice@x.com")
        me = client.get("/users/me", headers=auth_headers(alice["access_token"])).json()
        assert me["has_password"] is True
        assert me["has_google"] is False

    def test_google_only_account_has_google(self, client, monkeypatch):
        patch_google_verifier(monkeypatch, sub="g-1")
        gina = google_signin(client, sub="g-1")
        me = client.get("/users/me", headers=auth_headers(gina["access_token"])).json()
        assert me["has_password"] is False
        assert me["has_google"] is True

    def test_dual_method_account_has_both(self, client, monkeypatch):
        register_ok(client, "alice", "alice@x.com")
        token = link_google(client, monkeypatch, "alice@x.com")
        me = client.get("/users/me", headers=auth_headers(token)).json()
        assert me["has_password"] is True
        assert me["has_google"] is True
