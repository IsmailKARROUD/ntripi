"""
test_user_images.py — Avatar and cover image upload / delete tests.

Mirrors the pattern from test_itinerary_image.py but exercises the user-level
avatar and cover-image endpoints. Storage is redirected to a per-test temp dir
via monkeypatch so artifacts don't leak between runs.
"""

import io
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from conftest import auth_headers, register_user
from app.storage.filesystem import FilesystemStorage


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_jpeg(width: int = 800, height: int = 800) -> bytes:
    img = Image.new("RGB", (width, height), color=(100, 149, 237))
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    return buf.getvalue()


def _make_png(width: int = 800, height: int = 800) -> bytes:
    img = Image.new("RGB", (width, height), color=(34, 139, 34))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _make_webp(width: int = 800, height: int = 800) -> bytes:
    img = Image.new("RGB", (width, height), color=(200, 50, 50))
    buf = io.BytesIO()
    img.save(buf, format="WEBP")
    return buf.getvalue()


def _upload(client, headers, path, image_bytes, filename="image.jpg",
            content_type="image/jpeg"):
    return client.post(
        path,
        files={"file": (filename, image_bytes, content_type)},
        headers=headers,
    )


# ---------------------------------------------------------------------------
# Fixture — redirect storage to a temp dir
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def _temp_storage(tmp_path):
    store = FilesystemStorage(str(tmp_path), "/uploads")
    with patch("app.routers.users.storage", return_value=store):
        yield store


# ---------------------------------------------------------------------------
# Avatar
# ---------------------------------------------------------------------------

class TestAvatarUpload:

    def test_jpeg_upload_succeeds(self, client: TestClient):
        alice = register_user(client, "alice_av", "alice@test.com")
        hdrs = auth_headers(alice["access_token"])
        resp = _upload(client, hdrs, "/users/me/avatar", _make_jpeg())

        assert resp.status_code == 200
        body = resp.json()
        assert body["avatar_url"].startswith("/uploads/avatars/")
        assert ".jpg?v=" in body["avatar_url"]
        # Version param is a positive unix timestamp
        version = int(body["avatar_url"].rsplit("?v=", 1)[1])
        assert version > 0

        me = client.get("/users/me", headers=hdrs).json()
        assert me["avatar_url"] == body["avatar_url"]

    def test_png_upload_succeeds(self, client: TestClient):
        alice = register_user(client, "alice_av2", "alice2@test.com")
        hdrs = auth_headers(alice["access_token"])
        resp = _upload(client, hdrs, "/users/me/avatar",
                       _make_png(), filename="a.png", content_type="image/png")
        assert resp.status_code == 200

    def test_webp_upload_succeeds(self, client: TestClient):
        alice = register_user(client, "alice_av3", "alice3@test.com")
        hdrs = auth_headers(alice["access_token"])
        resp = _upload(client, hdrs, "/users/me/avatar",
                       _make_webp(), filename="a.webp", content_type="image/webp")
        assert resp.status_code == 200

    def test_replace_overwrites_previous(self, client: TestClient):
        alice = register_user(client, "alice_av_r", "ar@test.com")
        hdrs = auth_headers(alice["access_token"])
        first = _upload(client, hdrs, "/users/me/avatar", _make_jpeg()).json()
        second = _upload(client, hdrs, "/users/me/avatar", _make_jpeg()).json()
        # Same UUID-based storage key, but each upload appends a fresh
        # ?v=<ts> so caches treat the URL as new.
        first_base = first["avatar_url"].rsplit("?v=", 1)[0]
        second_base = second["avatar_url"].rsplit("?v=", 1)[0]
        assert first_base == second_base
        assert first["avatar_url"] != second["avatar_url"]

    def test_too_small_rejected(self, client: TestClient):
        alice = register_user(client, "alice_av_s", "as@test.com")
        hdrs = auth_headers(alice["access_token"])
        resp = _upload(client, hdrs, "/users/me/avatar",
                       _make_jpeg(width=400, height=400))
        assert resp.status_code == 400

    def test_corrupt_rejected(self, client: TestClient):
        alice = register_user(client, "alice_av_c", "ac@test.com")
        hdrs = auth_headers(alice["access_token"])
        resp = _upload(client, hdrs, "/users/me/avatar",
                       b"not a real image at all")
        assert resp.status_code == 400

    def test_unauthenticated_rejected(self, client: TestClient):
        resp = _upload(client, {}, "/users/me/avatar", _make_jpeg())
        assert resp.status_code in (401, 403)

    def test_delete_clears_url(self, client: TestClient, _temp_storage):
        alice = register_user(client, "alice_av_d", "ad@test.com")
        hdrs = auth_headers(alice["access_token"])
        _upload(client, hdrs, "/users/me/avatar", _make_jpeg())

        del_resp = client.delete("/users/me/avatar", headers=hdrs)
        assert del_resp.status_code == 204

        me = client.get("/users/me", headers=hdrs).json()
        assert me["avatar_url"] is None


