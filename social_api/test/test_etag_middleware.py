"""
test/test_etag_middleware.py — Conditional-GET / 304 middleware behaviour.

Covers the middleware itself end-to-end against the real FastAPI app via
TestClient (no mocking — middleware sees the actual response pipeline).
Routes used as fixtures are existing public/auth endpoints; we don't add
test-only routes so the test reflects production behaviour faithfully.
"""

from fastapi.testclient import TestClient

from conftest import auth_headers, register_user


class TestETagMiddleware:
    """ETagMiddleware on /users/me and /health."""

    def test_get_json_response_has_etag_and_cache_control(
        self, client: TestClient
    ):
        # /users/me is a buffered JSON Pydantic response — the middleware's
        # default code path. Confirm both headers land on the response.
        user = register_user(client, "alice1", "alice@test.com")
        r = client.get("/users/me", headers=auth_headers(user["access_token"]))

        assert r.status_code == 200
        assert "etag" in {k.lower() for k in r.headers}
        etag = r.headers["etag"]
        assert etag.startswith('"') and etag.endswith('"')
        assert len(etag) == 18  # "<16 hex>"
        assert r.headers["cache-control"] == "private, no-cache"

    def test_if_none_match_match_returns_304_with_empty_body(
        self, client: TestClient
    ):
        # Round-trip the ETag — the server should reply 304 with no body and
        # the same ETag echoed back.
        user = register_user(client, "alice1", "alice@test.com")
        first = client.get("/users/me", headers=auth_headers(user["access_token"]))
        etag = first.headers["etag"]

        second = client.get(
            "/users/me",
            headers={
                **auth_headers(user["access_token"]),
                "If-None-Match": etag,
            },
        )

        assert second.status_code == 304
        assert second.content == b""
        assert second.headers["etag"] == etag

    def test_if_none_match_mismatch_returns_200_with_body(
        self, client: TestClient
    ):
        # A stale or bogus token must not short-circuit — the server still
        # ships the full body.
        user = register_user(client, "alice1", "alice@test.com")
        r = client.get(
            "/users/me",
            headers={
                **auth_headers(user["access_token"]),
                "If-None-Match": '"stale1234abcdef"',
            },
        )

        assert r.status_code == 200
        assert r.json()["username"] == "alice1"
        assert r.headers["etag"] != '"stale1234abcdef"'

    def test_same_body_produces_same_etag(self, client: TestClient):
        # Determinism check: identical responses must hash to identical
        # ETags. Without this, 304 would never trigger.
        user = register_user(client, "alice1", "alice@test.com")
        first = client.get("/users/me", headers=auth_headers(user["access_token"]))
        second = client.get("/users/me", headers=auth_headers(user["access_token"]))

        assert first.headers["etag"] == second.headers["etag"]

    def test_different_users_produce_different_etags(self, client: TestClient):
        # Two users hit the same URL → different bodies → different ETags.
        # Guards against the failure mode where the cache key strips Authorization
        # but the ETag would otherwise collide and leak content cross-user.
        u1 = register_user(client, "alice1", "alice@test.com")
        u2 = register_user(client, "bob1", "bob@test.com")

        r1 = client.get("/users/me", headers=auth_headers(u1["access_token"]))
        r2 = client.get("/users/me", headers=auth_headers(u2["access_token"]))

        assert r1.headers["etag"] != r2.headers["etag"]

    def test_non_get_method_is_not_etagged(self, client: TestClient):
        # POST /auth/register is JSON 201, but mutations must never carry the
        # cache ETag — that's the concurrency ETag's job, set explicitly by
        # endpoints that need it.
        r = client.post(
            "/auth/register",
            json={
                "username": "charlie1",
                "email": "charlie@test.com",
                "password": "test1234",
                "tos_accepted": True,
            },
        )
        assert r.status_code == 201
        assert "etag" not in {k.lower() for k in r.headers}

    def test_health_endpoint_is_etagged(self, client: TestClient):
        # /health is unauthenticated JSON — the middleware should still emit
        # an ETag. This also doubles as a smoke test for the no-auth path.
        r = client.get("/health")
        assert r.status_code == 200
        assert "etag" in {k.lower() for k in r.headers}

    def test_endpoint_set_etag_is_preserved(self, client: TestClient):
        # GET /itineraries/{id} sets its own ETag from _etag_value() — the
        # middleware must NOT overwrite it, or the If-Match concurrency
        # contract would break.
        owner = register_user(client, "alice1", "alice@test.com")
        create = client.post(
            "/itineraries/",
            json={"title": "Trip", "visibility": "only_me"},
            headers=auth_headers(owner["access_token"]),
        )
        assert create.status_code == 201
        itin_id = create.json()["id"]

        detail = client.get(
            f"/itineraries/{itin_id}",
            headers=auth_headers(owner["access_token"]),
        )
        assert detail.status_code == 200
        endpoint_etag = detail.headers["etag"]

        # The endpoint's ETag is a 16-hex-char hash of updated_at — different
        # from a body hash, but byte-comparable. The middleware should leave
        # it alone, and the 304 round-trip should still work with it.
        revisit = client.get(
            f"/itineraries/{itin_id}",
            headers={
                **auth_headers(owner["access_token"]),
                "If-None-Match": endpoint_etag,
            },
        )
        assert revisit.status_code == 304
        assert revisit.headers["etag"] == endpoint_etag
