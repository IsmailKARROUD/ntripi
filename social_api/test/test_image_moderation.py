"""
test_image_moderation.py — Tests for the backend AWS Rekognition moderation tier.

Covers the three upload endpoints (itinerary cover, avatar, user cover) through
the shared process_and_store seam. The Rekognition client is stubbed via
monkeypatching moderation_service._rekognition_client; storage is redirected to
a per-test temp dir (patched in image_service — the actual save funnel — so
"file absent on reject" assertions are reliable); operator emails are captured
by monkeypatching send_email as imported in moderation_service.

Default behaviour (moderation disabled) is asserted first so the rest of the
suite proves the opt-in scan doesn't change existing upload flows.
"""

from __future__ import annotations

import io
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from conftest import TestingSessionLocal, auth_headers, register_user
from app.config import get_settings
from app.models.image_moderation_log import ImageModerationLog
from app.models.itinerary import Itinerary
from app.services import moderation_service


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_jpeg(width: int = 800, height: int = 800) -> bytes:
    img = Image.new("RGB", (width, height), color=(100, 149, 237))
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    return buf.getvalue()


def _upload(client, headers, path, filename="image.jpg"):
    return client.post(
        path,
        files={"file": (filename, _make_jpeg(), "image/jpeg")},
        headers=headers,
    )


def _create_itinerary(client: TestClient, token: str, title: str = "Trip") -> str:
    r = client.post(
        "/itineraries/",
        json={"title": title, "currency": "EUR", "visibility": "public"},
        headers=auth_headers(token),
    )
    assert r.status_code == 201, r.json()
    return r.json()["id"]


class _StubRekognition:
    """Stand-in for the boto3 Rekognition client. Returns canned labels or
    raises, mirroring detect_moderation_labels' signature."""

    def __init__(self, labels: list[dict] | None = None, raises: bool = False):
        self._labels = labels or []
        self._raises = raises

    def detect_moderation_labels(self, *, Image, MinConfidence):  # noqa: N803
        if self._raises:
            raise RuntimeError("simulated AWS outage")
        return {"ModerationLabels": self._labels}


def _enable_moderation(monkeypatch, reject: float = 80.0, flag: float = 50.0) -> None:
    s = get_settings()
    monkeypatch.setattr(s, "MODERATION_ENABLED", True)
    monkeypatch.setattr(s, "MODERATION_AWS_ACCESS_KEY_ID", "test-key")
    monkeypatch.setattr(s, "MODERATION_AWS_SECRET_ACCESS_KEY", "test-secret")
    monkeypatch.setattr(s, "MODERATION_AWS_REGION", "eu-west-1")
    monkeypatch.setattr(s, "MODERATION_REJECT_THRESHOLD", reject)
    monkeypatch.setattr(s, "MODERATION_FLAG_THRESHOLD", flag)


def _stub_rekognition(monkeypatch, labels=None, raises=False) -> None:
    stub = _StubRekognition(labels=labels, raises=raises)
    monkeypatch.setattr(moderation_service, "_rekognition_client", lambda settings: stub)


def _capture_emails(monkeypatch) -> list[dict]:
    sent: list[dict] = []
    monkeypatch.setattr(
        "app.services.moderation_service.send_email",
        lambda to, subject, html: sent.append({"to": to, "subject": subject, "html": html}),
    )
    return sent


def _count_logs() -> int:
    db = TestingSessionLocal()
    try:
        return db.query(ImageModerationLog).count()
    finally:
        db.close()


def _get_log() -> ImageModerationLog:
    db = TestingSessionLocal()
    try:
        return db.query(ImageModerationLog).one()
    finally:
        db.close()


def _itinerary_status(it_id: str) -> str:
    import uuid
    db = TestingSessionLocal()
    try:
        return db.get(Itinerary, uuid.UUID(it_id)).moderation_status
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Fixtures — redirect storage to a per-test temp dir at the save funnel
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def _temp_storage(tmp_path):
    from app.storage.filesystem import FilesystemStorage
    store = FilesystemStorage(str(tmp_path), "/uploads")
    # Patch at image_service (the real save funnel) plus both router namespaces
    # (used by the DELETE endpoints).
    with patch("app.services.image_service.storage", return_value=store), \
         patch("app.routers.users.storage", return_value=store), \
         patch("app.routers.itineraries.storage", return_value=store):
        yield store


# ---------------------------------------------------------------------------
# Disabled by default
# ---------------------------------------------------------------------------

class TestModerationDisabled:
    def test_upload_unscanned_when_disabled(self, client, _temp_storage):
        alice = register_user(client, "mod_off", "modoff@test.com")
        it_id = _create_itinerary(client, alice["access_token"])
        r = _upload(client, auth_headers(alice["access_token"]),
                    f"/itineraries/{it_id}/image")
        assert r.status_code == 200
        assert _count_logs() == 0                 # no scan → no audit row
        assert _itinerary_status(it_id) == "approved"
        assert _temp_storage._base.joinpath(f"itineraries/{it_id}.jpg").exists()


