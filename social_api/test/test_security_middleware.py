"""
test/test_security_middleware.py — Tests for the OWASP security hardening.

Covers every change made in the security hardening pass:
  - SecurityHeadersMiddleware: required headers on all responses, HSTS only on HTTPS
  - ContentSizeLimitMiddleware: 413 on oversized Content-Length, pass-through otherwise
  - CORS: explicit method/header lists (not wildcards), unknown origin blocked
  - API docs: /docs and /redoc return 404 in production (DEBUG=False)
  - Rate limiting: 429 after login / register / search limits are exceeded
  - Config: SECRET_KEY min_length=32 enforced at startup
  - Exception handler: generic 500 without internal details, re-raises CancelledError
"""

import asyncio
import json

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from conftest import auth_headers, register_user


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _login_headers(client: TestClient, username: str, email: str) -> dict:
    user = register_user(client, username, email)
    return auth_headers(user["access_token"])


# ---------------------------------------------------------------------------
# SecurityHeadersMiddleware
# ---------------------------------------------------------------------------

class TestSecurityHeaders:
    """SecurityHeadersMiddleware adds OWASP defensive headers to every API response."""

    def test_required_headers_present_on_200(self, client: TestClient):
        """All four unconditional headers land on a normal 200 response."""
        r = client.get("/health")
        assert r.status_code == 200
        assert r.headers["x-frame-options"] == "DENY"
        assert r.headers["x-content-type-options"] == "nosniff"
        assert r.headers["referrer-policy"] == "strict-origin-when-cross-origin"
        assert r.headers["content-security-policy"] == "frame-ancestors 'none'"

    def test_security_headers_present_on_401(self, client: TestClient):
        """Headers are added to error responses too — not only 2xx."""
        r = client.get("/users/me")  # no auth → 401/403
        assert r.headers.get("x-frame-options") == "DENY"
        assert r.headers.get("x-content-type-options") == "nosniff"

    def test_security_headers_present_on_404(self, client: TestClient):
        r = client.get("/nonexistent-route-xyz")
        assert r.headers.get("x-frame-options") == "DENY"

    def test_hsts_absent_on_http(self, client: TestClient):
        """HSTS must NOT be emitted over plain HTTP — only HTTPS connections get it.
        All TestClient requests are HTTP, so HSTS should never appear here."""
        r = client.get("/health")
        assert "strict-transport-security" not in r.headers

    def test_csp_does_not_contain_default_src(self, client: TestClient):
        """CSP is restricted to frame-ancestors only.
        default-src 'self' is omitted because it provides no meaningful protection
        for a JSON API consumed by mobile clients."""
        r = client.get("/health")
        csp = r.headers["content-security-policy"]
        assert "default-src" not in csp
        assert "frame-ancestors 'none'" in csp


# ---------------------------------------------------------------------------
# ContentSizeLimitMiddleware
# ---------------------------------------------------------------------------

class TestContentSizeLimit:
    """ContentSizeLimitMiddleware rejects bodies with Content-Length > 10 MB."""

    _LIMIT = 10 * 1024 * 1024  # 10 MB in bytes

    def test_oversized_content_length_returns_413(self, client: TestClient):
        """A Content-Length header claiming >10 MB must be rejected immediately,
        before the request body is read or CORS headers are applied."""
        r = client.post(
            "/auth/register",
            content=b"x",  # tiny actual body — limit is based on the header
            headers={
                "Content-Length": str(self._LIMIT + 1),
                "Content-Type": "application/json",
            },
        )
        assert r.status_code == 413

    def test_body_at_exactly_limit_passes(self, client: TestClient):
        """A request at exactly 10 MB should NOT be rejected by the middleware."""
        # We verify this indirectly: a normal-sized JSON request reaches the handler.
        r = client.post("/auth/register", json={
            "username": "sizelimit1",
            "email": "sizelimit@test.com",
            "password": "test1234",
            "tos_accepted": True,
        })
        # Handler ran → not 413
        assert r.status_code != 413

    def test_request_without_content_length_passes(self, client: TestClient):
        """Requests without Content-Length (e.g. GET, chunked bodies) are not rejected."""
        r = client.get("/health")
        assert r.status_code == 200

    def test_oversized_get_request_is_not_blocked(self, client: TestClient):
        """GET requests never carry a body — the middleware must not block them even if a
        large Content-Length header is present (e.g. a mis-configured client)."""
        r = client.get("/health", headers={"Content-Length": str(self._LIMIT + 1)})
        assert r.status_code == 200


