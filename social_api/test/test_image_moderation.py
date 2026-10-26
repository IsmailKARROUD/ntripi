"""
test_image_moderation.py — Tests for the backend image moderation tier, with
either provider MODERATION_PROVIDER can select: AWS Rekognition or Google Cloud
Vision.

Covers the three upload endpoints (itinerary cover, avatar, user cover) through
the shared process_and_store seam. The Rekognition client is stubbed via
monkeypatching moderation_service._rekognition_client. Cloud Vision is stubbed
lower, at requests' HTTPAdapter.send, so the real request is built, sent through
the timing hook and parsed; only its bearer is stubbed (_vision_access_token).
Storage is redirected to a per-test temp dir (patched in image_service — the
actual save funnel — so "file absent on reject" assertions are reliable); flag
emails are captured by monkeypatching send_email as imported in
moderation_service, and outage alerts by patching it as imported in
operator_alerts, which throttles them.

Default behaviour (moderation disabled) is asserted first so the rest of the
suite proves the opt-in scan doesn't change existing upload flows.
"""

from __future__ import annotations

import asyncio
import base64
import io
import json
import logging
import re
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import patch

import pytest
import requests
from botocore.exceptions import ClientError
from fastapi.testclient import TestClient
from google.auth.exceptions import RefreshError
from PIL import Image
from pydantic import ValidationError

from conftest import TestingSessionLocal, auth_headers, register_user
from app.config import IMAGE_MODERATION_PROVIDERS, Settings, get_settings
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


def _thread_kind() -> str:
    """Where a send ran: a worker thread has no running event loop."""
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        return "worker thread"
    return "event loop"


