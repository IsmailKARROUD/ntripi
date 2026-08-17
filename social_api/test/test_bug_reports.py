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

import copy
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


# ---------------------------------------------------------------------------
# Jira hand-off
# ---------------------------------------------------------------------------

JIRA_CONF = {
    "JIRA_BASE_URL": "https://ntripi.atlassian.net",
    "JIRA_EMAIL": "ops@ntripi.app",
    "JIRA_API_TOKEN": "token-abc",
    "JIRA_PROJECT_KEY": "NTRIPI",
}


class _FakeResponse:
    def __init__(self, status_code: int, payload: dict | None = None, text: str = ""):
        self.status_code = status_code
        self._payload = payload
        self.text = text or (str(payload) if payload else "")

    def json(self):
        if self._payload is None:
            raise ValueError("no json")
        return self._payload


def _configure_jira(monkeypatch, **overrides) -> None:
    settings = get_settings()
    for name, value in {**JIRA_CONF, **overrides}.items():
        monkeypatch.setattr(settings, name, value)


# The admin _sign_in_admin creates, and the Jira account it resolves to.
ADMIN_EMAIL = "ops@test.com"
ADMIN_ACCOUNT_ID = "5b10a2844c20165700ede21g"


def _stub_jira(
    monkeypatch,
    response: _FakeResponse | Exception | list,
    *,
    lookup: _FakeResponse | Exception | None = None,
    lookup_calls: list | None = None,
) -> list[dict]:
    """Intercept the transport. jira_service does a local `import requests`,
    which resolves the same module object, so patching requests.post works.

    `requests.get` is stubbed too and MUST be: create_issue looks the acting
    admin's accountId up first, so leaving it live would put every test in this
    file on a real network call. It defaults to finding the admin.

    `response` may be a list, consumed in order — the reporter-rejected path
    posts twice. Only POSTs land in the returned list, so index-based
    assertions keep meaning what they did before the lookup existed.
    """
    calls: list[dict] = []
    posts = list(response) if isinstance(response, list) else [response]

    def _fake_post(url, **kwargs):
        # Snapshot: the retry mutates the same payload dict it posted first,
        # so recording the reference would show both calls post-mutation.
        calls.append({"url": url, **copy.deepcopy(kwargs)})
        # Hold the last one once exhausted: most tests post exactly once.
        nxt = posts.pop(0) if len(posts) > 1 else posts[0]
        if isinstance(nxt, Exception):
            raise nxt
        return nxt

    found = _FakeResponse(200, [
        {"accountId": ADMIN_ACCOUNT_ID, "emailAddress": ADMIN_EMAIL},
    ])
    lookup_response = found if lookup is None else lookup

    def _fake_get(url, **kwargs):
        if lookup_calls is not None:
            lookup_calls.append({"url": url, **kwargs})
        if isinstance(lookup_response, Exception):
            raise lookup_response
        return lookup_response

    monkeypatch.setattr("requests.post", _fake_post)
    monkeypatch.setattr("requests.get", _fake_get)
    return calls


def _file_report(client: TestClient) -> None:
    client.post("/bug-reports", data={
        "message": "The map goes blank.", "category": "visual", "platform": "ios",
    })


def test_jira_button_hidden_when_unconfigured(
    client: TestClient, admin_enabled, monkeypatch
):
    _set_operator_email(monkeypatch, None)
    _capture_emails(monkeypatch)
    _file_report(client)
    _sign_in_admin(client)

    page = client.get("/admin/bugs", auth=ADMIN_BASIC)
    assert "Create Jira issue" not in page.text

    # The route still exists but refuses, rather than 500ing on a missing token.
    calls = _stub_jira(monkeypatch, _FakeResponse(201, {"key": "X-1"}))
    resp = client.post(
        f"/admin/bugs/{_only_report().id}/jira",
        auth=ADMIN_BASIC, follow_redirects=False,
    )
    assert resp.status_code == 303
    assert "error=" in resp.headers["location"]
    assert calls == []


def test_create_jira_stores_key_and_renders_link(
    client: TestClient, admin_enabled, monkeypatch
):
    _set_operator_email(monkeypatch, None)
    _capture_emails(monkeypatch)
    _file_report(client)
    _sign_in_admin(client)
    _configure_jira(monkeypatch)
    _stub_jira(monkeypatch, _FakeResponse(201, {"id": "10052", "key": "NTRIPI-6"}))

    report = _only_report()
    resp = client.post(
        f"/admin/bugs/{report.id}/jira", auth=ADMIN_BASIC, follow_redirects=False,
    )
    assert resp.status_code == 303
    assert "NTRIPI-6" in resp.headers["location"]

    db = TestingSessionLocal()
    try:
        assert db.get(BugReport, report.id).jira_issue_key == "NTRIPI-6"
    finally:
        db.close()

    page = client.get("/admin/bugs", auth=ADMIN_BASIC)
    assert "https://ntripi.atlassian.net/browse/NTRIPI-6" in page.text
    # Filed already — the button must be gone, not merely disabled.
    assert "Create Jira issue" not in page.text


