"""
test_report_thresholds.py — distinct-reporter auto-hide, aliases, CSAM escalation.

Covers the Phase-3 report machinery: the canonical vocabulary (with legacy
aliases still accepted on the wire), polymorphic targets, the distinct-reporter
counts that hide content before a human looks, the classifier-corroboration
discount, and the CSAM escalation that cannot be closed as routine.

The invariant that matters most here: an automated hide must not bump the
itinerary's concurrency ETag, or the author's open editor 412s over a change
they cannot see.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

import pytest

from conftest import (
    TestingSessionLocal, auth_headers, locked_headers, register_user,
)
from app.config import get_settings
from app.models.content_report import ContentReport
from app.models.itinerary import Itinerary
from app.models.itinerary_rating import ItineraryRating
from app.models.legal_escalation import LegalEscalation
from app.models.moderation_log import ModerationLog
from app.models.text_moderation_decision import TextModerationDecision
from app.models.user import User


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

@pytest.fixture()
def author(client):
    return register_user(client, "author", "author@example.com")


@pytest.fixture()
def reporters(client):
    """Four distinct accounts — enough to cross even the spam threshold."""
    return [
        register_user(client, f"rep{index}", f"rep{index}@example.com")
        for index in range(4)
    ]


class _Mailbox(list):
    """Captured emails, with a filter for the ones this suite cares about.

    The patch point is shared with registration/verification mail, so the raw
    list also contains those — `moderation` narrows it to auto-action notices."""

    @property
    def moderation(self) -> list[dict]:
        return [mail for mail in self if "hidden pending review" in mail["subject"]]


@pytest.fixture(autouse=True)
def capture_email(monkeypatch):
    sent = _Mailbox()
    monkeypatch.setattr(
        "app.services.email_service.send_email",
        lambda to, subject, html: sent.append({"to": to, "subject": subject, "html": html}),
    )
    return sent


def _itinerary(client, token, title="A trip") -> str:
    response = client.post(
        "/itineraries/",
        json={"title": title, "currency": "EUR", "visibility": "public"},
        headers=auth_headers(token),
    )
    assert response.status_code == 201, response.json()
    return response.json()["id"]


def _report(client, target_id, token=None, reason="spam", target_type="itinerary"):
    body = {"target_type": target_type, "target_id": target_id, "reason": reason}
    headers = auth_headers(token) if token else {}
    return client.post("/reports", json=body, headers=headers)


def _row(model, row_id: str):
    db = TestingSessionLocal()
    try:
        row = db.get(model, uuid.UUID(row_id))
        if row is not None:
            db.expunge(row)
        return row
    finally:
        db.close()


def _reports() -> list[ContentReport]:
    db = TestingSessionLocal()
    try:
        return db.query(ContentReport).all()
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


def _escalations() -> list[LegalEscalation]:
    db = TestingSessionLocal()
    try:
        return db.query(LegalEscalation).all()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Canonical vocabulary + legacy aliases
# ---------------------------------------------------------------------------

def test_legacy_reason_is_stored_canonically(client, author, reporters):
    """Already-installed clients still send the old vocabulary; rejecting it
    would break every deployed app."""
    itinerary = _itinerary(client, author["access_token"])
    response = client.post(
        "/reports",
        json={"itinerary_id": itinerary, "reason": "copyright"},
        headers=auth_headers(reporters[0]["access_token"]),
    )

    assert response.status_code == 201
    assert [r.reason for r in _reports()] == ["other"]


def test_legacy_itinerary_id_field_still_works(client, author, reporters):
    itinerary = _itinerary(client, author["access_token"])
    response = client.post(
        "/reports",
        json={"itinerary_id": itinerary, "reason": "spam"},
        headers=auth_headers(reporters[0]["access_token"]),
    )

    assert response.status_code == 201
    report = _reports()[0]
    assert report.target_type == "itinerary"
    assert str(report.target_id) == itinerary


def test_canonical_reason_is_accepted(client, author, reporters):
    itinerary = _itinerary(client, author["access_token"])
    assert _report(
        client, itinerary, reporters[0]["access_token"], "hate_speech"
    ).status_code == 201


def test_unknown_reason_is_still_a_422(client, author, reporters):
    itinerary = _itinerary(client, author["access_token"])
    assert _report(
        client, itinerary, reporters[0]["access_token"], "rude"
    ).status_code == 422


def test_a_report_with_no_target_is_rejected(client, reporters):
    response = client.post(
        "/reports", json={"reason": "spam"},
        headers=auth_headers(reporters[0]["access_token"]),
    )
    assert response.status_code == 422


# ---------------------------------------------------------------------------
# Distinct-reporter thresholds
# ---------------------------------------------------------------------------

def test_one_report_below_threshold_does_not_hide(client, author, reporters):
    itinerary = _itinerary(client, author["access_token"])
    _report(client, itinerary, reporters[0]["access_token"], "spam")

    assert _row(Itinerary, itinerary).hidden_at is None
    assert _logs("auto_hide_reports") == []


def test_threshold_reached_hides_immediately(client, author, reporters):
    """hate_speech needs two distinct reporters — the second one takes it down
    without waiting for the review deadline."""
    itinerary = _itinerary(client, author["access_token"])

    _report(client, itinerary, reporters[0]["access_token"], "hate_speech")
    assert _row(Itinerary, itinerary).hidden_at is None

    _report(client, itinerary, reporters[1]["access_token"], "hate_speech")

    row = _row(Itinerary, itinerary)
    assert row.hidden_at is not None
    assert row.moderation_status == "hidden"
    assert len(_logs("auto_hide_reports")) == 1


def test_one_user_reporting_repeatedly_counts_once(client, author, reporters):
    """Otherwise a single griefer could hide anything."""
    itinerary = _itinerary(client, author["access_token"])

    for _ in range(5):
        _report(client, itinerary, reporters[0]["access_token"], "hate_speech")

    assert _row(Itinerary, itinerary).hidden_at is None
    assert len(_reports()) == 1  # re-reporting is idempotent


def test_reports_of_different_reasons_do_not_accumulate(client, author, reporters):
    """Thresholds are per reason — a spam report and a harassment report are not
    two votes for the same thing."""
    itinerary = _itinerary(client, author["access_token"])

    _report(client, itinerary, reporters[0]["access_token"], "harassment")
    _report(client, itinerary, reporters[1]["access_token"], "spam")

    assert _row(Itinerary, itinerary).hidden_at is None


@pytest.mark.parametrize("reason", ["csam", "sexual_content", "violence_threat"])
def test_severe_categories_hide_on_a_single_report(client, author, reporters, reason):
    itinerary = _itinerary(client, author["access_token"])
    _report(client, itinerary, reporters[0]["access_token"], reason)

    assert _row(Itinerary, itinerary).hidden_at is not None


def test_auto_hide_resolves_the_report_as_auto_hidden(client, author, reporters):
    """Distinct from content_hidden — the audit trail must not claim a moderator
    acted when none did."""
    itinerary = _itinerary(client, author["access_token"])
    _report(client, itinerary, reporters[0]["access_token"], "sexual_content")

    assert [r.resolution for r in _reports()] == ["auto_hidden"]


def test_thresholds_are_configurable(client, author, reporters, monkeypatch):
    monkeypatch.setattr(
        get_settings(), "REPORT_HIDE_THRESHOLDS", "spam:1,hate_speech:9",
    )
    itinerary = _itinerary(client, author["access_token"])

    _report(client, itinerary, reporters[0]["access_token"], "spam")
    assert _row(Itinerary, itinerary).hidden_at is not None


def test_an_unknown_reason_key_never_auto_hides(client, author, reporters, monkeypatch):
    """A threshold config missing a category must fail safe — leave it to a human
    rather than hiding on the first report."""
    monkeypatch.setattr(get_settings(), "REPORT_HIDE_THRESHOLDS", "spam:4")
    itinerary = _itinerary(client, author["access_token"])

    _report(client, itinerary, reporters[0]["access_token"], "hate_speech")
    assert _row(Itinerary, itinerary).hidden_at is None


# ---------------------------------------------------------------------------
# The classifier-corroboration discount
# ---------------------------------------------------------------------------

def _flag_itinerary(itinerary_id: str) -> None:
    db = TestingSessionLocal()
    try:
        row = db.get(Itinerary, uuid.UUID(itinerary_id))
        row.moderation_status = "flagged"
        db.commit()
    finally:
        db.close()


def test_already_flagged_content_needs_one_fewer_reporter(client, author, reporters):
    """Machine suspicion plus one human report is high confidence — waiting for a
    second reporter would leave it up for no good reason."""
    itinerary = _itinerary(client, author["access_token"])
    _flag_itinerary(itinerary)

    _report(client, itinerary, reporters[0]["access_token"], "hate_speech")

    assert _row(Itinerary, itinerary).hidden_at is not None


def _seed_decision(itinerary_id: str, scores: dict) -> None:
    db = TestingSessionLocal()
    try:
        db.add(TextModerationDecision(
            content_hash="a" * 64,
            target_type="itinerary",
            target_id=uuid.UUID(itinerary_id),
            outcome="review",
            scores=scores,
            policy_version="1",
            source="write",
        ))
        db.commit()
    finally:
        db.close()


def test_a_corroborating_score_discounts_the_threshold(client, author, reporters):
    itinerary = _itinerary(client, author["access_token"])
    _seed_decision(itinerary, {"hate": 0.55})  # at hate's review threshold

    _report(client, itinerary, reporters[0]["access_token"], "hate_speech")

    assert _row(Itinerary, itinerary).hidden_at is not None


def test_a_score_for_an_unrelated_category_does_not_discount(client, author, reporters):
    """A high harassment score is not evidence for a spam report."""
    itinerary = _itinerary(client, author["access_token"])
    _seed_decision(itinerary, {"harassment": 0.9})

    _report(client, itinerary, reporters[0]["access_token"], "hate_speech")

    assert _row(Itinerary, itinerary).hidden_at is None


def test_the_discount_floors_at_one_reporter(client, author, reporters):
    """A category already needing one reporter cannot be discounted to zero."""
    itinerary = _itinerary(client, author["access_token"])
    _flag_itinerary(itinerary)

    assert _row(Itinerary, itinerary).hidden_at is None  # flagged alone hides nothing


# ---------------------------------------------------------------------------
# The ETag invariant
# ---------------------------------------------------------------------------

def test_auto_hide_does_not_bump_the_authors_etag(client, author, reporters):
    """The concurrency ETag IS updated_at. Moving it here would 412 the author's
    open editor over a moderation change they cannot even see."""
    itinerary = _itinerary(client, author["access_token"])
    before = client.get(
        f"/itineraries/{itinerary}", headers=auth_headers(author["access_token"])
    ).headers["ETag"]

    _report(client, itinerary, reporters[0]["access_token"], "sexual_content")

    after = client.get(
        f"/itineraries/{itinerary}", headers=auth_headers(author["access_token"])
    ).headers["ETag"]
    assert before == after

    # And the author's in-flight edit still succeeds with the old ETag.
    response = client.post(
        f"/itineraries/{itinerary}/annotations",
        json={"type": "info", "content": "still editing"},
        headers=locked_headers(client, itinerary,
                               auth_headers(author["access_token"]), before),
    )
    assert response.status_code == 201


# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------

def test_already_hidden_content_is_not_hidden_twice(client, author, reporters):
    itinerary = _itinerary(client, author["access_token"])

    _report(client, itinerary, reporters[0]["access_token"], "sexual_content")
    _report(client, itinerary, reporters[1]["access_token"], "sexual_content")

    # One hide, one audit row — the second report finds it already down.
    assert len(_logs("auto_hide_reports")) == 1


# ---------------------------------------------------------------------------
# CSAM escalation
# ---------------------------------------------------------------------------

def test_csam_report_opens_a_legal_escalation(client, author, reporters):
    itinerary = _itinerary(client, author["access_token"])
    _report(client, itinerary, reporters[0]["access_token"], "csam")

    escalations = _escalations()
    assert len(escalations) == 1
    assert escalations[0].source == "report"
    assert escalations[0].closed_at is None
    assert len(_logs("legal_escalate")) == 1


def test_csam_escalation_is_not_opened_twice(client, author, reporters):
    itinerary = _itinerary(client, author["access_token"])
    _report(client, itinerary, reporters[0]["access_token"], "csam")
    _report(client, itinerary, reporters[1]["access_token"], "csam")

    assert len(_escalations()) == 1


def test_a_non_csam_report_opens_no_escalation(client, author, reporters):
    itinerary = _itinerary(client, author["access_token"])
    _report(client, itinerary, reporters[0]["access_token"], "sexual_content")

    assert _escalations() == []


# ---------------------------------------------------------------------------
# Author notification + audit privacy
# ---------------------------------------------------------------------------

def test_auto_hide_notifies_the_author_with_an_appeal_path(
    client, author, reporters, capture_email
):
    itinerary = _itinerary(client, author["access_token"], title="My Trip")
    _report(client, itinerary, reporters[0]["access_token"], "sexual_content")

    assert len(capture_email.moderation) == 1
    email = capture_email.moderation[0]
    assert email["to"] == "author@example.com"
    assert "My Trip" in email["html"]          # their own content, to them
    assert "/appeal/" in email["html"]         # one-tap contest path
    assert "sexual content" in email["html"]   # plain language, not the raw id


def test_notification_copy_is_not_accusatory(client, author, reporters, capture_email):
    """An automated hide pending review is not a finding of guilt."""
    itinerary = _itinerary(client, author["access_token"])
    _report(client, itinerary, reporters[0]["access_token"], "sexual_content")

    body = capture_email.moderation[0]["html"].lower()
    assert "pending review" in body
    assert "not deleted" in body
    for accusation in ("you violated", "your violation", "banned", "punish"):
        assert accusation not in body


def test_automated_audit_rows_carry_no_snapshot_or_personal_data(
    client, author, reporters
):
    """§26: an audit record must never contain raw content text, email addresses,
    or display names."""
    itinerary = _itinerary(client, author["access_token"], title="Secret Title")
    _report(client, itinerary, reporters[0]["access_token"], "sexual_content")

    row = _logs("auto_hide_reports")[0]
    assert row.admin_user_id is None     # no human acted
    assert row.content_snapshot is None
    assert "Secret Title" not in row.reason
    assert "author@example.com" not in row.reason
    # …but the reason is still a real statement of reasons, not a generic string.
    assert "sexual content" in row.reason
    assert "threshold" in row.reason


def test_exactly_one_audit_row_per_action(client, author, reporters):
    itinerary = _itinerary(client, author["access_token"])
    _report(client, itinerary, reporters[0]["access_token"], "hate_speech")
    _report(client, itinerary, reporters[1]["access_token"], "hate_speech")

    assert len(_logs("auto_hide_reports")) == 1


# ---------------------------------------------------------------------------
# Polymorphic targets
# ---------------------------------------------------------------------------

def test_a_rating_can_be_reported_and_hidden(client, author, reporters):
    itinerary = _itinerary(client, author["access_token"])
    client.post(
        f"/itineraries/{itinerary}/ratings",
        json={"stars": 1, "note": "abusive review"},
        headers=auth_headers(reporters[0]["access_token"]),
    )

    db = TestingSessionLocal()
    try:
        rating_id = str(db.query(ItineraryRating).one().id)
    finally:
        db.close()

    response = _report(
        client, rating_id, reporters[1]["access_token"], "harassment", "rating"
    )
    assert response.status_code == 201
    _report(client, rating_id, reporters[2]["access_token"], "harassment", "rating")

    assert _row(ItineraryRating, rating_id).moderation_status == "hidden"
    # The itinerary itself is untouched — a stranger's review is not the owner's
    # content.
    assert _row(Itinerary, itinerary).hidden_at is None


def test_hiding_a_rating_updates_the_average(client, author, reporters):
    itinerary = _itinerary(client, author["access_token"])
    client.post(
        f"/itineraries/{itinerary}/ratings",
        json={"stars": 1, "note": "abusive review"},
        headers=auth_headers(reporters[0]["access_token"]),
    )
    assert _row(Itinerary, itinerary).rating_count == 1

    db = TestingSessionLocal()
    try:
        rating_id = str(db.query(ItineraryRating).one().id)
    finally:
        db.close()
    _report(client, rating_id, reporters[1]["access_token"], "sexual_content", "rating")

    row = _row(Itinerary, itinerary)
    assert row.rating_count == 0
    assert row.rating_avg is None


def test_a_profile_can_be_reported_and_hidden(client, author, reporters):
    client.patch(
        "/users/me",
        json={"display_name": "Abusive Name"},
        headers=auth_headers(author["access_token"]),
    )
    response = _report(
        client, author["user_id"], reporters[0]["access_token"], "harassment", "user"
    )
    assert response.status_code == 201
    _report(client, author["user_id"], reporters[1]["access_token"], "harassment", "user")

    assert _row(User, author["user_id"]).moderation_status == "hidden"
    # A hidden profile is not a ban — the account still works.
    assert _row(User, author["user_id"]).is_active is True


def test_reporting_your_own_content_is_refused(client, author):
    itinerary = _itinerary(client, author["access_token"])
    response = _report(client, itinerary, author["access_token"], "spam")

    assert response.status_code == 400
    assert response.json()["code"] == "report_own_content"


def test_a_hidden_itinerary_404s_rather_than_admitting_it_was_moderated(
    client, author, reporters
):
    itinerary = _itinerary(client, author["access_token"])
    _report(client, itinerary, reporters[0]["access_token"], "sexual_content")

    # Now hidden. A fresh reporter must not be able to tell that from a 404.
    response = _report(client, itinerary, reporters[1]["access_token"], "spam")
    assert response.status_code == 404
