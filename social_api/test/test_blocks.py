"""
test_blocks.py — user blocking.

The property that matters: a block cuts visibility in BOTH directions. A block
that only hid the blocker's view would leave the blocked user free to keep
reading, quoting and reacting to someone who asked to be left alone — which is
the harassment pattern the feature exists to stop.

Also pins that a block is indistinguishable from an absent account, so the
blocked user is never told, and that the list is viewable and reversible
(reviewers check for exactly that).
"""

from __future__ import annotations

import uuid

import pytest

from conftest import TestingSessionLocal, auth_headers, register_user
from app.models.user import User
from app.models.user_block import UserBlock


@pytest.fixture()
def alice(client):
    return register_user(client, "alice", "alice@example.com")


@pytest.fixture()
def bruno(client):
    return register_user(client, "bruno", "bruno@example.com")


def _itinerary(client, token, title="A trip") -> str:
    response = client.post(
        "/itineraries/",
        json={"title": title, "currency": "EUR", "visibility": "public"},
        headers=auth_headers(token),
    )
    assert response.status_code == 201, response.json()
    return response.json()["id"]


def _block(client, token, target_id):
    return client.post(f"/users/{target_id}/block", headers=auth_headers(token))


def _unblock(client, token, target_id):
    return client.delete(f"/users/{target_id}/block", headers=auth_headers(token))


def _feed_ids(client, token) -> list[str]:
    response = client.get("/itineraries/feed?sort=recent", headers=auth_headers(token))
    return [item["id"] for item in response.json()]


def _make_public(client, token) -> None:
    """Public accounts auto-accept follows, which keeps the follow tests simple."""
    client.patch("/users/me", json={"is_private": False}, headers=auth_headers(token))


# ---------------------------------------------------------------------------
# Creating and lifting
# ---------------------------------------------------------------------------

def test_blocking_succeeds_and_is_recorded(client, alice, bruno):
    assert _block(client, alice["access_token"], bruno["user_id"]).status_code == 204

    db = TestingSessionLocal()
    try:
        assert db.query(UserBlock).count() == 1
    finally:
        db.close()


def test_blocking_twice_is_idempotent(client, alice, bruno):
    _block(client, alice["access_token"], bruno["user_id"])
    assert _block(client, alice["access_token"], bruno["user_id"]).status_code == 204

    db = TestingSessionLocal()
    try:
        assert db.query(UserBlock).count() == 1
    finally:
        db.close()


def test_you_cannot_block_yourself(client, alice):
    response = _block(client, alice["access_token"], alice["user_id"])
    assert response.status_code == 400
    assert response.json()["code"] == "cannot_block_self"


def test_blocking_an_unknown_user_404s(client, alice):
    response = _block(client, alice["access_token"], str(uuid.uuid4()))
    assert response.status_code == 404


def test_unblocking_restores_visibility(client, alice, bruno):
    itinerary = _itinerary(client, bruno["access_token"])
    _block(client, alice["access_token"], bruno["user_id"])
    assert itinerary not in _feed_ids(client, alice["access_token"])

    assert _unblock(client, alice["access_token"], bruno["user_id"]).status_code == 204
    assert itinerary in _feed_ids(client, alice["access_token"])


def test_unblocking_someone_who_is_not_blocked_is_a_no_op(client, alice, bruno):
    """An optimistic UI must never have to error on this."""
    assert _unblock(client, alice["access_token"], bruno["user_id"]).status_code == 204


# ---------------------------------------------------------------------------
# Both-direction invisibility
# ---------------------------------------------------------------------------

def test_the_blockers_feed_loses_the_blocked_users_content(client, alice, bruno):
    itinerary = _itinerary(client, bruno["access_token"], title="Bruno's trip")
    assert itinerary in _feed_ids(client, alice["access_token"])

    _block(client, alice["access_token"], bruno["user_id"])

    assert itinerary not in _feed_ids(client, alice["access_token"])


def test_the_blocked_users_feed_loses_the_blockers_content(client, alice, bruno):
    """The direction that actually stops harassment."""
    itinerary = _itinerary(client, alice["access_token"], title="Alice's trip")
    assert itinerary in _feed_ids(client, bruno["access_token"])

    _block(client, alice["access_token"], bruno["user_id"])

    assert itinerary not in _feed_ids(client, bruno["access_token"])


def test_the_blocked_user_cannot_open_the_blockers_itinerary(client, alice, bruno):
    itinerary = _itinerary(client, alice["access_token"])
    _block(client, alice["access_token"], bruno["user_id"])

    response = client.get(
        f"/itineraries/{itinerary}", headers=auth_headers(bruno["access_token"])
    )
    assert response.status_code == 403


def test_the_owner_still_sees_their_own_content(client, alice, bruno):
    itinerary = _itinerary(client, alice["access_token"])
    _block(client, alice["access_token"], bruno["user_id"])

    response = client.get(
        f"/itineraries/{itinerary}", headers=auth_headers(alice["access_token"])
    )
    assert response.status_code == 200


# ---------------------------------------------------------------------------
# Profiles: a block looks exactly like an absent account
# ---------------------------------------------------------------------------

