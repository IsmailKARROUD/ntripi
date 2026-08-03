"""
test_csam_takedown.py — the operator response to a Cloudflare CSAM notice.

Cloudflare hash-matches at the edge on content it is already serving, so unlike
an upload-time scan the object exists here and the response is an operator
action rather than an automatic one. The assertions below are the ones that make
that action defensible: the object is hashed BEFORE deletion (afterwards the
hash is the only evidence), the evidence row is purge-exempt, the account is
locked without being told why, and the escalation lands in the lane that cannot
be closed without a CyberTipline report number.
"""

from __future__ import annotations

import io
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from conftest import (
    ADMIN_BASIC, TestingSessionLocal, admin_session, auth_headers, make_admin,
    register_user,
)
from app.models.image_moderation_log import ImageModerationLog
from app.models.itinerary import Itinerary
from app.models.legal_escalation import LegalEscalation
from app.models.moderation_log import ModerationLog
from app.models.refresh_token import RefreshToken
from app.models.user import User
from app.services import admin_service


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_jpeg(width: int = 800, height: int = 800) -> bytes:
    img = Image.new("RGB", (width, height), color=(100, 149, 237))
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    return buf.getvalue()


def _admin(client: TestClient) -> dict:
    account = register_user(client, "csamops", "csamops@test.com")
    make_admin("csamops@test.com")
    admin_session(client, "csamops@test.com")
    return account


def _itinerary(client: TestClient, token: str) -> str:
    r = client.post(
        "/itineraries/",
        json={"title": "Trip", "currency": "EUR", "visibility": "public"},
        headers=auth_headers(token),
    )
    assert r.status_code == 201, r.json()
    return r.json()["id"]


def _upload(client, headers, path):
    return client.post(
        path,
        files={"file": ("image.jpg", _make_jpeg(), "image/jpeg")},
        headers=headers,
    )


def _takedown(client: TestClient, path: str):
    return client.post(
        "/admin/legal/takedown", data={"path": path},
        auth=ADMIN_BASIC, follow_redirects=False,
    )


def _user(user_id: str) -> User:
    db = TestingSessionLocal()
    try:
        return db.get(User, uuid.UUID(user_id))
    finally:
        db.close()


def _rows(model, **filters) -> list:
    db = TestingSessionLocal()
    try:
        q = db.query(model)
        for column, value in filters.items():
            q = q.filter(getattr(model, column) == value)
        return q.all()
    finally:
        db.close()


@pytest.fixture(autouse=True)
def _temp_storage(tmp_path):
    from app.storage.filesystem import FilesystemStorage
    store = FilesystemStorage(str(tmp_path), "/uploads")
    with patch("app.services.image_service.storage", return_value=store), \
         patch("app.services.admin_service.storage", return_value=store), \
         patch("app.routers.users.storage", return_value=store), \
         patch("app.routers.itineraries.storage", return_value=store):
        yield store


# ---------------------------------------------------------------------------
# Path parsing — the operator pastes whatever the digest email gave them
# ---------------------------------------------------------------------------

class TestParseStorageKey:
    def test_accepts_the_three_key_shapes(self):
        entity = uuid.uuid4()
        for folder, kind in (
            ("avatars", "avatar"),
            ("covers", "user_cover"),
            ("itineraries", "itinerary_cover"),
        ):
            parsed = admin_service.parse_storage_key(f"{folder}/{entity}.jpg")
            assert parsed == (kind, entity, f"{folder}/{entity}.jpg")

    @pytest.mark.parametrize("template", [
        "https://images.ntripi.app/avatars/{id}.jpg",
        "/avatars/{id}.jpg",
        "avatars/{id}.jpg?v=1755012345678",
        "/uploads/avatars/{id}.jpg",
        "  avatars/{id}.jpg  ",
    ])
    def test_normalises_urls_prefixes_and_cache_busters(self, template):
        entity = uuid.uuid4()
        parsed = admin_service.parse_storage_key(template.format(id=entity))
        assert parsed == ("avatar", entity, f"avatars/{entity}.jpg")

    @pytest.mark.parametrize("path", [
        "", "   ", "avatars/not-a-uuid.jpg", "unknown/{}.jpg".format(uuid.uuid4()),
        "avatars/", "https://images.ntripi.app/", "../../etc/passwd",
    ])
    def test_refuses_anything_it_did_not_write(self, path):
        # Guessing at an unrecognised path could suspend an unrelated account.
        assert admin_service.parse_storage_key(path) is None


# ---------------------------------------------------------------------------
# The takedown itself
# ---------------------------------------------------------------------------

