"""
test_admin_text_queues.py — the text-flag queue and the legal-escalation lane.

Two properties matter beyond "the pages render": a self-harm flag must be
visibly distinguished (its right response differs from abuse), and a CSAM
escalation must be impossible to close from the routine queue — that separation
is the whole reason the lane exists.
"""

from __future__ import annotations

import uuid

import pytest

from conftest import (
    ADMIN_BASIC, TestingSessionLocal, admin_session, auth_headers, make_admin,
    register_user,
)
from app.models.content_report import ContentReport
from app.models.itinerary import Itinerary
from app.models.legal_escalation import LegalEscalation
from app.models.moderation_log import ModerationLog
from app.models.text_moderation_decision import TextModerationDecision
from app.config import get_settings
from app.services import text_moderation_service as tms
from app.services.text_moderation_providers import ProviderResult


def _flat(html: str) -> str:
    """Collapse HTML whitespace so an assertion can match prose that the
    template wraps across source lines."""
    return " ".join(html.split())


class StubProvider:
    name = "stub"
    model = "stub-model"

    def __init__(self, scores):
        self.scores = scores

    def score(self, text: str) -> ProviderResult:
        return ProviderResult(scores=self.scores, provider=self.name, model=self.model)


@pytest.fixture(autouse=True)
def no_mail(monkeypatch):
    monkeypatch.setattr(
        "app.services.email_service.send_email", lambda to, subject, html: None
    )


@pytest.fixture()
def moderator(client, admin_enabled):
    register_user(client, "moddy", "mod@example.com")
    make_admin("mod@example.com")
    admin_session(client, "moddy")


@pytest.fixture()
def author(client):
    return register_user(client, "author", "author@example.com")


@pytest.fixture()
def reporter(client):
    return register_user(client, "reporter", "reporter@example.com")


def _flagging_provider(monkeypatch, scores):
    monkeypatch.setattr(get_settings(), "TEXT_MODERATION_PROVIDER", "openai")
    monkeypatch.setattr(get_settings(), "OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(
        tms, "get_provider_chain", lambda settings: [StubProvider(scores)]
    )


def _itinerary(client, token, title="A trip") -> str:
    response = client.post(
        "/itineraries/",
        json={"title": title, "currency": "EUR", "visibility": "public"},
        headers=auth_headers(token),
    )
    assert response.status_code == 201, response.json()
    return response.json()["id"]


def _decision_id() -> str:
    db = TestingSessionLocal()
    try:
        return str(
            db.query(TextModerationDecision)
            .filter(TextModerationDecision.outcome == "review").one().id
        )
    finally:
        db.close()


def _row(model, row_id):
    db = TestingSessionLocal()
    try:
        row = db.get(model, uuid.UUID(str(row_id)))
        if row is not None:
            db.expunge(row)
        return row
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Text-flag queue
# ---------------------------------------------------------------------------

def test_a_flagged_itinerary_appears_in_the_queue(client, author, moderator, monkeypatch):
    _flagging_provider(monkeypatch, {"harassment": 0.6})
    _itinerary(client, author["access_token"], title="Borderline Trip")

    page = client.get("/admin/text-flags", auth=ADMIN_BASIC)

    assert page.status_code == 200
    assert "Borderline Trip" in page.text
    assert "harassment" in page.text


def test_a_self_harm_flag_is_visually_distinguished(client, author, moderator, monkeypatch):
    """The right response to self-harm content is support, not enforcement —
    a moderator working at speed must not mistake it for abuse."""
    _flagging_provider(monkeypatch, {"self-harm/intent": 0.4})
    _itinerary(client, author["access_token"])

    page = client.get("/admin/text-flags", auth=ADMIN_BASIC)

    assert "self-harm" in page.text
    assert "cut someone off from support" in _flat(page.text)


def test_approving_a_flag_clears_it_and_the_content_status(
    client, author, moderator, monkeypatch
):
    _flagging_provider(monkeypatch, {"harassment": 0.6})
    itinerary = _itinerary(client, author["access_token"])
    assert _row(Itinerary, itinerary).moderation_status == "flagged"

    response = client.post(
        f"/admin/text-flags/{_decision_id()}/action",
        data={"action": "approve", "reason": "Read it; it's fine."},
        auth=ADMIN_BASIC, follow_redirects=False,
    )

    assert response.status_code == 303
    assert _row(Itinerary, itinerary).moderation_status == "approved"
    assert _row(TextModerationDecision, _decision_id()).reviewed_at is not None


