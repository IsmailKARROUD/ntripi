"""
test_moderation_sweep.py — SLA enforcement, post-outage re-check, and the
scheduler-facing endpoint.

The properties under test are the ones that make the sweep safe to run on a
timer from anywhere: it is idempotent (a second run does nothing), it never
bumps an itinerary's concurrency ETag, and the endpoint that triggers it is
invisible until configured, constant-time on its token, and rate limited.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest

from conftest import TestingSessionLocal, auth_headers, register_user
from app.config import get_settings
from app.models.content_report import ContentReport
from app.models.itinerary import Itinerary
from app.models.moderation_log import ModerationLog
from app.models.text_moderation_cache import TextModerationCache
from app.models.text_moderation_decision import TextModerationDecision
from app.models.user import User
from app.services import sweep_service, text_moderation_service as tms
from app.services.text_moderation_providers import ProviderResult

SWEEP_URL = "/internal/moderation-sweep"
TOKEN = "sweep-token-for-tests"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

class StubProvider:
    name = "stub"
    model = "stub-model"

    def __init__(self, scores=None):
        self.scores = scores or {}
        self.calls: list[str] = []

    def score(self, text: str) -> ProviderResult:
        self.calls.append(text)
        return ProviderResult(scores=self.scores, provider=self.name, model=self.model)


@pytest.fixture()
def sweep_enabled(monkeypatch):
    monkeypatch.setattr(get_settings(), "SWEEP_TOKEN", TOKEN)
    return TOKEN


@pytest.fixture()
def author(client):
    return register_user(client, "author", "author@example.com")


@pytest.fixture()
def reporter(client):
    return register_user(client, "reporter", "reporter@example.com")


@pytest.fixture(autouse=True)
def mailbox(monkeypatch):
    sent: list[dict] = []
    monkeypatch.setattr(
        "app.services.email_service.send_email",
        lambda to, subject, html: sent.append({"to": to, "subject": subject, "html": html}),
    )
    return sent


def _moderation_mail(mailbox) -> list[dict]:
    return [m for m in mailbox if "hidden pending review" in m["subject"]]


def _itinerary(client, token, title="A trip") -> str:
    response = client.post(
        "/itineraries/",
        json={"title": title, "currency": "EUR", "visibility": "public"},
        headers=auth_headers(token),
    )
    assert response.status_code == 201, response.json()
    return response.json()["id"]


def _run_sweep() -> dict:
    """Run the sweep directly against the test DB (no HTTP)."""
    db = TestingSessionLocal()
    try:
        return sweep_service.run_moderation_sweep(db, get_settings())
    finally:
        db.close()


def _age_report(report_id: uuid.UUID, hours: int) -> None:
    db = TestingSessionLocal()
    try:
        report = db.get(ContentReport, report_id)
        report.created_at = datetime.now(timezone.utc) - timedelta(hours=hours)
        db.commit()
    finally:
        db.close()


def _seed_pending_report(client, itinerary_id, reporter_token, reason="spam",
                         age_hours=25) -> uuid.UUID:
    """File a report that will not auto-hide, then backdate it past the SLA."""
    client.post(
        "/reports",
        json={"target_type": "itinerary", "target_id": itinerary_id, "reason": reason},
        headers=auth_headers(reporter_token),
    )
    db = TestingSessionLocal()
    try:
        report_id = db.query(ContentReport).filter(
            ContentReport.resolution == "pending"
        ).one().id
    finally:
        db.close()
    _age_report(report_id, age_hours)
    return report_id


def _row(model, row_id):
    db = TestingSessionLocal()
    try:
        row = db.get(model, uuid.UUID(str(row_id)))
        if row is not None:
            db.expunge(row)
        return row
    finally:
        db.close()


def _logs(action: str | None = None) -> list[ModerationLog]:
    db = TestingSessionLocal()
    try:
        query = db.query(ModerationLog)
        if action:
            query = query.filter(ModerationLog.action == action)
        return query.all()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# SLA enforcement
# ---------------------------------------------------------------------------

def test_report_within_the_deadline_is_left_alone(client, author, reporter):
    itinerary = _itinerary(client, author["access_token"])
    _seed_pending_report(client, itinerary, reporter["access_token"], age_hours=2)

    counters = _run_sweep()

    assert counters["sla_hidden"] == 0
    assert _row(Itinerary, itinerary).hidden_at is None


def test_report_past_the_deadline_is_auto_actioned(client, author, reporter):
    """The deadline is 24 h from filing; the threshold fires earlier so a missed
    run still leaves margin."""
    itinerary = _itinerary(client, author["access_token"])
    _seed_pending_report(client, itinerary, reporter["access_token"], age_hours=25)

    counters = _run_sweep()

    assert counters["sla_hidden"] == 1
    row = _row(Itinerary, itinerary)
    assert row.hidden_at is not None
    assert row.moderation_status == "hidden"


def test_sla_action_resolves_the_report_as_auto_hidden(client, author, reporter):
    itinerary = _itinerary(client, author["access_token"])
    report_id = _seed_pending_report(client, itinerary, reporter["access_token"])

    _run_sweep()

    assert _row(ContentReport, report_id).resolution == "auto_hidden"


def test_sla_action_writes_exactly_one_audit_row(client, author, reporter):
    itinerary = _itinerary(client, author["access_token"])
    _seed_pending_report(client, itinerary, reporter["access_token"])

    _run_sweep()

    rows = _logs("auto_hide_sla")
    assert len(rows) == 1
    assert rows[0].admin_user_id is None      # no human acted
    assert rows[0].content_snapshot is None   # automated rows hold no content
    assert "deadline" in rows[0].reason       # real statement of reasons


def test_sla_action_notifies_the_author(client, author, reporter, mailbox):
    itinerary = _itinerary(client, author["access_token"], title="My Trip")
    _seed_pending_report(client, itinerary, reporter["access_token"])

    _run_sweep()

    mails = _moderation_mail(mailbox)
    assert len(mails) == 1
    assert mails[0]["to"] == "author@example.com"
    assert "could not review the report in time" in mails[0]["html"]
    assert "/appeal/" in mails[0]["html"]  # the appeal path stays open


def test_running_the_sweep_twice_changes_nothing(client, author, reporter):
    """Idempotency is what makes a timer-driven sweep safe."""
    itinerary = _itinerary(client, author["access_token"])
    _seed_pending_report(client, itinerary, reporter["access_token"])

    first = _run_sweep()
    second = _run_sweep()

    assert first["sla_hidden"] == 1
    assert second["sla_hidden"] == 0
    assert len(_logs("auto_hide_sla")) == 1


def test_sla_hide_preserves_the_authors_etag(client, author, reporter):
    itinerary = _itinerary(client, author["access_token"])
    before = client.get(
        f"/itineraries/{itinerary}", headers=auth_headers(author["access_token"])
    ).headers["ETag"]
    _seed_pending_report(client, itinerary, reporter["access_token"])

    _run_sweep()

    after = client.get(
        f"/itineraries/{itinerary}", headers=auth_headers(author["access_token"])
    ).headers["ETag"]
    assert before == after


def test_sla_closes_a_report_whose_target_vanished(client, author, reporter):
    """A report pointing at purged content must not be re-scanned forever."""
    itinerary = _itinerary(client, author["access_token"])
    report_id = _seed_pending_report(client, itinerary, reporter["access_token"])

    client.delete(
        f"/itineraries/{itinerary}", headers=auth_headers(author["access_token"])
    )
    counters = _run_sweep()

    assert counters["sla_already_hidden"] == 1
    assert _row(ContentReport, report_id).resolution == "auto_hidden"


def test_sla_threshold_is_configurable(client, author, reporter, monkeypatch):
    monkeypatch.setattr(get_settings(), "MODERATION_SLA_HOURS", 1)
    itinerary = _itinerary(client, author["access_token"])
    _seed_pending_report(client, itinerary, reporter["access_token"], age_hours=2)

    assert _run_sweep()["sla_hidden"] == 1


# ---------------------------------------------------------------------------
# Post-outage re-check
# ---------------------------------------------------------------------------

def _make_pending(client, author, monkeypatch) -> str:
    """Publish an itinerary during a total provider outage, so it lands 'pending'."""
    monkeypatch.setattr(get_settings(), "TEXT_MODERATION_PROVIDER", "openai")
    monkeypatch.setattr(get_settings(), "OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(tms, "get_provider_chain", lambda settings: [])
    itinerary = _itinerary(client, author["access_token"], title="Written during an outage")
    assert _row(Itinerary, itinerary).moderation_status == "pending"
    return itinerary


def test_pending_content_is_rechecked_and_approved(client, author, monkeypatch):
    """'pending' is not a resting state — the sweep is the other half of the
    never-silently-approve promise."""
    itinerary = _make_pending(client, author, monkeypatch)

    monkeypatch.setattr(tms, "get_provider_chain", lambda settings: [StubProvider({"hate": 0.01})])
    counters = _run_sweep()

    assert counters["rechecked"] == 1
    assert _row(Itinerary, itinerary).moderation_status == "approved"


def test_pending_content_rechecked_into_a_flag(client, author, monkeypatch):
    itinerary = _make_pending(client, author, monkeypatch)

    monkeypatch.setattr(
        tms, "get_provider_chain", lambda settings: [StubProvider({"harassment": 0.6})]
    )
    _run_sweep()

    assert _row(Itinerary, itinerary).moderation_status == "flagged"
    assert _row(Itinerary, itinerary).hidden_at is None  # a flag is not a takedown


def test_recheck_that_would_have_blocked_the_write_takes_content_down(
    client, author, monkeypatch, mailbox
):
    """The write already happened, so there is no request to 422 — hide it and
    tell the author instead."""
    itinerary = _make_pending(client, author, monkeypatch)

    monkeypatch.setattr(
        tms, "get_provider_chain", lambda settings: [StubProvider({"hate": 0.9})]
    )
    counters = _run_sweep()

    assert counters["recheck_hidden"] == 1
    row = _row(Itinerary, itinerary)
    assert row.hidden_at is not None
    assert row.moderation_status == "rejected"
    assert len(_moderation_mail(mailbox)) == 1
    assert len(_logs("auto_reject")) == 1


def test_recheck_takedown_preserves_the_authors_etag(client, author, monkeypatch):
    itinerary = _make_pending(client, author, monkeypatch)
    before = client.get(
        f"/itineraries/{itinerary}", headers=auth_headers(author["access_token"])
    ).headers["ETag"]

    monkeypatch.setattr(
        tms, "get_provider_chain", lambda settings: [StubProvider({"hate": 0.9})]
    )
    _run_sweep()

    after = client.get(
        f"/itineraries/{itinerary}", headers=auth_headers(author["access_token"])
    ).headers["ETag"]
    assert before == after


def test_still_pending_when_the_provider_is_still_down(client, author, monkeypatch):
    itinerary = _make_pending(client, author, monkeypatch)

    counters = _run_sweep()  # chain still empty

    assert counters["still_pending"] == 1
    assert _row(Itinerary, itinerary).moderation_status == "pending"


def test_recheck_is_skipped_when_moderation_is_disabled(client, author, monkeypatch):
    itinerary = _make_pending(client, author, monkeypatch)
    monkeypatch.setattr(get_settings(), "TEXT_MODERATION_PROVIDER", "disabled")

    assert _run_sweep()["rechecked"] == 0
    assert _row(Itinerary, itinerary).moderation_status == "pending"


def test_recheck_decisions_are_marked_as_such(client, author, monkeypatch):
    _make_pending(client, author, monkeypatch)
    monkeypatch.setattr(
        tms, "get_provider_chain", lambda settings: [StubProvider({"hate": 0.01})]
    )
    _run_sweep()

    db = TestingSessionLocal()
    try:
        sources = {row.source for row in db.query(TextModerationDecision).all()}
    finally:
        db.close()
    assert "recheck" in sources


# ---------------------------------------------------------------------------
# Housekeeping
# ---------------------------------------------------------------------------

def test_expired_cache_entries_are_purged(client):
    db = TestingSessionLocal()
    try:
        now = datetime.now(timezone.utc)
        db.add_all([
            TextModerationCache(
                cache_key="a" * 64, outcome="approve", scores={}, provider="p",
                model="m", created_at=now, expires_at=now - timedelta(days=1),
            ),
            TextModerationCache(
                cache_key="b" * 64, outcome="approve", scores={}, provider="p",
                model="m", created_at=now, expires_at=now + timedelta(days=1),
            ),
        ])
        db.commit()
    finally:
        db.close()

    assert _run_sweep()["cache_purged"] == 1

    db = TestingSessionLocal()
    try:
        assert {row.cache_key for row in db.query(TextModerationCache).all()} == {"b" * 64}
    finally:
        db.close()


def test_purge_never_removes_an_unreviewed_queue_item(client):
    """An unreviewed decision is a moderator's to-do; retention must not eat it."""
    old = datetime.now(timezone.utc) - timedelta(days=400)
    db = TestingSessionLocal()
    try:
        db.add_all([
            TextModerationDecision(
                content_hash="a" * 64, target_type="itinerary", outcome="review",
                scores={}, policy_version="1", source="write", created_at=old,
                reviewed_at=None,
            ),
            TextModerationDecision(
                content_hash="b" * 64, target_type="itinerary", outcome="review",
                scores={}, policy_version="1", source="write", created_at=old,
                reviewed_at=old,
            ),
        ])
        db.commit()
    finally:
        db.close()

    assert _run_sweep()["decisions_purged"] == 1

    db = TestingSessionLocal()
    try:
        remaining = {row.content_hash for row in db.query(TextModerationDecision).all()}
    finally:
        db.close()
    assert remaining == {"a" * 64}