def _http_error() -> requests.HTTPError:
    """What a provider called through `requests` raises: the request URL, key
    included, sits in the message, and .response is a Response, not a dict."""
    response = requests.Response()
    response.status_code = 403
    response.url = "https://vision.example/v1/annotate?key=SECRET-KEY-123"
    return requests.HTTPError(
        f"403 Client Error: Forbidden for url: {response.url}", response=response,
    )


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
        _enable_moderation(monkeypatch)   # the secret stays set, as "test-secret"
        monkeypatch.setattr(get_settings(), "MODERATION_AWS_ACCESS_KEY_ID", None)
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
        html = alerts[0]["html"]
        assert "MODERATION_AWS_ACCESS_KEY_ID, MODERATION_AWS_REGION" in html
        assert "MODERATION_AWS_SECRET_ACCESS_KEY" not in html   # set, so not missing
        assert "test-secret" not in html                         # names, never values

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

    @pytest.mark.parametrize("region, line", [
        ("eu-west-1", "image moderation unavailable: scan failed (RuntimeError), "
                      "uploads stored unscanned"),
        (None, "image moderation not configured: missing MODERATION_AWS_REGION, "
               "uploads stored unscanned"),
    ], ids=["scan-failed", "not-configured"])
    def test_unset_operator_email_logs_a_warning_instead(
        self, client, monkeypatch, _temp_storage, caplog, region, line
    ):
        _enable_moderation(monkeypatch)
        monkeypatch.setattr(get_settings(), "MODERATION_AWS_REGION", region)
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
        assert warnings == [line]

    @pytest.mark.parametrize("region, status", [
        ("eu-west-1", "pending"), (None, "approved"),
    ], ids=["scan-failed", "not-configured"])
    def test_an_alert_that_breaks_never_fails_the_upload(
        self, client, monkeypatch, _temp_storage, region, status
    ):
        """The alert runs in the fail-open branch: a bug in it must never turn
        an upload that is being allowed into a 500."""
        _enable_moderation(monkeypatch)
        monkeypatch.setattr(get_settings(), "MODERATION_AWS_REGION", region)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", _OPS)
        _stub_rekognition(monkeypatch, raises=True)

        def broken(*args, **kwargs):
            raise RuntimeError("bug in the alert")

        monkeypatch.setattr(operator_alerts, "notify_operator", broken)
        alice = register_user(client, "mod_brk", "modbrk@test.com")
        it_id = _create_itinerary(client, alice["access_token"])

        r = _upload(client, auth_headers(alice["access_token"]), f"/itineraries/{it_id}/image")

        assert r.status_code == 200
        assert _temp_storage._base.joinpath(f"itineraries/{it_id}.jpg").exists()
        assert _itinerary_status(it_id) == status

    def test_a_cover_saved_through_the_form_alerts_too(
        self, client, monkeypatch, _temp_storage
    ):
        """The app saves covers through the form routes, which reach the scan
        from a worker thread through anyio.from_thread — the alert's own hop to
        a thread must work from there, and the unscanned row must still find
        its trip."""
        _enable_moderation(monkeypatch)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", _OPS)
        _stub_rekognition(monkeypatch, raises=True)
        alerts = _capture_alerts(monkeypatch)
        token = register_user(client, "mod_form", "modform@test.com")["access_token"]

        trips = []
        for title in ("Islands", "Coast walk"):
            r = client.post("/itineraries/form", headers=auth_headers(token), files={
                "fields": (None, json.dumps({"title": title})),
                "image": ("cover.jpg", _make_jpeg(), "image/jpeg"),
            })
            assert r.status_code == 201, r.text
            trips.append(r.json()["id"])
            assert _itinerary_status(trips[-1]) == "pending"

        assert [a["subject"] for a in alerts] == [_UNAVAILABLE]
        db = TestingSessionLocal()
        try:
            rows = db.query(ImageModerationLog).all()
        finally:
            db.close()
        assert {r.action for r in rows} == {"error_allowed"}
        assert sorted(str(r.target_itinerary_id) for r in rows) == sorted(trips)

    @pytest.mark.parametrize("scan, region, sender", [
        ({"labels": _SUGGESTIVE}, "eu-west-1", "moderation_service"),
        ({"raises": True}, "eu-west-1", "operator_alerts"),
        ({"labels": []}, None, "operator_alerts"),
    ], ids=["flag-email", "scan-failed-alert", "not-configured-alert"])
    def test_operator_emails_leave_the_event_loop(
        self, client, monkeypatch, _temp_storage, scan, region, sender
    ):
        """moderate_or_raise runs on the event loop and send_email blocks for
        up to 10 s: sent from the loop, a slow mail provider stalled every
        request on the server."""
        _enable_moderation(monkeypatch)
        monkeypatch.setattr(get_settings(), "MODERATION_AWS_REGION", region)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", _OPS)
        _stub_rekognition(monkeypatch, **scan)
        sent_from: list[str] = []
        monkeypatch.setattr(f"app.services.{sender}.send_email",
                            lambda to, subject, html: sent_from.append(_thread_kind()))
        hdrs = auth_headers(register_user(client, "mod_loop", "modloop@test.com")["access_token"])

        assert _upload(client, hdrs, "/users/me/avatar").status_code == 200
        assert sent_from == ["worker thread"]

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

    @pytest.mark.parametrize("error, code", [
        (ClientError(
            {"Error": {"Code": "UnrecognizedClientException",
                       "Message": "The security token included in the request is invalid."}},
            "DetectModerationLabels",
        ), "UnrecognizedClientException"),
        (_http_error(), None),
    ], ids=["botocore", "requests"])
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


class _WithResponse(Exception):
    def __init__(self, response):
        super().__init__("a message the alert must never read")
        self.response = response


@pytest.mark.parametrize("error, code", [
    (ClientError({"Error": {"Code": "ThrottlingException"}}, "DetectModerationLabels"),
     "ThrottlingException"),
    (ClientError({"Error": {}}, "DetectModerationLabels"), None),
    (_WithResponse({"Error": "not a mapping"}), None),
    (_WithResponse({"Error": {"Code": 403}}), None),
    (_WithResponse({"Error": {"Code": ""}}), None),
    (_http_error(), None),
    (RuntimeError("no response at all"), None),
], ids=["botocore", "botocore-without-code", "error-not-a-dict", "code-not-a-string",
        "empty-code", "requests-response-object", "no-response"])
