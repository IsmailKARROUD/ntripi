"""
test_notifications.py — Tests for the in-app notification feed.

Covers the three suppression rules that only hold because
notification_service.notify is the single writer (self, muted, blocked), the
idempotent call sites (re-save, rating edit, repeat auto-hide), the feed and
badge endpoints, the IDOR guards on marking read and deleting, and the retention
purge — both its read window and its hard age cap.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from conftest import (
    TestingSessionLocal, auth_headers, make_admin, register_user,
)
from app.config import Settings, get_settings
from app.models.notification import Notification
from app.services import notification_service
from app.services.token_util import as_aware_utc


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _create_itinerary(client, token, *, visibility="public", title="Test Trip"):
    r = client.post(
        "/itineraries/",
        json={"title": title, "visibility": visibility},
        headers=auth_headers(token),
    )
    assert r.status_code == 201, r.json()
    return r.json()


def _set_private(client, token, is_private: bool) -> None:
    r = client.patch(
        "/users/me", json={"is_private": is_private}, headers=auth_headers(token),
    )
    assert r.status_code == 200, r.json()


def _instant(value: str) -> datetime:
    """Parse a wire datetime to an aware instant, naive or not."""
    return as_aware_utc(datetime.fromisoformat(value))


def _feed(client, token) -> dict:
    r = client.get("/notifications", headers=auth_headers(token))
    assert r.status_code == 200, r.json()
    return r.json()


def _types(client, token) -> list[str]:
    return [n["type"] for n in _feed(client, token)["notifications"]]


def _rows() -> list[Notification]:
    db = TestingSessionLocal()
    try:
        return db.query(Notification).all()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Follows
# ---------------------------------------------------------------------------

def test_follow_request_notifies_the_target_only(client: TestClient):
    alice = register_user(client, "alice", "alice@x.com")
    bobby = register_user(client, "bobby", "bob@x.com")
    _set_private(client, bobby["access_token"], True)

    r = client.post(
        f"/users/{bobby['user_id']}/follow", headers=auth_headers(alice["access_token"]),
    )
    assert r.status_code == 201, r.json()

    assert _types(client, bobby["access_token"]) == ["follow_request"]
    # The actor is never notified about their own action.
    assert _types(client, alice["access_token"]) == []


def test_public_follow_notifies_new_follower_not_request(client: TestClient):
    alice = register_user(client, "alice", "alice@x.com")
    bobby = register_user(client, "bobby", "bob@x.com")
    _set_private(client, bobby["access_token"], False)

    client.post(
        f"/users/{bobby['user_id']}/follow", headers=auth_headers(alice["access_token"]),
    )

    assert _types(client, bobby["access_token"]) == ["new_follower"]


def test_accepting_a_request_notifies_the_requester(client: TestClient):
    alice = register_user(client, "alice", "alice@x.com")
    bobby = register_user(client, "bobby", "bob@x.com")
    _set_private(client, bobby["access_token"], True)

    client.post(
        f"/users/{bobby['user_id']}/follow", headers=auth_headers(alice["access_token"]),
    )
    requests = client.get(
        "/users/me/follow-requests", headers=auth_headers(bobby["access_token"]),
    ).json()
    follow_id = requests[0]["follow_id"]

    r = client.post(
        f"/users/me/follow-requests/{follow_id}/accept",
        headers=auth_headers(bobby["access_token"]),
    )
    assert r.status_code == 200, r.json()

    assert _types(client, alice["access_token"]) == ["follow_accepted"]


def test_going_public_notifies_every_pending_requester(client: TestClient):
    """The bulk auto-accept is a separate code path from the single accept."""
    owner = register_user(client, "owner", "owner@x.com")
    _set_private(client, owner["access_token"], True)

    fans = [
        register_user(client, f"fan{i}", f"fan{i}@x.com") for i in range(3)
    ]
    for fan in fans:
        client.post(
            f"/users/{owner['user_id']}/follow",
            headers=auth_headers(fan["access_token"]),
        )

    _set_private(client, owner["access_token"], False)

    for fan in fans:
        assert _types(client, fan["access_token"]) == ["follow_accepted"]


def test_muted_follow_accepted_writes_no_row(client: TestClient):
    alice = register_user(client, "alice", "alice@x.com")
    bobby = register_user(client, "bobby", "bob@x.com")
    _set_private(client, bobby["access_token"], True)

    r = client.patch(
        "/users/me", json={"notify_follow_accepted": False},
        headers=auth_headers(alice["access_token"]),
    )
    assert r.status_code == 200
    assert r.json()["notify_follow_accepted"] is False

    client.post(
        f"/users/{bobby['user_id']}/follow", headers=auth_headers(alice["access_token"]),
    )
    requests = client.get(
        "/users/me/follow-requests", headers=auth_headers(bobby["access_token"]),
    ).json()
    client.post(
        f"/users/me/follow-requests/{requests[0]['follow_id']}/accept",
        headers=auth_headers(bobby["access_token"]),
    )

    assert _types(client, alice["access_token"]) == []


def test_blocked_user_generates_no_notification(client: TestClient):
    alice = register_user(client, "alice", "alice@x.com")
    bobby = register_user(client, "bobby", "bob@x.com")
    _set_private(client, bobby["access_token"], False)

    # Bob blocks Alice; visibility is cut in both directions, and that includes
    # being told the blocked user did something.
    r = client.post(
        f"/users/{alice['user_id']}/block", headers=auth_headers(bobby["access_token"]),
    )
    assert r.status_code in (200, 201, 204), r.text

    # Driven through notify() directly rather than through the follow endpoint:
    # a blocked follow is refused upstream, so going via HTTP would pass even if
    # the block check were missing from the seam.
    from app.models.user import User

    db = TestingSessionLocal()
    try:
        actor = db.get(User, uuid.UUID(alice["user_id"]))
        assert notification_service.notify(
            db, user_id=uuid.UUID(bobby["user_id"]),
            type="new_follower", actor=actor,
        ) is None
        db.commit()
    finally:
        db.close()

    assert _rows() == []
    assert _types(client, bobby["access_token"]) == []


# ---------------------------------------------------------------------------
# Itineraries
# ---------------------------------------------------------------------------

def test_first_rating_notifies_owner_and_edits_do_not(client: TestClient):
    owner = register_user(client, "owner", "owner@x.com")
    rater = register_user(client, "rater", "rater@x.com")
    itinerary = _create_itinerary(client, owner["access_token"])

    for stars in (5, 3):  # POST is an upsert — the second call is an edit
        r = client.post(
            f"/itineraries/{itinerary['id']}/ratings",
            json={"stars": stars}, headers=auth_headers(rater["access_token"]),
        )
        assert r.status_code in (200, 201), r.json()

    assert _types(client, owner["access_token"]) == ["itinerary_rated"]


def test_muted_ratings_write_no_row_but_the_rating_still_lands(client: TestClient):
    owner = register_user(client, "owner", "owner@x.com")
    rater = register_user(client, "rater", "rater@x.com")
    client.patch(
        "/users/me", json={"notify_ratings": False},
        headers=auth_headers(owner["access_token"]),
    )
    itinerary = _create_itinerary(client, owner["access_token"])

    r = client.post(
        f"/itineraries/{itinerary['id']}/ratings",
        json={"stars": 4}, headers=auth_headers(rater["access_token"]),
    )
    assert r.status_code in (200, 201), r.json()
    # Suppressing the notification must never suppress the write it rode with.
    assert r.json()["stars"] == 4
    assert _types(client, owner["access_token"]) == []


def test_saving_twice_notifies_once(client: TestClient):
    owner = register_user(client, "owner", "owner@x.com")
    saver = register_user(client, "saver", "saver@x.com")
    itinerary = _create_itinerary(client, owner["access_token"])

    for _ in range(2):  # save is idempotent — the second call early-returns
        r = client.post(
            f"/itineraries/{itinerary['id']}/save",
            headers=auth_headers(saver["access_token"]),
        )
        assert r.status_code == 204, r.text

    assert _types(client, owner["access_token"]) == ["itinerary_saved"]


def test_feed_resolves_the_entity_title(client: TestClient):
    owner = register_user(client, "owner", "owner@x.com")
    saver = register_user(client, "saver", "saver@x.com")
    itinerary = _create_itinerary(client, owner["access_token"], title="Kyoto 5 days")
    client.post(
        f"/itineraries/{itinerary['id']}/save",
        headers=auth_headers(saver["access_token"]),
    )

    item = _feed(client, owner["access_token"])["notifications"][0]
    assert item["entity_title"] == "Kyoto 5 days"
    assert item["entity_type"] == "itinerary"
    assert item["actor_username"] == "saver"


# ---------------------------------------------------------------------------
# Access grants
# ---------------------------------------------------------------------------

def test_allowlisting_a_user_notifies_them_about_that_itinerary(
    client: TestClient,
):
    """A restricted itinerary shows up in no feed and no search, so this row is
    the only way the person learns they were let in. It has to carry enough for
    the client to name the trip and the person who shared it."""
    owner = register_user(client, "owner", "owner@x.com")
    guest = register_user(client, "bobby", "bobby@x.com")
    itinerary = _create_itinerary(
        client, owner["access_token"],
        visibility="restricted", title="Kyoto 5 days",
    )

    r = client.post(
        f"/itineraries/{itinerary['id']}/allowed-users",
        json={"user_id": guest["user_id"]},
        headers=auth_headers(owner["access_token"]),
    )
    assert r.status_code == 201, r.text

    item = _feed(client, guest["access_token"])["notifications"][0]
    assert item["type"] == "itinerary_viewer_added"
    assert item["entity_type"] == "itinerary"
    assert item["entity_id"] == itinerary["id"]
    assert item["entity_title"] == "Kyoto 5 days"
    assert item["actor_username"] == "owner"


def test_the_owner_is_not_notified_by_their_own_allowlist_grant(
    client: TestClient,
):
    """Nothing stops an owner adding themselves; notify's self rule does."""
    owner = register_user(client, "owner", "owner@x.com")
    itinerary = _create_itinerary(
        client, owner["access_token"], visibility="restricted",
    )

    client.post(
        f"/itineraries/{itinerary['id']}/allowed-users",
        json={"user_id": owner["user_id"]},
        headers=auth_headers(owner["access_token"]),
    )

    assert _types(client, owner["access_token"]) == []


