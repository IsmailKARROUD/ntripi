"""
test_image_moderation.py — Tests for the backend AWS Rekognition moderation tier.

Covers the three upload endpoints (itinerary cover, avatar, user cover) through
the shared process_and_store seam. The Rekognition client is stubbed via
monkeypatching moderation_service._rekognition_client; storage is redirected to
a per-test temp dir (patched in image_service — the actual save funnel — so
"file absent on reject" assertions are reliable); flag emails are captured
by monkeypatching send_email as imported in moderation_service, and outage
alerts by patching it as imported in operator_alerts, which throttles them.

Default behaviour (moderation disabled) is asserted first so the rest of the
suite proves the opt-in scan doesn't change existing upload flows.
"""

from __future__ import annotations

import io
import logging
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pytest
from botocore.exceptions import ClientError
from fastapi.testclient import TestClient
from PIL import Image

from conftest import TestingSessionLocal, auth_headers, register_user
from app.config import get_settings
from app.models.image_moderation_log import ImageModerationLog
from app.models.itinerary import Itinerary
from app.services import moderation_service, operator_alerts


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
    raises (`error`, else a generic outage), mirroring detect_moderation_labels'
    signature."""

    def __init__(self, labels: list[dict] | None = None, raises: bool = False,
                 error: Exception | None = None):
        self._labels = labels or []
        self._raises = raises
        self._error = error

    def detect_moderation_labels(self, *, Image, MinConfidence):  # noqa: N803
        if self._error is not None:
            raise self._error
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


def _stub_rekognition(monkeypatch, labels=None, raises=False, error=None) -> None:
    stub = _StubRekognition(labels=labels, raises=raises, error=error)
    monkeypatch.setattr(moderation_service, "_rekognition_client", lambda settings: stub)


def _capture_emails(monkeypatch) -> list[dict]:
    sent: list[dict] = []
    monkeypatch.setattr(
        "app.services.moderation_service.send_email",
        lambda to, subject, html: sent.append({"to": to, "subject": subject, "html": html}),
    )
    return sent


def _capture_alerts(monkeypatch) -> list[dict]:
    sent: list[dict] = []
    monkeypatch.setattr(
        "app.services.operator_alerts.send_email",
        lambda to, subject, html: sent.append({"to": to, "subject": subject, "html": html}),
    )
    return sent


def _raise_mail_outage(to, subject, html):
    raise RuntimeError("mail provider down")


def _an_hour_later(monkeypatch) -> None:
    """Move operator_alerts' clock past the cooldown — no sleeping."""
    later = datetime.now(timezone.utc) + timedelta(minutes=61)
    monkeypatch.setattr(operator_alerts, "_now", lambda: later)


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


def _set_itinerary_status(it_id: str, status: str) -> None:
    import uuid
    db = TestingSessionLocal()
    try:
        db.get(Itinerary, uuid.UUID(it_id)).moderation_status = status
        db.commit()
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
        assert sent == []  # no flag email; the outage alert is TestOperatorAlerts'


# ---------------------------------------------------------------------------
# Operator alerts — a scan that cannot run emails OPERATOR_EMAIL, hourly
# ---------------------------------------------------------------------------

_OPS = "ops@example.com"
_UNAVAILABLE = "[Ntripi] Image moderation unavailable — uploads stored unscanned"
_NOT_CONFIGURED = "[Ntripi] Image moderation not configured — uploads stored unscanned"
_SUGGESTIVE = [{"Name": "Suggestive", "ParentName": "", "Confidence": 60.0}]


