"""
test_place_refresh_sweep.py — the yearly check of stored Google place IDs.

Google recommends refreshing a place ID once it is a year old, with the free
IDs-only Place Details call. The sweep does it in batches, after its own
commit: an ID Google still knows is stamped, a replaced one is swapped, a dead
one is marked (never re-found — an editor picks again), and an outage stops the
batch. None of it may move the itinerary's concurrency ETag.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest
import requests

from conftest import TestingSessionLocal, auth_headers, edit_now, register_user
from app.config import get_settings
from app.models.itinerary import Itinerary
from app.models.stop import Stop
from app.services import google_places, sweep_service

OLD = datetime.now(timezone.utc) - timedelta(days=400)
FRESH = datetime.now(timezone.utc) - timedelta(days=10)


class FakeResponse:
    def __init__(self, status_code, payload=None):
        self.status_code = status_code
        self._payload = payload

    def json(self):
        if self._payload is None:
            raise ValueError("no JSON")
        return self._payload


class FakeDetails:
    """Answers per place ID; records the order of the calls."""

    def __init__(self):
        self.answers: dict[str, object] = {}
        self.calls: list[tuple[str, dict]] = []

    def get(self, url, headers=None, timeout=None):
        place_id = url.rsplit("/", 1)[1]
        self.calls.append((place_id, headers))
        answer = self.answers.get(place_id, FakeResponse(200, {"id": place_id}))
        if isinstance(answer, Exception):
            raise answer
        return answer


@pytest.fixture()
def details(monkeypatch):
    fake = FakeDetails()
    monkeypatch.setattr(google_places.requests, "get", fake.get)
    monkeypatch.setattr(get_settings(), "GOOGLE_PLACES_API_KEY", "test-places-key")
    return fake


@pytest.fixture()
def trip(client):
    user = register_user(client, "alice", "alice@example.com")
    headers = auth_headers(user["access_token"])
    response = client.post("/itineraries/", json={"title": "T", "currency": "EUR"},
                           headers=headers)
    return response.json()["id"], headers


def _google_stop(client, trip, place_id: str, checked_at: datetime | None) -> str:
    itinerary_id, headers = trip
    response = client.post(
        f"/itineraries/{itinerary_id}/stops",
        json={"place_name": "P", "place_source": "google",
              "google_place_id": place_id, "google_place_query": "q"},
        headers=edit_now(client, itinerary_id, headers),
    )
    assert response.status_code == 201, response.text
    stop_id = response.json()["id"]
    db = TestingSessionLocal()
    db.get(Stop, uuid.UUID(stop_id)).google_place_checked_at = checked_at
    db.commit()
    db.close()
    return stop_id


def _row(stop_id: str) -> Stop:
    db = TestingSessionLocal()
    try:
        return db.get(Stop, uuid.UUID(stop_id))
    finally:
        db.close()


def _sweep() -> dict:
    db = TestingSessionLocal()
    try:
        return sweep_service.run_moderation_sweep(db, get_settings())
    finally:
        db.close()


def test_a_year_old_id_is_confirmed_with_the_free_ids_only_call(client, trip, details):
    stop_id = _google_stop(client, trip, "ChIJoldplaceid0000001", OLD)

    counters = _sweep()

    [(place_id, headers)] = details.calls
    assert place_id == "ChIJoldplaceid0000001"
    assert headers["X-Goog-FieldMask"] == "id"
    assert counters["place_ids_checked"] == 1
    assert _row(stop_id).google_place_checked_at.replace(tzinfo=timezone.utc) > OLD


def test_a_fresh_id_is_left_alone(client, trip, details):
    _google_stop(client, trip, "ChIJfreshplaceid00001", FRESH)
    _sweep()
    assert details.calls == []


def test_a_replaced_id_is_swapped_and_a_dead_one_marked(client, trip, details):
    moved = _google_stop(client, trip, "ChIJmovedplaceid00001", OLD)
    dead = _google_stop(client, trip, "ChIJdeadplaceid000001", OLD)
    details.answers["ChIJmovedplaceid00001"] = FakeResponse(200, {"id": "ChIJnewplaceid0000001"})
    details.answers["ChIJdeadplaceid000001"] = FakeResponse(404, {"error": {"status": "NOT_FOUND"}})

    counters = _sweep()

    assert _row(moved).google_place_id == "ChIJnewplaceid0000001"
    assert _row(dead).google_place_id == "ChIJdeadplaceid000001"  # kept: never re-found
    assert _row(dead).google_place_missing_at is not None
    assert (counters["place_ids_changed"], counters["place_ids_missing"]) == (1, 1)

    # A marked ID is not asked about again.
    details.calls.clear()
    _sweep()
    assert [call[0] for call in details.calls] == []


def test_an_outage_stops_the_batch_and_leaves_the_rows(client, trip, details):
    first = _google_stop(client, trip, "ChIJfirstplaceid00001", OLD - timedelta(days=2))
    second = _google_stop(client, trip, "ChIJsecondplaceid0001", OLD)
    details.answers["ChIJfirstplaceid00001"] = requests.Timeout("slow")

    _sweep()

    assert [call[0] for call in details.calls] == ["ChIJfirstplaceid00001"]
    assert _row(first).google_place_checked_at.replace(tzinfo=timezone.utc) < OLD
    assert _row(first).google_place_missing_at is None
    assert _row(second).google_place_checked_at.replace(tzinfo=timezone.utc) == OLD


def test_a_batch_is_bounded(client, trip, details, monkeypatch):
    monkeypatch.setattr(get_settings(), "GOOGLE_PLACE_REFRESH_BATCH", 2)
    for i in range(3):
        _google_stop(client, trip, f"ChIJbatchplaceid0000{i}", OLD - timedelta(days=i))
    _sweep()
    assert len(details.calls) == 2


def test_without_the_key_nothing_is_asked(client, trip, details, monkeypatch):
    _google_stop(client, trip, "ChIJoldplaceid0000001", OLD)
    monkeypatch.setattr(get_settings(), "GOOGLE_PLACES_API_KEY", "")
    _sweep()
    assert details.calls == []


def test_a_refresh_never_moves_the_itinerary_etag(client, trip, details):
    itinerary_id, _ = trip
    _google_stop(client, trip, "ChIJmovedplaceid00001", OLD)
    details.answers["ChIJmovedplaceid00001"] = FakeResponse(200, {"id": "ChIJnewplaceid0000001"})
    db = TestingSessionLocal()
    before = db.get(Itinerary, uuid.UUID(itinerary_id)).updated_at
    db.close()

    _sweep()

    db = TestingSessionLocal()
    after = db.get(Itinerary, uuid.UUID(itinerary_id)).updated_at
    db.close()
    assert after == before


def test_an_editors_new_pick_meanwhile_wins(client, trip, details, monkeypatch):
    """The write is conditional on the ID the sweep read."""
    stop_id = _google_stop(client, trip, "ChIJmovedplaceid00001", OLD)
    details.answers["ChIJmovedplaceid00001"] = FakeResponse(200, {"id": "ChIJnewplaceid0000001"})
    real_refresh = google_places.refresh

    def pick_meanwhile(settings, place_id):
        db = TestingSessionLocal()
        db.get(Stop, uuid.UUID(stop_id)).google_place_id = "ChIJeditorspick000001"
        db.commit()
        db.close()
        return real_refresh(settings, place_id)

    monkeypatch.setattr(google_places, "refresh", pick_meanwhile)
    _sweep()

    assert _row(stop_id).google_place_id == "ChIJeditorspick000001"