# ---------------------------------------------------------------------------
# Moderation
# ---------------------------------------------------------------------------

def test_auto_hide_notifies_the_author_once(client: TestClient):
    """The second auto_hide is a no-op, so it must not stack a second notice."""
    from app.models.itinerary import Itinerary
    from app.services import moderation_actions

    owner = register_user(client, "owner", "owner@x.com")
    itinerary = _create_itinerary(client, owner["access_token"])

    db = TestingSessionLocal()
    try:
        row = db.get(Itinerary, uuid.UUID(itinerary["id"]))
        for _ in range(2):
            moderation_actions.auto_hide(
                db, "itinerary", row,
                action="auto_hide_reports", reason="threshold reached",
            )
        db.commit()
    finally:
        db.close()

    feed = _feed(client, owner["access_token"])["notifications"]
    assert [n["type"] for n in feed] == ["moderation_action"]
    # The action name rides in subtype so a new moderation action needs no new type.
    assert feed[0]["subtype"] == "auto_hide_reports"
    # System action — naming the reporter would out them.
    assert feed[0]["actor_id"] is None


def _warn(warned_id: str, admin_id: str, reason: str = "be nicer") -> None:
    """Issue an operator warning straight through the service."""
    from app.models.user import User
    from app.services import admin_service

    db = TestingSessionLocal()
    try:
        admin_service.warn_user(
            db,
            db.get(User, uuid.UUID(admin_id)),
            db.get(User, uuid.UUID(warned_id)),
            reason,
        )
    finally:
        db.close()


