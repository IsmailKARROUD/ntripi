"""
test_notification_titles.py — a taken-down trip is never named in a notification.

A notification names its trip by resolving the title when it is read (the feed,
routers/notifications.py) or when its push is queued (notification_service).
Until 2026-11-09 neither looked at the trip's state, so a hidden or removed
trip's title — often the very text a moderator took down — kept showing in the
feed and went out on lock screens. A trip is now named only while
itinerary_access.public_listing_criteria lists it; otherwise the row reads as
its untitled sentence ("One of your itineraries was hidden"), to its owner too,
who finds which trip on Account status.

Coverage:
  the feed names a live trip, and drops the name once it is hidden, removed,
    its owner suspended, or a block stands — for the owner and for a granted
    editor alike; a restored trip is named again
  a takedown notice's push is untitled; an access grant's push to a live trip
    still names it
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi.testclient import TestClient

from conftest import TestingSessionLocal, auth_headers, make_admin, register_user
from test_push import _capture, _enable, _register
from app.models.itinerary import Itinerary
from app.models.user import User
from app.services import admin_service

TITLE = "Kyoto in spring"


def _world(client: TestClient):
    """A public trip someone saved and someone else edits: the owner's
    'saved' notice and the editor's grant both name it."""
    owner = register_user(client, "owner", "owner@x.com")
    saver = register_user(client, "saver", "saver@x.com")
    editor = register_user(client, "editor", "editor@x.com")
    r = client.post("/itineraries/", json={"title": TITLE, "visibility": "public"},
                    headers=auth_headers(owner["access_token"]))
    assert r.status_code == 201, r.text
    trip = r.json()["id"]
    r = client.post(f"/itineraries/{trip}/save",
                    headers=auth_headers(saver["access_token"]))
    assert r.status_code in (200, 201, 204), r.text
    r = client.post(f"/itineraries/{trip}/editors", json={"user_id": editor["user_id"]},
                    headers=auth_headers(owner["access_token"]))
    assert r.status_code == 201, r.text
    return owner, editor, trip


def _titles(client: TestClient, user: dict) -> list[str | None]:
    r = client.get("/notifications", headers=auth_headers(user["access_token"]))
    assert r.status_code == 200, r.text
    return [n["entity_title"] for n in r.json()["notifications"]
            if n["entity_type"] == "itinerary"]


def _set(trip: str, **fields) -> None:
    db = TestingSessionLocal()
    try:
        row = db.get(Itinerary, uuid.UUID(trip))
        for name, value in fields.items():
            setattr(row, name, value)
        db.commit()
    finally:
        db.close()


def test_a_live_trip_is_named(client):
    owner, editor, _ = _world(client)
    assert _titles(client, owner) == [TITLE]
    assert _titles(client, editor) == [TITLE]


def test_a_hidden_trip_is_named_to_nobody_and_again_once_restored(client):
    owner, editor, trip = _world(client)
    _set(trip, hidden_at=datetime.now(timezone.utc))
    assert _titles(client, owner) == [None]
    assert _titles(client, editor) == [None]

    _set(trip, hidden_at=None)
    assert _titles(client, owner) == [TITLE]


def test_a_removed_trip_is_not_named(client):
    owner, editor, trip = _world(client)
    _set(trip, deleted_at=datetime.now(timezone.utc))
    assert _titles(client, owner) == [None]
    assert _titles(client, editor) == [None]


def test_a_suspended_owners_trip_is_not_named(client):
    owner, editor, _ = _world(client)
    db = TestingSessionLocal()
    try:
        db.get(User, uuid.UUID(owner["user_id"])).is_active = False
        db.commit()
    finally:
        db.close()
    assert _titles(client, editor) == [None]


def test_a_block_drops_the_name(client):
    owner, editor, _ = _world(client)
    r = client.post(f"/users/{owner['user_id']}/block",
                    headers=auth_headers(editor["access_token"]))
    assert r.status_code == 204, r.text
    assert _titles(client, editor) == [None]


def test_a_takedown_notice_never_names_the_trip_in_a_push(monkeypatch, client):
    """The tray entry is on a lock screen: the hidden title is what was taken
    down, so the notice says only that one of the owner's trips was."""
    owner, _, trip = _world(client)
    admin = register_user(client, "moderator1", "admin@x.com")
    make_admin("admin@x.com")
    _register(client, owner["access_token"], device="owner-dev")
    _enable(monkeypatch)
    sent = _capture(monkeypatch)

    db = TestingSessionLocal()
    try:
        admin_service.hide_itinerary(
            db, db.get(User, uuid.UUID(admin["user_id"])),
            db.get(Itinerary, uuid.UUID(trip)), "test",
        )
    finally:
        db.close()

    assert len(sent) == 1, sent
    visible = sent[0]["message"]["notification"]
    assert visible["title"] == "One of your itineraries was hidden"
    assert TITLE not in str(sent[0])
    # And the feed row agrees.
    hidden = [n for n in client.get(
        "/notifications", headers=auth_headers(owner["access_token"]),
    ).json()["notifications"] if n["type"] == "moderation_action"]
    assert [n["entity_title"] for n in hidden] == [None]


def test_an_access_grant_to_a_live_trip_still_names_it_in_a_push(monkeypatch, client):
    owner = register_user(client, "owner", "owner@x.com")
    editor = register_user(client, "editor", "editor@x.com")
    _register(client, editor["access_token"], device="editor-dev")
    r = client.post("/itineraries/", json={"title": TITLE, "visibility": "public"},
                    headers=auth_headers(owner["access_token"]))
    trip = r.json()["id"]
    _enable(monkeypatch)
    sent = _capture(monkeypatch)

    r = client.post(f"/itineraries/{trip}/editors", json={"user_id": editor["user_id"]},
                    headers=auth_headers(owner["access_token"]))
    assert r.status_code == 201, r.text
    assert len(sent) == 1, sent
    assert TITLE in sent[0]["message"]["notification"]["title"]
