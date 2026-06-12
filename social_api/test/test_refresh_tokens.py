"""
test_refresh_tokens.py — Tests for refresh-token issuance, rotation, theft
detection, and logout.

Reuses the `client` + `register_user` fixtures from conftest.py.
"""

import pytest
from fastapi.testclient import TestClient

from conftest import auth_headers, register_user


def _login(client: TestClient, identifier: str = "alice@test.com") -> dict:
    response = client.post(
        "/auth/login",
        json={"identifier": identifier, "password": "test1234"},
    )
    assert response.status_code == 200
    return response.json()


class TestRefreshTokenIssuance:
    def test_login_returns_refresh_token(self, client: TestClient):
        register_user(client, "alice1", "alice@test.com")
        data = _login(client)
        assert data["refresh_token"]
        assert "refresh_expires_at" in data
        assert data["refresh_token"] != data["access_token"]

    def test_register_returns_refresh_token(self, client: TestClient):
        data = register_user(client, "alice1", "alice@test.com")
        assert data["refresh_token"]
        assert data["refresh_token"] != data["access_token"]


class TestRefreshRotation:
    def test_refresh_returns_new_token_pair(self, client: TestClient):
        initial = register_user(client, "alice1", "alice@test.com")

        response = client.post(
            "/auth/refresh",
            json={"refresh_token": initial["refresh_token"]},
        )
        assert response.status_code == 200
        rotated = response.json()
        # Refresh token MUST rotate (security guarantee).
        # Access token may be byte-identical when refresh happens in the same
        # second as issue (JWT is deterministic with second-precision iat/exp);
        # in production refresh happens >=15 min later so this is moot.
        assert rotated["refresh_token"] != initial["refresh_token"]
        assert rotated["user_id"] == initial["user_id"]
        assert rotated["access_token"]  # non-empty

    def test_old_refresh_token_rejected_after_rotation(self, client: TestClient):
        initial = register_user(client, "alice1", "alice@test.com")

        # Use it once — succeeds.
        first = client.post(
            "/auth/refresh",
            json={"refresh_token": initial["refresh_token"]},
        )
        assert first.status_code == 200

        # Use the same token again — replay should be rejected.
        replay = client.post(
            "/auth/refresh",
            json={"refresh_token": initial["refresh_token"]},
        )
        assert replay.status_code == 401
        assert replay.json()["detail"] == "invalid_grant"

    def test_replay_revokes_entire_family(self, client: TestClient):
        """
        After a replay attack is detected, even the current (legitimate)
        refresh token should stop working — the whole family is dead.
        """
        initial = register_user(client, "alice1", "alice@test.com")

        # Honest rotation.
        first_rotation = client.post(
            "/auth/refresh",
            json={"refresh_token": initial["refresh_token"]},
        ).json()

        # Attacker replays the old (now-revoked) token.
        replay = client.post(
            "/auth/refresh",
            json={"refresh_token": initial["refresh_token"]},
        )
        assert replay.status_code == 401

        # The legitimate user's current token is now also dead.
        followup = client.post(
            "/auth/refresh",
            json={"refresh_token": first_rotation["refresh_token"]},
        )
        assert followup.status_code == 401
        assert followup.json()["detail"] == "invalid_grant"

    def test_refresh_with_unknown_token_returns_401(self, client: TestClient):
        register_user(client, "alice1", "alice@test.com")
        response = client.post(
            "/auth/refresh",
            json={"refresh_token": "definitely-not-a-real-token"},
        )
        assert response.status_code == 401

    def test_refreshed_access_token_works_on_protected_route(
        self, client: TestClient
    ):
        initial = register_user(client, "alice1", "alice@test.com")
        rotated = client.post(
            "/auth/refresh",
            json={"refresh_token": initial["refresh_token"]},
        ).json()

        me = client.get(
            "/users/me", headers=auth_headers(rotated["access_token"])
        )
        assert me.status_code == 200
        assert me.json()["username"] == "alice1"


class TestRefreshExpiry:
    def test_expired_refresh_token_returns_401(self, client: TestClient):
        """
        Manually expire a token in the DB and verify the endpoint rejects it.
        Simulates 30 days of inactivity without waiting in real time.
        """
        from datetime import datetime, timedelta, timezone
        from app.models.refresh_token import RefreshToken
        from conftest import TestingSessionLocal

        initial = register_user(client, "alice1", "alice@test.com")

        import uuid

        with TestingSessionLocal() as db:
            row = (
                db.query(RefreshToken)
                .filter(RefreshToken.user_id == uuid.UUID(initial["user_id"]))
                .one()
            )
            row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
            db.commit()

        response = client.post(
            "/auth/refresh",
            json={"refresh_token": initial["refresh_token"]},
        )
        assert response.status_code == 401


class TestLogoutEndpoint:
    def test_logout_revokes_refresh_token(self, client: TestClient):
        initial = register_user(client, "alice1", "alice@test.com")

        logout = client.post(
            "/auth/logout",
            json={"refresh_token": initial["refresh_token"]},
        )
        assert logout.status_code == 204

        # The revoked token can no longer be used to refresh.
        refresh = client.post(
            "/auth/refresh",
            json={"refresh_token": initial["refresh_token"]},
        )
        assert refresh.status_code == 401

    def test_logout_unknown_token_still_204(self, client: TestClient):
        """Don't leak token validity — logout always returns 204."""
        response = client.post(
            "/auth/logout",
            json={"refresh_token": "nope-never-issued"},
        )
        assert response.status_code == 204
