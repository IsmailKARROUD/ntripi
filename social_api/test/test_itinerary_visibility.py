"""
tests/test_itinerary_visibility.py — Tests for the four-level visibility system.

Every test is independent: it uses the 'client' fixture which provides a fresh
SQLite in-memory database. No state leaks between tests.

Visibility levels under test:
  public      — any authenticated user can view
  followers   — owner + accepted followers only
  restricted  — owner + explicit allowlist only
  only_me     — owner only

The helpers at the top of this file mirror the pattern in test_follows.py.
"""

import pytest
from fastapi.testclient import TestClient

from conftest import auth_headers, register_user


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_public(client: TestClient, token: str) -> None:
    """Make the authenticated user's account public (follows auto-accept)."""
    client.patch("/users/me", headers=auth_headers(token), json={"is_private": False})


def make_private(client: TestClient, token: str) -> None:
    """Make the authenticated user's account private (follows require approval)."""
    client.patch("/users/me", headers=auth_headers(token), json={"is_private": True})


def create_itinerary(
    client: TestClient,
    token: str,
    visibility: str = "only_me",
    title: str = "Test Trip",
) -> dict:
    """Create an itinerary and return the response body. Asserts 201."""
    response = client.post(
        "/itineraries/",
        json={"title": title, "visibility": visibility},
        headers=auth_headers(token),
    )
    assert response.status_code == 201, f"create_itinerary failed: {response.json()}"
    return response.json()


def fetch_itinerary(client: TestClient, token: str, itinerary_id: str):
    """GET /itineraries/{id} and return the raw response (do not assert)."""
    return client.get(
        f"/itineraries/{itinerary_id}",
        headers=auth_headers(token),
    )


def follow_user(client: TestClient, follower_token: str, target_id: str):
    """Send a follow request and return the response."""
    return client.post(
        f"/users/{target_id}/follow",
        headers=auth_headers(follower_token),
    )


def accept_follow(client: TestClient, owner_token: str, follow_id: str) -> None:
    """Owner accepts a pending follow request."""
    resp = client.post(
        f"/users/me/follow-requests/{follow_id}/accept",
        headers=auth_headers(owner_token),
    )
    assert resp.status_code == 200


def setup_accepted_follow(
    client: TestClient,
    follower_token: str,
    owner_token: str,
    owner_id: str,
) -> None:
    """
    Make the owner public and have the follower follow them.
    Since the owner is public, the follow is auto-accepted.
    """
    make_public(client, owner_token)
    resp = follow_user(client, follower_token, owner_id)
    assert resp.status_code == 201
    assert resp.json()["status"] == "accepted"


def add_to_allowlist(
    client: TestClient,
    owner_token: str,
    itinerary_id: str,
    user_id: str,
):
    """Add a user to the allowlist and return the response."""
    return client.post(
        f"/itineraries/{itinerary_id}/allowed-users",
        json={"user_id": user_id},
        headers=auth_headers(owner_token),
    )


def remove_from_allowlist(
    client: TestClient,
    owner_token: str,
    itinerary_id: str,
    user_id: str,
):
    """Remove a user from the allowlist and return the response."""
    return client.delete(
        f"/itineraries/{itinerary_id}/allowed-users/{user_id}",
        headers=auth_headers(owner_token),
    )


def update_visibility(
    client: TestClient,
    token: str,
    itinerary_id: str,
    visibility: str,
) -> None:
    """PATCH an itinerary's visibility and assert 200."""
    resp = client.patch(
        f"/itineraries/{itinerary_id}",
        json={"visibility": visibility},
        headers=auth_headers(token),
    )
    assert resp.status_code == 200


# ---------------------------------------------------------------------------
# Class: TestVisibilityPublic
# ---------------------------------------------------------------------------