def test_provider_error_code_reads_botocores_shape(error, code):
    """Duck-typed, so the alert never imports a provider: in botocore's shape
    only a response["Error"]["Code"] string is a code, and a response with no
    readable body carries none."""
    assert moderation_service._provider_error_code(error) == code


def _google_error(status: int, body) -> requests.HTTPError:
    """What the Cloud Vision call raises for a non-2xx answer: the body is
    Google's, the message ours."""
    response = requests.Response()
    response.status_code = status
    response._content = body if isinstance(body, bytes) else json.dumps(body).encode()
    return requests.HTTPError(f"Cloud Vision answered HTTP {status}", response=response)


@pytest.mark.parametrize("error, code", [
    (_google_error(403, {"error": {"status": "PERMISSION_DENIED",
                                   "details": [{"reason": "SERVICE_DISABLED"}]}}),
     "PERMISSION_DENIED/SERVICE_DISABLED"),
    (_google_error(403, {"error": {"status": "PERMISSION_DENIED", "details": [
        {"@type": "type.googleapis.com/google.rpc.Help"}, {"reason": "BILLING_DISABLED"},
    ]}}), "PERMISSION_DENIED/BILLING_DISABLED"),
    (_google_error(401, {"error": {"status": "UNAUTHENTICATED"}}), "UNAUTHENTICATED"),
    (_google_error(500, b"<html>Server Error</html>"), None),
    (_google_error(503, {"error": {"code": 503}}), None),
    (_google_error(403, {"error": {"status": "", "details": [{"reason": "SERVICE_DISABLED"}]}}),
     None),
    (_google_error(403, ["not", "an", "object"]), None),
], ids=["status-and-reason", "reason-after-other-details", "status-only", "html-body",
        "no-status", "empty-status", "body-not-an-object"])
def test_provider_error_code_reads_googles_shape(error, code):
    """Cloud Vision's code is its error.status, plus the first details[].reason
    when there is one — read off the body, never the message."""
    assert moderation_service._provider_error_code(error) == code


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


# ---------------------------------------------------------------------------
# Google Cloud Vision — the same pipeline behind MODERATION_PROVIDER=google_vision
# ---------------------------------------------------------------------------

_VISION_URL = "https://eu-vision.googleapis.com/v1/images:annotate"
_VISION_KEY = json.dumps({"type": "service_account", "project_id": "ntripi-test"})
_CLEAN = {
    "adult": "VERY_UNLIKELY", "spoof": "VERY_UNLIKELY", "medical": "VERY_UNLIKELY",
    "violence": "VERY_UNLIKELY", "racy": "VERY_UNLIKELY",
}


def _enable_google_vision(monkeypatch, reject: str = "VERY_LIKELY", flag: str = "LIKELY") -> None:
    s = get_settings()
    monkeypatch.setattr(s, "MODERATION_ENABLED", True)
    monkeypatch.setattr(s, "MODERATION_PROVIDER", "google_vision")
    monkeypatch.setattr(s, "MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON", _VISION_KEY)
    monkeypatch.setattr(s, "MODERATION_GOOGLE_REJECT_LIKELIHOOD", reject)
    monkeypatch.setattr(s, "MODERATION_GOOGLE_FLAG_LIKELIHOOD", flag)
    # A real bearer needs a real service account; the request is what we test.
    monkeypatch.setattr(moderation_service, "_vision_access_token", lambda settings: "test-bearer")


def _safe_search(**levels) -> dict:
    """A 200 body carrying one SafeSearch annotation, clean unless overridden."""
    return {"responses": [{"safeSearchAnnotation": {**_CLEAN, **levels}}]}