class TestOperatorAlerts:
    def test_failed_scan_alerts_once_an_hour(self, client, monkeypatch, _temp_storage):
        _enable_moderation(monkeypatch)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", _OPS)
        _stub_rekognition(monkeypatch, raises=True)
        alerts = _capture_alerts(monkeypatch)
        hdrs = auth_headers(register_user(client, "mod_out", "modout@test.com")["access_token"])

        assert _upload(client, hdrs, "/users/me/avatar").status_code == 200
        assert _upload(client, hdrs, "/users/me/avatar").status_code == 200
        assert len(alerts) == 1                     # the second failure is suppressed
        assert alerts[0]["to"] == _OPS
        assert alerts[0]["subject"] == _UNAVAILABLE
        assert "/admin/flagged" in alerts[0]["html"]

        _an_hour_later(monkeypatch)
        assert _upload(client, hdrs, "/users/me/avatar").status_code == 200
        assert len(alerts) == 2

    def test_scans_that_answer_send_no_alert(self, client, monkeypatch, _temp_storage):
        """Clean, flagged and rejected images were all scanned: nothing to say
        about the tier. The flag still sends its own email."""
        _enable_moderation(monkeypatch)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", _OPS)
        alerts = _capture_alerts(monkeypatch)
        flag_emails = _capture_emails(monkeypatch)
        hdrs = auth_headers(register_user(client, "mod_ans", "modans@test.com")["access_token"])

        for labels, expected in (
            ([], 200),
            (_SUGGESTIVE, 200),
            ([{"Name": "Explicit Nudity", "ParentName": "", "Confidence": 95.0}], 422),
        ):
            _stub_rekognition(monkeypatch, labels=labels)
            assert _upload(client, hdrs, "/users/me/avatar").status_code == expected

        assert alerts == []
        assert [e["subject"] for e in flag_emails] == ["[Ntripi] Image flagged: avatar"]

    def test_switched_on_without_credentials_alerts_once_an_hour(
        self, client, monkeypatch, _temp_storage
    ):
        _enable_moderation(monkeypatch)
        monkeypatch.setattr(get_settings(), "MODERATION_AWS_REGION", None)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", _OPS)
        _stub_rekognition(monkeypatch, labels=[])   # a scan would leave a row
        alerts = _capture_alerts(monkeypatch)
        alice = register_user(client, "mod_nocfg", "modnocfg@test.com")
        hdrs = auth_headers(alice["access_token"])
        it_id = _create_itinerary(client, alice["access_token"])

        for _ in range(2):
            assert _upload(client, hdrs, f"/itineraries/{it_id}/image").status_code == 200
        # Stored exactly as before: unscanned, approved, no audit row.
        assert _temp_storage._base.joinpath(f"itineraries/{it_id}.jpg").exists()
        assert _itinerary_status(it_id) == "approved"
        assert _count_logs() == 0
        assert len(alerts) == 1
        assert alerts[0]["subject"] == _NOT_CONFIGURED
        assert "MODERATION_AWS_REGION" in alerts[0]["html"]

        _an_hour_later(monkeypatch)
        assert _upload(client, hdrs, f"/itineraries/{it_id}/image").status_code == 200
        assert len(alerts) == 2

    def test_switched_off_sends_nothing(self, client, monkeypatch, _temp_storage):
        """MODERATION_ENABLED=False is a choice, not a failure."""
        monkeypatch.setattr(get_settings(), "MODERATION_ENABLED", False)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", _OPS)
        alerts = _capture_alerts(monkeypatch)
        hdrs = auth_headers(register_user(client, "mod_offa", "modoffa@test.com")["access_token"])

        assert _upload(client, hdrs, "/users/me/avatar").status_code == 200
        assert alerts == []

    def test_each_situation_has_its_own_hour(self, client, monkeypatch, _temp_storage):
        _enable_moderation(monkeypatch)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", _OPS)
        alerts = _capture_alerts(monkeypatch)
        hdrs = auth_headers(register_user(client, "mod_two", "modtwo@test.com")["access_token"])

        monkeypatch.setattr(get_settings(), "MODERATION_AWS_REGION", None)
        assert _upload(client, hdrs, "/users/me/avatar").status_code == 200
        monkeypatch.setattr(get_settings(), "MODERATION_AWS_REGION", "eu-west-1")
        _stub_rekognition(monkeypatch, raises=True)
        assert _upload(client, hdrs, "/users/me/avatar").status_code == 200

        assert [a["subject"] for a in alerts] == [_NOT_CONFIGURED, _UNAVAILABLE]

    def test_unset_operator_email_logs_a_warning_instead(
        self, client, monkeypatch, _temp_storage, caplog
    ):
        _enable_moderation(monkeypatch)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", None)
        _stub_rekognition(monkeypatch, raises=True)
        alerts = _capture_alerts(monkeypatch)
        alice = register_user(client, "mod_noops", "modnoops@test.com")
        it_id = _create_itinerary(client, alice["access_token"])

        with caplog.at_level(logging.WARNING, logger="app.services.operator_alerts"):
            r = _upload(client, auth_headers(alice["access_token"]),
                        f"/itineraries/{it_id}/image")

        assert r.status_code == 200
        assert _temp_storage._base.joinpath(f"itineraries/{it_id}.jpg").exists()
        assert alerts == []
        warnings = [
            rec.getMessage() for rec in caplog.records
            if rec.name == "app.services.operator_alerts" and rec.levelno == logging.WARNING
        ]
        assert len(warnings) == 1
        assert warnings[0].startswith("image moderation unavailable: scan failed (RuntimeError)")

    def test_a_failed_alert_email_never_fails_the_upload(
        self, client, monkeypatch, _temp_storage
    ):
        _enable_moderation(monkeypatch)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", _OPS)
        _stub_rekognition(monkeypatch, raises=True)
        monkeypatch.setattr("app.services.operator_alerts.send_email", _raise_mail_outage)
        alice = register_user(client, "mod_mailx", "modmailx@test.com")
        it_id = _create_itinerary(client, alice["access_token"])

        r = _upload(client, auth_headers(alice["access_token"]), f"/itineraries/{it_id}/image")

        assert r.status_code == 200
        assert _temp_storage._base.joinpath(f"itineraries/{it_id}.jpg").exists()
        assert _itinerary_status(it_id) == "pending"
        assert _get_log().action == "error_allowed"

    def test_a_failed_flag_email_never_fails_the_upload(
        self, client, monkeypatch, _temp_storage
    ):
        _enable_moderation(monkeypatch)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", _OPS)
        _stub_rekognition(monkeypatch, labels=_SUGGESTIVE)
        monkeypatch.setattr("app.services.moderation_service.send_email", _raise_mail_outage)
        alice = register_user(client, "mod_flagx", "modflagx@test.com")
        it_id = _create_itinerary(client, alice["access_token"])

        r = _upload(client, auth_headers(alice["access_token"]), f"/itineraries/{it_id}/image")

        assert r.status_code == 200
        assert _temp_storage._base.joinpath(f"itineraries/{it_id}.jpg").exists()
        assert _itinerary_status(it_id) == "flagged"
        assert _get_log().action == "flagged"

    @pytest.mark.parametrize("error,code", [
        (ClientError(
            {"Error": {"Code": "UnrecognizedClientException",
                       "Message": "The security token included in the request is invalid."}},
            "DetectModerationLabels",
        ), "UnrecognizedClientException"),
        # A provider whose HTTP client puts the request URL, key included, in its message.
        (RuntimeError("GET https://vision.example/v1/annotate?key=SECRET-KEY-123 failed"), None),
    ], ids=["botocore", "other-provider"])
    def test_alert_names_the_error_never_its_message_or_the_upload(
        self, client, monkeypatch, _temp_storage, error, code
    ):
        _enable_moderation(monkeypatch)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", _OPS)
        _stub_rekognition(monkeypatch, error=error)
        alerts = _capture_alerts(monkeypatch)
        alice = register_user(client, "mod_priv", "modpriv@test.com")

        r = _upload(client, auth_headers(alice["access_token"]), "/users/me/avatar")
        assert r.status_code == 200

        email = alerts[0]["subject"] + alerts[0]["html"]
        assert f"<strong>Exception:</strong> {type(error).__name__}" in email
        assert ("Provider error code" in email) == (code is not None)
        if code is not None:
            assert code in email
        assert "(UTC)" in email
        for leak in (
            "security token", "SECRET-KEY-123", "vision.example",   # the message
            "avatars/", str(alice["user_id"]),                      # the storage key
            "mod_priv", "modpriv@test.com",                         # the uploader
        ):
            assert leak not in email


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

    def test_cover_delete_leaves_moderation_status_alone(self, client, monkeypatch, _temp_storage):
        """The column also carries text flags, so the owner removing a cover
        cannot tell which tier raised it — only a moderator lowers it."""
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
        assert _itinerary_status(it_id) == "flagged"

    def test_cover_delete_cannot_clear_a_moderator_reject(self, client, _temp_storage):
        alice = register_user(client, "mod_rej", "modrej@test.com")
        hdrs = auth_headers(alice["access_token"])
        it_id = _create_itinerary(client, alice["access_token"])
        _set_itinerary_status(it_id, "rejected")  # remove_flagged_image's outcome

        r = client.delete(f"/itineraries/{it_id}/image", headers=hdrs)
        assert r.status_code == 204
        assert _itinerary_status(it_id) == "rejected"

    def test_clean_cover_upload_does_not_clear_a_text_flag(self, client, _temp_storage):
        alice = register_user(client, "mod_txt", "modtxt@test.com")
        hdrs = auth_headers(alice["access_token"])
        it_id = _create_itinerary(client, alice["access_token"])
        _set_itinerary_status(it_id, "flagged")  # raised by the text tier

        r = _upload(client, hdrs, f"/itineraries/{it_id}/image")  # moderation off
        assert r.status_code == 200
        assert _itinerary_status(it_id) == "flagged"