def test_warning_notifies_the_warned_user(client: TestClient):
    warned = register_user(client, "warned", "warned@x.com")
    operator = register_user(client, "operator", "ops@x.com")
    make_admin("ops@x.com")

    _warn(warned["user_id"], operator["user_id"])

    feed = _feed(client, warned["access_token"])["notifications"]
    assert [n["type"] for n in feed] == ["moderation_action"]
    assert feed[0]["subtype"] == "warn"
    # The moderator is never named to the person they warned.
    assert feed[0]["actor_id"] is None
    # A warning is against the person, so it carries no itinerary to show.
    assert feed[0]["entity_type"] == "user"
    assert feed[0]["entity_title"] is None

    # The operator is not notified about the action they took.
    assert _types(client, operator["access_token"]) == []


def test_a_second_warning_is_a_second_notification(client: TestClient):
    """Unlike auto_hide, warnings are NOT idempotent — escalation is the point,
    and collapsing the second one would hide that this has happened before."""
    warned = register_user(client, "warned", "warned@x.com")
    operator = register_user(client, "operator", "ops@x.com")
    make_admin("ops@x.com")

    _warn(warned["user_id"], operator["user_id"], "first")
    _warn(warned["user_id"], operator["user_id"], "second")

    feed = _feed(client, warned["access_token"])["notifications"]
    assert [n["subtype"] for n in feed] == ["warn", "warn"]