# ---------------------------------------------------------------------------
# Clean / approve
# ---------------------------------------------------------------------------

class TestModerationApprove:
    def test_clean_scan_stores_and_logs_approved(self, client, monkeypatch, _temp_storage):
        _enable_moderation(monkeypatch)
        _stub_rekognition(monkeypatch, labels=[])
        alice = register_user(client, "mod_clean", "modclean@test.com")
        it_id = _create_itinerary(client, alice["access_token"])
        r = _upload(client, auth_headers(alice["access_token"]),
                    f"/itineraries/{it_id}/image")
        assert r.status_code == 200
        assert _temp_storage._base.joinpath(f"itineraries/{it_id}.jpg").exists()
        assert _itinerary_status(it_id) == "approved"
        log = _get_log()
        assert log.action == "approved"
        assert log.labels == []
        assert log.target_kind == "itinerary_cover"


# ---------------------------------------------------------------------------
# Hard reject
# ---------------------------------------------------------------------------

class TestModerationReject:
    def test_explicit_nudity_rejected(self, client, monkeypatch, _temp_storage):
        _enable_moderation(monkeypatch)
        _stub_rekognition(monkeypatch, labels=[
            {"Name": "Explicit Nudity", "ParentName": "", "Confidence": 95.0},
        ])
        sent = _capture_emails(monkeypatch)
        alice = register_user(client, "mod_rej", "modrej@test.com")
        it_id = _create_itinerary(client, alice["access_token"])
        r = _upload(client, auth_headers(alice["access_token"]),
                    f"/itineraries/{it_id}/image")

        assert r.status_code == 422
        assert r.json()["code"] == "image_moderation_rejected"
        # Nothing stored, URL untouched, but the audit row survived the 422.
        assert not _temp_storage._base.joinpath(f"itineraries/{it_id}.jpg").exists()
        db = TestingSessionLocal()
        try:
            import uuid
            it = db.get(Itinerary, uuid.UUID(it_id))
            assert it.cover_image_url is None
        finally:
            db.close()
        log = _get_log()
        assert log.action == "rejected"
        assert sent == []                          # reject never emails

    def test_reject_via_parent_category(self, client, monkeypatch, _temp_storage):
        _enable_moderation(monkeypatch)
        # Child label under a reject parent — caught via ParentName.
        _stub_rekognition(monkeypatch, labels=[
            {"Name": "Graphic Male Nudity", "ParentName": "Explicit Nudity", "Confidence": 90.0},
        ])
        alice = register_user(client, "mod_rej_p", "modrejp@test.com")
        it_id = _create_itinerary(client, alice["access_token"])
        r = _upload(client, auth_headers(alice["access_token"]),
                    f"/itineraries/{it_id}/image")
        assert r.status_code == 422
        assert r.json()["code"] == "image_moderation_rejected"

    def test_below_reject_threshold_not_rejected(self, client, monkeypatch, _temp_storage):
        _enable_moderation(monkeypatch, reject=80.0, flag=50.0)
        # Reject category but only 70% → flag, not reject.
        _stub_rekognition(monkeypatch, labels=[
            {"Name": "Violence", "ParentName": "", "Confidence": 70.0},
        ])
        _capture_emails(monkeypatch)
        alice = register_user(client, "mod_soft", "modsoft@test.com")
        it_id = _create_itinerary(client, alice["access_token"])
        r = _upload(client, auth_headers(alice["access_token"]),
                    f"/itineraries/{it_id}/image")
        assert r.status_code == 200
        assert _itinerary_status(it_id) == "flagged"


# ---------------------------------------------------------------------------
# Soft flag
# ---------------------------------------------------------------------------

class TestModerationFlag:
    def test_flag_stores_logs_and_emails(self, client, monkeypatch, _temp_storage):
        _enable_moderation(monkeypatch)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", "ops@example.com")
        _stub_rekognition(monkeypatch, labels=[
            {"Name": "Suggestive", "ParentName": "", "Confidence": 60.0},
        ])
        sent = _capture_emails(monkeypatch)
        alice = register_user(client, "mod_flag", "modflag@test.com")
        it_id = _create_itinerary(client, alice["access_token"])
        r = _upload(client, auth_headers(alice["access_token"]),
                    f"/itineraries/{it_id}/image")

        assert r.status_code == 200
        assert _temp_storage._base.joinpath(f"itineraries/{it_id}.jpg").exists()
        assert _itinerary_status(it_id) == "flagged"
        log = _get_log()
        assert log.action == "flagged"
        assert log.labels == [{"name": "Suggestive", "confidence": 60.0}]
        assert len(sent) == 1
        assert "Suggestive" in sent[0]["html"]
        # Dismiss SQL is HTML-escaped (quotes → &#x27;); match a quote-free span.
        assert "UPDATE itineraries SET moderation_status" in sent[0]["html"]

    def test_flag_without_operator_email_skips_send(self, client, monkeypatch, _temp_storage):
        _enable_moderation(monkeypatch)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", None)
        _stub_rekognition(monkeypatch, labels=[
            {"Name": "Suggestive", "ParentName": "", "Confidence": 60.0},
        ])
        sent = _capture_emails(monkeypatch)
        alice = register_user(client, "mod_flag_noemail", "modflagne@test.com")
        it_id = _create_itinerary(client, alice["access_token"])
        r = _upload(client, auth_headers(alice["access_token"]),
                    f"/itineraries/{it_id}/image")
        assert r.status_code == 200
        assert _itinerary_status(it_id) == "flagged"
        assert sent == []