class TestCsamTakedown:
    def test_itinerary_cover_takedown(self, client, admin_enabled, _temp_storage):
        alice = register_user(client, "csamup", "csamup@test.com")
        it_id = _itinerary(client, alice["access_token"])
        assert _upload(
            client, auth_headers(alice["access_token"]), f"/itineraries/{it_id}/image"
        ).status_code == 200
        stored = _temp_storage._base / f"itineraries/{it_id}.jpg"
        assert stored.exists()
        expected_hash = __import__("hashlib").sha256(stored.read_bytes()).hexdigest()

        db = TestingSessionLocal()
        try:
            before = db.get(Itinerary, uuid.UUID(it_id)).updated_at
        finally:
            db.close()

        _admin(client)
        r = _takedown(client, f"itineraries/{it_id}.jpg")
        assert r.status_code == 303

        # Object gone, cover cleared, itinerary marked rejected.
        assert not stored.exists()
        db = TestingSessionLocal()
        try:
            it = db.get(Itinerary, uuid.UUID(it_id))
            assert it.cover_image_url is None
            assert it.moderation_status == "rejected"
            # updated_at IS the ETag — a moderation write must not move it.
            assert it.updated_at == before
        finally:
            db.close()

        # Evidence: hashed before deletion, and purge-exempt.
        logs = _rows(ImageModerationLog, action="rejected_csam")
        assert len(logs) == 1
        assert logs[0].image_hash == expected_hash
        assert logs[0].labels[0]["provider"] == "cloudflare"
        assert logs[0].labels[0]["object_present"] is True
        assert logs[0].target_itinerary_id == uuid.UUID(it_id)

        # Uploader locked out, tokens revoked.
        assert _user(alice["user_id"]).is_active is False
        live = [
            t for t in _rows(RefreshToken, user_id=uuid.UUID(alice["user_id"]))
            if t.revoked_at is None
        ]
        assert live == []

        # Escalation opened in the lane that demands a closure note.
        escalations = _rows(LegalEscalation)
        assert len(escalations) == 1
        assert escalations[0].source == "hash_match"
        assert escalations[0].target_type == "user"
        assert escalations[0].target_id == uuid.UUID(alice["user_id"])
        assert escalations[0].closed_at is None

        # One operator ban row, carrying the evidence hash in its snapshot.
        bans = _rows(ModerationLog, action="ban")
        assert len(bans) == 1
        assert bans[0].admin_user_id is not None
        assert bans[0].content_snapshot["image_hash"] == expected_hash
        assert expected_hash in bans[0].reason

    def test_avatar_takedown_clears_the_url(self, client, admin_enabled, _temp_storage):
        alice = register_user(client, "csamav", "csamav@test.com")
        assert _upload(
            client, auth_headers(alice["access_token"]), "/users/me/avatar"
        ).status_code == 200
        assert _user(alice["user_id"]).avatar_url is not None

        _admin(client)
        assert _takedown(client, f"avatars/{alice['user_id']}.jpg").status_code == 303

        user = _user(alice["user_id"])
        assert user.avatar_url is None
        assert user.is_active is False
        assert _rows(ImageModerationLog, action="rejected_csam")[0].target_kind == "avatar"

    def test_uploader_is_never_notified(self, client, admin_enabled, monkeypatch,
                                        _temp_storage):
        """A notice would tell someone whose upload matched a law-enforcement
        corpus exactly what was detected."""
        sent: list = []
        monkeypatch.setattr(
            "app.services.admin_service.email_service.send_email",
            lambda to, subject, html: sent.append(to),
        )
        alice = register_user(client, "csamquiet", "csamquiet@test.com")
        _upload(client, auth_headers(alice["access_token"]), "/users/me/avatar")
        _admin(client)
        sent.clear()  # drop the registration mail; only the takedown is under test
        _takedown(client, f"avatars/{alice['user_id']}.jpg")
        assert sent == []

    def test_locks_the_account_on_the_next_request(self, client, admin_enabled,
                                                   _temp_storage):
        alice = register_user(client, "csamlock", "csamlock@test.com")
        hdrs = auth_headers(alice["access_token"])
        _upload(client, hdrs, "/users/me/avatar")
        _admin(client)
        _takedown(client, f"avatars/{alice['user_id']}.jpg")

        r = client.get("/users/me", headers=hdrs)
        assert r.status_code == 403
        assert r.json()["code"] == "account_deactivated"

    def test_missing_object_still_suspends_and_escalates(self, client, admin_enabled,
                                                         _temp_storage):
        """Cloudflare's digest is daily — the object may already be gone. The
        account action must still happen; only the hash is unavailable."""
        alice = register_user(client, "csamgone", "csamgone@test.com")
        _admin(client)
        assert _takedown(client, f"avatars/{alice['user_id']}.jpg").status_code == 303

        assert _user(alice["user_id"]).is_active is False
        log = _rows(ImageModerationLog, action="rejected_csam")[0]
        assert log.image_hash == admin_service.HASH_UNAVAILABLE
        assert log.labels[0]["object_present"] is False
        assert len(_rows(LegalEscalation)) == 1

    def test_repeat_takedown_is_idempotent(self, client, admin_enabled, _temp_storage):
        alice = register_user(client, "csamdup", "csamdup@test.com")
        _upload(client, auth_headers(alice["access_token"]), "/users/me/avatar")
        _admin(client)
        path = f"avatars/{alice['user_id']}.jpg"
        assert _takedown(client, path).status_code == 303
        assert _takedown(client, path).status_code == 303

        # One open escalation (escalate dedupes); both attempts are evidence.
        assert len(_rows(LegalEscalation)) == 1
        assert len(_rows(ImageModerationLog, action="rejected_csam")) == 2
        assert _user(alice["user_id"]).is_active is False

    def test_legal_page_renders_form_and_takedown_result(self, client, admin_enabled,
                                                         _temp_storage):
        alice = register_user(client, "csampage", "csampage@test.com")
        _upload(client, auth_headers(alice["access_token"]), "/users/me/avatar")
        _admin(client)
        _takedown(client, f"avatars/{alice['user_id']}.jpg")

        page = client.get("/admin/legal", auth=ADMIN_BASIC)
        assert page.status_code == 200
        assert "/admin/legal/takedown" in page.text          # the paste form
        assert "Cloudflare hash match" in page.text          # the escalation row

    def test_unknown_path_changes_nothing(self, client, admin_enabled, _temp_storage):
        alice = register_user(client, "csamsafe", "csamsafe@test.com")
        _upload(client, auth_headers(alice["access_token"]), "/users/me/avatar")
        _admin(client)

        r = _takedown(client, "wat/12345.png")
        assert r.status_code == 303
        assert "error=" in r.headers["location"]
        assert _user(alice["user_id"]).is_active is True
        assert _rows(ImageModerationLog, action="rejected_csam") == []
        assert _rows(LegalEscalation) == []

    def test_path_for_a_deleted_account_changes_nothing(self, client, admin_enabled,
                                                        _temp_storage):
        _admin(client)
        r = _takedown(client, f"avatars/{uuid.uuid4()}.jpg")
        assert r.status_code == 303
        assert "error=" in r.headers["location"]
        assert _rows(ImageModerationLog, action="rejected_csam") == []


