"""
test_link_rule.py — no user text carries a link, except a stop's map link.

The samples live in social_flutter/test/support/link_rule_samples.json, which
the app's own test reads too: the server's find_link and the app's findLink
quote the same characters for every one of them, or one suite fails. The two
top-level-domain lists (app/constants/tlds.py and the app's
lib/core/text/tlds.dart) are generated together and held equal here.

Coverage:
  TestDetector    — every sample; the two TLD lists are one
  TestRefusal     — a changed value with a link is refused, naming the field and
                    the exact text; an unchanged one never is
  TestWritePaths  — every write that stores user text refuses a new link with
                    422 text_contains_link before any moderation call, and lets
                    an untouched old link through (the trip form re-sends the
                    note on every save)
"""

import json
import re
import uuid
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from app.constants.tlds import IANA_TLDS, IANA_TLDS_VERSION
from app.errors import ApiError
from app.models.annotation import Annotation
from app.models.itinerary import Itinerary
from app.models.itinerary_annotation import ItineraryAnnotation
from app.models.itinerary_rating import ItineraryRating
from app.models.stop import Stop
from app.models.transport_leg import TransportLeg
from app.models.user import User
from app.services import text_moderation_service as tms
from app.services.text_moderation_providers import ProviderResult
from app.validators.links import find_link, refuse_new_links
from conftest import (
    ADULT_DOB, TestingSessionLocal, auth_headers, edit_now, register_user,
)

API = Path(__file__).resolve().parents[1]
FLUTTER = API.parent / "social_flutter"
SAMPLES = FLUTTER / "test" / "support" / "link_rule_samples.json"
DART_TLDS = FLUTTER / "lib" / "core" / "text" / "tlds.dart"

LINK = "www.example.com"
OLD = "Booked on booking.com before the rule"


def _samples() -> list[dict]:
    assert SAMPLES.exists(), (
        f"{SAMPLES} is missing — the server and the app share this list, so "
        "the test runs with the whole monorepo checked out"
    )
    return json.loads(SAMPLES.read_text("utf-8"))["samples"]


class TestDetector:
    @pytest.mark.parametrize("case", _samples(), ids=lambda c: c["why"])
    def test_each_sample(self, case):
        assert find_link(case["text"]) == case["match"]

    def test_the_two_tld_lists_are_one(self):
        source = DART_TLDS.read_text("utf-8")
        version = re.search(r"const ianaTldsVersion = '(\d+)';", source)
        names = re.findall(r"^  '(.+)',$", source, re.M)
        assert version and version.group(1) == IANA_TLDS_VERSION
        assert set(names) == IANA_TLDS and len(names) == len(IANA_TLDS)


class TestRefusal:
    def test_a_changed_value_is_refused_with_the_field_and_the_text(self):
        with pytest.raises(ApiError) as caught:
            refuse_new_links({"title": "Trip", "notes": f"see {LINK} first"})
        error = caught.value
        assert error.status_code == 422 and error.code == "text_contains_link"
        assert error.extra == {"field": "notes", "match": LINK}

    def test_an_unchanged_value_is_spared_from_a_mapping_or_a_row(self):
        refuse_new_links({"notes": OLD}, {"notes": OLD})

        class Row:
            notes = OLD
        refuse_new_links({"notes": OLD}, Row())

    def test_no_text_is_never_refused(self):
        refuse_new_links({"notes": None, "title": ""})


# ---------------------------------------------------------------------------
# Write paths
# ---------------------------------------------------------------------------

class _CountingProvider:
    name = "stub"
    model = "stub-model"

    def __init__(self):
        self.calls: list[str] = []

    def score(self, text: str) -> ProviderResult:
        self.calls.append(text)
        return ProviderResult(scores={"hate": 0.01}, provider=self.name, model=self.model)


@pytest.fixture()
def provider(monkeypatch):
    monkeypatch.setattr(get_settings(), "TEXT_MODERATION_PROVIDER", "openai")
    monkeypatch.setattr(get_settings(), "OPENAI_API_KEY", "test-key")
    stub = _CountingProvider()
    monkeypatch.setattr(tms, "get_provider_chain", lambda settings: [stub])
    return stub


@pytest.fixture()
def owner(client):
    return register_user(client, "owner", "owner@example.com")


def _hdrs(user) -> dict:
    return auth_headers(user["access_token"])


def _trip(client, user, **fields) -> str:
    r = client.post("/itineraries/",
                    json={"title": "Links", "currency": "EUR", **fields},
                    headers=_hdrs(user))
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _seed(model, row_id, **values) -> None:
    """Store text as it was stored before the rule — the API would refuse it."""
    db = TestingSessionLocal()
    try:
        row = db.get(model, uuid.UUID(str(row_id)))
        for key, value in values.items():
            setattr(row, key, value)
        db.commit()
    finally:
        db.close()


def _refused(r, field: str, match: str, provider) -> None:
    assert r.status_code == 422, r.text
    body = r.json()
    assert body["code"] == "text_contains_link", body
    assert body["field"] == field and body["match"] == match
    assert provider.calls == [], "a refused write must not spend a moderation call"


