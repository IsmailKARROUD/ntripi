"""
test_recommended_duration.py — the author's recommended time to spend on a trip.

`recommended_duration_min` is one minimum, set on the app's days/hours/minutes
wheel and stored in minutes (1 … 527,039, the wheel's 365 d 23 h 59 min); null
means not set, and the app then shows the length it computes from the stops.
It is the trip's length wherever one shows, so every trip answer carries it —
the summary (/me, /saved, a profile's trips), the feed item (/feed,
shared-with-me) and the detail — always as the LAST key: JSON key order is part
of the API contract, and a field on the shared base would have landed in the
middle of the feed's and the detail's bodies (`_ItinerarySummaryFields`).

Not text: no moderation call, no translation. The owner and editors set it,
through the four trip writes: both creates and both PATCHes.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from conftest import auth_headers, edit_now, register_user
from test_image_moderation import _make_jpeg
from test_itinerary_form import (  # noqa: F401 — store is an autouse fixture
    _create_form, _editor, _save_form, _text_provider, store,
)

THREE_DAYS = 3 * 24 * 60
WHEEL_MAX = 365 * 24 * 60 + 23 * 60 + 59  # 527,039

SUMMARY_KEYS = [
    "id", "user_id", "title", "cover_image_url", "total_duration_min",
    "total_cost", "currency", "visibility", "created_at", "updated_at",
    "rating_avg", "rating_count", "stops_count",
]


@pytest.fixture()
def owner(client):
    return register_user(client, "owner", "owner@example.com")


@pytest.fixture()
def hdrs(owner):
    return auth_headers(owner["access_token"])


def _create(client: TestClient, hdrs: dict, **fields):
    body = {"title": "Coast walk", "visibility": "public", **fields}
    return client.post("/itineraries/", json=body, headers=hdrs)


def _detail(client: TestClient, trip: str, hdrs: dict) -> dict:
    r = client.get(f"/itineraries/{trip}", headers=hdrs)
    assert r.status_code == 200, r.text
    return r.json()


def _patch(client: TestClient, trip: str, hdrs: dict, body: dict, **params):
    return client.patch(f"/itineraries/{trip}", json=body,
                        headers=edit_now(client, trip, hdrs), params=params)


# ---------------------------------------------------------------------------
# The four writes
# ---------------------------------------------------------------------------

def test_a_create_sets_it_and_answers_it(client, hdrs):
    r = _create(client, hdrs, recommended_duration_min=THREE_DAYS)
    assert r.status_code == 201, r.text
    assert r.json()["recommended_duration_min"] == THREE_DAYS
    assert _detail(client, r.json()["id"], hdrs)["recommended_duration_min"] == THREE_DAYS


def test_a_create_without_it_leaves_it_unset(client, hdrs):
    r = _create(client, hdrs)
    assert r.status_code == 201, r.text
    assert r.json()["recommended_duration_min"] is None


def test_the_form_create_sets_it(client, owner):
    r = _create_form(client, owner["access_token"],
                     {"title": "Coast walk", "recommended_duration_min": 90},
                     image=_make_jpeg())
    assert r.status_code == 201, r.text
    assert r.json()["recommended_duration_min"] == 90


def test_a_patch_sets_and_null_clears_it(client, hdrs):
    trip = _create(client, hdrs).json()["id"]

    r = _patch(client, trip, hdrs, {"recommended_duration_min": THREE_DAYS})
    assert r.status_code == 200, r.text
    assert r.json()["recommended_duration_min"] == THREE_DAYS

    # Absent from a later edit: untouched.
    assert _patch(client, trip, hdrs, {"title": "Coast walk II"}).status_code == 200
    assert _detail(client, trip, hdrs)["recommended_duration_min"] == THREE_DAYS

    r = _patch(client, trip, hdrs, {"recommended_duration_min": None})
    assert r.status_code == 200, r.text
    assert _detail(client, trip, hdrs)["recommended_duration_min"] is None


def test_the_form_patch_sets_it(client, hdrs):
    trip = _create(client, hdrs).json()["id"]
    r = _save_form(client, trip, edit_now(client, trip, hdrs),
                   {"recommended_duration_min": 45})
    assert r.status_code == 200, r.text
    assert _detail(client, trip, hdrs)["recommended_duration_min"] == 45


@pytest.mark.parametrize("value", [0, -1, WHEEL_MAX + 1])
def test_outside_the_wheel_is_refused(client, hdrs, value):
    assert _create(client, hdrs, recommended_duration_min=value).status_code == 422
    trip = _create(client, hdrs).json()["id"]
    r = _patch(client, trip, hdrs, {"recommended_duration_min": value})
    assert r.status_code == 422
    assert r.json()["detail"][0]["loc"] == ["body", "recommended_duration_min"]


@pytest.mark.parametrize("value", [1, WHEEL_MAX])
def test_the_wheels_ends_are_accepted(client, hdrs, value):
    r = _create(client, hdrs, recommended_duration_min=value)
    assert r.status_code == 201, r.text
    assert r.json()["recommended_duration_min"] == value


def test_an_editor_may_set_it(client, hdrs):
    trip = _create(client, hdrs).json()["id"]
    editor = _editor(client, trip, hdrs)

    r = _patch(client, trip, editor, {"recommended_duration_min": THREE_DAYS})
    assert r.status_code == 200, r.text
    assert _detail(client, trip, hdrs)["recommended_duration_min"] == THREE_DAYS


def test_it_is_not_text_no_provider_is_called(client, hdrs, monkeypatch):
    provider = _text_provider(monkeypatch)
    trip = _create(client, hdrs).json()["id"]
    provider.calls.clear()

    r = _patch(client, trip, hdrs, {"recommended_duration_min": THREE_DAYS})
    assert r.status_code == 200, r.text
    assert provider.calls == []


# ---------------------------------------------------------------------------
# Every trip answer carries it, last
# ---------------------------------------------------------------------------

def test_the_summary_appends_it_last(client, hdrs):
    _create(client, hdrs, recommended_duration_min=THREE_DAYS)
    rows = client.get("/itineraries/me", headers=hdrs).json()
    assert list(rows[0]) == SUMMARY_KEYS + ["recommended_duration_min"]
    assert rows[0]["recommended_duration_min"] == THREE_DAYS


def test_the_detail_appends_it_last(client, hdrs):
    trip = _create(client, hdrs, recommended_duration_min=THREE_DAYS).json()["id"]
    assert list(_detail(client, trip, hdrs)) == SUMMARY_KEYS + [
        "description", "tracks", "segments", "annotations", "hidden",
        "recommended_periods", "recommended_weekdays", "recommended_period_note",
        "can_edit", "source_lang", "recommended_duration_min",
    ]


def test_a_feed_item_appends_it_last(client, hdrs):
    trip = _create(client, hdrs, recommended_duration_min=THREE_DAYS).json()["id"]
    editor = _editor(client, trip, hdrs)
    rows = client.get("/itineraries/shared-with-me", headers=editor).json()
    assert list(rows[0]) == SUMMARY_KEYS + [
        "owner", "source_lang", "title_translation", "recommended_duration_min",
    ]
    assert rows[0]["recommended_duration_min"] == THREE_DAYS


def test_the_public_feed_carries_it(client, hdrs):
    _create(client, hdrs, recommended_duration_min=THREE_DAYS)
    reader = register_user(client, "reader", "reader@example.com")
    rows = client.get("/itineraries/feed?sort=recent",
                      headers=auth_headers(reader["access_token"])).json()
    assert rows and list(rows[0])[-1] == "recommended_duration_min"
    assert rows[0]["recommended_duration_min"] == THREE_DAYS


def test_a_trip_edit_answer_carries_it(client, hdrs):
    trip = _create(client, hdrs).json()["id"]
    r = _patch(client, trip, hdrs, {"recommended_duration_min": THREE_DAYS},
               **{"return": "itinerary"})
    assert r.status_code == 200, r.text
    itinerary = r.json()["itinerary"]
    assert list(itinerary)[-1] == "recommended_duration_min"
    assert itinerary["recommended_duration_min"] == THREE_DAYS