class _FakeVision:
    """Cloud Vision without a network: answers `status` with `body` (a dict as
    JSON, bytes as they are), or raises `error`, and keeps what was sent."""

    def __init__(self, body=None, status: int = 200, error: Exception | None = None):
        self.body = _safe_search() if body is None else body
        self.status = status
        self.error = error
        self.sent: list[tuple[requests.PreparedRequest, dict]] = []

    def send(self, request, **kwargs):
        self.sent.append((request, kwargs))
        if self.error is not None:
            raise self.error
        response = requests.Response()
        response.status_code = self.status
        response.request = request
        response.url = request.url
        response.encoding = "utf-8"
        response._content = (
            self.body if isinstance(self.body, bytes) else json.dumps(self.body).encode()
        )
        return response


def _stub_vision(monkeypatch, **answer) -> _FakeVision:
    """Replace requests' transport, below Session.send — so requests.post, the
    timing hook and the response parsing all run for real. Call it after
    registering users: with PWNED_CHECK_ENABLED, registration uses requests too."""
    fake = _FakeVision(**answer)
    monkeypatch.setattr(requests.adapters.HTTPAdapter, "send",
                        lambda self, request, **kwargs: fake.send(request, **kwargs))
    return fake


def _labels_in(email_html: str) -> str:
    """The labels paragraph of a flag email."""
    return email_html.split("Labels (≥ flag threshold):</strong><br>\n")[1].split("</p>")[0]


