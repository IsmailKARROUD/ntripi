"""
test_text_moderation_endpoints.py — text moderation through the HTTP layer.

Proves the write paths behave as specified end-to-end: the four outcomes, the
"a version conflict must not consume a moderation call" rule, one provider call
per multi-field write, and the read filtering that keeps moderated content away
from everyone but its author.

The provider chain is stubbed at the service module (no network, no API key).
"""

from __future__ import annotations

import uuid

import pytest

from conftest import (
    TestingSessionLocal, auth_headers, etag_from_updated_at, register_user,
)
from app.config import get_settings
from app.models.itinerary import Itinerary
from app.models.itinerary_rating import ItineraryRating
from app.models.text_moderation_decision import TextModerationDecision
from app.models.user import User
from app.services import text_moderation_service as tms
from app.services.text_moderation_providers import ProviderResult


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

class CountingProvider:
    """Canned scores plus a call counter, so "was the provider actually hit?"
    is an exact assertion rather than an inference."""

    name = "stub"
    model = "stub-model"

    def __init__(self, scores: dict[str, float] | None = None):
        self.scores = scores or {}
        self.calls: list[str] = []

    def score(self, text: str) -> ProviderResult:
        self.calls.append(text)
        return ProviderResult(scores=self.scores, provider=self.name, model=self.model)


@pytest.fixture()
def provider(monkeypatch):
    """Enable text moderation with a clean-verdict stub. Tests that need a
    different verdict mutate `provider.scores`."""
    monkeypatch.setattr(get_settings(), "TEXT_MODERATION_PROVIDER", "openai")
    monkeypatch.setattr(get_settings(), "OPENAI_API_KEY", "test-key")
    stub = CountingProvider()
    monkeypatch.setattr(tms, "get_provider_chain", lambda settings: [stub])
    return stub


# Score sets that map onto each policy outcome (see moderation_policy).
CLEAN = {"hate": 0.01}
REVIEW = {"harassment": 0.6}
REJECT = {"hate": 0.9}
MINORS = {"sexual/minors": 0.15}


@pytest.fixture()
def owner(client):
    return register_user(client, "owner", "owner@example.com")


@pytest.fixture()
def stranger(client):
    return register_user(client, "stranger", "stranger@example.com")


def _create_itinerary(client, token, **fields) -> dict:
    body = {"title": "A trip", "currency": "EUR", "visibility": "public", **fields}
    response = client.post("/itineraries/", json=body, headers=auth_headers(token))
    assert response.status_code == 201, response.json()
    return response.json()


def _status_of(itinerary_id: str) -> str:
    return _itinerary_row(itinerary_id).moderation_status


def _itinerary_row(itinerary_id: str) -> Itinerary:
    """Fresh read of the row straight from the DB. Detached before return so the
    caller can read attributes after the session closes."""
    db = TestingSessionLocal()
    try:
        row = db.get(Itinerary, uuid.UUID(itinerary_id))
        assert row is not None
        db.expunge(row)
        return row
    finally:
        db.close()


def _decisions() -> list[TextModerationDecision]:
    db = TestingSessionLocal()
    try:
        return db.query(TextModerationDecision).all()
    finally:
        db.close()


def _etag(client, itinerary_id, token) -> str:
    response = client.get(f"/itineraries/{itinerary_id}", headers=auth_headers(token))
    return response.headers["ETag"]


# ---------------------------------------------------------------------------
# Default-off behaviour
# ---------------------------------------------------------------------------

def test_moderation_disabled_leaves_writes_untouched(client, owner):
    """The shipped default must behave exactly as it did before this feature."""
    itinerary = _create_itinerary(client, owner["access_token"], description="anything")
    assert itinerary["title"] == "A trip"
    assert _status_of(itinerary["id"]) == "approved"
    assert _decisions() == []


# ---------------------------------------------------------------------------
# Itinerary create / update
# ---------------------------------------------------------------------------

def test_clean_itinerary_publishes_approved(client, owner, provider):
    itinerary = _create_itinerary(client, owner["access_token"], description="Lovely walk")
    assert _status_of(itinerary["id"]) == "approved"
    assert len(provider.calls) == 1


def test_review_outcome_publishes_but_flags(client, owner, provider):
    """'flagged' is an internal state: the write succeeds and the author is not
    told, but a moderator gets a queue item."""
    provider.scores = REVIEW
    itinerary = _create_itinerary(client, owner["access_token"], description="borderline")

    assert _status_of(itinerary["id"]) == "flagged"
    assert [d.outcome for d in _decisions()] == ["review"]


