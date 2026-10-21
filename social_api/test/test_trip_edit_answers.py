"""
test_trip_edit_answers.py — a trip edit can answer with the whole trip.

Asked with `?return=itinerary`, every EDIT_GUARDED route answers with exactly
the body GET /itineraries/{id} would give the same caller right after the save,
so the app adopts it and never downloads the trip again. Asked nothing, each
answers exactly as it always has, so installed builds keep working.

CASES must hold exactly the routes test_edit_guard_coverage.py calls
EDIT_GUARDED: a new trip edit fails this file until it has a case, and a case
only passes by answering with the trip a GET would show.

Ratings are VIEWER_WRITE and answer with the trip's aggregate instead: the POST
always, the DELETE when asked with `?return=aggregate`.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

import pytest
from fastapi.testclient import TestClient
from httpx import Response
from pydantic import BaseModel

from conftest import (
    auth_headers, concurrency_part, edit_now, etag_from_updated_at, register_user,
)
from test_edit_guard_coverage import EDIT_GUARDED, _dependency_callables, _route_for
from test_itinerary_form import _backdate, _parts
from test_text_moderation_endpoints import MINORS, CountingProvider
from app.config import get_settings
from app.routers.itineraries import wants_itinerary
from app.schemas.itinerary import (
    AnnotationResponse, ItineraryAnnotationResponse, ItineraryDetail,
    ItinerarySummary, RatingResponse, StopResponse, TransitSegmentResponse,
    TransportLegResponse,
)
from app.services import text_moderation_service as tms

ANSWER = {"return": "itinerary"}


# ---------------------------------------------------------------------------
# A trip with something of every kind on it
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Trip:
    id: str
    owner: dict       # auth headers
    editor: dict
    track_a: str
    stop_a: str
    stop_a2: str      # A's second stop, so a reorder has something to reorder
    stop_b: str       # alone on track B
    note: str         # a trip-wide note
    stop_note: str    # a note on stop A
    segment: str      # A -> B, two legs
    leg: str          # one of them


def _seed(client: TestClient) -> Trip:
    """A public trip, its owner and one editor, with no claim left standing so
    either of the two can take one."""
    owner = register_user(client, "tripowner", "tripowner@example.com")
    editor = register_user(client, "tripeditor", "tripeditor@example.com")
    owner_h = auth_headers(owner["access_token"])
    editor_h = auth_headers(editor["access_token"])
    trip_id = client.post(
        "/itineraries/", json={"title": "Coast walk", "visibility": "public"},
        headers=owner_h,
    ).json()["id"]
    granted = client.post(f"/itineraries/{trip_id}/editors",
                          json={"user_id": editor["user_id"]}, headers=owner_h)
    assert granted.status_code == 201, granted.text

    def create(path: str, body: dict) -> dict:
        r = client.post(f"/itineraries/{trip_id}{path}", json=body,
                        headers=edit_now(client, trip_id, owner_h))
        assert r.status_code == 201, r.text
        return r.json()

    stop_a = create("/stops", {"place_name": "Harbour"})
    stop_a2 = create("/stops", {"place_name": "Market", "track_id": stop_a["track_id"]})
    stop_b = create("/stops", {"place_name": "Lighthouse",
                               "after_track_id": stop_a["track_id"]})
    note = create("/annotations", {"type": "info", "content": "Bring cash"})
    stop_note = create(f"/stops/{stop_a['id']}/annotations",
                       {"type": "advice", "content": "Go early"})
    segment = create("/segments", {
        "from_stop_id": stop_a["id"], "to_stop_id": stop_b["id"],
        "legs": [{"position": 1, "mode": "walk"},
                 {"position": 2, "mode": "bus", "line": "12"}],
    })
    # The owner's live claim would keep the editor out; ending it lets either claim.
    assert client.delete(f"/itineraries/{trip_id}/lock", headers=owner_h).status_code == 204
    return Trip(
        id=trip_id, owner=owner_h, editor=editor_h,
        track_a=stop_a["track_id"], stop_a=stop_a["id"], stop_a2=stop_a2["id"],
        stop_b=stop_b["id"], note=note["id"], stop_note=stop_note["id"],
        segment=segment["id"], leg=segment["legs"][0]["id"],
    )


# ---------------------------------------------------------------------------
# One case per trip edit
# ---------------------------------------------------------------------------

Send = Callable[[TestClient, Trip, dict, dict], Response]


@dataclass(frozen=True)
class Case:
    send: Send                              # (client, trip, headers, query params)
    status: int                             # asked for the trip
    legacy_status: int                      # asked nothing: what it always answered
    legacy_schema: type[BaseModel] | None   # None: an empty 204
    legacy_etag: bool                       # whether that answer carried an ETag
    created: Callable[[dict], set] | None = None  # the created kind's ids in a trip


def _json(method: str, path: Callable[[Trip], str],
          body: Callable[[Trip], dict] | None = None) -> Send:
    def send(client: TestClient, t: Trip, headers: dict, params: dict) -> Response:
        return client.request(method, f"/itineraries/{t.id}{path(t)}", params=params,
                              json=body(t) if body else None, headers=headers)
    return send


def _form(client: TestClient, t: Trip, headers: dict, params: dict) -> Response:
    return client.patch(f"/itineraries/{t.id}/form", params=params, headers=headers,
                        files=_parts({"title": "Coast walk, revised"}))


def _stop_ids(trip: dict) -> set:
    return {stop["id"] for track in trip["tracks"] for stop in track["stops"]}


def _note_ids(trip: dict) -> set:
    return {note["id"] for note in trip["annotations"]}


def _stop_note_ids(trip: dict) -> set:
    return {note["id"] for track in trip["tracks"] for stop in track["stops"]
            for note in stop["annotations"]}


def _segment_ids(trip: dict) -> set:
    return {segment["id"] for segment in trip["segments"]}


def _leg_ids(trip: dict) -> set:
    return {leg["id"] for segment in trip["segments"] for leg in segment["legs"]}


CASES: dict[tuple[str, str], Case] = {
    ("PATCH", "/itineraries/{itinerary_id}"): Case(
        _json("PATCH", lambda t: "", lambda t: {"title": "Coast walk, revised"}),
        200, 200, ItinerarySummary, legacy_etag=False),
    ("PATCH", "/itineraries/{itinerary_id}/form"): Case(
        _form, 200, 200, ItinerarySummary, legacy_etag=True),
    ("POST", "/itineraries/{itinerary_id}/stops"): Case(
        _json("POST", lambda t: "/stops",
              lambda t: {"place_name": "Cove", "track_id": t.track_a}),
        201, 201, StopResponse, legacy_etag=True, created=_stop_ids),
    # A move that empties track B: the route commits twice, and the answer
    # must come after the second.
    ("PATCH", "/itineraries/{itinerary_id}/stops/{stop_id}"): Case(
        _json("PATCH", lambda t: f"/stops/{t.stop_b}",
              lambda t: {"place_name": "Lighthouse point", "track_id": t.track_a}),
        200, 200, StopResponse, legacy_etag=True),
    ("DELETE", "/itineraries/{itinerary_id}/stops/{stop_id}"): Case(
        _json("DELETE", lambda t: f"/stops/{t.stop_a2}"),
        200, 204, None, legacy_etag=True),
    ("POST", "/itineraries/{itinerary_id}/reorder"): Case(
        _json("POST", lambda t: "/reorder",
              lambda t: {"stop_orders": {t.track_a: [t.stop_a2, t.stop_a]}}),
        200, 200, ItineraryDetail, legacy_etag=True),
    ("POST", "/itineraries/{itinerary_id}/annotations"): Case(
        _json("POST", lambda t: "/annotations",
              lambda t: {"type": "caution", "content": "The tide comes in fast"}),
        201, 201, ItineraryAnnotationResponse, legacy_etag=False, created=_note_ids),
    ("PATCH", "/itineraries/{itinerary_id}/annotations/{annotation_id}"): Case(
        _json("PATCH", lambda t: f"/annotations/{t.note}",
              lambda t: {"content": "Bring more cash"}),
        200, 200, ItineraryAnnotationResponse, legacy_etag=False),
    ("DELETE", "/itineraries/{itinerary_id}/annotations/{annotation_id}"): Case(
        _json("DELETE", lambda t: f"/annotations/{t.note}"),
        200, 204, None, legacy_etag=False),
    ("POST", "/itineraries/{itinerary_id}/stops/{stop_id}/annotations"): Case(
        _json("POST", lambda t: f"/stops/{t.stop_b}/annotations",
              lambda t: {"type": "info", "content": "Closed on Mondays"}),
        201, 201, AnnotationResponse, legacy_etag=False, created=_stop_note_ids),
    ("PATCH", "/itineraries/{itinerary_id}/stops/{stop_id}/annotations/{annotation_id}"): Case(
        _json("PATCH", lambda t: f"/stops/{t.stop_a}/annotations/{t.stop_note}",
              lambda t: {"content": "Go at dawn"}),
        200, 200, AnnotationResponse, legacy_etag=False),
    ("DELETE", "/itineraries/{itinerary_id}/stops/{stop_id}/annotations/{annotation_id}"): Case(
        _json("DELETE", lambda t: f"/stops/{t.stop_a}/annotations/{t.stop_note}"),
        200, 204, None, legacy_etag=False),
    ("POST", "/itineraries/{itinerary_id}/segments"): Case(
        _json("POST", lambda t: "/segments",
              lambda t: {"from_stop_id": t.stop_a2, "to_stop_id": t.stop_b,
                         "legs": [{"position": 1, "mode": "walk"}]}),
        201, 201, TransitSegmentResponse, legacy_etag=False, created=_segment_ids),
    ("PATCH", "/itineraries/{itinerary_id}/segments/{segment_id}"): Case(
        _json("PATCH", lambda t: f"/segments/{t.segment}",
              lambda t: {"from_stop_id": t.stop_a, "to_stop_id": t.stop_b,
                         "legs": [{"position": 1, "mode": "tram", "line": "28"}]}),
        200, 200, TransitSegmentResponse, legacy_etag=False),
    ("DELETE", "/itineraries/{itinerary_id}/segments/{segment_id}"): Case(
        _json("DELETE", lambda t: f"/segments/{t.segment}"),
        200, 204, None, legacy_etag=False),
    ("POST", "/itineraries/{itinerary_id}/segments/{segment_id}/legs"): Case(
        _json("POST", lambda t: f"/segments/{t.segment}/legs",
              lambda t: {"position": 3, "mode": "ferry"}),
        201, 201, TransportLegResponse, legacy_etag=False, created=_leg_ids),
    ("PATCH", "/itineraries/{itinerary_id}/segments/{segment_id}/legs/{leg_id}"): Case(
        _json("PATCH", lambda t: f"/segments/{t.segment}/legs/{t.leg}",
              lambda t: {"mode": "bike"}),
        200, 200, TransportLegResponse, legacy_etag=False),
    ("DELETE", "/itineraries/{itinerary_id}/segments/{segment_id}/legs/{leg_id}"): Case(
        _json("DELETE", lambda t: f"/segments/{t.segment}/legs/{t.leg}"),
        200, 204, None, legacy_etag=False),
}

ROUTES = sorted(EDIT_GUARDED)


def _route_id(route: tuple[str, str]) -> str:
    method, path = route
    return f"{method} {path.removeprefix('/itineraries/{itinerary_id}') or '/'}"


# ---------------------------------------------------------------------------
# Structure: no trip edit without the full-trip answer
# ---------------------------------------------------------------------------

def test_every_trip_edit_takes_the_opt_in():
    for method, path in ROUTES:
        assert wants_itinerary in _dependency_callables(_route_for(method, path)), (
            f"{method} {path} edits a trip but cannot answer with it: depend on "
            "wants_itinerary and return _trip_edit_answer after the last commit."
        )


def test_every_trip_edit_has_a_case():
    missing = EDIT_GUARDED - set(CASES)
    assert not missing, (
        f"Add a case to CASES for each new trip edit, proving it answers with the "
        f"trip a GET would show: {sorted(missing)}"
    )
    assert not set(CASES) - EDIT_GUARDED, "CASES names a route that is not a trip edit"


# ---------------------------------------------------------------------------
# Asked for the trip
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("actor", ["owner", "editor"])
@pytest.mark.parametrize("route", ROUTES, ids=_route_id)
def test_the_answer_is_the_trip_a_get_shows(client: TestClient, route, actor):
    t = _seed(client)
    viewer = getattr(t, actor)
    case = CASES[route]
    before = client.get(f"/itineraries/{t.id}", headers=viewer).json()

    r = case.send(client, t, edit_now(client, t.id, viewer), ANSWER)

    assert r.status_code == case.status, r.text
    body = r.json()
    assert list(body) == ["itinerary", "created_id"]
    after = client.get(f"/itineraries/{t.id}", headers=viewer)
    # can_edit and every other field as THIS viewer's GET has them.
    assert body["itinerary"] == after.json()
    assert body["itinerary"] != before
    assert concurrency_part(r.headers["etag"]) == concurrency_part(after.headers["etag"])
    if case.created is None:
        assert body["created_id"] is None
    else:
        assert body["created_id"] in case.created(body["itinerary"]) - case.created(before)


@pytest.mark.parametrize("route", ROUTES, ids=_route_id)
def test_the_answered_stamp_is_the_next_if_match(client: TestClient, route):
    t = _seed(client)
    # SQLite stamps updated_at in whole seconds; backdating makes the save move it.
    _backdate(t.id)
    headers = edit_now(client, t.id, t.owner)

    r = CASES[route].send(client, t, headers, ANSWER)
    assert r.status_code == CASES[route].status, r.text
    answered = etag_from_updated_at(r.json()["itinerary"]["updated_at"])

    def next_save(if_match: str):
        return client.patch(f"/itineraries/{t.id}", json={"title": "Next save"},
                            headers={**headers, "If-Match": if_match})

    assert next_save(headers["If-Match"]).status_code == 412  # read before the save
    assert next_save(answered).status_code == 200


def test_an_unknown_return_value_is_refused(client: TestClient):
    t = _seed(client)
    r = CASES[("PATCH", "/itineraries/{itinerary_id}")].send(
        client, t, edit_now(client, t.id, t.owner), {"return": "everything"},
    )
    assert r.status_code == 422, r.text


def _hide_on_the_spot(monkeypatch) -> None:
    """Every text scanned from here on gets the minors verdict, which hides the
    trip at once from everyone but its owner."""
    monkeypatch.setattr(get_settings(), "TEXT_MODERATION_PROVIDER", "openai")
    monkeypatch.setattr(get_settings(), "OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(tms, "get_provider_chain",
                        lambda settings: [CountingProvider(MINORS)])


def _add_note(client: TestClient, t: Trip, viewer: dict) -> Response:
    return client.post(f"/itineraries/{t.id}/annotations", params=ANSWER,
                       json={"type": "info", "content": "A note moderation hides"},
                       headers=edit_now(client, t.id, viewer))


def test_a_save_that_hides_the_trip_from_its_editor_answers_without_it(
    client: TestClient, monkeypatch,
):
    """The editor who wrote it loses the trip with everyone else, so there is
    no trip to give them — and a GET refuses them too."""
    t = _seed(client)
    _hide_on_the_spot(monkeypatch)

    r = _add_note(client, t, t.editor)

    assert r.status_code == 201, r.text
    assert r.json()["itinerary"] is None
    assert r.json()["created_id"] is not None
    assert client.get(f"/itineraries/{t.id}", headers=t.editor).status_code == 403


def test_a_save_that_hides_the_trip_answers_its_owner_with_the_hidden_trip(
    client: TestClient, monkeypatch,
):
    """`hidden` is true only in the owner's view — the answer is theirs too."""
    t = _seed(client)
    _hide_on_the_spot(monkeypatch)

    r = _add_note(client, t, t.owner)

    assert r.status_code == 201, r.text
    assert r.json()["itinerary"]["hidden"] is True
    assert r.json()["itinerary"] == client.get(f"/itineraries/{t.id}", headers=t.owner).json()