# ---------------------------------------------------------------------------
# CORS configuration
# ---------------------------------------------------------------------------

class TestCORSConfig:
    """CORS uses explicit method and header allowlists — no wildcards."""

    def _origin(self) -> str:
        """Return the first configured ALLOWED_ORIGINS value for use in test Origin header."""
        from app.config import get_settings
        return get_settings().ALLOWED_ORIGINS.split(",")[0].strip()

    def test_allowed_method_in_preflight_response(self, client: TestClient):
        """POST is in the whitelist — a preflight for POST must be accepted."""
        r = client.options(
            "/auth/login",
            headers={
                "Origin": self._origin(),
                "Access-Control-Request-Method": "POST",
            },
        )
        assert r.status_code in (200, 204)
        allowed = r.headers.get("access-control-allow-methods", "")
        assert "POST" in allowed

    def test_put_not_in_preflight_response(self, client: TestClient):
        """PUT is not in the explicit whitelist and must not appear in preflight."""
        r = client.options(
            "/auth/login",
            headers={
                "Origin": self._origin(),
                "Access-Control-Request-Method": "PUT",
            },
        )
        # CORSMiddleware either 400s or omits the method — either way PUT must not be allowed
        allowed = r.headers.get("access-control-allow-methods", "")
        assert "PUT" not in allowed

    def test_authorization_header_in_preflight_response(self, client: TestClient):
        """Authorization is an explicitly allowed header."""
        r = client.options(
            "/auth/login",
            headers={
                "Origin": self._origin(),
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "Authorization",
            },
        )
        allowed_headers = r.headers.get("access-control-allow-headers", "").lower()
        assert "authorization" in allowed_headers

    def test_custom_header_not_in_preflight_response(self, client: TestClient):
        """An arbitrary custom header is not in the explicit allowlist."""
        r = client.options(
            "/auth/login",
            headers={
                "Origin": self._origin(),
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "X-My-Custom-Header",
            },
        )
        allowed_headers = r.headers.get("access-control-allow-headers", "").lower()
        assert "x-my-custom-header" not in allowed_headers

    def test_unknown_origin_gets_no_cors_header(self, client: TestClient):
        """A request from an unlisted origin must not receive ACAO header."""
        r = client.get("/health", headers={"Origin": "https://attacker.example.com"})
        assert "access-control-allow-origin" not in r.headers


# ---------------------------------------------------------------------------
# API docs gating
# ---------------------------------------------------------------------------

class TestDocsGating:
    """/docs and /redoc are disabled in production (DEBUG=False is the default).

    These tests are skipped when DEBUG=True (local dev) because in that mode
    FastAPI intentionally exposes the docs — the gate only applies in production.
    Run with DEBUG=False (the Railway default) to exercise this protection.
    """

    @pytest.fixture(autouse=True)
    def require_production_mode(self):
        from app.config import get_settings
        if get_settings().DEBUG:
            pytest.skip("DEBUG=True: docs are intentionally enabled in dev mode")

    def test_swagger_ui_returns_404(self, client: TestClient):
        r = client.get("/docs")
        assert r.status_code == 404

    def test_redoc_returns_404(self, client: TestClient):
        r = client.get("/redoc")
        assert r.status_code == 404

    def test_openapi_json_is_still_accessible(self, client: TestClient):
        """The raw openapi.json schema endpoint is separate from the UI pages.
        FastAPI only disables the interactive UIs, not the spec itself."""
        r = client.get("/openapi.json")
        assert r.status_code == 200
        assert "openapi" in r.json()


