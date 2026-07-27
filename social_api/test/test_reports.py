"""
test_reports.py — Tests for content reporting (POST /reports) and the
share-page report UI.

Covers: authenticated + anonymous reports, self-report rejection, unknown
itinerary, invalid reason, idempotent duplicates, per-user and per-IP daily
limits, IP-hash scrubbing, and the OPERATOR_EMAIL-unset short-circuit.

Emails are captured by monkeypatching send_email as imported into
report_service (mirrors test_email_verification._capture_emails).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from conftest import TestingSessionLocal, auth_headers, register_user
from app.config import get_settings
from app.models.content_report import ContentReport


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _create_itinerary(client: TestClient, token: str, title: str = "Test Trip",
                      visibility: str = "public") -> str:
    r = client.post(
        "/itineraries/",
        json={"title": title, "currency": "EUR", "visibility": visibility},
        headers=auth_headers(token),
    )
    assert r.status_code == 201, r.json()
    return r.json()["id"]


def _capture_emails(monkeypatch) -> list[dict]:
    """Intercept report_service.send_email and record its calls."""
    sent: list[dict] = []

    def _fake_send_email(to, subject, html):
        sent.append({"to": to, "subject": subject, "html": html})

    monkeypatch.setattr("app.services.report_service.send_email", _fake_send_email)
    return sent


def _set_operator_email(monkeypatch, value: str | None) -> None:
    """Point the cached settings singleton at an operator address (or None)."""
    monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", value)


def _seed_report(*, reporter_user_id=None, reported_itinerary_id=None,
                 reporter_ip_hash=None, age: timedelta = timedelta(0),
                 reason: str = "spam") -> uuid.UUID:
    """Insert a ContentReport row directly with an explicit aware created_at."""
    db = TestingSessionLocal()
    try:
        report = ContentReport(
            reported_itinerary_id=reported_itinerary_id,
            reporter_user_id=reporter_user_id,
            reason=reason,
            reporter_ip_hash=reporter_ip_hash,
            created_at=datetime.now(timezone.utc) - age,
        )
        db.add(report)
        db.commit()
        db.refresh(report)
        return report.id
    finally:
        db.close()


def _count_reports() -> int:
    db = TestingSessionLocal()
    try:
        return db.query(ContentReport).count()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------

class TestReportHappyPath:
    def test_authenticated_report_succeeds_and_emails_operator(self, client, monkeypatch):
        _set_operator_email(monkeypatch, "ops@example.com")
        sent = _capture_emails(monkeypatch)

        owner = register_user(client, "owner1", "owner1@example.com")
        reporter = register_user(client, "reporter1", "reporter1@example.com")
        it_id = _create_itinerary(client, owner["access_token"], "Weekend in Paris")

        r = client.post(
            "/reports",
            json={"itinerary_id": it_id, "reason": "spam", "notes": "bad content"},
            headers=auth_headers(reporter["access_token"]),
        )
        assert r.status_code == 201, r.json()
        assert r.json() == {"ok": True}

        assert len(sent) == 1
        html = sent[0]["html"]
        assert it_id in html                          # share URL carries the itinerary id
        assert "spam" in html
        assert "reporter1" in html                    # reporter username
        # No-further-action snippet (quotes are HTML-escaped in the email body).
        assert "content_reports SET resolution" in html
        assert "dismissed" in html

    def test_anonymous_report_succeeds(self, client, monkeypatch):
        _set_operator_email(monkeypatch, "ops@example.com")
        sent = _capture_emails(monkeypatch)

        owner = register_user(client, "owner2", "owner2@example.com")
        it_id = _create_itinerary(client, owner["access_token"])

        r = client.post("/reports", json={"itinerary_id": it_id, "reason": "nsfw"})
        assert r.status_code == 201, r.json()
        assert len(sent) == 1
        assert "Anonymous" in sent[0]["html"]


# ---------------------------------------------------------------------------
# Validation / rejection
# ---------------------------------------------------------------------------

class TestReportValidation:
    def test_self_report_rejected(self, client, monkeypatch):
        sent = _capture_emails(monkeypatch)
        owner = register_user(client, "owner3", "owner3@example.com")
        it_id = _create_itinerary(client, owner["access_token"])

        r = client.post(
            "/reports",
            json={"itinerary_id": it_id, "reason": "spam"},
            headers=auth_headers(owner["access_token"]),
        )
        assert r.status_code == 400
        assert r.json()["code"] == "report_own_content"
        assert sent == []

    def test_unknown_itinerary_returns_404(self, client):
        r = client.post(
            "/reports",
            json={"itinerary_id": str(uuid.uuid4()), "reason": "spam"},
        )
        assert r.status_code == 404
        assert r.json()["code"] == "itinerary_not_found"

    def test_invalid_reason_returns_422(self, client):
        owner = register_user(client, "owner4", "owner4@example.com")
        it_id = _create_itinerary(client, owner["access_token"])
        r = client.post("/reports", json={"itinerary_id": it_id, "reason": "rude"})
        assert r.status_code == 422


# ---------------------------------------------------------------------------
# Idempotency & rate limits
# ---------------------------------------------------------------------------

class TestReportLimits:
    def test_duplicate_authenticated_report_is_idempotent(self, client, monkeypatch):
        _set_operator_email(monkeypatch, "ops@example.com")
        sent = _capture_emails(monkeypatch)

        owner = register_user(client, "owner5", "owner5@example.com")
        reporter = register_user(client, "reporter5", "reporter5@example.com")
        it_id = _create_itinerary(client, owner["access_token"])
        headers = auth_headers(reporter["access_token"])

        r1 = client.post("/reports", json={"itinerary_id": it_id, "reason": "spam"}, headers=headers)
        r2 = client.post("/reports", json={"itinerary_id": it_id, "reason": "spam"}, headers=headers)
        assert r1.status_code == 201 and r2.status_code == 201
        assert _count_reports() == 1          # second call added no row
        assert len(sent) == 1                 # and sent no second email

    def test_duplicate_anonymous_report_is_idempotent(self, client, monkeypatch):
        _set_operator_email(monkeypatch, "ops@example.com")
        sent = _capture_emails(monkeypatch)

        owner = register_user(client, "owner_anon_dup", "owner_anon_dup@example.com")
        it_id = _create_itinerary(client, owner["access_token"])

        # TestClient has a constant client IP, so the IP hash is stable across requests.
        r1 = client.post("/reports", json={"itinerary_id": it_id, "reason": "spam"})
        r2 = client.post("/reports", json={"itinerary_id": it_id, "reason": "spam"})
        assert r1.status_code == 201 and r2.status_code == 201
        assert _count_reports() == 1          # second call added no row
        assert len(sent) == 1                 # and sent no second email

    def test_per_user_daily_limit(self, client, monkeypatch):
        _set_operator_email(monkeypatch, "ops@example.com")
        _capture_emails(monkeypatch)

        owner = register_user(client, "owner6", "owner6@example.com")
        reporter = register_user(client, "reporter6", "reporter6@example.com")
        # Direct ORM inserts need a UUID object; the API returns it as a string.
        reporter_id = uuid.UUID(reporter["user_id"])

        # Seed 10 recent reports from this user. reported_itinerary_id stays
        # None (the limit counts by reporter, not itinerary) — avoids seeding
        # ten throwaway itineraries just to satisfy the FK.
        for _ in range(10):
            _seed_report(reporter_user_id=reporter_id)

        it_id = _create_itinerary(client, owner["access_token"])
        r = client.post(
            "/reports",
            json={"itinerary_id": it_id, "reason": "spam"},
            headers=auth_headers(reporter["access_token"]),
        )
        assert r.status_code == 429
        assert r.json()["code"] == "report_rate_limited"

    def test_anonymous_per_ip_daily_limit(self, client, monkeypatch):
        _set_operator_email(monkeypatch, "ops@example.com")
        _capture_emails(monkeypatch)

        owner = register_user(client, "owner7", "owner7@example.com")

        # Create 3 different itineraries and report each once from the same IP.
        # TestClient sends a constant client IP, so the per-IP hash is stable.
        # Each report on a different itinerary counts toward the limit.
        for i in range(3):
            it_id = _create_itinerary(client, owner["access_token"], title=f"Trip {i+1}")
            r = client.post("/reports", json={"itinerary_id": it_id, "reason": "spam"})
            assert r.status_code == 201, r.json()

        # A 4th report on a new itinerary hits the IP daily limit.
        it_id_4 = _create_itinerary(client, owner["access_token"], title="Trip 4")
        r = client.post("/reports", json={"itinerary_id": it_id_4, "reason": "spam"})
        assert r.status_code == 429
        assert r.json()["code"] == "report_rate_limited"

    def test_expired_ip_hash_is_scrubbed(self, client, monkeypatch):
        _set_operator_email(monkeypatch, "ops@example.com")
        _capture_emails(monkeypatch)

        owner = register_user(client, "owner8", "owner8@example.com")
        it_id = _create_itinerary(client, owner["access_token"])

        old_id = _seed_report(reporter_ip_hash="deadbeef" * 8,
                              age=timedelta(days=2))

        # A fresh anonymous report triggers the scrub of expired hashes.
        r = client.post("/reports", json={"itinerary_id": it_id, "reason": "spam"})
        assert r.status_code == 201, r.json()

        db = TestingSessionLocal()
        try:
            old = db.get(ContentReport, old_id)
            assert old.reporter_ip_hash is None
        finally:
            db.close()

    def test_operator_email_unset_skips_send(self, client, monkeypatch):
        _set_operator_email(monkeypatch, None)
        sent = _capture_emails(monkeypatch)

        owner = register_user(client, "owner9", "owner9@example.com")
        it_id = _create_itinerary(client, owner["access_token"])
        r = client.post("/reports", json={"itinerary_id": it_id, "reason": "spam"})
        assert r.status_code == 201
        assert sent == []                     # no operator address → no email


# ---------------------------------------------------------------------------
# Share-page report UI (test_share.py itself is skipped post-refactor)
# ---------------------------------------------------------------------------

class TestShareReportUI:
    def test_public_share_page_has_report_ui(self, client):
        owner = register_user(client, "owner10", "owner10@example.com")
        it_id = _create_itinerary(client, owner["access_token"], visibility="public")
        r = client.get(f"/share/i/{it_id}")
        assert r.status_code == 200
        assert "report-dialog" in r.text
        assert "report-link" in r.text
        # Report button sits in the top-right cluster next to the "Public itinerary" badge.
        assert "hero-top-actions" in r.text
        # The thank-you confirmation must offer an explicit close control.
        assert "report-close" in r.text

    def test_private_share_page_has_no_report_ui(self, client):
        owner = register_user(client, "owner11", "owner11@example.com")
        it_id = _create_itinerary(client, owner["access_token"], visibility="followers")
        r = client.get(f"/share/i/{it_id}")
        assert r.status_code == 200
        assert "report-dialog" not in r.text
