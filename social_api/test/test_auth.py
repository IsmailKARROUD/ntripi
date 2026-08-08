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
            "tos_accepted": True,
            "date_of_birth": "2000-01-01",
        })

        assert response.status_code == 201

        data = response.json()
        # Verify all expected fields are present in the response
        assert "access_token" in data
        assert "refresh_token" in data
        assert "refresh_expires_at" in data
        assert "user_id" in data
        assert data["username"] == "alice1"
        assert data["token_type"] == "bearer"

        # Tokens should be non-empty strings
        assert len(data["access_token"]) > 0
        assert len(data["refresh_token"]) > 0

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
            "tos_accepted": True,
            "date_of_birth": "2000-01-01",
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
            "tos_accepted": True,
            "date_of_birth": "2000-01-01",
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
            "identifier": "alice@test.com",
            "password": "test1234",
        })

        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data
        assert "refresh_token" in data
        assert data["username"] == "alice1"

    def test_login_wrong_password(self, client: TestClient):
        """Wrong password should return 401 Unauthorized."""
        register_user(client, "alice1", "alice@test.com")

        response = client.post("/auth/login", json={
            "identifier": "alice@test.com",
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
            "identifier": "nobody@test.com",
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
            "identifier": "alice@test.com",
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


class TestLogout:
    """
    Logout on this API is client-side only: the Flutter app deletes the stored
    JWT from secure storage. There is no /auth/logout endpoint because JWTs are
    stateless — the server cannot invalidate them.

    What we CAN test here is the server-side behavior that makes logout secure:
      1. A request with no token is rejected (what happens immediately after logout).
      2. A request with a tampered token is rejected (token cannot be forged).
      3. A request with a completely fake token string is rejected.

    These tests verify that once the client discards a token, the server will
    refuse any further access — which is the security guarantee we rely on.
    """

    def test_no_token_after_logout_returns_403(self, client: TestClient):
        """
        After logout the client sends no token at all.
        Protected endpoints must return 403 Forbidden.
        """
        register_user(client, "alice1", "alice@test.com")

        # Simulate a logged-out client: make a request with no Authorization header.
        response = client.get("/users/me")

        assert response.status_code == 403

    def test_tampered_token_after_logout_returns_401(self, client: TestClient):
        data = register_user(client, "alice1", "alice@test.com")
        token = data["access_token"]

        # Corrupt the signature: replace the last 10 characters with 'x'.
        # A JWT has three base64 parts separated by '.'. Changing the signature
        # part makes the token invalid without changing the readable payload.
        tampered_token = token[:-10] + "x" * 10

        response = client.get("/users/me", headers=auth_headers(tampered_token))

        assert response.status_code == 401

    def test_fake_token_returns_401(self, client: TestClient):
        """
        A completely fabricated token string must be rejected.
        This covers the case where someone tries to forge a token from scratch.
        """
        response = client.get(
            "/users/me",
            headers=auth_headers("this.is.not.a.real.jwt"),
        )

        assert response.status_code == 401

    def test_valid_token_still_works_before_logout(self, client: TestClient):
        """
        Sanity check: a freshly issued token must grant access to protected
        endpoints. This ensures the rejection tests above are meaningful —
        if all tokens were rejected, those tests would pass for the wrong reason.
        """
        data = register_user(client, "alice1", "alice@test.com")
        token = data["access_token"]

        response = client.get("/users/me", headers=auth_headers(token))

        assert response.status_code == 200
        assert response.json()["username"] == "alice1"


class TestUsernameValidation:

    def test_valid_letters_only_succeeds(self, client: TestClient):
        assert register_user(client, "alice", "alice@test.com")["username"] == "alice"

    def test_valid_letters_and_numbers_succeeds(self, client: TestClient):
        assert register_user(client, "alice42", "a@test.com")["username"] == "alice42"

    def test_valid_with_underscore_succeeds(self, client: TestClient):
        assert register_user(client, "alice_smith", "a@test.com")["username"] == "alice_smith"

    def test_valid_with_period_succeeds(self, client: TestClient):
        assert register_user(client, "alice.smith", "a@test.com")["username"] == "alice.smith"

    def test_invalid_with_hyphen_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "alice-smith", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_invalid_with_space_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "alice smith", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_invalid_with_emoji_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "alice\U0001f389", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_invalid_with_accent_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "élise", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_starts_with_number_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "1alice", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_starts_with_period_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": ".alice", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_starts_with_underscore_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "_alice", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_ends_with_period_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "alice.", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_ends_with_underscore_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "alice_", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_consecutive_periods_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "ali..ce", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_consecutive_underscores_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "ali__ce", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_period_underscore_adjacent_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "ali._ce", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_too_short_3_chars_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "ali", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_minimum_4_chars_succeeds(self, client: TestClient):
        assert register_user(client, "alic", "a@test.com")["username"] == "alic"

    def test_too_long_31_chars_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "a" * 31, "email": "a@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_max_30_chars_succeeds(self, client: TestClient):
        name = "a" + "b" * 28 + "c"  # 30 chars, starts with letter, ends with letter
        assert register_user(client, name, "a@test.com")["username"] == name

    def test_reserved_username_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "admin", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_reserved_username_case_insensitive(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "ADMIN", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422


class TestPasswordCharsetAndLength:
    """
    Passwords accept Unicode (NIST 800-63B) but are capped at 72 UTF-8 bytes —
    bcrypt 5.x raises ValueError above that, which used to surface as a 500.
    The digit rule counts ASCII digits only, matching the Flutter client's [0-9].
    """

    def _register(self, client: TestClient, password: str):
        return client.post("/auth/register", json={
            "username": "alice1",
            "email": "alice@test.com",
            "password": password,
            "tos_accepted": True,
            "date_of_birth": "2000-01-01",
        })

    def test_register_73_char_ascii_password_rejected(self, client: TestClient):
        # 73 chars = 73 bytes — over the bcrypt cap but under max_length=128,
        # so this used to blow up inside hashpw instead of validating.
        response = self._register(client, "a" * 72 + "1")
        assert response.status_code == 422

    def test_register_72_char_ascii_password_succeeds(self, client: TestClient):
        response = self._register(client, "a" * 71 + "1")
        assert response.status_code == 201

    def test_register_long_arabic_password_rejected(self, client: TestClient):
        # 39 Arabic chars (2 bytes each) + digit = 79 bytes from only 40 chars
        response = self._register(client, "م" * 39 + "1")
        assert response.status_code == 422

    def test_register_short_arabic_password_succeeds_and_logs_in(self, client: TestClient):
        password = "مرحبا" * 3 + "1"  # 31 UTF-8 bytes — comfortably under 72
        assert self._register(client, password).status_code == 201

        login = client.post("/auth/login", json={
            "identifier": "alice@test.com",
            "password": password,
        })
        assert login.status_code == 200

    def test_register_nfkc_expanding_password_rejected(self, client: TestClient):
        # ﷺ expands to 18 chars under NFKC — the byte cap must count the
        # normalized form that actually gets hashed, not the raw input.
        response = self._register(client, "ﷺ" * 7 + "1")
        assert response.status_code == 422

    def test_arabic_indic_digit_does_not_satisfy_digit_rule(self, client: TestClient):
        # '٣'.isdigit() is True in Python, but the client requires [0-9] —
        # server must agree so the API doesn't accept what the app rejects.
        response = self._register(client, "abcdefgh٣")
        assert response.status_code == 422

    def test_login_overlong_password_returns_401_not_500(self, client: TestClient):
        register_user(client, "alice1", "alice@test.com")
        response = client.post("/auth/login", json={
            "identifier": "alice@test.com",
            "password": "x" * 100,
        })
        assert response.status_code == 401

    def test_login_overlong_password_unknown_user_returns_401(self, client: TestClient):
        # exercises the timing-safe dummy-hash path for missing users
        response = client.post("/auth/login", json={
            "identifier": "nobody@test.com",
            "password": "x" * 100,
        })
        assert response.status_code == 401


class TestEmailAsciiOnly:
    """
    Internationalized addresses pass Pydantic's EmailStr, but reset/verification
    mail delivery to them (SMTPUTF8) is unreliable — the API rejects them.
    """

    def test_register_arabic_local_part_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "alice1", "email": "مثال@example.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_register_arabic_domain_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "alice1", "email": "user@مثال.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_forgot_password_arabic_email_rejected(self, client: TestClient):
        r = client.post("/auth/forgot-password", json={"email": "مثال@example.com"})
        assert r.status_code == 422


class TestCaseInsensitiveUsername:

    def test_register_uppercase_then_lowercase_rejected(self, client: TestClient):
        register_user(client, "Ismail", "first@test.com")
        r = client.post("/auth/register", json={"username": "ismail", "email": "second@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 409

    def test_register_lowercase_then_uppercase_rejected(self, client: TestClient):
        register_user(client, "ismail", "first@test.com")
        r = client.post("/auth/register", json={"username": "ISMAIL", "email": "second@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 409

    def test_register_mixed_case_rejected(self, client: TestClient):
        register_user(client, "Ismail", "first@test.com")
        r = client.post("/auth/register", json={"username": "iSmAiL", "email": "second@test.com", "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
        assert r.status_code == 409

    def test_username_display_form_preserved(self, client: TestClient):
        data = register_user(client, "Ismail", "ismail@test.com")
        token = data["access_token"]
        me = client.get("/users/me", headers=auth_headers(token)).json()
        assert me["username"] == "Ismail"

    def test_login_with_lowercase_works(self, client: TestClient):
        register_user(client, "Ismail", "ismail@test.com")
        r = client.post("/auth/login", json={"identifier": "ismail", "password": "test1234"})
        assert r.status_code == 200

    def test_login_with_uppercase_works(self, client: TestClient):
        register_user(client, "Ismail", "ismail@test.com")
        r = client.post("/auth/login", json={"identifier": "ISMAIL", "password": "test1234"})
        assert r.status_code == 200

    def test_login_with_original_case_works(self, client: TestClient):
        register_user(client, "Ismail", "ismail@test.com")
        r = client.post("/auth/login", json={"identifier": "Ismail", "password": "test1234"})
        assert r.status_code == 200

    def test_user_lookup_by_username_case_insensitive(self, client: TestClient):
        data = register_user(client, "Ismail", "ismail@test.com")
        token = data["access_token"]
        headers = auth_headers(token)
        r = client.get("/users/by-username/ismail", headers=headers)
        assert r.status_code == 200
        assert r.json()["username"] == "Ismail"
        r2 = client.get("/users/by-username/ISMAIL", headers=headers)
        assert r2.status_code == 200
        assert r2.json()["username"] == "Ismail"


class TestDisplayName:

    def test_register_without_display_name_works(self, client: TestClient):
        data = register_user(client, "alice1", "alice@test.com", display_name=None)
        token = data["access_token"]
        me = client.get("/users/me", headers=auth_headers(token)).json()
        assert me["display_name"] is None

    def test_register_with_display_name_works(self, client: TestClient):
        data = register_user(client, "alice1", "alice@test.com", display_name="Alice Smith")
        token = data["access_token"]
        me = client.get("/users/me", headers=auth_headers(token)).json()
        assert me["display_name"] == "Alice Smith"

    def test_unicode_display_name_works(self, client: TestClient):
        data = register_user(client, "alice1", "alice@test.com", display_name="إسماعيل")
        token = data["access_token"]
        me = client.get("/users/me", headers=auth_headers(token)).json()
        assert me["display_name"] == "إسماعيل"

    def test_display_name_too_long_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "alice1", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "display_name": "x" * 51, "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_display_name_with_control_chars_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "alice1", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "display_name": "Alice\x00Smith", "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_display_name_with_zero_width_chars_rejected(self, client: TestClient):
        r = client.post("/auth/register", json={"username": "alice1", "email": "a@test.com", "password": "test1234", "tos_accepted": True, "display_name": "Alice​Smith", "date_of_birth": "2000-01-01"})
        assert r.status_code == 422

    def test_empty_display_name_becomes_none(self, client: TestClient):
        data = register_user(client, "alice1", "alice@test.com", display_name="   ")
        token = data["access_token"]
        me = client.get("/users/me", headers=auth_headers(token)).json()
        assert me["display_name"] is None


class TestUserUpdate:

    def test_update_display_name_succeeds(self, client: TestClient):
        data = register_user(client, "alice1", "alice@test.com")
        headers = auth_headers(data["access_token"])
        r = client.patch("/users/me", json={"display_name": "Alice Updated"}, headers=headers)
        assert r.status_code == 200
        assert r.json()["display_name"] == "Alice Updated"

    def test_update_display_name_to_empty_clears_it(self, client: TestClient):
        data = register_user(client, "alice1", "alice@test.com", display_name="Alice")
        headers = auth_headers(data["access_token"])
        r = client.patch("/users/me", json={"display_name": "  "}, headers=headers)
        assert r.status_code == 200
        assert r.json()["display_name"] is None

    def test_username_not_accepted_in_user_update(self, client: TestClient):
        data = register_user(client, "alice1", "alice@test.com")
        headers = auth_headers(data["access_token"])
        r = client.patch("/users/me", json={"username": "hackedname", "display_name": "Alice"}, headers=headers)
        assert r.status_code == 200
        assert r.json()["username"] == "alice1"


class TestUsernameLookup:

    def test_lookup_returns_display_username(self, client: TestClient):
        data = register_user(client, "Ismail", "ismail@test.com")
        headers = auth_headers(data["access_token"])
        r = client.get("/users/by-username/ismail", headers=headers)
        assert r.status_code == 200
        assert r.json()["username"] == "Ismail"

    def test_search_finds_by_username(self, client: TestClient):
        data = register_user(client, "alice1", "alice@test.com")
        register_user(client, "bobby1", "bob@test.com")
        headers = auth_headers(data["access_token"])
        r = client.get("/users/search?q=bobby", headers=headers)
        assert r.status_code == 200
        results = r.json()
        assert any(u["username"] == "bobby1" for u in results)

    def test_search_finds_by_display_name(self, client: TestClient):
        data = register_user(client, "alice1", "alice@test.com")
        register_user(client, "bobby1", "bob@test.com", display_name="Robert Paulson")
        headers = auth_headers(data["access_token"])
        r = client.get("/users/search?q=Robert", headers=headers)
        assert r.status_code == 200
        results = r.json()
        assert any(u["username"] == "bobby1" for u in results)

    def test_search_case_insensitive(self, client: TestClient):
        data = register_user(client, "alice1", "alice@test.com")
        register_user(client, "bobby1", "bob@test.com")
        headers = auth_headers(data["access_token"])
        r = client.get("/users/search?q=BOBBY", headers=headers)
        assert r.status_code == 200
        results = r.json()
        assert any(u["username"] == "bobby1" for u in results)