def test_create_jira_is_idempotent(client: TestClient, admin_enabled, monkeypatch):
    _set_operator_email(monkeypatch, None)
    _capture_emails(monkeypatch)
    _file_report(client)
    _sign_in_admin(client)
    _configure_jira(monkeypatch)
    calls = _stub_jira(monkeypatch, _FakeResponse(201, {"key": "NTRIPI-6"}))

    report_id = _only_report().id
    for _ in range(2):
        client.post(
            f"/admin/bugs/{report_id}/jira", auth=ADMIN_BASIC, follow_redirects=False,
        )

    # The second POST must not reach Jira at all.
    assert len(calls) == 1


def test_create_jira_surfaces_api_error(
    client: TestClient, admin_enabled, monkeypatch
):
    _set_operator_email(monkeypatch, None)
    _capture_emails(monkeypatch)
    _file_report(client)
    _sign_in_admin(client)
    _configure_jira(monkeypatch)
    _stub_jira(monkeypatch, _FakeResponse(
        400, text='{"errors":{"issuetype":"valid issue type is required"}}',
    ))

    report_id = _only_report().id
    resp = client.post(
        f"/admin/bugs/{report_id}/jira", auth=ADMIN_BASIC, follow_redirects=False,
    )
    assert resp.status_code == 303
    assert "error=" in resp.headers["location"]

    db = TestingSessionLocal()
    try:
        row = db.get(BugReport, report_id)
        assert row.jira_issue_key is None   # fails closed
        assert row.status == "open"
    finally:
        db.close()


def test_create_jira_survives_transport_failure(
    client: TestClient, admin_enabled, monkeypatch
):
    _set_operator_email(monkeypatch, None)
    _capture_emails(monkeypatch)
    _file_report(client)
    _sign_in_admin(client)
    _configure_jira(monkeypatch)
    _stub_jira(monkeypatch, RuntimeError("connection reset"))

    report_id = _only_report().id
    resp = client.post(
        f"/admin/bugs/{report_id}/jira", auth=ADMIN_BASIC, follow_redirects=False,
    )
    assert resp.status_code == 303
    assert "error=" in resp.headers["location"]

    db = TestingSessionLocal()
    try:
        assert db.get(BugReport, report_id).jira_issue_key is None
    finally:
        db.close()


def test_jira_payload_shape(client: TestClient, admin_enabled, monkeypatch):
    _set_operator_email(monkeypatch, None)
    _capture_emails(monkeypatch)
    token = register_user(client, "jirauser", "jira@example.com")["access_token"]
    client.post(
        "/bug-reports",
        data={"message": "Map blank", "category": "visual", "platform": "ios"},
        files={"screenshot": ("s.png", _png(800, 1400), "image/png")},
        headers=auth_headers(token),
    )
    _sign_in_admin(client)
    _configure_jira(monkeypatch)
    calls = _stub_jira(monkeypatch, _FakeResponse(201, {"key": "NTRIPI-7"}))

    client.post(
        f"/admin/bugs/{_only_report().id}/jira",
        auth=ADMIN_BASIC, follow_redirects=False,
    )

    body = calls[0]["json"]["fields"]
    assert calls[0]["url"] == "https://ntripi.atlassian.net/rest/api/3/issue"
    assert calls[0]["auth"] == ("ops@ntripi.app", "token-abc")
    assert body["project"] == {"key": "NTRIPI"}
    assert body["issuetype"] == {"name": "Bug"}
    assert body["summary"].startswith("[visual] Map blank")
    assert len(body["summary"]) <= 255

    # description must be ADF — v3 rejects a plain string.
    assert body["description"]["type"] == "doc"
    assert body["description"]["version"] == 1
    text = " ".join(
        node["text"]
        for para in body["description"]["content"]
        for node in para.get("content", [])
    )
    assert "@jirauser" in text
    # Privacy: username yes, email never.
    assert "jira@example.com" not in text
    # Screenshot link must be absolute, not the relative filesystem /uploads path.
    assert "http" in text.split("Screenshot: ")[1][:8]


def test_jira_base_url_trailing_slash(client: TestClient, admin_enabled, monkeypatch):
    _set_operator_email(monkeypatch, None)
    _capture_emails(monkeypatch)
    _file_report(client)
    _sign_in_admin(client)
    _configure_jira(monkeypatch, JIRA_BASE_URL="https://ntripi.atlassian.net/")
    calls = _stub_jira(monkeypatch, _FakeResponse(201, {"key": "NTRIPI-8"}))

    client.post(
        f"/admin/bugs/{_only_report().id}/jira",
        auth=ADMIN_BASIC, follow_redirects=False,
    )
    assert calls[0]["url"] == "https://ntripi.atlassian.net/rest/api/3/issue"


# ---------------------------------------------------------------------------
# Jira reporter attribution — the acting admin, when Jira knows them
# ---------------------------------------------------------------------------