def _stop(client, user, trip_id, **fields) -> dict:
    r = client.post(f"/itineraries/{trip_id}/stops",
                    json={"place_name": "Stop", **fields},
                    headers=edit_now(client, trip_id, _hdrs(user)))
    assert r.status_code == 201, r.text
    return r.json()


class TestWritePaths:
    def test_create_trip(self, client, owner, provider):
        r = client.post("/itineraries/",
                        json={"title": "Links", "currency": "EUR",
                              "description": f"Read {LINK} first"},
                        headers=_hdrs(owner))
        _refused(r, "description", LINK, provider)

    def test_create_trip_with_a_cover(self, client, owner, provider):
        r = client.post("/itineraries/form",
                        data={"fields": json.dumps({"title": "anna.paris",
                                                    "currency": "EUR"})},
                        files={"image": ("c.jpg", b"never read", "image/jpeg")},
                        headers=_hdrs(owner))
        _refused(r, "title", "anna.paris", provider)

    def test_update_trip(self, client, owner, provider):
        trip = _trip(client, owner)
        provider.calls.clear()
        r = client.patch(f"/itineraries/{trip}",
                         json={"recommended_period_note": f"Go via {LINK}"},
                         headers=edit_now(client, trip, _hdrs(owner)))
        _refused(r, "recommended_period_note", LINK, provider)

    def test_an_old_link_rides_along_an_unrelated_save(self, client, owner, provider):
        trip = _trip(client, owner)
        _seed(Itinerary, trip, recommended_period_note=OLD, description=OLD)
        r = client.patch(f"/itineraries/{trip}",
                         json={"title": "Renamed", "recommended_period_note": OLD},
                         headers=edit_now(client, trip, _hdrs(owner)))
        assert r.status_code == 200, r.text
        # The form route re-sends the note on every save too.
        r = client.patch(f"/itineraries/{trip}/form",
                         data={"fields": json.dumps({"title": "Again",
                                                     "recommended_period_note": OLD})},
                         headers=edit_now(client, trip, _hdrs(owner)))
        assert r.status_code == 200, r.text

    def test_update_trip_form_refuses_a_new_link(self, client, owner, provider):
        trip = _trip(client, owner)
        provider.calls.clear()
        r = client.patch(f"/itineraries/{trip}/form",
                         data={"fields": json.dumps({"title": "Mail anna@gmail.com"})},
                         headers=edit_now(client, trip, _hdrs(owner)))
        _refused(r, "title", "anna@gmail.com", provider)

    def test_add_stop(self, client, owner, provider):
        trip = _trip(client, owner)
        provider.calls.clear()
        r = client.post(f"/itineraries/{trip}/stops",
                        json={"place_name": "booking.com"},
                        headers=edit_now(client, trip, _hdrs(owner)))
        _refused(r, "place_name", "booking.com", provider)

    def test_a_google_search_text_is_checked(self, client, owner, provider):
        trip = _trip(client, owner)
        provider.calls.clear()
        r = client.post(f"/itineraries/{trip}/stops",
                        json={"place_name": "Lunch", "place_source": "google",
                              "google_place_id": "ChIJLU7jZClu5kcR4PcOOO6p3I0",
                              "google_place_query": f"cafe {LINK}"},
                        headers=edit_now(client, trip, _hdrs(owner)))
        _refused(r, "google_place_query", LINK, provider)

    def test_update_stop(self, client, owner, provider):
        trip = _trip(client, owner)
        stop = _stop(client, owner, trip)
        _seed(Stop, stop["id"], notes=OLD)
        r = client.patch(f"/itineraries/{trip}/stops/{stop['id']}",
                         json={"place_name": "Renamed", "notes": OLD},
                         headers=edit_now(client, trip, _hdrs(owner)))
        assert r.status_code == 200, r.text
        provider.calls.clear()
        r = client.patch(f"/itineraries/{trip}/stops/{stop['id']}",
                         json={"notes": f"{OLD}, and {LINK}"},
                         headers=edit_now(client, trip, _hdrs(owner)))
        _refused(r, "notes", "booking.com", provider)

    def test_trip_annotations(self, client, owner, provider):
        trip = _trip(client, owner)
        provider.calls.clear()
        r = client.post(f"/itineraries/{trip}/annotations",
                        json={"type": "info", "content": f"Tickets: {LINK}"},
                        headers=edit_now(client, trip, _hdrs(owner)))
        _refused(r, "content", LINK, provider)

        r = client.post(f"/itineraries/{trip}/annotations",
                        json={"type": "info", "content": "Bring cash"},
                        headers=edit_now(client, trip, _hdrs(owner)))
        assert r.status_code == 201, r.text
        note_id = r.json()["id"]
        _seed(ItineraryAnnotation, note_id, content=OLD)
        r = client.patch(f"/itineraries/{trip}/annotations/{note_id}",
                         json={"type": "caution", "content": OLD},
                         headers=edit_now(client, trip, _hdrs(owner)))
        assert r.status_code == 200, r.text

    def test_stop_annotations(self, client, owner, provider):
        trip = _trip(client, owner)
        stop = _stop(client, owner, trip)
        provider.calls.clear()
        r = client.post(f"/itineraries/{trip}/stops/{stop['id']}/annotations",
                        json={"type": "advice", "content": f"Book at {LINK}"},
                        headers=edit_now(client, trip, _hdrs(owner)))
        _refused(r, "content", LINK, provider)

        r = client.post(f"/itineraries/{trip}/stops/{stop['id']}/annotations",
                        json={"type": "advice", "content": "Go early"},
                        headers=edit_now(client, trip, _hdrs(owner)))
        assert r.status_code == 201, r.text
        note_id = r.json()["id"]
        _seed(Annotation, note_id, content=OLD)
        r = client.patch(
            f"/itineraries/{trip}/stops/{stop['id']}/annotations/{note_id}",
            json={"content": OLD, "type": "info"},
            headers=edit_now(client, trip, _hdrs(owner)))
        assert r.status_code == 200, r.text

    def test_transport_legs(self, client, owner, provider):
        trip = _trip(client, owner)
        a = _stop(client, owner, trip)
        b = _stop(client, owner, trip)
        provider.calls.clear()
        segment = {"from_stop_id": a["id"], "to_stop_id": b["id"]}
        r = client.post(f"/itineraries/{trip}/segments",
                        json={**segment, "legs": [{"position": 1, "mode": "bus",
                                                   "notes": f"Times on {LINK}"}]},
                        headers=edit_now(client, trip, _hdrs(owner)))
        _refused(r, "leg0_notes", LINK, provider)

        r = client.post(f"/itineraries/{trip}/segments",
                        json={**segment, "legs": [{"position": 1, "mode": "bus",
                                                   "notes": "Line 42"}]},
                        headers=edit_now(client, trip, _hdrs(owner)))
        assert r.status_code == 201, r.text
        seg = r.json()
        leg_id = seg["legs"][0]["id"]
        _seed(TransportLeg, leg_id, notes=OLD)

        # A segment update replaces every leg: the old leg's text is not new.
        r = client.patch(f"/itineraries/{trip}/segments/{seg['id']}",
                         json={**segment, "legs": [{"position": 1, "mode": "tram",
                                                    "notes": OLD}]},
                         headers=edit_now(client, trip, _hdrs(owner)))
        assert r.status_code == 200, r.text
        new_leg = r.json()["legs"][0]["id"]

        provider.calls.clear()
        r = client.patch(f"/itineraries/{trip}/segments/{seg['id']}/legs/{new_leg}",
                         json={"direction": "towards anna.paris"},
                         headers=edit_now(client, trip, _hdrs(owner)))
        _refused(r, "direction", "anna.paris", provider)

        r = client.post(f"/itineraries/{trip}/segments/{seg['id']}/legs",
                        json={"position": 2, "mode": "walk", "line": "x.co.uk"},
                        headers=edit_now(client, trip, _hdrs(owner)))
        _refused(r, "leg0_line", "x.co.uk", provider)

    def test_ratings(self, client, owner, provider):
        trip = _trip(client, owner, visibility="public")
        rater = register_user(client, "rater", "rater@example.com")
        provider.calls.clear()
        r = client.post(f"/itineraries/{trip}/ratings",
                        json={"stars": 4, "note": f"Cheaper on {LINK}"},
                        headers=_hdrs(rater))
        _refused(r, "note", LINK, provider)

        r = client.post(f"/itineraries/{trip}/ratings",
                        json={"stars": 4, "note": "Lovely"}, headers=_hdrs(rater))
        assert r.status_code == 201, r.text
        db = TestingSessionLocal()
        try:  # the review's own row, found by trip and reviewer
            review = db.query(ItineraryRating).filter_by(
                itinerary_id=uuid.UUID(trip), user_id=uuid.UUID(rater["user_id"]),
            ).one()
            review.note = OLD
            db.commit()
        finally:
            db.close()
        r = client.post(f"/itineraries/{trip}/ratings",
                        json={"stars": 5, "note": OLD}, headers=_hdrs(rater))
        assert r.status_code == 201, r.text

    def test_profile(self, client, owner, provider):
        r = client.patch("/users/me", json={"bio": f"My blog: {LINK}"},
                         headers=_hdrs(owner))
        _refused(r, "bio", LINK, provider)

        _seed(User, owner["user_id"], bio=OLD)
        r = client.patch("/users/me", json={"display_name": "Anna", "bio": OLD},
                         headers=_hdrs(owner))
        assert r.status_code == 200, r.text

    def test_sign_up(self, client, provider):
        base = {"email": "anna@example.com", "password": "test1234",
                "tos_accepted": True, "date_of_birth": ADULT_DOB}
        r = client.post("/auth/register", json={**base, "username": "anna.paris"})
        _refused(r, "username", "anna.paris", provider)

        r = client.post("/auth/register",
                        json={**base, "username": "annatravels",
                              "display_name": f"Anna {LINK}"})
        _refused(r, "display_name", LINK, provider)