class TestGoogleVision:
    def test_a_clean_answer_approves(self, client, monkeypatch, _temp_storage):
        _enable_google_vision(monkeypatch)
        alice = register_user(client, "gv_clean", "gvclean@test.com")
        it_id = _create_itinerary(client, alice["access_token"])
        _stub_vision(monkeypatch)

        r = _upload(client, auth_headers(alice["access_token"]), f"/itineraries/{it_id}/image")

        assert r.status_code == 200
        assert _temp_storage._base.joinpath(f"itineraries/{it_id}.jpg").exists()
        assert _itinerary_status(it_id) == "approved"
        log = _get_log()
        assert (log.action, log.labels, log.provider) == ("approved", [], "google_vision")

    def test_adult_very_likely_rejects_and_stores_nothing(self, client, monkeypatch, _temp_storage):
        _enable_google_vision(monkeypatch)
        sent = _capture_emails(monkeypatch)
        alice = register_user(client, "gv_rej", "gvrej@test.com")
        it_id = _create_itinerary(client, alice["access_token"])
        _stub_vision(monkeypatch, body=_safe_search(adult="VERY_LIKELY"))

        r = _upload(client, auth_headers(alice["access_token"]), f"/itineraries/{it_id}/image")

        assert r.status_code == 422
        assert r.json()["code"] == "image_moderation_rejected"
        assert not _temp_storage._base.joinpath(f"itineraries/{it_id}.jpg").exists()
        log = _get_log()
        assert log.action == "rejected"
        assert log.labels == [{"name": "adult", "likelihood": "VERY_LIKELY"}]
        assert sent == []                          # reject never emails

    def test_racy_likely_flags_and_the_email_names_the_level(
        self, client, monkeypatch, _temp_storage
    ):
        _enable_google_vision(monkeypatch)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", _OPS)
        sent = _capture_emails(monkeypatch)
        alice = register_user(client, "gv_flag", "gvflag@test.com")
        it_id = _create_itinerary(client, alice["access_token"])
        _stub_vision(monkeypatch, body=_safe_search(racy="LIKELY"))

        r = _upload(client, auth_headers(alice["access_token"]), f"/itineraries/{it_id}/image")

        assert r.status_code == 200
        assert _temp_storage._base.joinpath(f"itineraries/{it_id}.jpg").exists()
        assert _itinerary_status(it_id) == "flagged"
        log = _get_log()
        assert log.action == "flagged"
        assert log.labels == [{"name": "racy", "likelihood": "LIKELY"}]
        [email] = sent
        # Google's level, never a percentage: a confidence Google never gave.
        assert _labels_in(email["html"]).strip() == "racy (LIKELY)"

    def test_spoof_alone_approves(self, client, monkeypatch, _temp_storage):
        """spoof detects edited images and memes, not harm."""
        _enable_google_vision(monkeypatch)
        alice = register_user(client, "gv_spoof", "gvspoof@test.com")
        it_id = _create_itinerary(client, alice["access_token"])
        _stub_vision(monkeypatch, body=_safe_search(spoof="VERY_LIKELY"))

        r = _upload(client, auth_headers(alice["access_token"]), f"/itineraries/{it_id}/image")

        assert r.status_code == 200
        assert _itinerary_status(it_id) == "approved"
        assert _get_log().action == "approved"

    @pytest.mark.parametrize("answer", [
        {"error": requests.ConnectionError("connection refused")},
        {"error": requests.ReadTimeout("read timed out")},
        {"status": 500, "body": {"error": {"code": 500, "status": "INTERNAL"}}},
        {"status": 302, "body": b""},
        {"body": b"<html>not json</html>"},
        {"body": {"responses": [{"error": {"code": 3, "message": "Bad image data."}}]}},
        {"body": {"responses": [{}]}},
        {"body": {"responses": []}},
        {"body": _safe_search(adult="UNKNOWN")},
        # proto3 JSON leaves an UNKNOWN out: an absent category was never classified.
        {"body": {"responses": [{"safeSearchAnnotation": {
            "adult": "VERY_UNLIKELY", "spoof": "VERY_UNLIKELY",
            "medical": "VERY_UNLIKELY", "racy": "VERY_UNLIKELY",
        }}]}},
    ], ids=["connection-error", "timeout", "http-500", "non-2xx-redirect", "not-json",
            "per-image-error", "no-annotation", "no-response", "adult-unknown",
            "violence-omitted"])
    def test_every_failed_scan_fails_open_and_alerts_once(
        self, client, monkeypatch, _temp_storage, answer
    ):
        """None of these is a verdict, so none may ever count as an approval."""
        _enable_google_vision(monkeypatch)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", _OPS)
        alerts = _capture_alerts(monkeypatch)
        flag_emails = _capture_emails(monkeypatch)
        alice = register_user(client, "gv_fail", "gvfail@test.com")
        it_id = _create_itinerary(client, alice["access_token"])
        _stub_vision(monkeypatch, **answer)

        r = _upload(client, auth_headers(alice["access_token"]), f"/itineraries/{it_id}/image")

        assert r.status_code == 200
        assert _temp_storage._base.joinpath(f"itineraries/{it_id}.jpg").exists()
        assert _itinerary_status(it_id) == "pending"
        log = _get_log()
        assert (log.action, log.labels, log.provider) == ("error_allowed", [], "google_vision")
        assert [a["subject"] for a in alerts] == [_UNAVAILABLE]
        assert flag_emails == []

    @pytest.mark.parametrize("break_it", ["token", "project"])
    def test_no_bearer_or_no_project_fails_open_without_a_request(
        self, client, monkeypatch, _temp_storage, break_it
    ):
        _enable_google_vision(monkeypatch)
        if break_it == "token":
            def no_token(settings):
                raise RefreshError("invalid_grant: account not found")
            monkeypatch.setattr(moderation_service, "_vision_access_token", no_token)
        else:
            monkeypatch.setattr(get_settings(), "MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON",
                                json.dumps({"type": "service_account"}))
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", _OPS)
        alerts = _capture_alerts(monkeypatch)
        hdrs = auth_headers(register_user(client, "gv_tok", "gvtok@test.com")["access_token"])
        fake = _stub_vision(monkeypatch)

        assert _upload(client, hdrs, "/users/me/avatar").status_code == 200

        assert fake.sent == []
        assert _get_log().action == "error_allowed"
        assert [a["subject"] for a in alerts] == [_UNAVAILABLE]

    def test_a_disabled_api_alert_names_status_and_reason_never_the_message(
        self, client, monkeypatch, _temp_storage, caplog
    ):
        project = "123456789012"
        console = f"https://console.developers.google.com/apis/api/vision.googleapis.com/overview?project={project}"
        _enable_google_vision(monkeypatch)
        monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", _OPS)
        alerts = _capture_alerts(monkeypatch)
        alice = register_user(client, "gv_403", "gv403@test.com")
        _stub_vision(monkeypatch, status=403, body={"error": {
            "code": 403,
            "message": (f"Cloud Vision API has not been used in project {project} before or "
                        f"it is disabled. Enable it by visiting {console} then retry."),
            "status": "PERMISSION_DENIED",
            "details": [
                {"@type": "type.googleapis.com/google.rpc.ErrorInfo", "reason": "SERVICE_DISABLED",
                 "domain": "googleapis.com",
                 "metadata": {"consumer": f"projects/{project}", "service": "vision.googleapis.com",
                              "activationUrl": console}},
                {"@type": "type.googleapis.com/google.rpc.Help",
                 "links": [{"description": "Google developers console API activation",
                            "url": console}]},
            ],
        }})

        with caplog.at_level(logging.WARNING, logger="app.services.operator_alerts"):
            r = _upload(client, auth_headers(alice["access_token"]), "/users/me/avatar")

        assert r.status_code == 200
        email = alerts[0]["subject"] + alerts[0]["html"]
        assert "<strong>Exception:</strong> HTTPError" in email
        assert "<strong>Provider error code:</strong> PERMISSION_DENIED/SERVICE_DISABLED" in email
        assert ("image moderation unavailable: scan failed (HTTPError "
                "PERMISSION_DENIED/SERVICE_DISABLED), uploads stored unscanned") in [
            rec.getMessage() for rec in caplog.records if rec.name == "app.services.operator_alerts"
        ]
        for leak in (project, "console.developers.google.com", "has not been used",
                     "ntripi-test", "test-bearer", "gv_403", "gv403@test.com"):
            assert leak not in email

    def test_the_request_goes_to_the_eu_endpoint_with_the_image_and_nothing_else(
        self, client, monkeypatch, _temp_storage
    ):
        """No user id, no email, no storage key, no URL — the text providers' rule."""
        _enable_google_vision(monkeypatch)
        alice = register_user(client, "gv_body", "gvbody@test.com")
        fake = _stub_vision(monkeypatch)

        assert _upload(client, auth_headers(alice["access_token"]), "/users/me/avatar").status_code == 200

        [(request, kwargs)] = fake.sent
        stored = _temp_storage._base.joinpath(f"avatars/{alice['user_id']}.jpg").read_bytes()
        assert (request.method, request.url) == ("POST", _VISION_URL)
        assert json.loads(request.body) == {
            "requests": [{
                "image": {"content": base64.b64encode(stored).decode("ascii")},
                "features": [{"type": "SAFE_SEARCH_DETECTION"}],
            }],
            "parent": "projects/ntripi-test/locations/eu",
        }
        assert request.headers["Authorization"] == "Bearer test-bearer"
        assert kwargs["timeout"] == (3, 3)          # Rekognition's budget

    def test_a_scan_shows_in_the_slow_request_log(self, client, monkeypatch, _temp_storage, caplog):
        """Plain requests, not the gRPC SDK: the outbound timing hook sees it."""
        _enable_google_vision(monkeypatch)
        monkeypatch.setattr(get_settings(), "SLOW_REQUEST_LOG_MS", 0)
        hdrs = auth_headers(register_user(client, "gv_time", "gvtime@test.com")["access_token"])
        _stub_vision(monkeypatch)

        with caplog.at_level(logging.WARNING, logger="app.middleware.request_timing"):
            assert _upload(client, hdrs, "/users/me/avatar").status_code == 200

        [line] = [
            rec.getMessage() for rec in caplog.records
            if rec.name == "app.middleware.request_timing"
            and " POST /users/me/avatar " in rec.getMessage()
        ]
        assert re.search(r" ext=eu-vision\.googleapis\.com:\d+ms/1 ", line)

    @pytest.mark.parametrize("provider, named, absent", [
        ("google_vision", "missing: <code>MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON</code>",
         "MODERATION_AWS"),
        ("rekognition", "missing: <code>MODERATION_AWS_ACCESS_KEY_ID, "
                        "MODERATION_AWS_SECRET_ACCESS_KEY, MODERATION_AWS_REGION</code>",
         "MODERATION_GOOGLE"),
    ], ids=["google_vision", "rekognition"])
    def test_not_configured_names_only_the_selected_providers_settings(
        self, client, monkeypatch, _temp_storage, provider, named, absent
    ):
        """Both providers unconfigured; each alert names its own gap only."""
        s = get_settings()
        monkeypatch.setattr(s, "MODERATION_ENABLED", True)
        monkeypatch.setattr(s, "MODERATION_PROVIDER", provider)
        monkeypatch.setattr(s, "OPERATOR_EMAIL", _OPS)
        for name in ("MODERATION_AWS_ACCESS_KEY_ID", "MODERATION_AWS_SECRET_ACCESS_KEY",
                     "MODERATION_AWS_REGION", "MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON"):
            monkeypatch.setattr(s, name, None)
        alerts = _capture_alerts(monkeypatch)
        hdrs = auth_headers(register_user(client, "gv_nocfg", "gvnocfg@test.com")["access_token"])

        assert _upload(client, hdrs, "/users/me/avatar").status_code == 200

        assert _count_logs() == 0
        [alert] = alerts
        assert alert["subject"] == _NOT_CONFIGURED
        assert named in alert["html"]
        assert absent not in alert["html"]

    @pytest.mark.parametrize("provider, scan, action", [
        ("rekognition", {"labels": []}, "approved"),
        ("rekognition", {"labels": _SUGGESTIVE}, "flagged"),
        ("rekognition", {"labels": [{"Name": "Explicit Nudity", "ParentName": "",
                                     "Confidence": 95.0}]}, "rejected"),
        ("rekognition", {"raises": True}, "error_allowed"),
        ("google_vision", {}, "approved"),
        ("google_vision", {"body": _safe_search(racy="LIKELY")}, "flagged"),
        ("google_vision", {"body": _safe_search(violence="VERY_LIKELY")}, "rejected"),
        ("google_vision", {"status": 503, "body": b""}, "error_allowed"),
    ])
    def test_every_scan_row_names_its_provider(
        self, client, monkeypatch, _temp_storage, provider, scan, action
    ):
        hdrs = auth_headers(register_user(client, "gv_prov", "gvprov@test.com")["access_token"])
        if provider == "rekognition":
            _enable_moderation(monkeypatch)
            _stub_rekognition(monkeypatch, **scan)
        else:
            _enable_google_vision(monkeypatch)
            _stub_vision(monkeypatch, **scan)
        _capture_emails(monkeypatch)
        _capture_alerts(monkeypatch)

        _upload(client, hdrs, "/users/me/avatar")

        log = _get_log()
        assert (log.action, log.provider) == (action, provider)