def test_warning_is_appealable_from_account_status(client: TestClient):
    """The notification's whole tap target is the violations feed, so a warning
    that never lands there would send the user to an empty screen."""
    warned = register_user(client, "warned", "warned@x.com")
    operator = register_user(client, "operator", "ops@x.com")
    make_admin("ops@x.com")

    _warn(warned["user_id"], operator["user_id"])

    violations = client.get(
        "/appeals/violations", headers=auth_headers(warned["access_token"]),
    ).json()["violations"]
    assert [v["action"] for v in violations] == ["warn"]
    assert violations[0]["appealable"] is True


# ---------------------------------------------------------------------------
# Feed, badge and mark-read
# ---------------------------------------------------------------------------

def test_unread_count_and_mark_all_read(client: TestClient):
    owner = register_user(client, "owner", "owner@x.com")
    itinerary = _create_itinerary(client, owner["access_token"])
    for i in range(2):
        saver = register_user(client, f"saver{i}", f"saver{i}@x.com")
        client.post(
            f"/itineraries/{itinerary['id']}/save",
            headers=auth_headers(saver["access_token"]),
        )

    headers = auth_headers(owner["access_token"])
    assert client.get(
        "/notifications/unread-count", headers=headers
    ).json()["unread_count"] == 2

    # Omitting `ids` marks everything read.
    assert client.post("/notifications/read", json={}, headers=headers).status_code == 204
    assert client.get(
        "/notifications/unread-count", headers=headers
    ).json()["unread_count"] == 0
    assert all(n["read"] for n in _feed(client, owner["access_token"])["notifications"])


def test_mark_read_with_explicit_ids(client: TestClient):
    owner = register_user(client, "owner", "owner@x.com")
    itinerary = _create_itinerary(client, owner["access_token"])
    for i in range(2):
        saver = register_user(client, f"saver{i}", f"saver{i}@x.com")
        client.post(
            f"/itineraries/{itinerary['id']}/save",
            headers=auth_headers(saver["access_token"]),
        )

    headers = auth_headers(owner["access_token"])
    first = _feed(client, owner["access_token"])["notifications"][0]["id"]
    client.post("/notifications/read", json={"ids": [first]}, headers=headers)

    assert client.get(
        "/notifications/unread-count", headers=headers
    ).json()["unread_count"] == 1


def test_latest_at_is_the_arrival_signal_and_survives_mark_read(
    client: TestClient,
):
    """The count answers "how many"; latest_at answers "has anything arrived".

    They must not be the same signal. Marking everything read drives the count
    to zero, and if the client keyed its cue off that it would read the drop as
    news. Worse in the other direction: a read on another device cancelling out
    an arrival leaves the count unchanged and swallows the arrival entirely.
    latest_at only ever moves forward, and nothing anyone reads can move it.
    """
    owner = register_user(client, "owner", "owner@x.com")
    itinerary = _create_itinerary(client, owner["access_token"])
    headers = auth_headers(owner["access_token"])

    saver = register_user(client, "saver", "saver@x.com")
    client.post(
        f"/itineraries/{itinerary['id']}/save",
        headers=auth_headers(saver["access_token"]),
    )

    badge = client.get("/notifications/unread-count", headers=headers).json()
    page = _feed(client, owner["access_token"])
    # Compared as instants, not strings: badge_state normalizes to aware UTC,
    # while an item's created_at is whatever the driver returned — naive under
    # SQLite, aware under PostgreSQL. Same moment, two spellings.
    assert _instant(badge["latest_at"]) == _instant(
        page["notifications"][0]["created_at"]
    )
    # Both endpoints answer with the same value, so a feed load can move the
    # client's arrival baseline without spending a second request.
    assert page["latest_at"] == badge["latest_at"]

    client.post("/notifications/read", json={}, headers=headers)

    after = client.get("/notifications/unread-count", headers=headers).json()
    assert after["unread_count"] == 0
    assert after["latest_at"] == badge["latest_at"]


def test_latest_at_is_null_without_notifications(client: TestClient):
    user = register_user(client, "lonely", "lonely@x.com")

    assert client.get(
        "/notifications/unread-count", headers=auth_headers(user["access_token"]),
    ).json() == {"unread_count": 0, "latest_at": None}


