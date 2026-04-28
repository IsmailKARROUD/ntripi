"""
test_itinerary_image.py — Cover image upload, processing, and OG tag tests.

Uses PIL to synthesise minimal valid images in memory so tests have no
dependency on files on disk. Storage is redirected to a temporary directory
for each test via monkeypatch so nothing leaks between runs.
"""

import io
import os
import tempfile
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from test.conftest import auth_headers, register_user
from app.storage.filesystem import FilesystemStorage


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_jpeg(width: int = 800, height: int = 800) -> bytes:
    """Return raw JPEG bytes for a solid-colour image of the given dimensions."""
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


def _create_itinerary(client: TestClient, headers: dict) -> str:
    """Create a minimal itinerary and return its ID."""
    resp = client.post(
        "/itineraries/",
        json={"title": "Test Trip", "visibility": "public"},
        headers=headers,
    )
    assert resp.status_code == 201
    return resp.json()["id"]


def _upload_image(client, headers, itin_id, image_bytes, filename="cover.jpg"):
    return client.post(
        f"/itineraries/{itin_id}/image",
        files={"file": (filename, image_bytes, "image/jpeg")},
        headers=headers,
    )


# ---------------------------------------------------------------------------
# Fixture — redirects storage to a temp dir for isolation
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def _temp_storage(tmp_path):
    """Redirect all storage operations to a per-test temp directory."""
    store = FilesystemStorage(str(tmp_path), "/uploads")
    with patch("app.routers.itineraries.storage", return_value=store):
        yield store


# ---------------------------------------------------------------------------
# TestImageUpload
# ---------------------------------------------------------------------------

class TestImageUpload:

    def test_owner_uploads_jpeg_succeeds(self, client: TestClient):
        alice = register_user(client, "alice_img", "alice@img.test")
        hdrs = auth_headers(alice["access_token"])
        itin_id = _create_itinerary(client, hdrs)

        resp = _upload_image(client, hdrs, itin_id, _make_jpeg())

        assert resp.status_code == 200
        data = resp.json()
        assert "cover_image_url" in data
        assert data["cover_image_url"].startswith("/uploads/")

        # cover_image_url is persisted on the itinerary row
        detail = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        assert detail.json()["cover_image_url"] == data["cover_image_url"]

    def test_owner_uploads_png_succeeds(self, client: TestClient):
        alice = register_user(client, "alice_png", "alice@png.test")
        hdrs = auth_headers(alice["access_token"])
        itin_id = _create_itinerary(client, hdrs)

        resp = client.post(
            f"/itineraries/{itin_id}/image",
            files={"file": ("cover.png", _make_png(), "image/png")},
            headers=hdrs,
        )

        assert resp.status_code == 200
        # Server always re-encodes as JPEG regardless of input format
        assert resp.json()["cover_image_url"].endswith(".jpg")

    def test_owner_uploads_webp_succeeds(self, client: TestClient):
        alice = register_user(client, "alice_webp", "alice@webp.test")
        hdrs = auth_headers(alice["access_token"])
        itin_id = _create_itinerary(client, hdrs)

        resp = client.post(
            f"/itineraries/{itin_id}/image",
            files={"file": ("cover.webp", _make_webp(), "image/webp")},
            headers=hdrs,
        )

        assert resp.status_code == 200

    def test_non_owner_rejected(self, client: TestClient):
        alice = register_user(client, "alice_own", "alice@own.test")
        bob = register_user(client, "bob_intruder", "bob@own.test")
        itin_id = _create_itinerary(client, auth_headers(alice["access_token"]))

        resp = _upload_image(
            client, auth_headers(bob["access_token"]), itin_id, _make_jpeg()
        )

        assert resp.status_code == 403

    def test_unauthenticated_rejected(self, client: TestClient):
        alice = register_user(client, "alice_unauth", "alice@unauth.test")
        itin_id = _create_itinerary(client, auth_headers(alice["access_token"]))

        resp = client.post(
            f"/itineraries/{itin_id}/image",
            files={"file": ("cover.jpg", _make_jpeg(), "image/jpeg")},
        )

        assert resp.status_code == 401

    def test_too_small_rejected(self, client: TestClient):
        alice = register_user(client, "alice_small", "alice@small.test")
        hdrs = auth_headers(alice["access_token"])
        itin_id = _create_itinerary(client, hdrs)

        resp = _upload_image(client, hdrs, itin_id, _make_jpeg(100, 100))

        assert resp.status_code == 400
        assert "small" in resp.json()["detail"].lower()

    def test_too_large_rejected(self, client: TestClient):
        alice = register_user(client, "alice_large", "alice@large.test")
        hdrs = auth_headers(alice["access_token"])
        itin_id = _create_itinerary(client, hdrs)

        big_bytes = b"\xff\xd8\xff" + b"x" * (11 * 1024 * 1024)  # >10 MB

        resp = _upload_image(client, hdrs, itin_id, big_bytes)

        assert resp.status_code == 400
        assert "10 MB" in resp.json()["detail"] or "10mb" in resp.json()["detail"].lower()

    def test_invalid_format_rejected(self, client: TestClient):
        alice = register_user(client, "alice_fmt", "alice@fmt.test")
        hdrs = auth_headers(alice["access_token"])
        itin_id = _create_itinerary(client, hdrs)

        # GIF is not in ALLOWED_FORMATS
        img = Image.new("RGB", (800, 800), color=(0, 0, 0))
        buf = io.BytesIO()
        img.save(buf, format="GIF")

        resp = client.post(
            f"/itineraries/{itin_id}/image",
            files={"file": ("cover.gif", buf.getvalue(), "image/gif")},
            headers=hdrs,
        )

        assert resp.status_code == 400

    def test_corrupt_file_rejected(self, client: TestClient):
        alice = register_user(client, "alice_corrupt", "alice@corrupt.test")
        hdrs = auth_headers(alice["access_token"])
        itin_id = _create_itinerary(client, hdrs)

        resp = _upload_image(client, hdrs, itin_id, b"not an image at all")

        assert resp.status_code == 400

    def test_replacing_image_overwrites_previous(self, client: TestClient, _temp_storage):
        alice = register_user(client, "alice_replace", "alice@replace.test")
        hdrs = auth_headers(alice["access_token"])
        itin_id = _create_itinerary(client, hdrs)

        url_a = _upload_image(client, hdrs, itin_id, _make_jpeg()).json()["cover_image_url"]
        url_b = _upload_image(client, hdrs, itin_id, _make_png(), "cover.png").json()["cover_image_url"]

        # Both uploads use the same key so the URL is identical — only one file on disk
        assert url_a == url_b
        assert client.get(f"/itineraries/{itin_id}", headers=hdrs).json()["cover_image_url"] == url_b

    def test_delete_image_clears_url(self, client: TestClient):
        alice = register_user(client, "alice_del", "alice@del.test")
        hdrs = auth_headers(alice["access_token"])
        itin_id = _create_itinerary(client, hdrs)

        _upload_image(client, hdrs, itin_id, _make_jpeg())

        resp = client.delete(f"/itineraries/{itin_id}/image", headers=hdrs)
        assert resp.status_code == 204

        detail = client.get(f"/itineraries/{itin_id}", headers=hdrs).json()
        assert detail["cover_image_url"] is None

    def test_delete_no_image_succeeds(self, client: TestClient):
        alice = register_user(client, "alice_nodel", "alice@nodel.test")
        hdrs = auth_headers(alice["access_token"])
        itin_id = _create_itinerary(client, hdrs)

        resp = client.delete(f"/itineraries/{itin_id}/image", headers=hdrs)
        assert resp.status_code == 204

    def test_image_url_in_itinerary_response(self, client: TestClient):
        alice = register_user(client, "alice_resp", "alice@resp.test")
        hdrs = auth_headers(alice["access_token"])
        itin_id = _create_itinerary(client, hdrs)

        upload_url = _upload_image(client, hdrs, itin_id, _make_jpeg()).json()["cover_image_url"]

        detail = client.get(f"/itineraries/{itin_id}", headers=hdrs).json()
        assert detail["cover_image_url"] == upload_url

    def test_image_url_in_share_landing_page_og_tag(self, client: TestClient):
        alice = register_user(client, "alice_og", "alice@og.test")
        hdrs = auth_headers(alice["access_token"])
        itin_id = _create_itinerary(client, hdrs)

        upload_url = _upload_image(client, hdrs, itin_id, _make_jpeg()).json()["cover_image_url"]

        html = client.get(f"/share/i/{itin_id}").text

        # og:image must contain an absolute URL that includes the upload path
        assert 'property="og:image"' in html
        assert upload_url.lstrip("/") in html

    def test_no_image_uses_default_og_image(self, client: TestClient):
        alice = register_user(client, "alice_defog", "alice@defog.test")
        hdrs = auth_headers(alice["access_token"])
        itin_id = _create_itinerary(client, hdrs)

        html = client.get(f"/share/i/{itin_id}").text

        assert "ntripi-og-default.jpg" in html


