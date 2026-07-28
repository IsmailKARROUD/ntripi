"""
test_admin_auth.py — The two gates in front of the moderation dashboard.

Layer 1 is HTTP Basic (off → the whole router 404s), layer 2 is a per-admin
session cookie carrying scope="admin". The scope check is the load-bearing one:
API access tokens are signed with the same key, so without it a stolen mobile
token would open the dashboard.
"""

from fastapi.testclient import TestClient

from conftest import ADMIN_BASIC, admin_session, auth_headers, make_admin, register_user
from app.routers.admin import ADMIN_COOKIE


def _admin_user(client: TestClient, username: str = "opsadmin",
                email: str = "ops@test.com") -> dict:
    account = register_user(client, username, email)
    make_admin(email)
    return account


class TestBasicAuthLayer:

    def test_404_when_credentials_not_configured(self, client: TestClient):
        # No admin_enabled fixture → feature off → the panel is invisible.
        for path in ("/admin", "/admin/login", "/admin/reports"):
            assert client.get(path).status_code == 404, path

    def test_401_without_basic_credentials(self, client: TestClient, admin_enabled):
        resp = client.get("/admin/login")
        assert resp.status_code == 401
        assert "Basic" in resp.headers.get("www-authenticate", "")

    def test_401_with_wrong_basic_password(self, client: TestClient, admin_enabled):
        resp = client.get("/admin/login", auth=(ADMIN_BASIC[0], "wrong"))
        assert resp.status_code == 401

    def test_login_form_reachable_with_basic(self, client: TestClient, admin_enabled):
        resp = client.get("/admin/login", auth=ADMIN_BASIC)
        assert resp.status_code == 200
        assert "Admin sign in" in resp.text or "Ntripi admin" in resp.text


class TestSessionLayer:

    def test_redirects_to_login_without_cookie(self, client: TestClient, admin_enabled):
        resp = client.get("/admin", auth=ADMIN_BASIC, follow_redirects=False)
        assert resp.status_code == 303
        assert resp.headers["location"] == "/admin/login"

    def test_non_admin_cannot_sign_in(self, client: TestClient, admin_enabled):
        register_user(client, "plainuser", "plain@test.com")
        resp = client.post(
            "/admin/login",
            data={"identifier": "plain@test.com", "password": "test1234"},
            auth=ADMIN_BASIC, follow_redirects=False,
        )
        assert resp.status_code == 401
        assert "set-cookie" not in resp.headers

    def test_wrong_password_rejected(self, client: TestClient, admin_enabled):
        _admin_user(client)
        resp = client.post(
            "/admin/login",
            data={"identifier": "ops@test.com", "password": "not-the-password"},
            auth=ADMIN_BASIC, follow_redirects=False,
        )
        assert resp.status_code == 401

    def test_admin_login_sets_hardened_cookie(self, client: TestClient, admin_enabled):
        _admin_user(client)
        resp = client.post(
            "/admin/login",
            data={"identifier": "ops@test.com", "password": "test1234"},
            auth=ADMIN_BASIC, follow_redirects=False,
        )
        assert resp.status_code == 303
        assert resp.headers["location"] == "/admin"

        cookie = resp.headers["set-cookie"]
        assert ADMIN_COOKIE in cookie
        assert "HttpOnly" in cookie
        assert "Path=/admin" in cookie
        # SameSite=Strict is the CSRF defense for every POST in the router.
        assert "samesite=strict" in cookie.lower()

    def test_cookie_is_secure_outside_debug(self, client: TestClient, admin_enabled,
                                            monkeypatch):
        """Secure is gated on DEBUG so the cookie still works over http in local
        dev — but production (DEBUG=False) must never send it in the clear."""
        from app.config import get_settings

        monkeypatch.setattr(get_settings(), "DEBUG", False)
        _admin_user(client)
        resp = client.post(
            "/admin/login",
            data={"identifier": "ops@test.com", "password": "test1234"},
            auth=ADMIN_BASIC, follow_redirects=False,
        )
        assert "Secure" in resp.headers["set-cookie"]

    def test_dashboard_reachable_after_login(self, client: TestClient, admin_enabled):
        _admin_user(client)
        admin_session(client, "ops@test.com")
        resp = client.get("/admin", auth=ADMIN_BASIC)
        assert resp.status_code == 200
        assert "Overview" in resp.text

    def test_api_access_token_is_not_an_admin_session(self, client: TestClient, admin_enabled):
        """A mobile access token replayed as the session cookie must not work —
        it is signed with the same key but carries no scope claim."""
        account = _admin_user(client)
        client.cookies.set(ADMIN_COOKIE, account["access_token"])
        resp = client.get("/admin", auth=ADMIN_BASIC, follow_redirects=False)
        assert resp.status_code == 303
        assert resp.headers["location"] == "/admin/login"

    def test_garbage_cookie_redirects(self, client: TestClient, admin_enabled):
        client.cookies.set(ADMIN_COOKIE, "not-a-jwt")
        resp = client.get("/admin", auth=ADMIN_BASIC, follow_redirects=False)
        assert resp.status_code == 303

    def test_revoked_admin_loses_access(self, client: TestClient, admin_enabled):
        """Rights are re-checked per request, so demoting or suspending an admin
        kills their open dashboard session immediately."""
        from sqlalchemy import select
        from conftest import TestingSessionLocal
        from app.models.user import User

        _admin_user(client)
        admin_session(client, "ops@test.com")
        assert client.get("/admin", auth=ADMIN_BASIC).status_code == 200

        db = TestingSessionLocal()
        try:
            user = db.execute(
                select(User).where(User.email == "ops@test.com")
            ).scalar_one()
            user.is_admin = False
            db.commit()
        finally:
            db.close()

        resp = client.get("/admin", auth=ADMIN_BASIC, follow_redirects=False)
        assert resp.status_code == 303

    def test_logout_clears_the_session(self, client: TestClient, admin_enabled):
        _admin_user(client)
        admin_session(client, "ops@test.com")

        resp = client.post("/admin/logout", auth=ADMIN_BASIC, follow_redirects=False)
        assert resp.status_code == 303
        assert resp.headers["location"] == "/admin/login"

        client.cookies.clear()
        assert client.get(
            "/admin", auth=ADMIN_BASIC, follow_redirects=False
        ).status_code == 303


class TestAdminResponseHeaders:

    def test_admin_pages_are_noindex_and_uncached(self, client: TestClient, admin_enabled):
        _admin_user(client)
        admin_session(client, "ops@test.com")
        resp = client.get("/admin", auth=ADMIN_BASIC)
        assert resp.headers["x-robots-tag"] == "noindex, nofollow"
        assert resp.headers["cache-control"] == "no-store"

    def test_public_pages_keep_their_headers(self, client: TestClient):
        resp = client.get("/")
        assert "x-robots-tag" not in resp.headers
        assert resp.headers.get("cache-control") != "no-store"

    def test_robots_txt_disallows_admin(self, client: TestClient):
        resp = client.get("/robots.txt")
        assert resp.status_code == 200
        assert "Disallow: /admin/" in resp.text