def test_latest_at_advances_when_the_count_does_not(client: TestClient):
    """The aliasing case the timestamp exists for.

    One notification read and one new one arriving between two polls leaves the
    count exactly where it was. A client watching the count would see nothing
    happen; latest_at still moves.
    """
    owner = register_user(client, "owner", "owner@x.com")
    itinerary = _create_itinerary(client, owner["access_token"])
    headers = auth_headers(owner["access_token"])

    for i in range(2):
        saver = register_user(client, f"saver{i}", f"saver{i}@x.com")
        client.post(
            f"/itineraries/{itinerary['id']}/save",
            headers=auth_headers(saver["access_token"]),
        )

    before = client.get("/notifications/unread-count", headers=headers).json()
    assert before["unread_count"] == 2

    # Read one (as another device would) and receive one, between two polls.
    oldest = _feed(client, owner["access_token"])["notifications"][-1]["id"]
    client.post("/notifications/read", json={"ids": [oldest]}, headers=headers)
    late = register_user(client, "late", "late@x.com")
    client.post(
        f"/itineraries/{itinerary['id']}/save",
        headers=auth_headers(late["access_token"]),
    )

    after = client.get("/notifications/unread-count", headers=headers).json()
    assert after["unread_count"] == before["unread_count"]  # masked
    assert after["latest_at"] > before["latest_at"]  # not masked


def test_cannot_mark_another_users_notifications_read(client: TestClient):
    owner = register_user(client, "owner", "owner@x.com")
    saver = register_user(client, "saver", "saver@x.com")
    itinerary = _create_itinerary(client, owner["access_token"])
    client.post(
        f"/itineraries/{itinerary['id']}/save",
        headers=auth_headers(saver["access_token"]),
    )

    victim_id = _feed(client, owner["access_token"])["notifications"][0]["id"]

    # 204 either way — the response must not reveal whose row that id is.
    r = client.post(
        "/notifications/read", json={"ids": [victim_id]},
        headers=auth_headers(saver["access_token"]),
    )
    assert r.status_code == 204

    assert client.get(
        "/notifications/unread-count", headers=auth_headers(owner["access_token"]),
    ).json()["unread_count"] == 1


def test_feed_is_scoped_to_the_current_user(client: TestClient):
    owner = register_user(client, "owner", "owner@x.com")
    saver = register_user(client, "saver", "saver@x.com")
    itinerary = _create_itinerary(client, owner["access_token"])
    client.post(
        f"/itineraries/{itinerary['id']}/save",
        headers=auth_headers(saver["access_token"]),
    )

    assert _feed(client, saver["access_token"])["notifications"] == []


def test_feed_requires_auth(client: TestClient):
    # 403, not 401 — HTTPBearer rejects a missing header before the dependency
    # runs, which is what every other authenticated endpoint here does too.
    assert client.get("/notifications").status_code == 403


def test_feed_is_newest_first_and_paginates(client: TestClient):
    owner = register_user(client, "owner", "owner@x.com")
    itinerary = _create_itinerary(client, owner["access_token"])
    for i in range(3):
        saver = register_user(client, f"saver{i}", f"saver{i}@x.com")
        client.post(
            f"/itineraries/{itinerary['id']}/save",
            headers=auth_headers(saver["access_token"]),
        )

    headers = auth_headers(owner["access_token"])
    page = client.get("/notifications?limit=2", headers=headers).json()
    assert len(page["notifications"]) == 2
    assert page["unread_count"] == 3  # the badge counts all of them, not the page

    rest = client.get("/notifications?limit=2&offset=2", headers=headers).json()
    assert len(rest["notifications"]) == 1

    ids = [n["id"] for n in page["notifications"]] + [
        n["id"] for n in rest["notifications"]
    ]
    assert len(set(ids)) == 3  # no row appears on two pages


# ---------------------------------------------------------------------------
# Deleting
# ---------------------------------------------------------------------------

def _one_notification(client, token) -> str:
    """Register a saver, have them save `token`'s itinerary, return the row id."""
    itinerary = _create_itinerary(client, token)
    saver = register_user(client, "saver", "saver@x.com")
    client.post(
        f"/itineraries/{itinerary['id']}/save",
        headers=auth_headers(saver["access_token"]),
    )
    return _feed(client, token)["notifications"][0]["id"]


def test_delete_removes_the_row_and_clears_the_badge(client: TestClient):
    owner = register_user(client, "owner", "owner@x.com")
    headers = auth_headers(owner["access_token"])
    notification_id = _one_notification(client, owner["access_token"])

    r = client.delete(f"/notifications/{notification_id}", headers=headers)
    assert r.status_code == 204

    # latest_at goes null along with the rows — there is no newest one left.
    assert _feed(client, owner["access_token"]) == {
        "notifications": [], "unread_count": 0, "latest_at": None
    }
    assert _rows() == []


