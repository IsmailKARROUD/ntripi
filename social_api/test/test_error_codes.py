"""test_error_codes.py — Verifies ApiError responses carry a stable `code`
sibling field while keeping `detail` byte-identical (so the Flutter client can
localize errors without string-matching the human message).

See app/errors.py and the api_error_handler in app/main.py.
"""

from fastapi.testclient import TestClient

from conftest import auth_headers, register_user


class TestErrorCodes:
    def test_not_found_includes_code_and_unchanged_detail(self, client: TestClient):
        token = register_user(client, "erra", "erra@test.com")["access_token"]
        resp = client.get(
            "/itineraries/00000000-0000-0000-0000-000000000000",
            headers=auth_headers(token),
        )
        assert resp.status_code == 404
        body = resp.json()
        # detail stays exactly as before; code is the new localization key.
        assert body["detail"] == "Itinerary not found."
        assert body["code"] == "itinerary_not_found"

    def test_incorrect_password_code(self, client: TestClient):
        register_user(client, "errb", "errb@test.com", password="test1234")
        resp = client.post(
            "/auth/login",
            json={"identifier": "errb@test.com", "password": "wrongpass9"},
        )
        assert resp.status_code == 401
        body = resp.json()
        assert body["code"] == "login_invalid"
        # exact human message preserved
        assert "incorrect" in body["detail"].lower()

    def test_cannot_follow_self_code(self, client: TestClient):
        reg = register_user(client, "errc", "errc@test.com")
        resp = client.post(
            f"/users/{reg['user_id']}/follow",
            headers=auth_headers(reg["access_token"]),
        )
        assert resp.status_code == 400
        assert resp.json()["code"] == "cannot_follow_self"

    def test_plain_http_exception_still_has_no_code(self, client: TestClient):
        # An invalid token hits the plain HTTPException `credentials_exception`
        # (not an ApiError), which must keep the legacy {"detail": ...} shape.
        resp = client.get("/users/me", headers=auth_headers("garbage.token.value"))
        assert resp.status_code == 401
        assert resp.json()["detail"] == "Could not validate credentials."
        assert "code" not in resp.json()
