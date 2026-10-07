"""
test_translation_pretranslate.py — public trip titles translated ahead of time.

A title strangers can read is translated in the background when it becomes
readable (a public trip created, a trip published) or changes. Nothing else
spends a translation: not drafts (only_me), not followers or restricted trips,
not stop or note saves, not a description edit. TestClient runs background
tasks right after the response, so the effects are visible at once.
"""

import uuid
from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from conftest import register_user
from app.config import get_settings
from app.models.itinerary import Itinerary
from app.services import translation_service
from translation_helpers import (  # noqa: F401 — engines is a fixture
    TITLE, cached_title_langs, engines, make_trip, set_row, write,
)


@pytest.fixture()
def pretranslating(monkeypatch, engines):
    monkeypatch.setattr(get_settings(), "TRANSLATION_PRETRANSLATE_LANGS", "fr,de,en")
    return engines


@pytest.fixture()
def owner(client):
    return register_user(client, "owner", "owner@example.com")


def test_a_public_trip_is_translated_into_every_language_but_its_own(
    client: TestClient, owner, pretranslating,
):
    trip = make_trip(client, owner["access_token"])
    assert cached_title_langs(trip) == ["de", "fr"]  # the title is English
    assert {lang for _, lang in pretranslating.first.calls} == {"fr", "de"}


@pytest.mark.parametrize("visibility", ["only_me", "followers", "restricted"])
def test_a_trip_strangers_cannot_read_is_never_pretranslated(
    client: TestClient, owner, pretranslating, visibility,
):
    make_trip(client, owner["access_token"], visibility=visibility)
    assert pretranslating.first.calls == []


def test_publishing_a_draft_translates_its_title(client: TestClient, owner, pretranslating):
    token = owner["access_token"]
    trip = make_trip(client, token, visibility="only_me")
    write(client, token, trip, "PATCH", f"/itineraries/{trip}", {"visibility": "public"})
    assert cached_title_langs(trip) == ["de", "fr"]


def test_a_new_public_title_is_translated_again(client: TestClient, owner, pretranslating):
    token = owner["access_token"]
    trip = make_trip(client, token)
    write(client, token, trip, "PATCH", f"/itineraries/{trip}",
          {"title": "Three days of hiking in the green hills"})

    texts = [fields["title"] for fields, _ in pretranslating.first.calls]
    assert texts.count("Three days of hiking in the green hills") == 2
    # The old title's translations went with the edit.
    assert cached_title_langs(trip) == ["de", "fr"]


@pytest.mark.parametrize("body", [
    {"description": "A whole new description of the walk along the harbour."},
    {"recommended_period_note": "Best in spring, before the crowds arrive."},
])
def test_other_edits_spend_nothing(client: TestClient, owner, pretranslating, body):
    token = owner["access_token"]
    trip = make_trip(client, token)
    calls = len(pretranslating.first.calls)
    write(client, token, trip, "PATCH", f"/itineraries/{trip}", body)
    write(client, token, trip, "POST", f"/itineraries/{trip}/stops",
          {"place_name": "Le Vieux-Port", "notes": "Arrive early in the morning."})
    assert len(pretranslating.first.calls) == calls


def test_running_it_again_spends_nothing(client: TestClient, owner, pretranslating):
    trip = make_trip(client, owner["access_token"])
    calls = len(pretranslating.first.calls)
    translation_service.pretranslate_title(uuid.UUID(trip), get_settings())
    assert len(pretranslating.first.calls) == calls


@pytest.mark.parametrize("values", [
    {"hidden_at": datetime.now(timezone.utc)},
    {"deleted_at": datetime.now(timezone.utc)},
    {"moderation_status": "hidden"},
    {"visibility": "only_me"},
], ids=["hidden", "deleted", "taken-down", "no-longer-public"])
def test_the_task_rereads_the_trip_and_skips_what_strangers_cannot_read(
    client: TestClient, owner, engines, values,
):
    trip = make_trip(client, owner["access_token"])
    set_row(Itinerary, trip, **values)
    translation_service.pretranslate_title(uuid.UUID(trip), get_settings())
    assert engines.first.calls == []


def test_nothing_is_scheduled_with_translation_off(client: TestClient, owner, monkeypatch):
    called = []
    monkeypatch.setattr(translation_service, "pretranslate_title",
                        lambda *a, **k: called.append(a))
    make_trip(client, owner["access_token"])
    assert called == []


def test_a_failing_engine_never_fails_the_save(client: TestClient, owner, pretranslating):
    from app.services.translation_providers import TranslatorUnavailableError
    from translation_fakes import FakeTranslator

    pretranslating.chain = [FakeTranslator("first", fail=TranslatorUnavailableError("down"))]
    trip = make_trip(client, owner["access_token"])  # make_trip asserts the 201
    assert cached_title_langs(trip) == []