class TestVisibilityPublic:

    def test_owner_can_view_public(self, client: TestClient):
        """Owner creates a public itinerary and fetches it. Expects 200."""
        alice = register_user(client, "alice", "alice@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "public")

        response = fetch_itinerary(client, alice["access_token"], itinerary["id"])

        assert response.status_code == 200

    def test_stranger_can_view_public(self, client: TestClient):
        """A user with no relationship to the owner can view a public itinerary."""
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "public")

        response = fetch_itinerary(client, bob["access_token"], itinerary["id"])

        assert response.status_code == 200

    def test_non_follower_can_view_public(self, client: TestClient):
        """Confirms public means everyone: a non-follower has the same access as a stranger."""
        alice = register_user(client, "alice", "alice@test.com")
        charlie = register_user(client, "charlie", "charlie@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "public")

        response = fetch_itinerary(client, charlie["access_token"], itinerary["id"])

        assert response.status_code == 200


# ---------------------------------------------------------------------------
# Class: TestVisibilityFollowers
# ---------------------------------------------------------------------------

class TestVisibilityFollowers:

    def test_owner_can_view_followers_itinerary(self, client: TestClient):
        """Owner always has access to their own itinerary, regardless of visibility."""
        alice = register_user(client, "alice", "alice@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "followers")

        response = fetch_itinerary(client, alice["access_token"], itinerary["id"])

        assert response.status_code == 200

    def test_accepted_follower_can_view(self, client: TestClient):
        """
        Bob follows Alice (public → auto-accepted).
        Bob can view Alice's followers itinerary.
        """
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "followers")

        setup_accepted_follow(client, bob["access_token"], alice["access_token"], alice["user_id"])

        response = fetch_itinerary(client, bob["access_token"], itinerary["id"])

        assert response.status_code == 200

    def test_pending_follower_cannot_view(self, client: TestClient):
        """
        Bob sends a follow request to Alice (private account).
        Alice does NOT accept, so Bob's follow stays pending.
        Bob cannot view Alice's followers itinerary.
        """
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "followers")

        make_private(client, alice["access_token"])
        resp = follow_user(client, bob["access_token"], alice["user_id"])
        assert resp.json()["status"] == "pending"

        response = fetch_itinerary(client, bob["access_token"], itinerary["id"])

        assert response.status_code == 403

    def test_stranger_cannot_view_followers_itinerary(self, client: TestClient):
        """Bob has no relationship with Alice. He cannot view her followers itinerary."""
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "followers")

        response = fetch_itinerary(client, bob["access_token"], itinerary["id"])

        assert response.status_code == 403


# ---------------------------------------------------------------------------
# Class: TestVisibilityRestricted
# ---------------------------------------------------------------------------

class TestVisibilityRestricted:

    def test_owner_can_view_restricted(self, client: TestClient):
        """Owner always has access to their own restricted itinerary."""
        alice = register_user(client, "alice", "alice@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "restricted")

        response = fetch_itinerary(client, alice["access_token"], itinerary["id"])

        assert response.status_code == 200

    def test_allowed_user_can_view(self, client: TestClient):
        """
        Alice creates a restricted itinerary and adds Bob to the allowlist.
        Bob can view it.
        """
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "restricted")

        add_resp = add_to_allowlist(
            client, alice["access_token"], itinerary["id"], bob["user_id"]
        )
        assert add_resp.status_code == 201

        response = fetch_itinerary(client, bob["access_token"], itinerary["id"])

        assert response.status_code == 200

    def test_non_allowed_user_cannot_view(self, client: TestClient):
        """Charlie is not in the allowlist. She cannot view the restricted itinerary."""
        alice = register_user(client, "alice", "alice@test.com")
        register_user(client, "bob1", "bob@test.com")
        charlie = register_user(client, "charlie", "charlie@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "restricted")

        response = fetch_itinerary(client, charlie["access_token"], itinerary["id"])

        assert response.status_code == 403

    def test_follower_without_allowlist_cannot_view(self, client: TestClient):
        """
        Key insight: followers visibility and restricted visibility are independent.
        Being an accepted follower of Alice does NOT grant access to her restricted
        itinerary. Explicit allowlist membership is required.
        """
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "restricted")

        # Bob follows Alice and is accepted — but is NOT in the allowlist.
        setup_accepted_follow(client, bob["access_token"], alice["access_token"], alice["user_id"])

        response = fetch_itinerary(client, bob["access_token"], itinerary["id"])

        assert response.status_code == 403

    def test_add_user_to_allowlist_requires_restricted_visibility(self, client: TestClient):
        """
        Alice creates a PUBLIC itinerary.
        Trying to add Bob to the allowlist must fail with 400.
        Allowlist only applies when visibility='restricted'.
        """
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "public")

        resp = add_to_allowlist(
            client, alice["access_token"], itinerary["id"], bob["user_id"]
        )

        assert resp.status_code == 400
        assert "restricted" in resp.json()["detail"].lower()

    def test_only_owner_can_manage_allowlist(self, client: TestClient):
        """
        Bob tries to add Charlie to Alice's allowlist.
        Only Alice (the owner) can do this. Bob receives 403.
        """
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        charlie = register_user(client, "charlie", "charlie@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "restricted")

        resp = add_to_allowlist(
            client, bob["access_token"], itinerary["id"], charlie["user_id"]
        )

        assert resp.status_code == 403

    def test_remove_user_from_allowlist_revokes_access(self, client: TestClient):
        """
        Alice adds Bob → Bob can view (200).
        Alice removes Bob → Bob can no longer view (403).
        """
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "restricted")

        # Grant access
        add_to_allowlist(client, alice["access_token"], itinerary["id"], bob["user_id"])
        assert fetch_itinerary(client, bob["access_token"], itinerary["id"]).status_code == 200

        # Revoke access
        remove_resp = remove_from_allowlist(
            client, alice["access_token"], itinerary["id"], bob["user_id"]
        )
        assert remove_resp.status_code == 204

        # Access should now be denied
        assert fetch_itinerary(client, bob["access_token"], itinerary["id"]).status_code == 403