# ---------------------------------------------------------------------------
# Asked nothing: what installed builds have always been sent
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("route", ROUTES, ids=_route_id)
def test_asked_nothing_the_answer_is_what_it_always_was(client: TestClient, route):
    t = _seed(client)
    case = CASES[route]

    r = case.send(client, t, edit_now(client, t.id, t.owner), {})

    assert r.status_code == case.legacy_status, r.text
    if case.legacy_schema is None:
        assert r.content == b""
    else:
        assert list(r.json()) == list(case.legacy_schema.model_fields)
    assert ("etag" in r.headers) == case.legacy_etag


def test_a_reorder_asked_nothing_still_answers_the_bare_trip(client: TestClient):
    t = _seed(client)
    r = CASES[("POST", "/itineraries/{itinerary_id}/reorder")].send(
        client, t, edit_now(client, t.id, t.editor), {},
    )
    assert r.status_code == 200, r.text
    assert r.json() == client.get(f"/itineraries/{t.id}", headers=t.editor).json()


# ---------------------------------------------------------------------------
# Ratings answer with the aggregate
# ---------------------------------------------------------------------------

def _rate(client: TestClient, t: Trip, headers: dict, stars: int) -> Response:
    r = client.post(f"/itineraries/{t.id}/ratings", json={"stars": stars}, headers=headers)
    assert r.status_code == 201, r.text
    return r