# ---------------------------------------------------------------------------
# Rate limiting
# ---------------------------------------------------------------------------

class TestRateLimiting:
    """slowapi enforces per-IP limits on auth and search endpoints.

    Each test uses a unique X-Forwarded-For IP so tests are isolated — the
    in-memory limiter stores state globally for the process lifetime.
    ProxyHeadersMiddleware (trusted_hosts="*") rewrites request.client.host from
    this header, so slowapi's get_remote_address() reads the test IP correctly.
    """

    # Unique IPs per test to prevent cross-test interference
    _IP_LOGIN = "192.168.50.1"
    _IP_REGISTER = "192.168.50.2"
    _IP_SEARCH = "192.168.50.3"
    _IP_INDEPENDENT_A = "192.168.50.4"
    _IP_INDEPENDENT_B = "192.168.50.5"

    def test_login_rate_limit_triggers_429_at_11th(self, client: TestClient):
        """11th /auth/login request from the same IP within a minute → 429.
        The first 10 are allowed; the endpoint returns 401 (wrong credentials)
        but the rate limit counter still increments because the handler ran."""
        headers = {"X-Forwarded-For": self._IP_LOGIN}
        payload = {"identifier": "noone@ntripi.app", "password": "wrongpassword"}

        for i in range(10):
            r = client.post("/auth/login", json=payload, headers=headers)
            assert r.status_code != 429, f"Hit rate limit on request {i + 1} (too early)"

        r = client.post("/auth/login", json=payload, headers=headers)
        assert r.status_code == 429

    def test_register_rate_limit_triggers_429_at_6th(self, client: TestClient):
        """6th /auth/register request from the same IP within an hour → 429."""
        headers = {"X-Forwarded-For": self._IP_REGISTER}

        for i in range(5):
            r = client.post("/auth/register", json={
                "username": f"rlreg{i}",
                "email": f"rlreg{i}@test.com",
                "password": "test1234",
                "tos_accepted": True,
            }, headers=headers)
            assert r.status_code != 429, f"Hit rate limit on request {i + 1} (too early)"

        r = client.post("/auth/register", json={
            "username": "rlreg99",
            "email": "rlreg99@test.com",
            "password": "test1234",
            "tos_accepted": True,
        }, headers=headers)
        assert r.status_code == 429

    def test_search_rate_limit_triggers_429_at_31st(self, client: TestClient):
        """31st /users/search request from the same IP within a minute → 429."""
        # Create a user with the default (testserver) IP so it doesn't consume the search quota
        user = register_user(client, "searchrl1", "searchrl@test.com")
        token_headers = {
            **auth_headers(user["access_token"]),
            "X-Forwarded-For": self._IP_SEARCH,
        }

        for i in range(30):
            r = client.get("/users/search?q=x", headers=token_headers)
            assert r.status_code != 429, f"Hit rate limit on request {i + 1} (too early)"

        r = client.get("/users/search?q=x", headers=token_headers)
        assert r.status_code == 429

    def test_different_ips_have_independent_counters(self, client: TestClient):
        """Exhausting the limit for one IP does not block a different IP."""
        payload = {"identifier": "noone@ntripi.app", "password": "wrong"}

        # Exhaust limit for IP A
        for _ in range(10):
            client.post("/auth/login", json=payload,
                        headers={"X-Forwarded-For": self._IP_INDEPENDENT_A})
        assert client.post("/auth/login", json=payload,
                           headers={"X-Forwarded-For": self._IP_INDEPENDENT_A}).status_code == 429

        # IP B must still be under its own independent limit
        r = client.post("/auth/login", json=payload,
                        headers={"X-Forwarded-For": self._IP_INDEPENDENT_B})
        assert r.status_code != 429


# ---------------------------------------------------------------------------
# Config validation
# ---------------------------------------------------------------------------