def _file_and_click(client, monkeypatch, response, **stub_kwargs):
    """File a report, sign in as the admin, click Create Jira issue."""
    _set_operator_email(monkeypatch, None)
    _capture_emails(monkeypatch)
    _file_report(client)
    _sign_in_admin(client)
    _configure_jira(monkeypatch)
    calls = _stub_jira(monkeypatch, response, **stub_kwargs)
    resp = client.post(
        f"/admin/bugs/{_only_report().id}/jira",
        auth=ADMIN_BASIC, follow_redirects=False,
    )
    return calls, resp


def test_jira_reporter_is_the_acting_admin(
    client: TestClient, admin_enabled, monkeypatch
):
    lookups: list[dict] = []
    calls, resp = _file_and_click(
        client, monkeypatch, _FakeResponse(201, {"key": "NTRIPI-9"}),
        lookup_calls=lookups,
    )

    # Looked up project-scoped, by the admin's own email.
    assert lookups[0]["url"].endswith("/rest/api/3/user/assignable/search")
    assert lookups[0]["params"] == {"project": "NTRIPI", "query": ADMIN_EMAIL}
    # ...and the resolved accountId became the Reporter.
    assert calls[0]["json"]["fields"]["reporter"] == {"id": ADMIN_ACCOUNT_ID}
    assert resp.status_code == 303
    assert "warning=" not in resp.headers["location"]
    assert _only_report().jira_issue_key == "NTRIPI-9"


def test_jira_warns_but_still_files_when_admin_is_not_a_jira_user(
    client: TestClient, admin_enabled, monkeypatch
):
    calls, resp = _file_and_click(
        client, monkeypatch, _FakeResponse(201, {"key": "NTRIPI-10"}),
        lookup=_FakeResponse(200, []),
    )

    # Attribution is lost, the ticket is not: that is the whole design.
    assert "reporter" not in calls[0]["json"]["fields"]
    assert _only_report().jira_issue_key == "NTRIPI-10"
    location = resp.headers["location"]
    assert "notice=" in location and "warning=" in location

    page = client.get(location, auth=ADMIN_BASIC)
    assert "flash warn" in page.text
    # The message has to name both halves to be actionable.
    assert ADMIN_EMAIL in page.text and "NTRIPI" in page.text


def test_jira_does_not_attribute_on_a_display_name_only_match(
    client: TestClient, admin_enabled, monkeypatch
):
    # `query` matches displayName as well as email, so a hit whose address does
    # not match exactly must NOT be attributed — that would file the ticket
    # under a colleague's name.
    calls, resp = _file_and_click(
        client, monkeypatch, _FakeResponse(201, {"key": "NTRIPI-11"}),
        lookup=_FakeResponse(200, [
            {"accountId": "someone-else", "emailAddress": "other@test.com"},
            {"accountId": "hidden-email"},  # privacy settings hide the address
        ]),
    )

    assert "reporter" not in calls[0]["json"]["fields"]
    assert "warning=" in resp.headers["location"]
    assert _only_report().jira_issue_key == "NTRIPI-11"


def test_jira_retries_without_reporter_when_the_field_is_rejected(
    client: TestClient, admin_enabled, monkeypatch
):
    # Reporter missing from the create screen, or no Modify Reporter permission.
    calls, resp = _file_and_click(client, monkeypatch, [
        _FakeResponse(400, {"errors": {"reporter": "Field 'reporter' cannot be set."}}),
        _FakeResponse(201, {"key": "NTRIPI-12"}),
    ])

    assert len(calls) == 2
    assert calls[0]["json"]["fields"]["reporter"] == {"id": ADMIN_ACCOUNT_ID}
    assert "reporter" not in calls[1]["json"]["fields"]
    assert _only_report().jira_issue_key == "NTRIPI-12"
    assert "warning=" in resp.headers["location"]


def test_jira_lookup_failure_still_files_the_ticket(
    client: TestClient, admin_enabled, monkeypatch
):
    # A dead lookup must never cost us the ticket — find_account_id swallows.
    calls, resp = _file_and_click(
        client, monkeypatch, _FakeResponse(201, {"key": "NTRIPI-13"}),
        lookup=RuntimeError("network down"),
    )

    assert "reporter" not in calls[0]["json"]["fields"]
    assert _only_report().jira_issue_key == "NTRIPI-13"
    assert "warning=" in resp.headers["location"]


def test_jira_400_unrelated_to_reporter_still_fails_closed(
    client: TestClient, admin_enabled, monkeypatch
):
    # Only a reporter-specific 400 is retried; a bad issue type must still
    # fail closed with nothing written, exactly as before.
    calls, resp = _file_and_click(
        client, monkeypatch,
        _FakeResponse(400, {"errors": {"issuetype": "valid issue type is required"}}),
    )

    assert len(calls) == 1
    assert _only_report().jira_issue_key is None
    assert "error=" in resp.headers["location"]
