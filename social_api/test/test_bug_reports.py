"""
test_bug_reports.py — Tests for in-app bug reporting (POST /bug-reports).

Covers: authenticated + signed-out submission, the multipart screenshot path
(including a portrait capture below the 600 px cover/avatar minimum), unknown
diagnostic values being dropped rather than 422'd, an empty message being
rejected, a malformed screenshot NOT losing the report, and the retention purge.

Emails are captured by monkeypatching send_email as imported into
bug_report_service (mirrors test_reports._capture_emails).
"""

from __future__ import annotations

import io
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient
from PIL import Image

from conftest import (
    ADMIN_BASIC, TestingSessionLocal, admin_session, auth_headers, make_admin,
    register_user,
)
from app.config import get_settings
from app.models.bug_report import BugReport
from app.services import admin_service, bug_report_service


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _png(width: int, height: int) -> bytes:
    """A solid-colour PNG of the given size, as the Flutter capture would send."""
    buf = io.BytesIO()
    Image.new("RGB", (width, height), (30, 110, 58)).save(buf, format="PNG")
    return buf.getvalue()


def _capture_emails(monkeypatch) -> list[dict]:
    sent: list[dict] = []

    def _fake_send_email(to, subject, html):
        sent.append({"to": to, "subject": subject, "html": html})

    monkeypatch.setattr("app.services.bug_report_service.send_email", _fake_send_email)
    return sent


def _set_operator_email(monkeypatch, value: str | None) -> None:
    monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", value)


def _only_report() -> BugReport:
    db = TestingSessionLocal()
    try:
        rows = db.query(BugReport).all()
        assert len(rows) == 1, f"expected exactly one bug report, got {len(rows)}"
        return rows[0]
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Submission
# ---------------------------------------------------------------------------

def test_authenticated_report_without_screenshot(client: TestClient, monkeypatch):
    _set_operator_email(monkeypatch, "ops@ntripi.app")
    sent = _capture_emails(monkeypatch)
    token = register_user(client, "buguser", "bug@example.com")["access_token"]

    r = client.post(
        "/bug-reports",
        data={
            "message": "The map goes blank when I rotate.",
            "category": "visual",
            "app_version": "0.3.0+12",
            "platform": "ios",
            "os_version": "iOS 18.2",
            "device_model": "iPhone 14 Pro",
            "route": "/itinerary/abc/stops",
            "locale": "fr",
            "theme_mode": "dark",
        },
        headers=auth_headers(token),
    )

    assert r.status_code == 201, r.json()
    assert r.json()["ok"] is True

    report = _only_report()
    assert report.user_id is not None
    assert report.message == "The map goes blank when I rotate."
    assert report.category == "visual"
    assert report.platform == "ios"
    assert report.device_model == "iPhone 14 Pro"
    assert report.status == "open"
    assert report.screenshot_key is None

    assert len(sent) == 1
    assert sent[0]["to"] == "ops@ntripi.app"


def test_signed_out_report_is_accepted(client: TestClient, monkeypatch):
    """Someone stuck on the login screen is exactly who needs to report."""
    _set_operator_email(monkeypatch, None)
    _capture_emails(monkeypatch)

    r = client.post("/bug-reports", data={"message": "Cannot sign in at all."})

    assert r.status_code == 201, r.json()
    assert _only_report().user_id is None


def test_screenshot_is_stored_and_downscaled(client: TestClient, monkeypatch):
    _set_operator_email(monkeypatch, None)
    _capture_emails(monkeypatch)
    token = register_user(client, "shotuser", "shot@example.com")["access_token"]

    r = client.post(
        "/bug-reports",
        data={"message": "See the screenshot."},
        files={"screenshot": ("screenshot.png", _png(860, 1864), "image/png")},
        headers=auth_headers(token),
    )

    assert r.status_code == 201, r.json()
    report = _only_report()
    assert report.screenshot_key == f"bug_reports/{report.id}.jpg"


def test_small_portrait_screenshot_is_accepted(client: TestClient, monkeypatch):
    """Below MIN_DIMENSION=600, which the cover/avatar pipelines reject. A bug
    report must not be lost because the device was small."""
    _set_operator_email(monkeypatch, None)
    _capture_emails(monkeypatch)

    r = client.post(
        "/bug-reports",
        data={"message": "Tiny screen bug."},
        files={"screenshot": ("screenshot.png", _png(360, 800), "image/png")},
    )

    assert r.status_code == 201, r.json()
    assert _only_report().screenshot_key is not None