def _aggregate(client: TestClient, t: Trip, headers: dict) -> tuple:
    trip = client.get(f"/itineraries/{t.id}", headers=headers).json()
    return trip["rating_avg"], trip["rating_count"]


def test_a_rating_answers_with_the_aggregate_the_trip_now_shows(client: TestClient):
    t = _seed(client)
    rater = auth_headers(register_user(client, "triprater", "triprater@example.com")
                         ["access_token"])
    _rate(client, t, t.editor, 2)

    body = _rate(client, t, rater, 5).json()

    # Appended after RatingResponse's own keys, never inserted among them.
    assert list(body) == [*RatingResponse.model_fields, "rating_avg", "rating_count"]
    assert (body["rating_avg"], body["rating_count"]) == _aggregate(client, t, rater) == (3.5, 2)


def test_reading_my_rating_carries_no_aggregate(client: TestClient):
    t = _seed(client)
    _rate(client, t, t.editor, 4)

    r = client.get(f"/itineraries/{t.id}/ratings/me", headers=t.editor)

    assert r.status_code == 200, r.text
    assert list(r.json()) == list(RatingResponse.model_fields)


def test_deleting_a_rating_answers_nothing_unless_asked(client: TestClient):
    t = _seed(client)
    _rate(client, t, t.editor, 4)

    r = client.delete(f"/itineraries/{t.id}/ratings/me", headers=t.editor)

    assert r.status_code == 204
    assert r.content == b""


def test_deleting_a_rating_when_asked_answers_the_aggregate_left(client: TestClient):
    t = _seed(client)
    rater = auth_headers(register_user(client, "triprater", "triprater@example.com")
                         ["access_token"])
    _rate(client, t, t.editor, 4)
    _rate(client, t, rater, 2)

    r = client.delete(f"/itineraries/{t.id}/ratings/me", params={"return": "aggregate"},
                      headers=rater)

    assert r.status_code == 200, r.text
    assert list(r.json()) == ["rating_avg", "rating_count"]
    assert (r.json()["rating_avg"], r.json()["rating_count"]) \
        == _aggregate(client, t, rater) == (4.0, 1)

    # The last rating leaves no average at all.
    r = client.delete(f"/itineraries/{t.id}/ratings/me", params={"return": "aggregate"},
                      headers=t.editor)
    assert r.json() == {"rating_avg": None, "rating_count": 0}
    assert _aggregate(client, t, t.editor) == (None, 0)