def test_hiding_from_the_queue_takes_the_content_down(
    client, author, moderator, monkeypatch
):
    _flagging_provider(monkeypatch, {"harassment": 0.6})
    itinerary = _itinerary(client, author["access_token"])

    client.post(
        f"/admin/text-flags/{_decision_id()}/action",
        data={"action": "hide", "reason": "Targeted abuse."},
        auth=ADMIN_BASIC, follow_redirects=False,
    )

    row = _row(Itinerary, itinerary)
    assert row.hidden_at is not None
    assert row.moderation_status == "hidden"


def test_a_moderator_hide_names_the_human_in_the_audit_trail(
    client, author, moderator, monkeypatch
):
    """An operator decision must not read as another automated action."""
    _flagging_provider(monkeypatch, {"harassment": 0.6})
    _itinerary(client, author["access_token"])
    client.post(
        f"/admin/text-flags/{_decision_id()}/action",
        data={"action": "hide", "reason": "Targeted abuse."},
        auth=ADMIN_BASIC, follow_redirects=False,
    )

    db = TestingSessionLocal()
    try:
        rows = db.query(ModerationLog).filter(ModerationLog.action == "hide").all()
    finally:
        db.close()

    assert any(row.admin_user_id is not None for row in rows)


def test_queue_actions_require_a_reason(client, author, moderator, monkeypatch):
    _flagging_provider(monkeypatch, {"harassment": 0.6})
    _itinerary(client, author["access_token"])

    response = client.post(
        f"/admin/text-flags/{_decision_id()}/action",
        data={"action": "approve", "reason": "   "},
        auth=ADMIN_BASIC, follow_redirects=False,
    )

    assert "error" in response.headers["location"]
    assert _row(TextModerationDecision, _decision_id()).reviewed_at is None


def test_a_reviewed_flag_cannot_be_actioned_twice(client, author, moderator, monkeypatch):
    _flagging_provider(monkeypatch, {"harassment": 0.6})
    _itinerary(client, author["access_token"])
    decision_id = _decision_id()
    client.post(
        f"/admin/text-flags/{decision_id}/action",
        data={"action": "approve", "reason": "Fine."},
        auth=ADMIN_BASIC, follow_redirects=False,
    )

    response = client.post(
        f"/admin/text-flags/{decision_id}/action",
        data={"action": "hide", "reason": "Changed my mind."},
        auth=ADMIN_BASIC, follow_redirects=False,
    )

    assert "notice" in response.headers["location"]


def test_the_queue_page_is_empty_when_nothing_is_flagged(client, moderator):
    page = client.get("/admin/text-flags", auth=ADMIN_BASIC)
    assert "No text flags awaiting review" in _flat(page.text)


# ---------------------------------------------------------------------------
# Legal escalations
# ---------------------------------------------------------------------------

def _csam_report(client, itinerary_id, reporter_token) -> None:
    response = client.post(
        "/reports",
        json={"target_type": "itinerary", "target_id": itinerary_id, "reason": "csam"},
        headers=auth_headers(reporter_token),
    )
    assert response.status_code == 201


def _escalation_id() -> str:
    db = TestingSessionLocal()
    try:
        return str(db.query(LegalEscalation).one().id)
    finally:
        db.close()


def _report_id() -> str:
    db = TestingSessionLocal()
    try:
        return str(db.query(ContentReport).one().id)
    finally:
        db.close()


def test_an_escalation_appears_in_its_own_lane(client, author, reporter, moderator):
    itinerary = _itinerary(client, author["access_token"], title="Escalated Trip")
    _csam_report(client, itinerary, reporter["access_token"])

    page = client.get("/admin/legal", auth=ADMIN_BASIC)

    assert page.status_code == 200
    assert "Escalated Trip" in page.text
    assert "obligations beyond taking the content down" in _flat(page.text)


def test_the_dashboard_shouts_about_open_escalations(client, author, reporter, moderator):
    itinerary = _itinerary(client, author["access_token"])
    _csam_report(client, itinerary, reporter["access_token"])

    page = client.get("/admin", auth=ADMIN_BASIC)

    assert "open legal escalation" in _flat(page.text)
    assert "cannot be closed as routine" in _flat(page.text)


def test_an_escalation_outlives_an_empty_reports_queue(
    client, author, reporter, moderator
):
    """The report that raised it auto-resolves on the spot, so a moderator can
    see an empty routine queue while the escalation is still open. It has to
    keep demanding attention from its own lane."""
    itinerary = _itinerary(client, author["access_token"])
    _csam_report(client, itinerary, reporter["access_token"])

    assert "Nothing in the queue" in _flat(
        client.get("/admin/reports", auth=ADMIN_BASIC).text
    )
    assert _row(LegalEscalation, _escalation_id()).closed_at is None
    assert "No open legal escalations" not in _flat(
        client.get("/admin/legal", auth=ADMIN_BASIC).text
    )


