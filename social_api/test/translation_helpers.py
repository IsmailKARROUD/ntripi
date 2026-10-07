"""
translation_helpers.py — shared setup for the translation endpoint, limits,
pre-translation and feed tests.

`engines` turns translation on (TRANSLATION_PROVIDERS=openai with a fake key),
keeps text moderation off, and swaps the engine chain for FakeTranslators —
no test reaches the network.
"""

import uuid

import pytest
from sqlalchemy import func, select

from conftest import TestingSessionLocal, auth_headers, edit_now
from app.config import get_settings
from app.models.content_translation import ContentTranslation
from app.services import translation_service
from translation_fakes import FakeTranslator

TITLE = "A slow weekend walking around the old harbour"
DESCRIPTION = "Two quiet days walking along the water and eating fresh fish at sunset."


class Engines:
    def __init__(self):
        self.first = FakeTranslator("first")
        self.chain = [self.first]


@pytest.fixture()
def engines(monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "TRANSLATION_PROVIDERS", "openai")
    monkeypatch.setattr(settings, "OPENAI_API_KEY", "sk-test")
    monkeypatch.setattr(settings, "TEXT_MODERATION_PROVIDER", "disabled")
    # Off unless a test turns it on: a public trip created on the way to
    # testing something else must not spend engine calls in the background.
    monkeypatch.setattr(settings, "TRANSLATION_PRETRANSLATE_LANGS", "")
    # Background pre-translation opens its own session; point it at the suite's.
    monkeypatch.setattr(translation_service, "_session_factory", TestingSessionLocal)
    state = Engines()
    monkeypatch.setattr(translation_service, "get_translator_chain", lambda s: state.chain)
    return state


def make_trip(client, token, *, visibility="public", title=TITLE,
              description=DESCRIPTION) -> str:
    body = {"title": title, "visibility": visibility}
    if description is not None:
        body["description"] = description
    r = client.post("/itineraries/", json=body, headers=auth_headers(token))
    assert r.status_code == 201, r.text
    return r.json()["id"]


def write(client, token, trip_id, method, path, body):
    r = client.request(method, path, json=body,
                       headers=edit_now(client, trip_id, auth_headers(token)))
    assert r.status_code in (200, 201), r.text
    return r.json()


def translate(client, token, items, lang="fr"):
    return client.post("/translations", json={"target_lang": lang, "items": items},
                       headers=auth_headers(token))


def trip_item(trip_id, fields=("title", "description")):
    return {"content_type": "itinerary", "content_id": trip_id, "fields": list(fields)}


def cached_count() -> int:
    db = TestingSessionLocal()
    try:
        return db.execute(select(func.count(ContentTranslation.id))).scalar_one()
    finally:
        db.close()


def cached_title_langs(trip_id) -> list[str]:
    db = TestingSessionLocal()
    try:
        return sorted(db.execute(select(ContentTranslation.target_lang).where(
            ContentTranslation.content_type == "itinerary",
            ContentTranslation.content_id == uuid.UUID(trip_id),
            ContentTranslation.field == "title",
        )).scalars())
    finally:
        db.close()


def set_row(model, row_id, **values) -> None:
    db = TestingSessionLocal()
    try:
        row = db.get(model, uuid.UUID(row_id))
        for name, value in values.items():
            setattr(row, name, value)
        db.commit()
    finally:
        db.close()