def test_the_blockers_profile_404s_for_the_blocked_user(client, alice, bruno):
    """Never a distinct error — the blocked user must not be able to tell."""
    _block(client, alice["access_token"], bruno["user_id"])

    response = client.get(
        f"/users/{alice['user_id']}", headers=auth_headers(bruno["access_token"])
    )
    assert response.status_code == 404
    assert response.json()["code"] == "user_not_found"


def test_the_blocked_users_profile_404s_for_the_blocker(client, alice, bruno):
    _block(client, alice["access_token"], bruno["user_id"])

    response = client.get(
        f"/users/{bruno['user_id']}", headers=auth_headers(alice["access_token"])
    )
    assert response.status_code == 404


def test_a_blocked_user_cannot_be_followed(client, alice, bruno):
    _block(client, alice["access_token"], bruno["user_id"])

    response = client.post(
        f"/users/{alice['user_id']}/follow", headers=auth_headers(bruno["access_token"])
    )
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# Follows are severed
# ---------------------------------------------------------------------------

def test_blocking_severs_an_existing_follow_and_fixes_the_counters(
    client, alice, bruno
):
    """Leaving the follow in place would keep delivering the blocked user's
    content and keep their name on the follower list."""
    _make_public(client, alice["access_token"])
    client.post(
        f"/users/{alice['user_id']}/follow", headers=auth_headers(bruno["access_token"])
    )

    db = TestingSessionLocal()
    try:
        assert db.get(User, uuid.UUID(alice["user_id"])).followers_count == 1
    finally:
        db.close()

    _block(client, alice["access_token"], bruno["user_id"])

    db = TestingSessionLocal()
    try:
        alice_row = db.get(User, uuid.UUID(alice["user_id"]))
        bruno_row = db.get(User, uuid.UUID(bruno["user_id"]))
        assert alice_row.followers_count == 0
        assert bruno_row.following_count == 0
    finally:
        db.close()


def test_unblocking_does_not_restore_the_follow(client, alice, bruno):
    """Re-following is a decision the user makes again, not one we make for them."""
    _make_public(client, alice["access_token"])
    client.post(
        f"/users/{alice['user_id']}/follow", headers=auth_headers(bruno["access_token"])
    )
    _block(client, alice["access_token"], bruno["user_id"])
    _unblock(client, alice["access_token"], bruno["user_id"])

    profile = client.get(
        f"/users/{alice['user_id']}", headers=auth_headers(bruno["access_token"])
    ).json()
    assert profile["is_following"] is False


# ---------------------------------------------------------------------------
# The blocked-users list
# ---------------------------------------------------------------------------

def test_the_blocked_list_is_viewable(client, alice, bruno):
    _block(client, alice["access_token"], bruno["user_id"])

    rows = client.get("/users/me/blocks", headers=auth_headers(alice["access_token"])).json()

    assert [row["username"] for row in rows] == ["bruno"]


def test_the_blocked_list_is_empty_by_default(client, alice):
    rows = client.get("/users/me/blocks", headers=auth_headers(alice["access_token"])).json()
    assert rows == []


def test_being_blocked_does_not_show_up_in_your_own_list(client, alice, bruno):
    """The blocked user is never told, including by inference from this list."""
    _block(client, alice["access_token"], bruno["user_id"])

    rows = client.get("/users/me/blocks", headers=auth_headers(bruno["access_token"])).json()
    assert rows == []


def test_the_list_shrinks_after_unblocking(client, alice, bruno):
    _block(client, alice["access_token"], bruno["user_id"])
    _unblock(client, alice["access_token"], bruno["user_id"])

    rows = client.get("/users/me/blocks", headers=auth_headers(alice["access_token"])).json()
    assert rows == []


# ---------------------------------------------------------------------------
# Account deletion
# ---------------------------------------------------------------------------

def test_deleting_an_account_removes_its_blocks(client, alice, bruno):
    """A block is a preference, not evidence — it goes with the account."""
    _block(client, alice["access_token"], bruno["user_id"])

    response = client.request(
        "DELETE", "/users/me",
        json={"password": "test1234"},
        headers=auth_headers(alice["access_token"]),
    )
    assert response.status_code == 204

    db = TestingSessionLocal()
    try:
        assert db.query(UserBlock).count() == 0
    finally:
        db.close()


# ---------------------------------------------------------------------------
# ToS version
# ---------------------------------------------------------------------------

def test_registration_records_the_accepted_tos_version(client, alice):
    db = TestingSessionLocal()
    try:
        user = db.query(User).filter(User.username_lower == "alice").one()
        assert user.tos_accepted_at is not None
        assert user.tos_accepted_version  # which revision, not merely that one existed
    finally:
        db.close()


def test_the_tos_endpoint_publishes_the_abuse_contact(client):
    """The in-app address must never drift from the backend config or the store
    listing, so there is exactly one source for it."""
    body = client.get("/auth/tos").json()

    assert body["version"]
    assert "@" in body["abuse_contact"]
    assert body["community_guidelines_url"].endswith("/guidelines")
