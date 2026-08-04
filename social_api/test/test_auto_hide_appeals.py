"""
test_auto_hide_appeals.py — contesting an automated decision.

Auto-hides are provisional: a classifier or a reporter count took the content
down and no human has judged it. So the contest path has to work end to end,
including for the SLA hide whose entire premise is "we could not review this in
time, but you can still ask us to".

Also pins the IDOR guard: an appeal target must belong to the person appealing.
"""

from __future__ import annotations

import uuid

import pytest

from conftest import (
    ADMIN_BASIC, TestingSessionLocal, admin_session, auth_headers, make_admin,
    register_user,
)
from app.models.appeal import Appeal
from app.models.itinerary import Itinerary
from app.models.itinerary_rating import ItineraryRating
from app.models.moderation_log import ModerationLog
from app.models.user import User


@pytest.fixture()
def author(client):
    return register_user(client, "author", "author@example.com")


@pytest.fixture()
def reporters(client):
    return [
        register_user(client, f"rep{index}", f"rep{index}@example.com")
        for index in range(3)
    ]


@pytest.fixture(autouse=True)
def no_mail(monkeypatch):
    monkeypatch.setattr(
        "app.services.email_service.send_email", lambda to, subject, html: None
    )


def _itinerary(client, token, title="A trip") -> str:
    response = client.post(
        "/itineraries/",
        json={"title": title, "currency": "EUR", "visibility": "public"},
        headers=auth_headers(token),
    )
    assert response.status_code == 201, response.json()
    return response.json()["id"]


def _auto_hide(client, itinerary_id, reporter_token, reason="sexual_content") -> None:
    """Trip a severe-category threshold so the content is hidden with no human
    involvement."""
    response = client.post(
        "/reports",
        json={"target_type": "itinerary", "target_id": itinerary_id, "reason": reason},
        headers=auth_headers(reporter_token),
    )
    assert response.status_code == 201


def _row(model, row_id):
    db = TestingSessionLocal()
    try:
        row = db.get(model, uuid.UUID(str(row_id)))
        if row is not None:
            db.expunge(row)
        return row
    finally:
        db.close()


def _appeal(client, token, target_type, target_id, reason="This was a mistake."):
    return client.post(
        "/appeals",
        json={"target_type": target_type, "target_id": target_id, "reason": reason},
        headers=auth_headers(token),
    )


# ---------------------------------------------------------------------------
# The violations feed surfaces automated actions
# ---------------------------------------------------------------------------

def test_an_auto_hide_appears_in_the_authors_violations_feed(client, author, reporters):
    itinerary = _itinerary(client, author["access_token"], title="My Trip")
    _auto_hide(client, itinerary, reporters[0]["access_token"])

    feed = client.get(
        "/appeals/violations", headers=auth_headers(author["access_token"])
    ).json()["violations"]

    assert len(feed) == 1
    assert feed[0]["action"] == "auto_hide_reports"
    assert feed[0]["appealable"] is True
    assert feed[0]["item_title"] == "My Trip"


def test_the_feed_never_returns_the_moderated_content_itself(client, author, reporters):
    itinerary = _itinerary(client, author["access_token"], title="My Trip")
    client.patch(
        f"/itineraries/{itinerary}",
        json={"description": "the actual prose that was flagged"},
        headers=auth_headers(author["access_token"]),
    )
    _auto_hide(client, itinerary, reporters[0]["access_token"])

    body = client.get(
        "/appeals/violations", headers=auth_headers(author["access_token"])
    ).text

    assert "the actual prose" not in body


def test_another_users_auto_hide_is_not_listed(client, author, reporters):
    itinerary = _itinerary(client, author["access_token"])
    _auto_hide(client, itinerary, reporters[0]["access_token"])

    feed = client.get(
        "/appeals/violations", headers=auth_headers(reporters[1]["access_token"])
    ).json()["violations"]

    assert feed == []


# ---------------------------------------------------------------------------
# Filing
# ---------------------------------------------------------------------------

def test_an_auto_hide_can_be_appealed(client, author, reporters):
    """The headline requirement: a one-tap contest path for automated takedowns."""
    itinerary = _itinerary(client, author["access_token"])
    _auto_hide(client, itinerary, reporters[0]["access_token"])

    response = _appeal(client, author["access_token"], "itinerary", itinerary)

    assert response.status_code == 201
    db = TestingSessionLocal()
    try:
        assert db.query(Appeal).one().status == "pending"
    finally:
        db.close()