# ---------------------------------------------------------------------------
# Graceful degradation
# ---------------------------------------------------------------------------

class TestModerationDegraded:
    def test_aws_error_allows_upload_pending(self, client, monkeypatch, _temp_storage):
        _enable_moderation(monkeypatch)
        _stub_rekognition(monkeypatch, raises=True)
        sent = _capture_emails(monkeypatch)
        alice = register_user(client, "mod_err", "moderr@test.com")
        it_id = _create_itinerary(client, alice["access_token"])
        r = _upload(client, auth_headers(alice["access_token"]),
                    f"/itineraries/{it_id}/image")
        assert r.status_code == 200
        assert _temp_storage._base.joinpath(f"itineraries/{it_id}.jpg").exists()
        assert _itinerary_status(it_id) == "pending"
        log = _get_log()
        assert log.action == "error_allowed"
        assert sent == []


# ---------------------------------------------------------------------------
# User images (avatar / cover) — no status column, log + email only
# ---------------------------------------------------------------------------

class TestModerationUserImages:
    def test_avatar_flag_logs_and_emails(self, client, monkeypatch, _temp_storage):
        _enable_moderation(monkeypatch)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", "ops@example.com")
        _stub_rekognition(monkeypatch, labels=[
            {"Name": "Suggestive", "ParentName": "", "Confidence": 60.0},
        ])
        sent = _capture_emails(monkeypatch)
        alice = register_user(client, "mod_av", "modav@test.com")
        r = _upload(client, auth_headers(alice["access_token"]), "/users/me/avatar")
        assert r.status_code == 200
        log = _get_log()
        assert log.target_kind == "avatar"
        assert log.action == "flagged"
        assert log.target_itinerary_id is None
        assert len(sent) == 1

    def test_avatar_reject_returns_422(self, client, monkeypatch, _temp_storage):
        _enable_moderation(monkeypatch)
        _stub_rekognition(monkeypatch, labels=[
            {"Name": "Explicit Nudity", "ParentName": "", "Confidence": 99.0},
        ])
        alice = register_user(client, "mod_av_rej", "modavrej@test.com")
        r = _upload(client, auth_headers(alice["access_token"]), "/users/me/avatar")
        assert r.status_code == 422
        assert r.json()["code"] == "image_moderation_rejected"
        me = client.get("/users/me", headers=auth_headers(alice["access_token"])).json()
        assert me["avatar_url"] is None


# ---------------------------------------------------------------------------
# Retention + delete reset
# ---------------------------------------------------------------------------

class TestModerationRetentionAndDelete:
    def test_old_logs_purged_on_next_scan(self, client, monkeypatch, _temp_storage):
        # Seed a log row 91 days old with an explicit aware timestamp.
        db = TestingSessionLocal()
        try:
            db.add(ImageModerationLog(
                image_hash="old" * 20 + "abcd",
                target_kind="avatar",
                action="approved",
                labels=[],
                created_at=datetime.now(timezone.utc) - timedelta(days=91),
            ))
            db.commit()
        finally:
            db.close()
        assert _count_logs() == 1

        _enable_moderation(monkeypatch)
        _stub_rekognition(monkeypatch, labels=[])
        alice = register_user(client, "mod_ret", "modret@test.com")
        r = _upload(client, auth_headers(alice["access_token"]), "/users/me/avatar")
        assert r.status_code == 200
        # Old row purged; only the fresh approved row remains.
        log = _get_log()
        assert log.action == "approved"
        assert log.target_kind == "avatar"

    def test_cover_delete_resets_moderation_status(self, client, monkeypatch, _temp_storage):
        _enable_moderation(monkeypatch)
        _stub_rekognition(monkeypatch, labels=[
            {"Name": "Suggestive", "ParentName": "", "Confidence": 60.0},
        ])
        alice = register_user(client, "mod_del", "moddel@test.com")
        hdrs = auth_headers(alice["access_token"])
        it_id = _create_itinerary(client, alice["access_token"])
        _upload(client, hdrs, f"/itineraries/{it_id}/image")
        assert _itinerary_status(it_id) == "flagged"

        r = client.delete(f"/itineraries/{it_id}/image", headers=hdrs)
        assert r.status_code == 204
        assert _itinerary_status(it_id) == "approved"