@pytest.mark.parametrize("levels, reject, flag, action, labels", [
    ({}, "VERY_LIKELY", "LIKELY", "approved", []),
    ({"adult": "LIKELY"}, "VERY_LIKELY", "LIKELY", "flagged",
     [{"name": "adult", "likelihood": "LIKELY"}]),
    ({"adult": "VERY_LIKELY", "racy": "VERY_LIKELY"}, "VERY_LIKELY", "LIKELY", "rejected",
     [{"name": "adult", "likelihood": "VERY_LIKELY"}, {"name": "racy", "likelihood": "VERY_LIKELY"}]),
    ({"racy": "VERY_LIKELY"}, "LIKELY", "LIKELY", "flagged",
     [{"name": "racy", "likelihood": "VERY_LIKELY"}]),
    ({"medical": "POSSIBLE"}, "LIKELY", "POSSIBLE", "flagged",
     [{"name": "medical", "likelihood": "POSSIBLE"}]),
    ({"violence": "LIKELY"}, "LIKELY", "POSSIBLE", "rejected",
     [{"name": "violence", "likelihood": "LIKELY"}]),
    ({"adult": "POSSIBLE"}, "VERY_LIKELY", "LIKELY", "approved", []),
    ({"spoof": "VERY_LIKELY"}, "VERY_LIKELY", "LIKELY", "approved", []),
    ({"racy": "UNKNOWN", "medical": "UNKNOWN"}, "VERY_LIKELY", "LIKELY", "approved", []),
], ids=["clean", "adult-flags", "adult-rejects", "racy-never-rejects", "flag-level-is-read",
        "reject-level-is-read", "below-the-flag-level", "spoof-is-ignored",
        "unknown-racy-or-medical-is-no-signal"])
