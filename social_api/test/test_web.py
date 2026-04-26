"""
test/test_web.py — Tests for the marketing homepage and web auth flow.

Coverage:
  - All public GET pages return 200 with expected HTML content
  - Open Graph meta tags present on homepage
  - POST /web/login: success → 302 + cookie; failure → 200 + error
  - POST /web/register: success → 302 + cookie; validation failures → 200 + error
  - Logged-in users redirected away from /login
"""

import pytest
from fastapi.testclient import TestClient

from conftest import register_user


class TestPublicPages:
    def test_homepage_returns_html(self, client: TestClient):
        response = client.get("/")
        assert response.status_code == 200
        assert "text/html" in response.headers["content-type"]
        assert "Ntripi" in response.text
        assert "Continue on web" in response.text

    def test_homepage_has_open_graph_tags(self, client: TestClient):
        response = client.get("/")
        assert response.status_code == 200
        assert 'property="og:title"' in response.text
        assert 'property="og:description"' in response.text
        assert 'property="og:url"' in response.text
        assert 'property="og:image"' in response.text

    def test_login_page_renders(self, client: TestClient):
        response = client.get("/login")
        assert response.status_code == 200
        assert 'action="/web/login"' in response.text

    def test_register_page_renders(self, client: TestClient):
        response = client.get("/register")
        assert response.status_code == 200
        assert 'action="/web/register"' in response.text

    def test_privacy_page_renders(self, client: TestClient):
        response = client.get("/privacy")
        assert response.status_code == 200
        assert "Privacy" in response.text

    def test_terms_page_renders(self, client: TestClient):
        response = client.get("/terms")
        assert response.status_code == 200
        assert "Terms" in response.text


class TestWebAuthFlow:
    def test_web_login_with_valid_credentials_sets_cookie_and_redirects(
        self, client: TestClient
    ):
        register_user(client, "webloginuser", "weblogin@example.com", password="password123")

        response = client.post(
            "/web/login",
            data={"email": "weblogin@example.com", "password": "password123"},
            follow_redirects=False,
        )

        assert response.status_code == 302
        assert response.headers["location"] == "/app/"
        assert "ntripi_session" in response.cookies

    def test_web_login_with_invalid_credentials_rerenders_form(
        self, client: TestClient
    ):
        response = client.post(
            "/web/login",
            data={"email": "nobody@example.com", "password": "wrongpassword1"},
            follow_redirects=False,
        )

        assert response.status_code == 200
        assert "text/html" in response.headers["content-type"]
        assert "Incorrect" in response.text or "email or password" in response.text
        assert "ntripi_session" not in response.cookies

    def test_web_register_creates_user_and_logs_in(self, client: TestClient):
        response = client.post(
            "/web/register",
            data={
                "email": "newuser@example.com",
                "username": "newuser1",
                "password": "secure123",
                "password_confirm": "secure123",
                "tos_accepted": "on",
            },
            follow_redirects=False,
        )

        assert response.status_code == 302
        assert response.headers["location"] == "/app/"
        assert "ntripi_session" in response.cookies

        # Verify user was actually created by logging in via the API
        login_resp = client.post(
            "/auth/login",
            json={"email": "newuser@example.com", "password": "secure123"},
        )
        assert login_resp.status_code == 200
        assert login_resp.json()["username"] == "newuser1"

    def test_web_register_validates_password_match(self, client: TestClient):
        response = client.post(
            "/web/register",
            data={
                "email": "mismatch@example.com",
                "username": "mismatch1",
                "password": "secure123",
                "password_confirm": "different1",
                "tos_accepted": "on",
            },
            follow_redirects=False,
        )

        assert response.status_code == 200
        assert "do not match" in response.text.lower() or "Passwords" in response.text
        assert "ntripi_session" not in response.cookies

        # Verify no user was created
        login_resp = client.post(
            "/auth/login",
            json={"email": "mismatch@example.com", "password": "secure123"},
        )
        assert login_resp.status_code == 401

    def test_web_register_requires_tos_acceptance(self, client: TestClient):
        response = client.post(
            "/web/register",
            data={
                "email": "notos@example.com",
                "username": "notos1",
                "password": "secure123",
                "password_confirm": "secure123",
                # tos_accepted intentionally omitted
            },
            follow_redirects=False,
        )

        assert response.status_code == 200
        assert "Terms of Service" in response.text or "tos" in response.text.lower()
        assert "ntripi_session" not in response.cookies

    def test_logged_in_user_redirected_from_login_page(self, client: TestClient):
        data = register_user(client, "alreadyin", "alreadyin@example.com", password="password123")
        token = data["access_token"]

        response = client.get(
            "/login",
            cookies={"ntripi_session": token},
            follow_redirects=False,
        )

        assert response.status_code == 302
        assert response.headers["location"] == "/app/"