# ---------------------------------------------------------------------------
# Cover image
# ---------------------------------------------------------------------------

class TestCoverImageUpload:

    def test_jpeg_upload_succeeds(self, client: TestClient):
        alice = register_user(client, "alice_cv", "alice@test.com")
        hdrs = auth_headers(alice["access_token"])
        resp = _upload(client, hdrs, "/users/me/cover-image", _make_jpeg())

        assert resp.status_code == 200
        body = resp.json()
        assert body["cover_image_url"].startswith("/uploads/covers/")
        assert ".jpg?v=" in body["cover_image_url"]
        version = int(body["cover_image_url"].rsplit("?v=", 1)[1])
        assert version > 0

        me = client.get("/users/me", headers=hdrs).json()
        assert me["cover_image_url"] == body["cover_image_url"]

    def test_png_upload_succeeds(self, client: TestClient):
        alice = register_user(client, "alice_cv2", "alice2@test.com")
        hdrs = auth_headers(alice["access_token"])
        resp = _upload(client, hdrs, "/users/me/cover-image",
                       _make_png(), filename="c.png", content_type="image/png")
        assert resp.status_code == 200

    def test_too_small_rejected(self, client: TestClient):
        alice = register_user(client, "alice_cv_s", "cs@test.com")
        hdrs = auth_headers(alice["access_token"])
        resp = _upload(client, hdrs, "/users/me/cover-image",
                       _make_jpeg(width=400, height=400))
        assert resp.status_code == 400

    def test_corrupt_rejected(self, client: TestClient):
        alice = register_user(client, "alice_cv_c", "cc@test.com")
        hdrs = auth_headers(alice["access_token"])
        resp = _upload(client, hdrs, "/users/me/cover-image", b"\x00\x01\x02junk")
        assert resp.status_code == 400

    def test_unauthenticated_rejected(self, client: TestClient):
        resp = _upload(client, {}, "/users/me/cover-image", _make_jpeg())
        assert resp.status_code in (401, 403)

    def test_delete_clears_url(self, client: TestClient):
        alice = register_user(client, "alice_cv_d", "cd@test.com")
        hdrs = auth_headers(alice["access_token"])
        _upload(client, hdrs, "/users/me/cover-image", _make_jpeg())

        del_resp = client.delete("/users/me/cover-image", headers=hdrs)
        assert del_resp.status_code == 204

        me = client.get("/users/me", headers=hdrs).json()
        assert me["cover_image_url"] is None

    def test_cover_visible_on_public_profile(self, client: TestClient):
        alice = register_user(client, "alice_cv_p", "cp@test.com")
        hdrs = auth_headers(alice["access_token"])
        _upload(client, hdrs, "/users/me/cover-image", _make_jpeg())

        bob = register_user(client, "bob_cv_p", "cp_b@test.com")
        bob_hdrs = auth_headers(bob["access_token"])
        resp = client.get(f"/users/{alice['user_id']}", headers=bob_hdrs)
        assert resp.status_code == 200
        assert resp.json()["cover_image_url"].startswith("/uploads/covers/")