def test_the_verdict_reads_googles_levels(levels, reject, flag, action, labels):
    settings = SimpleNamespace(
        MODERATION_GOOGLE_REJECT_LIKELIHOOD=reject, MODERATION_GOOGLE_FLAG_LIKELIHOOD=flag,
    )
    verdict = moderation_service._google_vision_verdict({**_CLEAN, **levels}, settings)
    assert (verdict.action, verdict.labels) == (action, labels)


def test_every_configurable_provider_has_a_scanner():
    """MODERATION_PROVIDER accepts exactly the names the seam can run."""
    assert set(moderation_service._PROVIDERS) == set(IMAGE_MODERATION_PROVIDERS)


# ---------------------------------------------------------------------------
# Configuration — a provider setup we cannot run refuses to boot
# ---------------------------------------------------------------------------

def _config(**overrides) -> Settings:
    # _env_file=None keeps a developer's local .env out of these assertions.
    return Settings(
        DATABASE_URL="postgresql://user:pass@localhost/db", SECRET_KEY="x" * 32,
        _env_file=None, **overrides,
    )


class TestProviderConfig:
    def test_defaults_keep_rekognition(self):
        s = _config()
        assert (s.MODERATION_PROVIDER, s.MODERATION_GOOGLE_REJECT_LIKELIHOOD,
                s.MODERATION_GOOGLE_FLAG_LIKELIHOOD) == ("rekognition", "VERY_LIKELY", "LIKELY")

    def test_google_vision_is_accepted(self):
        assert _config(MODERATION_PROVIDER="google_vision").MODERATION_PROVIDER == "google_vision"

    def test_an_unknown_provider_refuses_to_start(self):
        with pytest.raises(ValidationError, match="MODERATION_PROVIDER"):
            _config(MODERATION_PROVIDER="sightengine")

    @pytest.mark.parametrize("name", [
        "MODERATION_GOOGLE_REJECT_LIKELIHOOD", "MODERATION_GOOGLE_FLAG_LIKELIHOOD",
    ])
    @pytest.mark.parametrize("level", ["UNLIKELY", "likely", "SOMETIMES", ""])
    def test_an_unknown_likelihood_refuses_to_start(self, name, level):
        with pytest.raises(ValidationError, match=name):
            _config(**{name: level})

    def test_a_reject_level_below_the_flag_level_refuses_to_start(self):
        """It would reject images it never flags."""
        with pytest.raises(ValidationError, match="may not be below"):
            _config(MODERATION_GOOGLE_REJECT_LIKELIHOOD="LIKELY",
                    MODERATION_GOOGLE_FLAG_LIKELIHOOD="VERY_LIKELY")

    def test_equal_levels_are_accepted(self):
        s = _config(MODERATION_GOOGLE_REJECT_LIKELIHOOD="LIKELY",
                    MODERATION_GOOGLE_FLAG_LIKELIHOOD="LIKELY")
        assert s.MODERATION_GOOGLE_REJECT_LIKELIHOOD == s.MODERATION_GOOGLE_FLAG_LIKELIHOOD
