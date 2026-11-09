"""
test_currency.py — a trip's currency is a code from the ISO list.

The currency shows on every trip card, and until 2026-11-09 the API took any
three characters for it. It is now one of constants/currencies.py's codes —
exactly what the app's picker offers — on all four trip writes, refused with
422 `currency_not_supported` before any moderation call. A value the trip
already has is never refused (validators/currency.py), so a trip saved before
the rule, or priced in a currency later dropped from the list, stays editable.

Coverage:
  the server's list is the app's picker list, code for code
  both creates and both PATCHes refuse a code outside the list, costing no
    provider call; the metals, the test code and XXX are outside it
  an unchanged stored value passes; changing it to another unknown code does not
  an editor may change the currency, within the list
"""

from __future__ import annotations

import json
import uuid
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from conftest import TestingSessionLocal, auth_headers, edit_now, register_user
from test_image_moderation import _make_jpeg
from test_itinerary_form import (  # noqa: F401 — store is an autouse fixture
    _create_form, _editor, _save_form, _text_provider, store,
)
from app.constants.currencies import ISO_4217_CURRENCIES
from app.models.itinerary import Itinerary

APP_CURRENCIES = (
    Path(__file__).resolve().parents[2]
    / "social_flutter" / "assets" / "data" / "currencies.json"
)


@pytest.fixture()
def owner(client):
    return register_user(client, "owner", "owner@example.com")


@pytest.fixture()
def hdrs(owner):
    return auth_headers(owner["access_token"])


def _create(client: TestClient, hdrs: dict, **fields):
    body = {"title": "Coast walk", "visibility": "public", **fields}
    return client.post("/itineraries/", json=body, headers=hdrs)


def _patch(client: TestClient, trip: str, hdrs: dict, body: dict):
    return client.patch(f"/itineraries/{trip}", json=body,
                        headers=edit_now(client, trip, hdrs))


def _store_currency(trip: str, value: str) -> None:
    """Write a currency the API would refuse today, as one stored before the rule."""
    db = TestingSessionLocal()
    try:
        db.get(Itinerary, uuid.UUID(trip)).currency = value
        db.commit()
    finally:
        db.close()


def _stored_currency(trip: str) -> str:
    db = TestingSessionLocal()
    try:
        return db.get(Itinerary, uuid.UUID(trip)).currency
    finally:
        db.close()


def _refused(response) -> None:
    assert response.status_code == 422, response.text
    assert response.json()["code"] == "currency_not_supported"


def test_the_list_is_the_apps_picker():
    entries = json.loads(APP_CURRENCIES.read_text(encoding="utf-8"))
    picker = {entry["code"] for entry in entries if entry["type"] == "currency"}
    assert ISO_4217_CURRENCIES == picker


@pytest.mark.parametrize("code", ["EUR", "USD", "MAD", "JPY"])
def test_a_listed_code_is_accepted(client, hdrs, code):
    r = _create(client, hdrs, currency=code)
    assert r.status_code == 201, r.text
    assert r.json()["currency"] == code


@pytest.mark.parametrize("code", ["ABC", "eur", "XXX", "XAU", "XTS", "BGN"])
def test_a_code_outside_the_list_is_refused_on_create(client, hdrs, monkeypatch, code):
    provider = _text_provider(monkeypatch)
    _refused(_create(client, hdrs, currency=code))
    assert provider.calls == []  # refused before the scan


def test_the_form_create_refuses_it(client, owner):
    _refused(_create_form(client, owner["access_token"],
                          {"title": "Coast walk", "currency": "ABC"},
                          image=_make_jpeg()))


def test_a_patch_refuses_it_and_keeps_the_stored_one(client, hdrs, monkeypatch):
    trip = _create(client, hdrs, currency="USD").json()["id"]
    provider = _text_provider(monkeypatch)
    provider.calls.clear()

    _refused(_patch(client, trip, hdrs, {"currency": "ABC", "title": "Coast walk II"}))
    assert provider.calls == []
    assert _stored_currency(trip) == "USD"

    r = _patch(client, trip, hdrs, {"currency": "GBP"})
    assert r.status_code == 200, r.text
    assert _stored_currency(trip) == "GBP"


def test_the_form_patch_refuses_it(client, hdrs):
    trip = _create(client, hdrs).json()["id"]
    _refused(_save_form(client, trip, edit_now(client, trip, hdrs), {"currency": "ABC"}))


def test_a_stored_value_outside_the_list_stays_editable(client, hdrs):
    """The form sends the currency on every save: a trip priced before the rule
    must not need a new currency before any other edit can be saved."""
    trip = _create(client, hdrs).json()["id"]
    _store_currency(trip, "BGN")

    r = _save_form(client, trip, edit_now(client, trip, hdrs),
                   {"title": "Sofia", "currency": "BGN"})
    assert r.status_code == 200, r.text
    r = _patch(client, trip, hdrs, {"currency": "BGN"})
    assert r.status_code == 200, r.text

    _refused(_patch(client, trip, hdrs, {"currency": "ABC"}))
    assert _stored_currency(trip) == "BGN"

    r = _patch(client, trip, hdrs, {"currency": "EUR"})
    assert r.status_code == 200, r.text


def test_an_editor_changes_it_within_the_list(client, hdrs):
    trip = _create(client, hdrs).json()["id"]
    editor = _editor(client, trip, hdrs)

    _refused(_patch(client, trip, editor, {"currency": "ABC"}))
    r = _patch(client, trip, editor, {"currency": "CHF"})
    assert r.status_code == 200, r.text
    assert _stored_currency(trip) == "CHF"
