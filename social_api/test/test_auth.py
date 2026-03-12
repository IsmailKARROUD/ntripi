"""
tests/test_auth.py — Tests for POST /auth/register and POST /auth/login.

Each test function is completely independent. The 'client' fixture (from conftest.py)
gives every test a fresh database, so registering a user in one test doesn't
affect another test.

Test naming convention: test_<what>_<expected_outcome>
Examples:
  test_register_success           → happy path
  test_register_duplicate_username → specific failure case
  test_login_wrong_password        → specific failure case

This convention makes failing tests self-documenting — when a test fails,
you immediately know what broke and what the expected behavior was.
"""

import pytest
from fastapi.testclient import TestClient

from conftest import auth_headers, register_user


class TestRegister:
    """
    Groups all registration tests together.
    Using a class is optional but helps organize related tests visually
    and in test output reports.
    """

    def test_register_success(self, client: TestClient):
        """
        Happy path: a valid registration should return 201 with a token.
        This is the most fundamental test — if this fails, everything else will too.
        """
        response = client.post("/auth/register", json={
            "username": "alice1",
            "email": "alice@test.com",
            "password": "test1234",
            "display_name": "Alice",
        })

        assert response.status_code == 201

        data = response.json()
        # Verify all expected fields are present in the response
        assert "access_token" in data
        assert "user_id" in data
        assert data["username"] == "alice1"
        assert data["token_type"] == "bearer"

        # The token should be a non-empty string
        assert len(data["access_token"]) > 0

    def test_register_duplicate_username(self, client: TestClient):
        """
        Registering with a username that's already taken should return 409 Conflict.
        The error message should be specific to the username, not a generic conflict.
        """
        # Register the first user successfully
        register_user(client, "alice1", "alice@test.com")

        # Try to register with the same username but different email
        response = client.post("/auth/register", json={
            "username": "alice1",
            "email": "alice2@test.com",
            "password": "test1234",
        })

        assert response.status_code == 409
        assert "username" in response.json()["detail"].lower()

    def test_register_duplicate_email(self, client: TestClient):
        """
        Registering with an email that's already registered should return 409 Conflict.
        Importantly, the error should mention 'email', not 'username' — so the client
        can show the user the right error message.
        """
        register_user(client, "alice1", "alice@test.com")

        response = client.post("/auth/register", json={
            "username": "alice2",
            "email": "alice@test.com",  # Same email, different username
            "password": "test1234",
        })

        assert response.status_code == 409
        assert "email" in response.json()["detail"].lower()

    def test_register_invalid_username_special_chars(self, client: TestClient):
        """
        Usernames with spaces or special characters should be rejected with 422.
        422 Unprocessable Entity is FastAPI's standard response for validation failures.
        """
        response = client.post("/auth/register", json={
            "username": "alice smith",  # Space is not allowed
            "email": "alice@test.com",
            "password": "test1234",
        })
        assert response.status_code == 422

    def test_register_password_too_short(self, client: TestClient):
        """Passwords shorter than 8 characters should be rejected."""
        response = client.post("/auth/register", json={
            "username": "alice1",
            "email": "alice@test.com",
            "password": "abc1",  # Only 4 characters
        })
        assert response.status_code == 422

    def test_register_password_no_digit(self, client: TestClient):
        """Passwords without at least one digit should be rejected."""
        response = client.post("/auth/register", json={
            "username": "alice1",
            "email": "alice@test.com",
            "password": "nodigitshere",  # No digit
        })
        assert response.status_code == 422

    def test_register_invalid_email_format(self, client: TestClient):
        """Malformed email addresses should be rejected by Pydantic's EmailStr."""
        response = client.post("/auth/register", json={
            "username": "alice1",
            "email": "not-an-email",
            "password": "test1234",
        })
        assert response.status_code == 422


class TestLogin:

    def test_login_success(self, client: TestClient):
        """Happy path: correct credentials return a token."""
        register_user(client, "alice1", "alice@test.com")

        response = client.post("/auth/login", json={
            "email": "alice@test.com",
            "password": "test1234",
        })

        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data
        assert data["username"] == "alice1"

    def test_login_wrong_password(self, client: TestClient):
        """Wrong password should return 401 Unauthorized."""
        register_user(client, "alice1", "alice@test.com")

        response = client.post("/auth/login", json={
            "email": "alice@test.com",
            "password": "wrongpassword1",
        })

        assert response.status_code == 401
        # The error message should NOT say 'wrong password' specifically —
        # it should be generic to avoid revealing which part was wrong.
        assert "incorrect" in response.json()["detail"].lower()

    def test_login_nonexistent_email(self, client: TestClient):
        """
        Login with an email that doesn't exist should return 401.
        Critically, the error message should be IDENTICAL to the wrong-password
        case — this prevents email enumeration attacks.
        """
        response = client.post("/auth/login", json={
            "email": "nobody@test.com",
            "password": "test1234",
        })

        assert response.status_code == 401
        assert "incorrect" in response.json()["detail"].lower()

    def test_login_token_is_valid_for_protected_routes(self, client: TestClient):
        """
        The token returned by login should grant access to protected endpoints.
        This is an integration test — it crosses the boundary between auth and users.
        """
        register_user(client, "alice1", "alice@test.com")

        login_response = client.post("/auth/login", json={
            "email": "alice@test.com",
            "password": "test1234",
        })
        token = login_response.json()["access_token"]

        # Use the token to access a protected endpoint
        me_response = client.get("/users/me", headers=auth_headers(token))
        assert me_response.status_code == 200
        assert me_response.json()["username"] == "alice1"

    def test_protected_route_requires_auth(self, client: TestClient):
        """
        Accessing a protected endpoint without a token should return 403.
        This confirms the auth guard (get_current_user dependency) is working.
        """
        response = client.get("/users/me")
        assert response.status_code == 403