# ---------------------------------------------------------------------------
# Retention — the evidence row outlives the 90-day purge
# ---------------------------------------------------------------------------

class TestCsamRetention:
    def test_csam_rows_survive_a_purge_that_removes_ordinary_ones(
        self, client, monkeypatch, _temp_storage
    ):
        old = datetime.now(timezone.utc) - timedelta(days=91)
        db = TestingSessionLocal()
        try:
            db.add(ImageModerationLog(
                image_hash="a" * 64, target_kind="avatar",
                action="approved", labels=[], created_at=old,
            ))
            db.add(ImageModerationLog(
                image_hash="b" * 64, target_kind="avatar",
                action="rejected_csam", labels=[], created_at=old,
            ))
            db.commit()
        finally:
            db.close()

        # Any scan runs the opportunistic purge.
        from app.config import get_settings
        from app.services import moderation_service
        s = get_settings()
        monkeypatch.setattr(s, "MODERATION_ENABLED", True)
        monkeypatch.setattr(s, "MODERATION_AWS_ACCESS_KEY_ID", "k")
        monkeypatch.setattr(s, "MODERATION_AWS_SECRET_ACCESS_KEY", "s")
        monkeypatch.setattr(s, "MODERATION_AWS_REGION", "eu-west-1")

        class _Stub:
            def detect_moderation_labels(self, *, Image, MinConfidence):  # noqa: N803
                return {"ModerationLabels": []}

        monkeypatch.setattr(moderation_service, "_rekognition_client", lambda s: _Stub())

        alice = register_user(client, "csamret", "csamret@test.com")
        assert _upload(
            client, auth_headers(alice["access_token"]), "/users/me/avatar"
        ).status_code == 200

        actions = sorted(row.action for row in _rows(ImageModerationLog))
        assert actions == ["approved", "rejected_csam"]  # the old approved row is gone
        assert _rows(ImageModerationLog, action="rejected_csam")[0].image_hash == "b" * 64
