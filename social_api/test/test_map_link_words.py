"""
test_map_link_words.py — the words in a stop's map link are moderated.

A Google Maps link carries words someone typed — `google.com/maps/search/<words>`,
`?q=<words>`, a place's name — and Google shows them in the map's search box on
the stop page. Until 2026-11-09 no scan read them. `map_link_words`
(validators/map_link.py) reads them out of the link, and a stop write sends them
with the stop's other text, in the same provider request; the sweep's re-check
reads them too. They are not held to the link rule: they live inside the one
link a stop may have, so a search for `Hotel atlas.ma` stays legal.

Coverage:
  map_link_words — place, search and directions paths, the word parameters,
    decoding, and nothing for a short link or a bare viewport
  add_stop / update_stop send the words in the stop's one request; a reject
    in them refuses the write; a write that leaves the link alone sends none
  the words are not held to the link rule
  the sweep's re-check reads them
"""

from __future__ import annotations

import uuid

import pytest
from fastapi.testclient import TestClient

from conftest import TestingSessionLocal, auth_headers, edit_now, register_user
from app.config import get_settings
from app.models.itinerary import Itinerary
from app.services import sweep_service
from app.services import text_moderation_service as tms
from app.services.text_moderation_providers import ProviderResult
from app.validators.map_link import map_link_words

REJECT = {"hate": 0.9}


class WordProvider:
    """Rejects any text holding `word`; records every text it is sent."""

    name = "stub"
    model = "stub-model"

    def __init__(self, word: str):
        self.word = word
        self.calls: list[str] = []

    def score(self, text: str) -> ProviderResult:
        self.calls.append(text)
        scores = REJECT if self.word in text else {}
        return ProviderResult(scores=scores, provider=self.name, model=self.model)


@pytest.fixture()
def provider(monkeypatch):
    monkeypatch.setattr(get_settings(), "TEXT_MODERATION_PROVIDER", "openai")
    monkeypatch.setattr(get_settings(), "OPENAI_API_KEY", "test-key")
    stub = WordProvider("vile")
    monkeypatch.setattr(tms, "get_provider_chain", lambda settings: [stub])
    return stub


@pytest.fixture()
def trip(client):
    user = register_user(client, "alice", "alice@example.com")
    hdrs = auth_headers(user["access_token"])
    r = client.post("/itineraries/", json={"title": "Old town"}, headers=hdrs)
    assert r.status_code == 201, r.text
    return r.json()["id"], hdrs


def _add(client: TestClient, trip_id: str, hdrs: dict, **fields):
    return client.post(f"/itineraries/{trip_id}/stops",
                       json={"place_name": "Market", **fields},
                       headers=edit_now(client, trip_id, hdrs))


def _update(client: TestClient, trip_id: str, stop_id: str, hdrs: dict, **fields):
    return client.patch(f"/itineraries/{trip_id}/stops/{stop_id}", json=fields,
                        headers=edit_now(client, trip_id, hdrs))


# ---------------------------------------------------------------------------
# map_link_words
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("url, words", [
    ("https://www.google.com/maps/place/Eiffel+Tower/@48.85,2.29,17z/data=!3m1!4b1?entry=ttu",
     "Eiffel Tower"),
    ("https://www.google.com/maps/search/vile+words/@48.85,2.29,15z", "vile words"),
    ("https://www.google.com/maps/search/?api=1&query=Hotel+atlas.ma", "Hotel atlas.ma"),
    ("https://maps.google.com/?q=Caf%C3%A9+de+Flore&hl=fr", "Café de Flore"),
    ("https://www.google.com/maps/dir/Paris/Lyon/", "Paris\nLyon"),
    ("https://www.google.com/maps/dir/?api=1&origin=Home&destination=Souk&waypoints=A%7CB",
     "Home\nSouk\nA|B"),
    ("https://maps.google.com/maps?saddr=Rabat&daddr=Fes", "Rabat\nFes"),
])
def test_the_words_a_link_carries(url, words):
    assert map_link_words(url) == words


@pytest.mark.parametrize("url", [
    None,
    "https://maps.app.goo.gl/abc123",
    "https://goo.gl/maps/abc123",
    "https://www.google.com/maps/@48.85,2.29,15z",
    "https://www.google.com/maps",
])
def test_a_link_with_no_words(url):
    assert map_link_words(url) is None


# ---------------------------------------------------------------------------
# The stop writes
# ---------------------------------------------------------------------------

def test_add_stop_scans_the_words_with_the_stop_in_one_request(client, trip, provider):
    trip_id, hdrs = trip
    r = _add(client, trip_id, hdrs, notes="Fresh figs",
             map_url="https://www.google.com/maps/search/spice+souk")
    assert r.status_code == 201, r.text
    assert len(provider.calls) == 1
    assert "Fresh figs" in provider.calls[0] and "spice souk" in provider.calls[0]


def test_vile_words_in_a_link_refuse_the_stop(client, trip, provider):
    trip_id, hdrs = trip
    r = _add(client, trip_id, hdrs, map_url="https://www.google.com/maps/search/vile+words")
    assert r.status_code == 422, r.text
    assert r.json()["code"] == "text_moderation_rejected"


def test_the_words_are_not_held_to_the_link_rule(client, trip, provider):
    """A search for a hotel named after its site is a search, not a link in text."""
    trip_id, hdrs = trip
    r = _add(client, trip_id, hdrs,
             map_url="https://www.google.com/maps/search/?api=1&query=Hotel+atlas.ma")
    assert r.status_code == 201, r.text


def test_update_stop_scans_a_new_links_words_and_only_then(client, trip, provider):
    trip_id, hdrs = trip
    stop_id = _add(client, trip_id, hdrs,
                   map_url="https://www.google.com/maps/search/spice+souk").json()["id"]
    provider.calls.clear()

    r = _update(client, trip_id, stop_id, hdrs, notes="Go early")
    assert r.status_code == 200, r.text
    assert provider.calls == ["Go early"]  # the link was not part of this write

    r = _update(client, trip_id, stop_id, hdrs,
                map_url="https://www.google.com/maps/search/vile+words")
    assert r.status_code == 422, r.text
    r = client.get(f"/itineraries/{trip_id}", headers=hdrs)
    stops = [s for t in r.json()["tracks"] for s in t["stops"]]
    assert stops[0]["map_url"] == "https://www.google.com/maps/search/spice+souk"


def test_the_sweeps_recheck_reads_the_words(client, trip):
    trip_id, hdrs = trip
    stop_id = _add(client, trip_id, hdrs,
                   map_url="https://www.google.com/maps/search/spice+souk").json()["id"]
    db = TestingSessionLocal()
    try:
        fields = sweep_service._itinerary_fields(db.get(Itinerary, uuid.UUID(trip_id)))
    finally:
        db.close()
    assert fields[f"stop:{stop_id}:map_url"] == "spice souk"