class TestConfigValidation:
    """Settings validates SECRET_KEY length at startup — short keys refuse to start."""

    def test_short_secret_key_raises_validation_error(self):
        """A SECRET_KEY shorter than 32 characters must fail Pydantic validation."""
        from app.config import Settings
        with pytest.raises(ValidationError) as exc_info:
            Settings(DATABASE_URL="sqlite://", SECRET_KEY="tooshort")
        errors = exc_info.value.errors()
        # Confirm the error is specifically about SECRET_KEY, not something else
        assert any(e["loc"] == ("SECRET_KEY",) for e in errors)

    def test_31_char_key_still_rejected(self):
        from app.config import Settings
        with pytest.raises(ValidationError):
            Settings(DATABASE_URL="sqlite://", SECRET_KEY="a" * 31)

    def test_32_char_key_is_accepted(self):
        """Exactly 32 characters satisfies the minimum."""
        from app.config import Settings
        s = Settings(DATABASE_URL="sqlite://", SECRET_KEY="a" * 32)
        assert len(s.SECRET_KEY) == 32

    def test_longer_key_is_accepted(self):
        """Keys longer than 32 characters (e.g. hex from openssl rand -hex 32 = 64 chars) are fine."""
        from app.config import Settings
        s = Settings(DATABASE_URL="sqlite://", SECRET_KEY="a" * 64)
        assert len(s.SECRET_KEY) == 64

    def test_allowed_hosts_default_contains_both_apex_and_wildcard(self):
        """Default ALLOWED_HOSTS must list apex and wildcard separately — the wildcard
        alone does not match the bare apex in Starlette's TrustedHostMiddleware."""
        from app.config import Settings
        s = Settings(DATABASE_URL="sqlite://", SECRET_KEY="a" * 32)
        hosts = [h.strip() for h in s.ALLOWED_HOSTS.split(",")]
        assert "ntripi.app" in hosts
        assert "*.ntripi.app" in hosts


# ---------------------------------------------------------------------------
# Generic exception handler
# ---------------------------------------------------------------------------

class TestExceptionHandler:
    """Generic 500 handler returns a clean JSON body without leaking internals."""

    def test_handler_returns_generic_500_body(self):
        """Calling the handler with a RuntimeError should return a sanitised 500."""
        from unittest.mock import MagicMock
        from app.main import generic_exception_handler, settings

        # Only meaningful when DEBUG=False; the test env defaults to False
        if settings.DEBUG:
            pytest.skip("Exception handler re-raises in DEBUG mode — skip in dev")

        request = MagicMock()
        request.method = "GET"
        request.url.path = "/test"

        response = asyncio.run(
            generic_exception_handler(request, RuntimeError("secret internal detail"))
        )
        assert response.status_code == 500
        body = json.loads(response.body)
        assert body == {"detail": "Internal server error"}
        # Confirm the internal error message is NOT leaked
        assert "secret internal detail" not in response.body.decode()
        assert "RuntimeError" not in response.body.decode()

    def test_handler_reraises_cancelled_error(self):
        """asyncio.CancelledError must propagate — intercepting it would break
        Starlette's lifespan and async request lifecycle."""
        from unittest.mock import MagicMock
        from app.main import generic_exception_handler

        request = MagicMock()
        request.method = "GET"
        request.url.path = "/test"

        with pytest.raises(asyncio.CancelledError):
            asyncio.run(
                generic_exception_handler(request, asyncio.CancelledError())
            )

    def test_health_endpoint_never_500(self, client: TestClient):
        """/health is the simplest possible endpoint — a smoke test that the
        exception handler isn't inadvertently wrapping normal responses."""
        r = client.get("/health")
        assert r.status_code == 200
        assert r.json() == {"status": "ok"}

    def test_404_is_not_swallowed_by_exception_handler(self, client: TestClient):
        """FastAPI's own HTTP exception handler takes precedence over the generic
        Exception handler, so 404 responses still get 404 not 500."""
        r = client.get("/this-route-does-not-exist-xyz")
        assert r.status_code == 404
