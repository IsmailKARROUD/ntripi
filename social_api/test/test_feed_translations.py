"""
test_feed_translations.py — cached title translations riding along in the feed.

GET /itineraries/feed?lang=xx carries each trip's source_lang and, when the
cache holds one for the current title, its translation into `lang`. The
language is a query parameter so the URL stays the client cache's whole key.
"""

import uuid

import pytest
from fastapi.testclient import TestClient

from conftest import TestingSessionLocal, auth_headers, register_user
from app.models.content_translation import ContentTranslation
from app.services.translation_service import source_hash
from translation_helpers import TITLE, engines, make_trip  # noqa: F401 — engines is a fixture


def _seed_title(trip_id, text_hashed, translated, lang="fr", source_lang="en"):
    db = TestingSessionLocal()
    try:
        db.add(ContentTranslation(
            itinerary_id=uuid.UUID(trip_id), content_type="itinerary",
            content_id=uuid.UUID(trip_id), field="title", target_lang=lang,
            source_hash=source_hash(text_hashed), source_lang=source_lang,
            translated_text=translated, provider="fake",
        ))
        db.commit()
    finally:
        db.close()


def _feed(client, token, lang=None):
    url = "/itineraries/feed" + (f"?lang={lang}" if lang else "")
    r = client.get(url, headers=auth_headers(token))
    assert r.status_code == 200, r.text
    return r.json()


@pytest.fixture()
def reader_and_trip(client):
    owner = register_user(client, "owner", "owner@example.com")
    reader = register_user(client, "reader", "reader@example.com")
    return reader, make_trip(client, owner["access_token"])


def test_the_translation_rides_along_for_the_asked_language(
    client: TestClient, reader_and_trip, engines,
):
    reader, trip = reader_and_trip
    _seed_title(trip, TITLE, "Un week-end tranquille autour du vieux port")

    item = _feed(client, reader["access_token"], lang="fr")[0]
    assert item["source_lang"] == "en"
    assert item["title_translation"] == {
        "lang": "fr", "text": "Un week-end tranquille autour du vieux port"}
    assert _feed(client, reader["access_token"], lang="de")[0]["title_translation"] is None


def test_without_a_language_there_is_no_translation(client: TestClient, reader_and_trip, engines):
    reader, trip = reader_and_trip
    _seed_title(trip, TITLE, "Un week-end tranquille")
    item = _feed(client, reader["access_token"])[0]
    assert item["source_lang"] == "en"
    assert item["title_translation"] is None


def test_a_translation_of_an_older_title_is_ignored(client: TestClient, reader_and_trip, engines):
    reader, trip = reader_and_trip
    _seed_title(trip, "A title the trip no longer has", "Un ancien titre")
    assert _feed(client, reader["access_token"], lang="fr")[0]["title_translation"] is None


def test_a_title_already_in_the_language_gets_none(client: TestClient, reader_and_trip, engines):
    reader, trip = reader_and_trip
    _seed_title(trip, TITLE, TITLE, lang="en", source_lang="en")
    assert _feed(client, reader["access_token"], lang="en")[0]["title_translation"] is None


def test_with_translation_off_nothing_rides_along(client: TestClient, reader_and_trip):
    reader, trip = reader_and_trip
    _seed_title(trip, TITLE, "Un week-end tranquille")
    assert _feed(client, reader["access_token"], lang="fr")[0]["title_translation"] is None


def test_new_keys_are_appended_after_owner(client: TestClient, reader_and_trip, engines):
    reader, _ = reader_and_trip
    keys = list(_feed(client, reader["access_token"], lang="fr")[0])
    assert keys[-3:] == ["owner", "source_lang", "title_translation"]


def test_a_malformed_language_is_422(client: TestClient, reader_and_trip, engines):
    reader, _ = reader_and_trip
    r = client.get("/itineraries/feed?lang=fra", headers=auth_headers(reader["access_token"]))
    assert r.status_code == 422