def test_an_escalated_report_is_refused_by_the_routine_dismiss_path(
    client, author, reporter, moderator
):
    """Defence in depth. The report normally auto-resolves before a moderator
    sees it, but if one is ever pending on escalated content — a reconfigured
    threshold, an un-hidden item — dismissing it must still be refused."""
    itinerary = _itinerary(client, author["access_token"])
    _csam_report(client, itinerary, reporter["access_token"])

    # Reopen the report to simulate the case the guard exists for.
    db = TestingSessionLocal()
    try:
        report = db.query(ContentReport).one()
        report.resolution = "pending"
        report.resolved_at = None
        db.commit()
        report_id = str(report.id)
    finally:
        db.close()

    response = client.post(
        f"/admin/reports/{report_id}/action",
        data={"action": "dismiss", "reason": "Looks fine to me."},
        auth=ADMIN_BASIC, follow_redirects=False,
    )

    assert "error" in response.headers["location"]
    assert _row(LegalEscalation, _escalation_id()).closed_at is None


def test_a_csam_report_is_actioned_without_a_moderator(client, author, reporter, moderator):
    """It auto-hides on the first report, so it never sits in the routine queue
    waiting to be dismissed in the first place."""
    itinerary = _itinerary(client, author["access_token"])
    _csam_report(client, itinerary, reporter["access_token"])

    assert _row(Itinerary, itinerary).hidden_at is not None
    assert _row(ContentReport, _report_id()).resolution == "auto_hidden"


def test_closing_an_escalation_requires_a_written_note(
    client, author, reporter, moderator
):
    itinerary = _itinerary(client, author["access_token"])
    _csam_report(client, itinerary, reporter["access_token"])

    response = client.post(
        f"/admin/legal/{_escalation_id()}/close",
        data={"note": "   "},
        auth=ADMIN_BASIC, follow_redirects=False,
    )

    assert "error" in response.headers["location"]
    assert _row(LegalEscalation, _escalation_id()).closed_at is None


def test_closing_an_escalation_with_a_note_records_who_and_why(
    client, author, reporter, moderator
):
    itinerary = _itinerary(client, author["access_token"])
    _csam_report(client, itinerary, reporter["access_token"])

    response = client.post(
        f"/admin/legal/{_escalation_id()}/close",
        data={"note": "Reported to the authorities on 2026-07-30, ref 12345."},
        auth=ADMIN_BASIC, follow_redirects=False,
    )

    assert response.status_code == 303
    row = _row(LegalEscalation, _escalation_id())
    assert row.closed_at is not None
    assert row.closed_by is not None
    assert "authorities" in row.closure_note


def test_a_closed_escalation_leaves_the_lane(client, author, reporter, moderator):
    itinerary = _itinerary(client, author["access_token"])
    _csam_report(client, itinerary, reporter["access_token"])
    client.post(
        f"/admin/legal/{_escalation_id()}/close",
        data={"note": "Handled."},
        auth=ADMIN_BASIC, follow_redirects=False,
    )

    page = client.get("/admin/legal", auth=ADMIN_BASIC)
    assert "No open legal escalations" in _flat(page.text)


# ---------------------------------------------------------------------------
# Polymorphic reports rendering
# ---------------------------------------------------------------------------

def test_the_reports_queue_renders_a_rating_target(client, author, reporter, moderator):
    itinerary = _itinerary(client, author["access_token"])
    client.post(
        f"/itineraries/{itinerary}/ratings",
        json={"stars": 1, "note": "a review"},
        headers=auth_headers(reporter["access_token"]),
    )
    db = TestingSessionLocal()
    try:
        from app.models.itinerary_rating import ItineraryRating
        rating_id = str(db.query(ItineraryRating).one().id)
    finally:
        db.close()

    client.post(
        "/reports",
        json={"target_type": "rating", "target_id": rating_id, "reason": "spam"},
        headers=auth_headers(author["access_token"]),
    )

    page = client.get("/admin/reports", auth=ADMIN_BASIC)
    assert page.status_code == 200
    assert "rating" in page.text


def test_the_reports_queue_survives_a_vanished_target(client, author, reporter, moderator):
    itinerary = _itinerary(client, author["access_token"])
    client.post(
        "/reports",
        json={"target_type": "itinerary", "target_id": itinerary, "reason": "spam"},
        headers=auth_headers(reporter["access_token"]),
    )
    client.delete(
        f"/itineraries/{itinerary}", headers=auth_headers(author["access_token"])
    )

    page = client.get("/admin/reports", auth=ADMIN_BASIC)
    assert page.status_code == 200
    assert "Content already gone" in _flat(page.text)