def test_filing_an_appeal_is_audited(client, author, reporters):
    """The audit row is the evidence that the contest path was available."""
    itinerary = _itinerary(client, author["access_token"])
    _auto_hide(client, itinerary, reporters[0]["access_token"])
    _appeal(client, author["access_token"], "itinerary", itinerary)

    db = TestingSessionLocal()
    try:
        rows = db.query(ModerationLog).filter(
            ModerationLog.action == "appeal_filed"
        ).all()
    finally:
        db.close()

    assert len(rows) == 1
    assert rows[0].admin_user_id is None
    assert rows[0].content_snapshot is None


def test_a_second_appeal_on_the_same_item_is_refused(client, author, reporters):
    itinerary = _itinerary(client, author["access_token"])
    _auto_hide(client, itinerary, reporters[0]["access_token"])
    _appeal(client, author["access_token"], "itinerary", itinerary)

    response = _appeal(client, author["access_token"], "itinerary", itinerary)

    assert response.status_code == 409
    assert response.json()["code"] == "appeal_already_pending"


def test_you_cannot_appeal_someone_elses_action(client, author, reporters):
    """The IDOR guard — without it anyone could contest anyone's moderation."""
    itinerary = _itinerary(client, author["access_token"])
    _auto_hide(client, itinerary, reporters[0]["access_token"])

    response = _appeal(client, reporters[1]["access_token"], "itinerary", itinerary)

    assert response.status_code == 404
    assert response.json()["code"] == "appeal_target_not_found"


def test_an_appeal_needs_a_reason(client, author, reporters):
    itinerary = _itinerary(client, author["access_token"])
    _auto_hide(client, itinerary, reporters[0]["access_token"])

    response = _appeal(client, author["access_token"], "itinerary", itinerary, reason="  ")

    assert response.status_code == 422


def test_clean_content_has_nothing_to_appeal(client, author):
    itinerary = _itinerary(client, author["access_token"])

    response = _appeal(client, author["access_token"], "itinerary", itinerary)

    assert response.status_code == 404


# ---------------------------------------------------------------------------
# Deciding
# ---------------------------------------------------------------------------

@pytest.fixture()
def moderator(client, admin_enabled):
    admin = register_user(client, "moddy", "mod@example.com")
    make_admin("mod@example.com")
    admin_session(client, "moddy")
    return admin


def _decide(client, appeal_id, decision, response_text="Reviewed."):
    return client.post(
        f"/admin/appeals/{appeal_id}/decide",
        data={"decision": decision, "admin_response": response_text},
        auth=ADMIN_BASIC, follow_redirects=False,
    )


def _appeal_id() -> str:
    db = TestingSessionLocal()
    try:
        return str(db.query(Appeal).one().id)
    finally:
        db.close()


def test_a_granted_appeal_makes_the_content_visible_again(
    client, author, reporters, moderator
):
    itinerary = _itinerary(client, author["access_token"])
    _auto_hide(client, itinerary, reporters[0]["access_token"])
    _appeal(client, author["access_token"], "itinerary", itinerary)

    assert _decide(client, _appeal_id(), "restore").status_code == 303

    row = _row(Itinerary, itinerary)
    assert row.hidden_at is None
    assert row.moderation_status == "approved"


def test_a_granted_appeal_preserves_the_authors_etag(
    client, author, reporters, moderator
):
    itinerary = _itinerary(client, author["access_token"])
    before = client.get(
        f"/itineraries/{itinerary}", headers=auth_headers(author["access_token"])
    ).headers["ETag"]
    _auto_hide(client, itinerary, reporters[0]["access_token"])
    _appeal(client, author["access_token"], "itinerary", itinerary)
    _decide(client, _appeal_id(), "restore")

    after = client.get(
        f"/itineraries/{itinerary}", headers=auth_headers(author["access_token"])
    ).headers["ETag"]
    assert before == after