# ---------------------------------------------------------------------------
# Class: TestVisibilityOnlyMe
# ---------------------------------------------------------------------------

class TestVisibilityOnlyMe:

    def test_owner_can_view_only_me(self, client: TestClient):
        """Owner can always view their own only_me itinerary."""
        alice = register_user(client, "alice", "alice@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "only_me")

        response = fetch_itinerary(client, alice["access_token"], itinerary["id"])

        assert response.status_code == 200

    def test_follower_cannot_view_only_me(self, client: TestClient):
        """Even an accepted follower cannot view an only_me itinerary."""
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "only_me")

        setup_accepted_follow(client, bob["access_token"], alice["access_token"], alice["user_id"])

        response = fetch_itinerary(client, bob["access_token"], itinerary["id"])

        assert response.status_code == 403

    def test_stranger_cannot_view_only_me(self, client: TestClient):
        """A user with no relationship to the owner cannot view an only_me itinerary."""
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "only_me")

        response = fetch_itinerary(client, bob["access_token"], itinerary["id"])

        assert response.status_code == 403


# ---------------------------------------------------------------------------
# Class: TestVisibilityChange
# ---------------------------------------------------------------------------

class TestVisibilityChange:

    def test_changing_from_public_to_only_me_blocks_access(self, client: TestClient):
        """
        Alice creates a public itinerary → Bob can view (200).
        Alice changes visibility to only_me → Bob is blocked (403).
        """
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "public")

        assert fetch_itinerary(client, bob["access_token"], itinerary["id"]).status_code == 200

        update_visibility(client, alice["access_token"], itinerary["id"], "only_me")

        assert fetch_itinerary(client, bob["access_token"], itinerary["id"]).status_code == 403

    def test_changing_from_only_me_to_public_grants_access(self, client: TestClient):
        """
        Alice creates an only_me itinerary → Bob is blocked (403).
        Alice changes visibility to public → Bob can now view (200).
        """
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "only_me")

        assert fetch_itinerary(client, bob["access_token"], itinerary["id"]).status_code == 403

        update_visibility(client, alice["access_token"], itinerary["id"], "public")

        assert fetch_itinerary(client, bob["access_token"], itinerary["id"]).status_code == 200

    def test_changing_to_restricted_requires_managing_allowlist(self, client: TestClient):
        """
        Alice creates a public itinerary → Bob can view (200).
        Alice changes to restricted → Bob (not in allowlist) gets 403.
        Alice adds Bob to allowlist → Bob can view again (200).
        """
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        itinerary = create_itinerary(client, alice["access_token"], "public")

        # Bob can view while public
        assert fetch_itinerary(client, bob["access_token"], itinerary["id"]).status_code == 200

        # Switch to restricted — Bob is not in the allowlist yet
        update_visibility(client, alice["access_token"], itinerary["id"], "restricted")
        assert fetch_itinerary(client, bob["access_token"], itinerary["id"]).status_code == 403

        # Alice adds Bob to the allowlist
        add_resp = add_to_allowlist(
            client, alice["access_token"], itinerary["id"], bob["user_id"]
        )
        assert add_resp.status_code == 201

        # Bob can view again
        assert fetch_itinerary(client, bob["access_token"], itinerary["id"]).status_code == 200


# ---------------------------------------------------------------------------
# Class: TestUserProfileItineraries
# ---------------------------------------------------------------------------

def _create_four_itineraries(client: TestClient, token: str) -> dict:
    """Create one itinerary per visibility level. Returns dict keyed by visibility."""
    return {
        v: create_itinerary(client, token, v, f"{v.title()} Trip")
        for v in ("public", "followers", "restricted", "only_me")
    }