# ---------------------------------------------------------------------------
# TestImageProcessing
# ---------------------------------------------------------------------------

class TestImageProcessing:

    def test_strips_exif_from_jpeg(self):
        from app.services.image_service import process_cover_image

        # Build a JPEG with EXIF data attached
        img = Image.new("RGB", (800, 800), color=(0, 128, 255))
        exif_bytes = img.getexif()
        # Write a dummy GPS tag (tag 34853)
        exif_bytes[34853] = b"\x00"
        buf = io.BytesIO()
        img.save(buf, format="JPEG", exif=exif_bytes.tobytes())
        raw = buf.getvalue()

        processed = process_cover_image(raw)

        # Re-open the processed output and verify no EXIF survives
        result = Image.open(io.BytesIO(processed))
        exif_out = result.getexif()
        assert 34853 not in exif_out  # GPS IFD tag is gone

    def test_resizes_large_image_to_1200x630(self):
        from app.services.image_service import process_cover_image

        raw = _make_jpeg(4000, 3000)
        processed = process_cover_image(raw)

        result = Image.open(io.BytesIO(processed))
        assert result.size == (1200, 630)

    def test_crops_wide_aspect_ratio_correctly(self):
        from app.services.image_service import process_cover_image

        # 1500×1500 is square; output must be 1200×630
        raw = _make_jpeg(1500, 1500)
        processed = process_cover_image(raw)

        result = Image.open(io.BytesIO(processed))
        assert result.size == (1200, 630)

    def test_crops_tall_aspect_ratio_correctly(self):
        from app.services.image_service import process_cover_image

        # 630×1200 portrait → must crop to 1200×630
        raw = _make_jpeg(630, 1200)
        processed = process_cover_image(raw)

        result = Image.open(io.BytesIO(processed))
        assert result.size == (1200, 630)

    def test_output_is_always_jpeg(self):
        from app.services.image_service import process_cover_image

        result = Image.open(io.BytesIO(process_cover_image(_make_png())))
        assert result.format == "JPEG"

        result = Image.open(io.BytesIO(process_cover_image(_make_webp())))
        assert result.format == "JPEG"