def test_delete_is_idempotent(client: TestClient):
    """The client removes the row on screen first and sends this afterwards, so
    a retry must not surface an error for something already gone."""
    owner = register_user(client, "owner", "owner@x.com")
    headers = auth_headers(owner["access_token"])
    notification_id = _one_notification(client, owner["access_token"])

    assert client.delete(f"/notifications/{notification_id}", headers=headers).status_code == 204
    assert client.delete(f"/notifications/{notification_id}", headers=headers).status_code == 204
    # An id that never existed answers the same — no existence oracle.
    assert client.delete(f"/notifications/{uuid.uuid4()}", headers=headers).status_code == 204


def test_cannot_delete_another_users_notification(client: TestClient):
    owner = register_user(client, "owner", "owner@x.com")
    notification_id = _one_notification(client, owner["access_token"])
    intruder = register_user(client, "intruder", "intruder@x.com")

    # 204 either way — the response must not reveal whose row that id is.
    r = client.delete(
        f"/notifications/{notification_id}",
        headers=auth_headers(intruder["access_token"]),
    )
    assert r.status_code == 204

    assert len(_feed(client, owner["access_token"])["notifications"]) == 1


def test_clear_all_empties_only_the_callers_feed(client: TestClient):
    owner = register_user(client, "owner", "owner@x.com")
    other = register_user(client, "other", "other@x.com")
    itinerary = _create_itinerary(client, owner["access_token"])
    others_itinerary = _create_itinerary(client, other["access_token"])
    for i in range(3):
        saver = register_user(client, f"saver{i}", f"saver{i}@x.com")
        client.post(
            f"/itineraries/{itinerary['id']}/save",
            headers=auth_headers(saver["access_token"]),
        )
        client.post(
            f"/itineraries/{others_itinerary['id']}/save",
            headers=auth_headers(saver["access_token"]),
        )

    r = client.delete("/notifications", headers=auth_headers(owner["access_token"]))
    assert r.status_code == 204

    # latest_at goes null along with the rows — there is no newest one left.
    assert _feed(client, owner["access_token"]) == {
        "notifications": [], "unread_count": 0, "latest_at": None
    }
    assert len(_feed(client, other["access_token"])["notifications"]) == 3


def test_delete_requires_auth(client: TestClient):
    # 403, not 401 — HTTPBearer rejects a missing header before the dependency
    # runs, same as every other authenticated endpoint here.
    assert client.delete(f"/notifications/{uuid.uuid4()}").status_code == 403
    assert client.delete("/notifications").status_code == 403


# ---------------------------------------------------------------------------
# Retention
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "read, age_days, expect_purged",
    [
        # Read and past the read window — the normal purge.
        (True, "read_window", 1),
        # Read but still inside it.
        (True, "fresh", 0),
        # Unread outlives the read window: the recipient still has to find out.
        (False, "read_window", 0),
        # …but not the hard cap. A year-old unread notice is not actionable.
        (False, "cap", 1),
    ],
)
def test_purge_honours_the_read_window_and_the_hard_cap(
    client: TestClient, read, age_days, expect_purged
):
    owner = register_user(client, "owner", "owner@x.com")
    saver = register_user(client, "saver", "saver@x.com")
    itinerary = _create_itinerary(client, owner["access_token"])
    client.post(
        f"/itineraries/{itinerary['id']}/save",
        headers=auth_headers(saver["access_token"]),
    )

    settings = get_settings()
    days = {
        "fresh": 1,
        "read_window": settings.NOTIFICATION_RETENTION_DAYS + 1,
        "cap": settings.NOTIFICATION_MAX_AGE_DAYS + 1,
    }[age_days]
    aged = datetime.now(timezone.utc) - timedelta(days=days)

    db = TestingSessionLocal()
    try:
        row = db.query(Notification).one()
        row.created_at = aged
        if read:
            row.read_at = aged
        db.commit()

        assert notification_service.purge_expired(db, settings) == expect_purged
        db.commit()
    finally:
        db.close()

    assert len(_rows()) == (0 if expect_purged else 1)


def test_max_age_below_the_read_window_refuses_to_boot():
    """A cap under the read window would silently shorten it — that has to fail
    at startup, not quietly lose notices early."""
    with pytest.raises(ValidationError):
        Settings(
            SECRET_KEY="x" * 32,
            NOTIFICATION_RETENTION_DAYS=90,
            NOTIFICATION_MAX_AGE_DAYS=10,
        )