def test_rejected_itinerary_is_not_created(client, owner, provider):
    provider.scores = REJECT
    response = client.post(
        "/itineraries/",
        json={"title": "A trip", "description": "vile", "currency": "EUR",
              "visibility": "public"},
        headers=auth_headers(owner["access_token"]),
    )

    assert response.status_code == 422
    assert response.json()["code"] == "text_moderation_rejected"

    db = TestingSessionLocal()
    try:
        assert db.query(Itinerary).count() == 0  # nothing written
    finally:
        db.close()


def test_rejection_response_never_echoes_the_submitted_text(client, owner, provider):
    provider.scores = REJECT
    secret = "the exact words the user typed"
    response = client.post(
        "/itineraries/",
        json={"title": "A trip", "description": secret, "currency": "EUR",
              "visibility": "public"},
        headers=auth_headers(owner["access_token"]),
    )

    assert secret not in response.text


def test_rejection_response_names_categories_in_plain_fields(client, owner, provider):
    """The client needs to say *why* in plain language, so category names ship
    as structured data rather than being baked into the message."""
    provider.scores = REJECT
    response = client.post(
        "/itineraries/",
        json={"title": "A trip", "description": "vile", "currency": "EUR",
              "visibility": "public"},
        headers=auth_headers(owner["access_token"]),
    )

    assert "hate" in response.json()["categories"]


def test_minors_score_publishes_hidden_and_escalated(client, owner, provider):
    provider.scores = MINORS
    itinerary = _create_itinerary(client, owner["access_token"], description="...")

    row = _itinerary_row(itinerary["id"])
    assert row.moderation_status == "hidden"
    assert row.hidden_at is not None