class TestUserProfileItineraries:

    def test_owner_sees_all_own_itineraries(self, client: TestClient):
        """Alice fetches her own profile itineraries. All 4 are returned."""
        alice = register_user(client, "alice", "alice@test.com")
        _create_four_itineraries(client, alice["access_token"])

        resp = client.get(
            f"/users/{alice['user_id']}/itineraries",
            headers=auth_headers(alice["access_token"]),
        )

        assert resp.status_code == 200
        assert len(resp.json()) == 4

    def test_stranger_sees_only_public(self, client: TestClient):
        """Bob has no relationship with Alice. He sees only the public itinerary."""
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        _create_four_itineraries(client, alice["access_token"])

        resp = client.get(
            f"/users/{alice['user_id']}/itineraries",
            headers=auth_headers(bob["access_token"]),
        )

        assert resp.status_code == 200
        items = resp.json()
        assert len(items) == 1
        assert items[0]["visibility"] == "public"

    def test_accepted_follower_sees_public_and_followers(self, client: TestClient):
        """
        Bob follows Alice (accepted). He sees public + followers = 2 itineraries.
        """
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        _create_four_itineraries(client, alice["access_token"])

        setup_accepted_follow(client, bob["access_token"], alice["access_token"], alice["user_id"])

        resp = client.get(
            f"/users/{alice['user_id']}/itineraries",
            headers=auth_headers(bob["access_token"]),
        )

        assert resp.status_code == 200
        items = resp.json()
        assert len(items) == 2
        visibilities = {i["visibility"] for i in items}
        assert visibilities == {"public", "followers"}

    def test_pending_follower_sees_only_public(self, client: TestClient):
        """
        Bob sends a follow request that Alice has not accepted.
        Pending follow grants no extra visibility — only public is returned.
        """
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        _create_four_itineraries(client, alice["access_token"])

        make_private(client, alice["access_token"])
        resp = follow_user(client, bob["access_token"], alice["user_id"])
        assert resp.json()["status"] == "pending"

        resp = client.get(
            f"/users/{alice['user_id']}/itineraries",
            headers=auth_headers(bob["access_token"]),
        )

        assert resp.status_code == 200
        items = resp.json()
        assert len(items) == 1
        assert items[0]["visibility"] == "public"

    def test_restricted_user_sees_public_and_restricted(self, client: TestClient):
        """
        Alice adds Bob to the restricted allowlist only (Bob is not a follower).
        Bob sees public + restricted = 2.
        """
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        itineraries = _create_four_itineraries(client, alice["access_token"])

        add_resp = add_to_allowlist(
            client, alice["access_token"], itineraries["restricted"]["id"], bob["user_id"]
        )
        assert add_resp.status_code == 201

        resp = client.get(
            f"/users/{alice['user_id']}/itineraries",
            headers=auth_headers(bob["access_token"]),
        )

        assert resp.status_code == 200
        items = resp.json()
        assert len(items) == 2
        visibilities = {i["visibility"] for i in items}
        assert visibilities == {"public", "restricted"}

    def test_follower_and_restricted_sees_three(self, client: TestClient):
        """
        Bob follows Alice (accepted) AND is in the restricted allowlist.
        Bob sees public + followers + restricted = 3.
        """
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        itineraries = _create_four_itineraries(client, alice["access_token"])

        setup_accepted_follow(client, bob["access_token"], alice["access_token"], alice["user_id"])
        add_to_allowlist(
            client, alice["access_token"], itineraries["restricted"]["id"], bob["user_id"]
        )

        resp = client.get(
            f"/users/{alice['user_id']}/itineraries",
            headers=auth_headers(bob["access_token"]),
        )

        assert resp.status_code == 200
        items = resp.json()
        assert len(items) == 3
        visibilities = {i["visibility"] for i in items}
        assert visibilities == {"public", "followers", "restricted"}

    def test_empty_list_for_user_with_no_itineraries(self, client: TestClient):
        """Alice has no itineraries. Bob fetches and gets 200 with empty list."""
        alice = register_user(client, "alice", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")

        resp = client.get(
            f"/users/{alice['user_id']}/itineraries",
            headers=auth_headers(bob["access_token"]),
        )

        assert resp.status_code == 200
        assert resp.json() == []

    def test_nonexistent_user_returns_404(self, client: TestClient):
        """Fetching itineraries for a non-existent user returns 404."""
        alice = register_user(client, "alice", "alice@test.com")

        resp = client.get(
            "/users/00000000-0000-0000-0000-000000000000/itineraries",
            headers=auth_headers(alice["access_token"]),
        )

        assert resp.status_code == 404