# ---------------------------------------------------------------------------
# The scheduler endpoint
# ---------------------------------------------------------------------------

def test_endpoint_404s_when_no_token_is_configured(client):
    """Unconfigured means invisible, not merely locked."""
    response = client.post(SWEEP_URL, headers={"Authorization": f"Bearer {TOKEN}"})
    assert response.status_code == 404


def test_endpoint_rejects_a_missing_token(client, sweep_enabled):
    response = client.post(SWEEP_URL)
    assert response.status_code == 401


def test_endpoint_rejects_a_wrong_token(client, sweep_enabled):
    response = client.post(SWEEP_URL, headers={"Authorization": "Bearer nope"})
    assert response.status_code == 401
    assert "token" not in response.text.lower()  # no detail for a prober


def test_endpoint_rejects_a_non_bearer_scheme(client, sweep_enabled):
    response = client.post(SWEEP_URL, headers={"Authorization": TOKEN})
    assert response.status_code == 401


def test_endpoint_runs_the_sweep_and_returns_counters(client, sweep_enabled):
    response = client.post(SWEEP_URL, headers={"Authorization": f"Bearer {TOKEN}"})

    assert response.status_code == 200
    assert response.json()["sla_hidden"] == 0


def test_endpoint_is_absent_from_the_openapi_schema(client, sweep_enabled):
    """A maintenance endpoint has no business being advertised."""
    schema = client.get("/openapi.json")
    if schema.status_code != 200:
        pytest.skip("docs disabled in this configuration")
    assert "/internal/moderation-sweep" not in schema.json()["paths"]


def test_endpoint_is_rate_limited(client, sweep_enabled):
    """Blunts token brute-forcing and a scheduler stuck in a retry loop."""
    codes = [
        client.post(SWEEP_URL, headers={"Authorization": f"Bearer {TOKEN}"}).status_code
        for _ in range(12)
    ]
    assert 429 in codes


def test_sweep_via_http_actions_an_overdue_report(client, author, reporter, sweep_enabled):
    itinerary = _itinerary(client, author["access_token"])
    _seed_pending_report(client, itinerary, reporter["access_token"])

    response = client.post(SWEEP_URL, headers={"Authorization": f"Bearer {TOKEN}"})

    assert response.json()["sla_hidden"] == 1
    assert _row(Itinerary, itinerary).hidden_at is not None