def test_provider_outage_publishes_as_pending(client, owner, monkeypatch):
    """A vendor outage must not block a user from posting."""
    monkeypatch.setattr(get_settings(), "TEXT_MODERATION_PROVIDER", "openai")
    monkeypatch.setattr(get_settings(), "OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(tms, "get_provider_chain", lambda settings: [])

    itinerary = _create_itinerary(client, owner["access_token"], description="Lovely walk")
    assert _status_of(itinerary["id"]) == "pending"


def test_update_only_scans_the_submitted_fields(client, owner, provider):
    itinerary = _create_itinerary(client, owner["access_token"], description="First text")
    provider.calls.clear()

    client.patch(
        f"/itineraries/{itinerary['id']}",
        json={"visibility": "only_me"},
        headers=auth_headers(owner["access_token"]),
    )
    assert provider.calls == []  # no text submitted, no paid call

    client.patch(
        f"/itineraries/{itinerary['id']}",
        json={"description": "Second text"},
        headers=auth_headers(owner["access_token"]),
    )
    assert len(provider.calls) == 1


def test_a_clean_edit_does_not_clear_an_existing_flag(client, owner, provider):
    """Two tiers write this column; escalate-only means a tidy caption cannot
    launder an unresolved flag."""
    provider.scores = REVIEW
    itinerary = _create_itinerary(client, owner["access_token"], description="borderline")
    assert _status_of(itinerary["id"]) == "flagged"

    provider.scores = CLEAN
    client.patch(
        f"/itineraries/{itinerary['id']}",
        json={"description": "entirely wholesome now"},
        headers=auth_headers(owner["access_token"]),
    )

    assert _status_of(itinerary["id"]) == "flagged"


# ---------------------------------------------------------------------------
# ETag interaction — the "a 412 must not cost a moderation call" rule
# ---------------------------------------------------------------------------

def test_stale_if_match_returns_412_without_calling_the_provider(client, owner, provider):
    itinerary = _create_itinerary(client, owner["access_token"])
    provider.calls.clear()

    response = client.post(
        f"/itineraries/{itinerary['id']}/stops",
        json={"place_name": "Grote Markt", "notes": "Go early"},
        headers={**auth_headers(owner["access_token"]),
                 "If-Match": etag_from_updated_at("2020-01-01T00:00:00+00:00")},
    )

    assert response.status_code == 412
    assert provider.calls == []


def test_missing_if_match_returns_428_without_calling_the_provider(client, owner, provider):
    itinerary = _create_itinerary(client, owner["access_token"])
    provider.calls.clear()

    response = client.post(
        f"/itineraries/{itinerary['id']}/stops",
        json={"place_name": "Grote Markt"},
        headers=auth_headers(owner["access_token"]),
    )

    assert response.status_code == 428
    assert provider.calls == []


def test_non_owner_gets_403_without_calling_the_provider(client, owner, stranger, provider):
    itinerary = _create_itinerary(client, owner["access_token"])
    etag = _etag(client, itinerary["id"], owner["access_token"])
    provider.calls.clear()

    response = client.post(
        f"/itineraries/{itinerary['id']}/stops",
        json={"place_name": "Grote Markt"},
        headers={**auth_headers(stranger["access_token"]), "If-Match": etag},
    )

    assert response.status_code == 403
    assert provider.calls == []


# ---------------------------------------------------------------------------
# Stops, annotations, legs — one call per request
# ---------------------------------------------------------------------------

def test_a_stops_three_text_fields_are_one_provider_call(client, owner, provider):
    itinerary = _create_itinerary(client, owner["access_token"])
    etag = _etag(client, itinerary["id"], owner["access_token"])
    provider.calls.clear()

    response = client.post(
        f"/itineraries/{itinerary['id']}/stops",
        json={"place_name": "Grote Markt", "place_address": "Brussels",
              "notes": "Go early"},
        headers={**auth_headers(owner["access_token"]), "If-Match": etag},
    )

    assert response.status_code == 201
    assert len(provider.calls) == 1
    assert all(word in provider.calls[0] for word in ("Grote", "Brussels", "early"))


def test_rejected_stop_text_blocks_the_stop(client, owner, provider):
    itinerary = _create_itinerary(client, owner["access_token"])
    etag = _etag(client, itinerary["id"], owner["access_token"])
    provider.scores = REJECT

    response = client.post(
        f"/itineraries/{itinerary['id']}/stops",
        json={"place_name": "Somewhere", "notes": "vile"},
        headers={**auth_headers(owner["access_token"]), "If-Match": etag},
    )

    assert response.status_code == 422
    assert response.json()["code"] == "text_moderation_rejected"


def test_stop_text_rolls_its_status_up_to_the_itinerary(client, owner, provider):
    """Stops have no status column — hiding is itinerary-level, so that is
    where a stop's verdict lands."""
    itinerary = _create_itinerary(client, owner["access_token"])
    etag = _etag(client, itinerary["id"], owner["access_token"])
    provider.scores = REVIEW

    client.post(
        f"/itineraries/{itinerary['id']}/stops",
        json={"place_name": "Somewhere", "notes": "borderline"},
        headers={**auth_headers(owner["access_token"]), "If-Match": etag},
    )

    assert _status_of(itinerary["id"]) == "flagged"


def test_rejected_annotation_is_not_created(client, owner, provider):
    itinerary = _create_itinerary(client, owner["access_token"])
    etag = _etag(client, itinerary["id"], owner["access_token"])
    provider.scores = REJECT

    response = client.post(
        f"/itineraries/{itinerary['id']}/annotations",
        json={"type": "advice", "content": "vile"},
        headers={**auth_headers(owner["access_token"]), "If-Match": etag},
    )

    assert response.status_code == 422


# ---------------------------------------------------------------------------
# Ratings — their own status, and their own read filter
# ---------------------------------------------------------------------------

def test_rejected_review_note_blocks_the_rating(client, owner, stranger, provider):
    itinerary = _create_itinerary(client, owner["access_token"])
    provider.scores = REJECT

    response = client.post(
        f"/itineraries/{itinerary['id']}/ratings",
        json={"stars": 1, "note": "vile"},
        headers=auth_headers(stranger["access_token"]),
    )

    assert response.status_code == 422


def test_a_hidden_review_note_does_not_hide_the_itinerary(client, owner, stranger, provider):
    """A stranger's moderated review must never take down someone else's trip."""
    itinerary = _create_itinerary(client, owner["access_token"])
    provider.scores = MINORS

    client.post(
        f"/itineraries/{itinerary['id']}/ratings",
        json={"stars": 3, "note": "..."},
        headers=auth_headers(stranger["access_token"]),
    )

    row = _itinerary_row(itinerary["id"])
    assert row.hidden_at is None
    assert row.moderation_status == "approved"


def _hide_rating(itinerary_id: str, author_id: str | None = None) -> None:
    db = TestingSessionLocal()
    try:
        query = db.query(ItineraryRating).filter(
            ItineraryRating.itinerary_id == uuid.UUID(itinerary_id)
        )
        if author_id is not None:
            query = query.filter(ItineraryRating.user_id == uuid.UUID(author_id))
        rating = query.one()
        rating.moderation_status = "hidden"
        db.commit()
    finally:
        db.close()


def test_hidden_rating_is_invisible_to_others_but_visible_to_its_author(
    client, owner, stranger, provider
):
    itinerary = _create_itinerary(client, owner["access_token"])
    client.post(
        f"/itineraries/{itinerary['id']}/ratings",
        json={"stars": 3, "note": "My review"},
        headers=auth_headers(stranger["access_token"]),
    )
    _hide_rating(itinerary["id"])

    as_owner = client.get(
        f"/itineraries/{itinerary['id']}/ratings",
        headers=auth_headers(owner["access_token"]),
    ).json()
    assert as_owner["ratings"] == []

    as_author = client.get(
        f"/itineraries/{itinerary['id']}/ratings",
        headers=auth_headers(stranger["access_token"]),
    ).json()
    assert [r["note"] for r in as_author["ratings"]] == ["My review"]


def test_hidden_rating_is_excluded_from_the_average(client, owner, stranger, provider):
    """The aggregate is a read path too — a hidden rating must not move the
    number everyone else sees. Two raters, one hidden: only the survivor counts."""
    third = register_user(client, "third", "third@example.com")
    itinerary = _create_itinerary(client, owner["access_token"])

    client.post(
        f"/itineraries/{itinerary['id']}/ratings",
        json={"stars": 1, "note": "Abusive review"},
        headers=auth_headers(stranger["access_token"]),
    )
    client.post(
        f"/itineraries/{itinerary['id']}/ratings",
        json={"stars": 5, "note": "Genuine review"},
        headers=auth_headers(third["access_token"]),
    )
    assert _itinerary_row(itinerary["id"]).rating_avg == 3.0

    _hide_rating(itinerary["id"], stranger["user_id"])
    # Averages are denormalized, so they move on the next recalculation — here
    # the surviving rater re-submitting an unchanged score.
    client.post(
        f"/itineraries/{itinerary['id']}/ratings",
        json={"stars": 5, "note": "Genuine review"},
        headers=auth_headers(third["access_token"]),
    )

    row = _itinerary_row(itinerary["id"])
    assert row.rating_count == 1
    assert row.rating_avg == 5.0  # the hidden 1-star is gone from the aggregate


# ---------------------------------------------------------------------------
# Profile text
# ---------------------------------------------------------------------------

def _hide_user(email: str) -> None:
    db = TestingSessionLocal()
    try:
        user = db.query(User).filter(User.email == email).one()
        user.moderation_status = "hidden"
        db.commit()
    finally:
        db.close()


def test_rejected_bio_is_not_saved(client, owner, provider):
    provider.scores = REJECT
    response = client.patch(
        "/users/me",
        json={"bio": "vile"},
        headers=auth_headers(owner["access_token"]),
    )

    assert response.status_code == 422
    profile = client.get("/users/me", headers=auth_headers(owner["access_token"])).json()
    assert profile["bio"] is None


def test_hidden_profile_text_degrades_to_the_username_for_others(
    client, owner, stranger, provider
):
    client.patch(
        "/users/me",
        json={"display_name": "Owner Name", "bio": "About me"},
        headers=auth_headers(owner["access_token"]),
    )
    _hide_user("owner@example.com")

    seen = client.get(
        f"/users/{owner['user_id']}", headers=auth_headers(stranger["access_token"])
    ).json()
    assert seen["display_name"] is None  # client renders @username instead
    assert seen["bio"] is None
    assert seen["username"] == "owner"


def test_author_still_sees_their_own_moderated_profile_text(client, owner, provider):
    client.patch(
        "/users/me",
        json={"display_name": "Owner Name", "bio": "About me"},
        headers=auth_headers(owner["access_token"]),
    )
    _hide_user("owner@example.com")

    own = client.get("/users/me", headers=auth_headers(owner["access_token"])).json()
    assert own["display_name"] == "Owner Name"
    assert own["bio"] == "About me"


def test_hidden_display_name_does_not_leak_through_search(
    client, owner, stranger, provider
):
    """Search is where an abusive handle would get the most reach."""
    client.patch(
        "/users/me",
        json={"display_name": "Owner Name"},
        headers=auth_headers(owner["access_token"]),
    )
    _hide_user("owner@example.com")

    results = client.get(
        "/users/search?q=owner", headers=auth_headers(stranger["access_token"])
    ).json()
    assert results
    assert all(row["display_name"] is None for row in results)


def test_a_rewritten_bio_clears_the_previous_flag(client, owner, provider):
    """Unlike itineraries, profile text is replaced wholesale, so a cleaned-up
    bio is genuinely new content."""
    provider.scores = REVIEW
    client.patch("/users/me", json={"bio": "borderline"},
                 headers=auth_headers(owner["access_token"]))

    db = TestingSessionLocal()
    try:
        assert db.query(User).filter(User.email == "owner@example.com").one(
        ).moderation_status == "flagged"
    finally:
        db.close()

    provider.scores = CLEAN
    client.patch("/users/me", json={"bio": "wholesome"},
                 headers=auth_headers(owner["access_token"]))

    db = TestingSessionLocal()
    try:
        assert db.query(User).filter(User.email == "owner@example.com").one(
        ).moderation_status == "approved"
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Length caps
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("field,limit", [("description", 4000)])
def test_oversized_text_is_rejected_before_the_provider(
    client, owner, provider, field, limit
):
    """Caps bound what one request can submit to a paid API — they must fire
    during validation, before any call is made."""
    response = client.post(
        "/itineraries/",
        json={"title": "A trip", field: "x" * (limit + 1), "currency": "EUR",
              "visibility": "public"},
        headers=auth_headers(owner["access_token"]),
    )

    assert response.status_code == 422
    assert provider.calls == []
