"""
test_recommended_period.py — the author's "best time to visit" on an itinerary.

Three optional parts, stored on the itinerary row and returned by the detail
endpoint only:

  recommended_periods      windows of {from_month, from_day, to_month, to_day}
  recommended_weekdays     ISO weekday numbers, 1 = Monday … 7 = Sunday
  recommended_period_note  the one-line "why"

The load-bearing rules pinned here:

  * A window carries NO YEAR, so from_month=9/to_month=3 is a wrap-around
    (September through March), never reversed input.
  * Windows may neither overlap NOR touch. Jan–Mar + Apr–Jun is one Jan–Jun,
    and Jan–Mar + Sep–Dec is one Sep–Mar across the year boundary. The client
    edits a month grid, which can only ever produce separated runs — so the
    accepted shapes are exactly the ones that round-trip through the editor.
  * The note is stored user prose and therefore goes to the text moderator.
  * The three fields stay OFF the summary payload — appending them there would
    shift JSON keys in ItineraryDetail and ItineraryFeedItem.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from conftest import auth_headers, edit_now, register_user
from app.config import get_settings
from app.services import text_moderation_service as tms
from app.services.text_moderation_providers import ProviderResult


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _window(from_month, to_month, from_day=None, to_day=None) -> dict:
    return {
        "from_month": from_month,
        "from_day": from_day,
        "to_month": to_month,
        "to_day": to_day,
    }


@pytest.fixture()
def owner(client):
    return register_user(client, "owner", "owner@example.com")


def _create(client: TestClient, token: str, **fields):
    """POST /itineraries/ without asserting — callers check the status."""
    body = {"title": "A trip", "currency": "EUR", "visibility": "public", **fields}
    return client.post("/itineraries/", json=body, headers=auth_headers(token))


def _create_ok(client: TestClient, token: str, **fields) -> str:
    resp = _create(client, token, **fields)
    assert resp.status_code == 201, resp.json()
    return resp.json()["id"]


def _detail(client: TestClient, token: str, itinerary_id: str) -> dict:
    resp = client.get(f"/itineraries/{itinerary_id}", headers=auth_headers(token))
    assert resp.status_code == 200, resp.json()
    return resp.json()


# ---------------------------------------------------------------------------
# Round-trips — each part usable on its own
# ---------------------------------------------------------------------------

def test_windows_only_round_trip(client, owner):
    token = owner["access_token"]
    itinerary_id = _create_ok(
        client, token,
        recommended_periods=[_window(4, 6, from_day=15, to_day=10)],
    )

    detail = _detail(client, token, itinerary_id)
    assert detail["recommended_periods"] == [
        {"from_month": 4, "from_day": 15, "to_month": 6, "to_day": 10}
    ]
    assert detail["recommended_weekdays"] is None
    assert detail["recommended_period_note"] is None


def test_weekdays_only_round_trip(client, owner):
    token = owner["access_token"]
    itinerary_id = _create_ok(client, token, recommended_weekdays=[6, 7])

    detail = _detail(client, token, itinerary_id)
    assert detail["recommended_weekdays"] == [6, 7]
    assert detail["recommended_periods"] is None


def test_note_only_round_trip(client, owner):
    """A "why" with no dates at all is a legitimate answer."""
    token = owner["access_token"]
    itinerary_id = _create_ok(
        client, token, recommended_period_note="Shoulder season, half the crowds",
    )

    detail = _detail(client, token, itinerary_id)
    assert detail["recommended_period_note"] == "Shoulder season, half the crowds"
    assert detail["recommended_periods"] is None
    assert detail["recommended_weekdays"] is None


def test_absent_when_never_set(client, owner):
    token = owner["access_token"]
    itinerary_id = _create_ok(client, token)

    detail = _detail(client, token, itinerary_id)
    assert detail["recommended_periods"] is None
    assert detail["recommended_weekdays"] is None
    assert detail["recommended_period_note"] is None


# ---------------------------------------------------------------------------
# Window shapes that must be accepted
# ---------------------------------------------------------------------------

def test_wrap_around_window(client, owner):
    """September through March — the year boundary is not an error."""
    token = owner["access_token"]
    itinerary_id = _create_ok(client, token, recommended_periods=[_window(9, 3)])

    detail = _detail(client, token, itinerary_id)
    assert detail["recommended_periods"] == [
        {"from_month": 9, "from_day": None, "to_month": 3, "to_day": None}
    ]


def test_single_month_window(client, owner):
    token = owner["access_token"]
    itinerary_id = _create_ok(client, token, recommended_periods=[_window(6, 6)])
    assert _detail(client, token, itinerary_id)["recommended_periods"][0]["to_month"] == 6


def test_two_separated_windows_sorted(client, owner):
    """Jan–Mar and Jun–Aug: separated by April/May, so genuinely two runs."""
    token = owner["access_token"]
    itinerary_id = _create_ok(
        client, token,
        recommended_periods=[_window(6, 8), _window(1, 3)],
    )

    months = [w["from_month"] for w in _detail(client, token, itinerary_id)["recommended_periods"]]
    assert months == [1, 6]  # sorted on the way in, so equivalent input stores identically


def test_leap_day_boundary_allowed(client, owner):
    """No year, so 29 February is a real choice rather than an off-by-one."""
    token = owner["access_token"]
    itinerary_id = _create_ok(
        client, token, recommended_periods=[_window(1, 2, from_day=10, to_day=29)],
    )
    assert _detail(client, token, itinerary_id)["recommended_periods"][0]["to_day"] == 29


def test_six_windows_allowed(client, owner):
    """Twelve alternating months is the densest legal arrangement."""
    token = owner["access_token"]
    windows = [_window(m, m) for m in (1, 3, 5, 7, 9, 11)]
    itinerary_id = _create_ok(client, token, recommended_periods=windows)
    assert len(_detail(client, token, itinerary_id)["recommended_periods"]) == 6


# ---------------------------------------------------------------------------
# Overlap and adjacency — the rules that keep the grid and the API in sync
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "windows, why",
    [
        ([_window(1, 6), _window(3, 7)], "overlapping — this is one Jan-Jul"),
        ([_window(1, 3), _window(4, 6)], "adjacent — this is one Jan-Jun"),
        ([_window(1, 3), _window(9, 12)], "adjacent across the year end — one Sep-Mar"),
        ([_window(2, 4), _window(2, 4)], "identical windows"),
        ([_window(11, 2), _window(12, 1)], "both wrap the year end"),
        ([_window(1, 12), _window(6, 6)], "a full-year window swallows every other"),
    ],
)
def test_overlapping_or_adjacent_windows_rejected(client, owner, windows, why):
    resp = _create(client, owner["access_token"], recommended_periods=windows)
    assert resp.status_code == 422, f"{why}: {resp.json()}"


def test_more_than_six_windows_rejected(client, owner):
    # Seven single-month windows cannot be non-adjacent in a 12-month year, so
    # this trips the count cap and the adjacency rule alike — both are 422.
    windows = [_window(m, m) for m in (1, 3, 5, 7, 9, 11, 12)]
    assert _create(client, owner["access_token"], recommended_periods=windows).status_code == 422


# ---------------------------------------------------------------------------
# Field-level validation
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "window, why",
    [
        (_window(2, 3, from_day=30), "30 February"),
        (_window(1, 2, to_day=31), "31 February"),
        (_window(4, 4, from_day=31), "31 April"),
        (_window(6, 6, from_day=20, to_day=10), "20 Jun -> 10 Jun within one month"),
        (_window(0, 5), "month 0"),
        (_window(1, 13), "month 13"),
        (_window(1, 5, from_day=0), "day 0"),
        (_window(1, 5, to_day=32), "day 32"),
    ],
)
def test_invalid_window_rejected(client, owner, window, why):
    resp = _create(client, owner["access_token"], recommended_periods=[window])
    assert resp.status_code == 422, f"{why}: {resp.json()}"


@pytest.mark.parametrize("weekdays", [[0], [8], [1, 1], [-1]])
def test_invalid_weekdays_rejected(client, owner, weekdays):
    assert _create(
        client, owner["access_token"], recommended_weekdays=weekdays
    ).status_code == 422


def test_note_over_cap_rejected(client, owner):
    assert _create(
        client, owner["access_token"], recommended_period_note="x" * 201,
    ).status_code == 422


def test_empty_lists_normalize_to_null(client, owner):
    """"Unset" gets one stored representation, so a cleared field reads as null."""
    token = owner["access_token"]
    itinerary_id = _create_ok(
        client, token,
        recommended_periods=[], recommended_weekdays=[], recommended_period_note="   ",
    )

    detail = _detail(client, token, itinerary_id)
    assert detail["recommended_periods"] is None
    assert detail["recommended_weekdays"] is None
    assert detail["recommended_period_note"] is None


# ---------------------------------------------------------------------------
# PATCH semantics
# ---------------------------------------------------------------------------

def test_patch_leaves_untouched_parts_alone(client, owner):
    token = owner["access_token"]
    itinerary_id = _create_ok(
        client, token,
        recommended_periods=[_window(4, 6)],
        recommended_weekdays=[6, 7],
        recommended_period_note="Blossom season",
    )

    resp = client.patch(
        f"/itineraries/{itinerary_id}",
        json={"recommended_weekdays": [1, 2, 3, 4, 5]},
        headers=edit_now(client, itinerary_id, auth_headers(token)),
    )
    assert resp.status_code == 200, resp.json()

    detail = _detail(client, token, itinerary_id)
    assert detail["recommended_weekdays"] == [1, 2, 3, 4, 5]
    assert detail["recommended_periods"] == [
        {"from_month": 4, "from_day": None, "to_month": 6, "to_day": None}
    ]
    assert detail["recommended_period_note"] == "Blossom season"


def test_patch_with_explicit_nulls_clears(client, owner):
    token = owner["access_token"]
    itinerary_id = _create_ok(
        client, token,
        recommended_periods=[_window(4, 6)],
        recommended_weekdays=[6, 7],
        recommended_period_note="Blossom season",
    )

    resp = client.patch(
        f"/itineraries/{itinerary_id}",
        json={
            "recommended_periods": None,
            "recommended_weekdays": None,
            "recommended_period_note": None,
        },
        headers=edit_now(client, itinerary_id, auth_headers(token)),
    )
    assert resp.status_code == 200, resp.json()

    detail = _detail(client, token, itinerary_id)
    assert detail["recommended_periods"] is None
    assert detail["recommended_weekdays"] is None
    assert detail["recommended_period_note"] is None


# updated_at (the concurrency ETag) is left to the existing ETag tests: SQLite's
# CURRENT_TIMESTAMP is second-granularity, so a same-second PATCH cannot be
# distinguished here without sleeping.


# ---------------------------------------------------------------------------
# API surface — detail only
# ---------------------------------------------------------------------------

def test_summary_payload_unchanged(client, owner):
    """GET /itineraries/me returns ItinerarySummary, which must not carry these.

    Appending them to the summary would shift JSON keys in both of its
    subclasses (ItineraryDetail, ItineraryFeedItem), and key order is contract.
    """
    token = owner["access_token"]
    _create_ok(client, token, recommended_period_note="Blossom season")

    resp = client.get("/itineraries/me", headers=auth_headers(token))
    assert resp.status_code == 200, resp.json()
    rows = resp.json()
    assert rows, "expected the owner's itinerary in the list"
    for key in ("recommended_periods", "recommended_weekdays", "recommended_period_note"):
        assert key not in rows[0]


# ---------------------------------------------------------------------------
# Moderation — the note is stored user prose
# ---------------------------------------------------------------------------

class _CountingProvider:
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
    monkeypatch.setattr(get_settings(), "TEXT_MODERATION_PROVIDER", "openai")
    monkeypatch.setattr(get_settings(), "OPENAI_API_KEY", "test-key")
    stub = _CountingProvider({"hate": 0.01})
    monkeypatch.setattr(tms, "get_provider_chain", lambda settings: [stub])
    return stub


def test_note_is_scanned_on_create(client, owner, provider):
    _create_ok(
        client, owner["access_token"],
        recommended_period_note="Go when the jacarandas bloom",
    )
    assert len(provider.calls) == 1
    assert "jacarandas" in provider.calls[0]


def test_note_is_scanned_on_update(client, owner, provider):
    token = owner["access_token"]
    itinerary_id = _create_ok(client, token)
    provider.calls.clear()

    resp = client.patch(
        f"/itineraries/{itinerary_id}",
        json={"recommended_period_note": "Avoid the monsoon"},
        headers=edit_now(client, itinerary_id, auth_headers(token)),
    )
    assert resp.status_code == 200, resp.json()
    assert len(provider.calls) == 1
    assert "monsoon" in provider.calls[0]


def test_dates_alone_do_not_bill_a_scan(client, owner, provider):
    """Months and weekdays are numbers — there is nothing for a classifier to read."""
    token = owner["access_token"]
    itinerary_id = _create_ok(client, token)
    provider.calls.clear()

    client.patch(
        f"/itineraries/{itinerary_id}",
        json={"recommended_periods": [_window(4, 6)], "recommended_weekdays": [6, 7]},
        headers=edit_now(client, itinerary_id, auth_headers(token)),
    )
    assert provider.calls == []