def test_a_denied_appeal_leaves_the_content_hidden(client, author, reporters, moderator):
    itinerary = _itinerary(client, author["access_token"])
    _auto_hide(client, itinerary, reporters[0]["access_token"])
    _appeal(client, author["access_token"], "itinerary", itinerary)

    _decide(client, _appeal_id(), "uphold")

    assert _row(Itinerary, itinerary).hidden_at is not None


def test_reducing_an_auto_hide_says_so_honestly(client, author, reporters, moderator):
    """A hide is already the lightest content penalty — there is nothing below it,
    and the response must not imply otherwise."""
    itinerary = _itinerary(client, author["access_token"])
    _auto_hide(client, itinerary, reporters[0]["access_token"])
    _appeal(client, author["access_token"], "itinerary", itinerary)

    assert _decide(client, _appeal_id(), "reduce").status_code == 303
    assert _row(Itinerary, itinerary).hidden_at is not None


def test_every_appeal_decision_writes_exactly_one_audit_row(
    client, author, reporters, moderator
):
    itinerary = _itinerary(client, author["access_token"])
    _auto_hide(client, itinerary, reporters[0]["access_token"])
    _appeal(client, author["access_token"], "itinerary", itinerary)
    _decide(client, _appeal_id(), "restore")

    db = TestingSessionLocal()
    try:
        actions = [row.action for row in db.query(ModerationLog).all()]
    finally:
        db.close()

    assert actions.count("appeal_restore") == 1
    assert actions.count("appeal_filed") == 1


# ---------------------------------------------------------------------------
# Non-itinerary targets
# ---------------------------------------------------------------------------

def _hidden_rating(client, author, reporters) -> str:
    itinerary = _itinerary(client, author["access_token"])
    client.post(
        f"/itineraries/{itinerary}/ratings",
        json={"stars": 1, "note": "a review"},
        headers=auth_headers(reporters[0]["access_token"]),
    )
    db = TestingSessionLocal()
    try:
        rating_id = str(db.query(ItineraryRating).one().id)
    finally:
        db.close()
    client.post(
        "/reports",
        json={"target_type": "rating", "target_id": rating_id, "reason": "sexual_content"},
        headers=auth_headers(reporters[1]["access_token"]),
    )
    assert _row(ItineraryRating, rating_id).moderation_status == "hidden"
    return rating_id


def test_a_hidden_review_is_appealable_by_its_author(client, author, reporters):
    rating_id = _hidden_rating(client, author, reporters)

    # reporters[0] wrote the review, so it is theirs to appeal.
    response = _appeal(client, reporters[0]["access_token"], "rating", rating_id)

    assert response.status_code == 201


def test_a_review_cannot_be_appealed_by_someone_else(client, author, reporters):
    rating_id = _hidden_rating(client, author, reporters)

    response = _appeal(client, author["access_token"], "rating", rating_id)

    assert response.status_code == 404


def test_restoring_a_review_puts_it_back_in_the_average(
    client, author, reporters, moderator
):
    rating_id = _hidden_rating(client, author, reporters)
    itinerary_id = str(_row(ItineraryRating, rating_id).itinerary_id)
    assert _row(Itinerary, itinerary_id).rating_count == 0

    _appeal(client, reporters[0]["access_token"], "rating", rating_id)
    _decide(client, _appeal_id(), "restore")

    assert _row(ItineraryRating, rating_id).moderation_status == "approved"
    assert _row(Itinerary, itinerary_id).rating_count == 1


def test_admin_appeals_page_renders_a_review_appeal_with_context(
    client, author, reporters, moderator
):
    """Rating and profile appeals used to render with no target column at all —
    the row builder only ever resolved itineraries."""
    rating_id = _hidden_rating(client, author, reporters)
    assert _appeal(
        client, reporters[0]["access_token"], "rating", rating_id
    ).status_code == 201

    page = client.get("/admin/appeals", auth=ADMIN_BASIC)

    assert page.status_code == 200
    assert "your review" in page.text


def test_a_hidden_profile_is_appealable_by_its_owner(client, author, reporters):
    client.post(
        "/reports",
        json={"target_type": "user", "target_id": author["user_id"],
              "reason": "sexual_content"},
        headers=auth_headers(reporters[0]["access_token"]),
    )
    assert _row(User, author["user_id"]).moderation_status == "hidden"

    response = _appeal(client, author["access_token"], "user", author["user_id"])

    assert response.status_code == 201