def test_malformed_screenshot_still_stores_the_report(client: TestClient, monkeypatch):
    """Losing the reporter's words because the capture was broken is the wrong
    trade — the report is kept, without the screenshot."""
    _set_operator_email(monkeypatch, None)
    _capture_emails(monkeypatch)

    r = client.post(
        "/bug-reports",
        data={"message": "Something broke."},
        files={"screenshot": ("screenshot.png", b"not an image at all", "image/png")},
    )

    assert r.status_code == 201, r.json()
    report = _only_report()
    assert report.message == "Something broke."
    assert report.screenshot_key is None


def test_unknown_diagnostics_are_dropped_not_rejected(client: TestClient, monkeypatch):
    """Diagnostics are best-effort: an odd value must not cost the whole report."""
    _set_operator_email(monkeypatch, None)
    _capture_emails(monkeypatch)

    r = client.post(
        "/bug-reports",
        data={
            "message": "Odd device.",
            "category": "not-a-category",
            "platform": "symbian",
        },
    )

    assert r.status_code == 201, r.json()
    report = _only_report()
    assert report.category is None
    assert report.platform is None


def test_blank_message_is_rejected(client: TestClient, monkeypatch):
    _set_operator_email(monkeypatch, None)
    _capture_emails(monkeypatch)

    r = client.post("/bug-reports", data={"message": "   "})

    assert r.status_code == 422
    assert r.json()["code"] == "bug_report_empty"


def test_overlong_message_is_rejected(client: TestClient, monkeypatch):
    _set_operator_email(monkeypatch, None)
    _capture_emails(monkeypatch)

    r = client.post("/bug-reports", data={"message": "x" * 2001})

    assert r.status_code == 422


def test_operator_email_unset_does_not_fail_the_report(client: TestClient, monkeypatch):
    _set_operator_email(monkeypatch, None)
    sent = _capture_emails(monkeypatch)

    r = client.post("/bug-reports", data={"message": "No operator configured."})

    assert r.status_code == 201
    assert sent == []


# ---------------------------------------------------------------------------
# Retention
# ---------------------------------------------------------------------------

def _seed(status: str, closed_days_ago: int | None) -> None:
    db = TestingSessionLocal()
    try:
        closed_at = (
            datetime.now(timezone.utc) - timedelta(days=closed_days_ago)
            if closed_days_ago is not None else None
        )
        db.add(BugReport(
            message="seeded", status=status, closed_at=closed_at,
        ))
        db.commit()
    finally:
        db.close()


def test_purge_only_removes_closed_reports_past_retention(client: TestClient):
    settings = get_settings()
    _seed("closed", closed_days_ago=settings.BUG_REPORT_RETENTION_DAYS + 1)
    _seed("closed", closed_days_ago=1)
    _seed("open", closed_days_ago=None)  # never purged — nobody has read it

    db = TestingSessionLocal()
    try:
        purged = bug_report_service.purge_expired(db, settings)
        db.commit()
        remaining = {(r.status, r.closed_at is not None) for r in db.query(BugReport).all()}
    finally:
        db.close()

    assert purged == 1
    assert remaining == {("closed", True), ("open", False)}


# ---------------------------------------------------------------------------
# Admin lane
# ---------------------------------------------------------------------------

def _sign_in_admin(client: TestClient) -> None:
    register_user(client, "opsadmin", "ops@test.com")
    make_admin("ops@test.com")
    admin_session(client, "ops@test.com")


def test_admin_lane_lists_and_closes_a_report(
    client: TestClient, admin_enabled, monkeypatch
):
    _set_operator_email(monkeypatch, None)
    _capture_emails(monkeypatch)
    client.post("/bug-reports", data={
        "message": "The map goes blank.", "category": "visual",
        "platform": "ios", "device_model": "iPhone15,2",
    })
    _sign_in_admin(client)

    page = client.get("/admin/bugs", auth=ADMIN_BASIC)
    assert page.status_code == 200
    assert "The map goes blank." in page.text
    assert "iPhone15,2" in page.text
    # Signed-out reporter renders as such rather than blowing up on a null FK.
    assert "signed out" in page.text

    report = _only_report()
    closed = client.post(
        f"/admin/bugs/{report.id}/close",
        data={"note": "Fixed in 0.3.1"},
        auth=ADMIN_BASIC,
        follow_redirects=False,
    )
    assert closed.status_code == 303

    db = TestingSessionLocal()
    try:
        row = db.get(BugReport, report.id)
        assert row.status == "closed"
        assert row.resolution_note == "Fixed in 0.3.1"
        assert row.closed_at is not None
        assert row.closed_by_admin_id is not None
        # Leaves the lane, and the dashboard tile agrees with it.
        assert admin_service.open_bug_reports(db) == []
        assert admin_service.overview_counts(db)["open_bug_reports"] == 0
    finally:
        db.close()
