"""
tests/test_follows.py — Tests for the hybrid follow system.

This is the most important test file because the follow system is the
architectural heart of the entire application.

The key behaviors under test:

  PUBLIC accounts:
    - Following is instant (status = 'accepted')
    - Counters update immediately
    - No approval step

  PRIVATE accounts:
    - Following creates a pending request (status = 'pending')
    - Counters do NOT update until the request is accepted
    - The target must explicitly accept or reject

  Both:
    - Cannot follow yourself
    - Cannot send duplicate follow requests
    - Unfollow removes the connection and restores counters
    - Cancelling a pending request removes it without affecting counters
    - Privacy walls protect followers/following lists on private accounts
"""

import pytest
from fastapi.testclient import TestClient

from conftest import auth_headers, register_user


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_private(client, token):
    """Helper to quickly make an account private."""
    client.patch("/users/me", headers=auth_headers(token),
                 json={"is_private": True})


def follow(client, follower_token, target_id):
    """Helper to send a follow request and return the full response."""
    return client.post(
        f"/users/{target_id}/follow",
        headers=auth_headers(follower_token),
    )


def get_profile(client, token, user_id=None):
    """Helper to get a user's profile. If user_id is None, gets /users/me."""
    if user_id is None:
        return client.get("/users/me", headers=auth_headers(token)).json()
    return client.get(f"/users/{user_id}",
                      headers=auth_headers(token)).json()


# ---------------------------------------------------------------------------
# Public Follow Tests
# ---------------------------------------------------------------------------

class TestPublicFollow:

    def test_follow_public_user_is_immediately_accepted(self, client: TestClient):
        """
        The most fundamental test of the hybrid model:
        Following a public user must result in status='accepted' immediately,
        without any approval step.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")

        response = follow(client, alice["access_token"], bob["user_id"])

        assert response.status_code == 201
        assert response.json()["status"] == "accepted"

    def test_follow_public_user_updates_counters_immediately(self, client: TestClient):
        """
        When Alice follows public Bob, BOTH counters must update immediately:
          - Alice's following_count goes from 0 to 1
          - Bob's followers_count goes from 0 to 1

        This validates the denormalized counter maintenance code.
        Counter integrity is critical — if counters drift from reality,
        the profile display will show wrong numbers.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")

        follow(client, alice["access_token"], bob["user_id"])

        alice_profile = get_profile(client, alice["access_token"])
        bob_profile = get_profile(client, bob["access_token"])

        assert alice_profile["following_count"] == 1
        assert bob_profile["followers_count"] == 1

    def test_cannot_follow_yourself(self, client: TestClient):
        """
        Attempting to follow yourself should return 400 Bad Request.
        This is enforced both at the API level (clear error message) and
        at the database level (CHECK constraint). We test the API level here.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        response = follow(client, alice["access_token"], alice["user_id"])
        assert response.status_code == 400

    def test_cannot_follow_same_user_twice(self, client: TestClient):
        """
        Sending a duplicate follow request should return 409 Conflict.
        The UNIQUE constraint in the database also enforces this, but
        the API should catch it first and return a clear error.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")

        follow(client, alice["access_token"], bob["user_id"])

        # Second follow attempt — must be rejected
        response = follow(client, alice["access_token"], bob["user_id"])
        assert response.status_code == 409

    def test_unfollow_removes_connection_and_restores_counters(self,
                                                                client: TestClient):
        """
        Unfollowing must:
          1. Delete the Follow record from the database
          2. Decrement Alice's following_count back to 0
          3. Decrement Bob's followers_count back to 0

        Counter integrity on unfollow is as important as on follow.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")

        # Follow first
        follow(client, alice["access_token"], bob["user_id"])

        # Then unfollow
        response = client.delete(
            f"/users/{bob['user_id']}/follow",
            headers=auth_headers(alice["access_token"]),
        )
        assert response.status_code == 204

        # Both counters must be back to 0
        assert get_profile(client, alice["access_token"])["following_count"] == 0
        assert get_profile(client, bob["access_token"])["followers_count"] == 0

    def test_unfollow_nonexistent_returns_404(self, client: TestClient):
        """
        Trying to unfollow someone you don't follow should return 404,
        not silently succeed or crash.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")

        response = client.delete(
            f"/users/{bob['user_id']}/follow",
            headers=auth_headers(alice["access_token"]),
        )
        assert response.status_code == 404

    def test_get_followers_list(self, client: TestClient):
        """
        GET /users/{id}/followers should list all accepted followers.
        Alice follows Bob, so Alice should appear in Bob's followers list.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")

        follow(client, alice["access_token"], bob["user_id"])

        response = client.get(
            f"/users/{bob['user_id']}/followers",
            headers=auth_headers(bob["access_token"]),
        )

        assert response.status_code == 200
        followers = response.json()
        assert len(followers) == 1
        assert followers[0]["username"] == "alice1"

    def test_get_following_list(self, client: TestClient):
        """
        GET /users/{id}/following should list all users this person follows.
        Alice follows Bob, so Bob should appear in Alice's following list.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")

        follow(client, alice["access_token"], bob["user_id"])

        response = client.get(
            f"/users/{alice['user_id']}/following",
            headers=auth_headers(alice["access_token"]),
        )

        assert response.status_code == 200
        following = response.json()
        assert len(following) == 1
        assert following[0]["username"] == "bob1"


# ---------------------------------------------------------------------------
# Private Follow Tests
# ---------------------------------------------------------------------------

class TestPrivateFollow:

    def test_follow_private_user_creates_pending_request(self, client: TestClient):
        """
        The other half of the hybrid model:
        Following a private user must result in status='pending'.
        The follow is NOT active until the target approves it.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        make_private(client, bob["access_token"])

        response = follow(client, alice["access_token"], bob["user_id"])

        assert response.status_code == 201
        assert response.json()["status"] == "pending"

    def test_pending_follow_does_not_update_counters(self, client: TestClient):
        """
        A pending follow request must NOT increment either counter.
        Counters only change when a follow is accepted.
        This is a subtle but important business rule.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        make_private(client, bob["access_token"])

        follow(client, alice["access_token"], bob["user_id"])

        # Neither counter should have moved
        assert get_profile(client, alice["access_token"])["following_count"] == 0
        assert get_profile(client, bob["access_token"])["followers_count"] == 0

    def test_cannot_send_duplicate_pending_request(self, client: TestClient):
        """
        Sending a second follow request while one is still pending
        should return 409, not create a duplicate record.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        make_private(client, bob["access_token"])

        follow(client, alice["access_token"], bob["user_id"])
        response = follow(client, alice["access_token"], bob["user_id"])

        assert response.status_code == 409

    def test_get_follow_requests_shows_pending_requests(self, client: TestClient):
        """
        GET /users/me/follow-requests should return pending requests
        received by the current user. Bob should see Alice's request.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        make_private(client, bob["access_token"])

        follow(client, alice["access_token"], bob["user_id"])

        response = client.get(
            "/users/me/follow-requests",
            headers=auth_headers(bob["access_token"]),
        )

        assert response.status_code == 200
        requests = response.json()
        assert len(requests) == 1
        assert requests[0]["username"] == "alice1"
        assert "follow_id" in requests[0]  # Needed to accept/reject

    def test_accept_follow_request_updates_status_and_counters(self,
                                                                 client: TestClient):
        """
        Accepting a follow request must:
          1. Change the follow status from 'pending' to 'accepted'
          2. Increment Alice's following_count from 0 to 1
          3. Increment Bob's followers_count from 0 to 1

        This is the most important state transition in the system.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        make_private(client, bob["access_token"])

        follow(client, alice["access_token"], bob["user_id"])

        # Bob gets the follow request
        requests = client.get(
            "/users/me/follow-requests",
            headers=auth_headers(bob["access_token"]),
        ).json()
        follow_id = requests[0]["follow_id"]

        # Bob accepts
        accept_response = client.post(
            f"/users/me/follow-requests/{follow_id}/accept",
            headers=auth_headers(bob["access_token"]),
        )

        assert accept_response.status_code == 200
        assert accept_response.json()["status"] == "accepted"

        # Now counters should have updated
        assert get_profile(client, alice["access_token"])["following_count"] == 1
        assert get_profile(client, bob["access_token"])["followers_count"] == 1

    def test_reject_follow_request_deletes_record(self, client: TestClient):
        """
        Rejecting a follow request must:
          1. Delete the Follow record entirely (not set status='rejected')
          2. Leave all counters unchanged
          3. Allow the requester to try again later (no blocking record)
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        make_private(client, bob["access_token"])

        follow(client, alice["access_token"], bob["user_id"])

        requests = client.get(
            "/users/me/follow-requests",
            headers=auth_headers(bob["access_token"]),
        ).json()
        follow_id = requests[0]["follow_id"]

        # Bob rejects
        reject_response = client.delete(
            f"/users/me/follow-requests/{follow_id}",
            headers=auth_headers(bob["access_token"]),
        )
        assert reject_response.status_code == 204

        # Counters should still be 0
        assert get_profile(client, alice["access_token"])["following_count"] == 0
        assert get_profile(client, bob["access_token"])["followers_count"] == 0

        # Follow requests list should now be empty
        new_requests = client.get(
            "/users/me/follow-requests",
            headers=auth_headers(bob["access_token"]),
        ).json()
        assert len(new_requests) == 0

    def test_cancel_pending_request_does_not_affect_counters(self,
                                                               client: TestClient):
        """
        Cancelling a pending request (DELETE /users/{id}/follow on a pending
        follow) should remove the record without touching any counters.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        make_private(client, bob["access_token"])

        follow(client, alice["access_token"], bob["user_id"])

        # Alice cancels the request
        response = client.delete(
            f"/users/{bob['user_id']}/follow",
            headers=auth_headers(alice["access_token"]),
        )
        assert response.status_code == 204

        # Counters must still be 0
        assert get_profile(client, alice["access_token"])["following_count"] == 0
        assert get_profile(client, bob["access_token"])["followers_count"] == 0

    def test_cannot_accept_someone_elses_follow_request(self, client: TestClient):
        """
        Security test: Charlie must not be able to accept a follow request
        that was sent to Bob. The accept endpoint must verify that
        following_id == current_user.id.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        charlie = register_user(client, "charlie1", "charlie@test.com")
        make_private(client, bob["access_token"])

        follow(client, alice["access_token"], bob["user_id"])

        requests = client.get(
            "/users/me/follow-requests",
            headers=auth_headers(bob["access_token"]),
        ).json()
        follow_id = requests[0]["follow_id"]

        # Charlie tries to accept Bob's follow request — should fail
        response = client.post(
            f"/users/me/follow-requests/{follow_id}/accept",
            headers=auth_headers(charlie["access_token"]),
        )
        assert response.status_code == 404  # Not found for Charlie


# ---------------------------------------------------------------------------
# Privacy Wall Tests
# ---------------------------------------------------------------------------

class TestPrivacyWall:

    def test_private_account_followers_hidden_from_non_followers(self,
                                                                   client: TestClient):
        """
        A non-follower should NOT be able to see a private account's
        followers list. This should return 403 Forbidden.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        charlie = register_user(client, "charlie1", "charlie@test.com")
        make_private(client, bob["access_token"])

        # Alice is an accepted follower of Bob
        follow(client, alice["access_token"], bob["user_id"])
        requests = client.get("/users/me/follow-requests",
                              headers=auth_headers(bob["access_token"])).json()
        client.post(f"/users/me/follow-requests/{requests[0]['follow_id']}/accept",
                    headers=auth_headers(bob["access_token"]))

        # Charlie is NOT a follower — should be blocked
        response = client.get(
            f"/users/{bob['user_id']}/followers",
            headers=auth_headers(charlie["access_token"]),
        )
        assert response.status_code == 403

    def test_private_account_followers_visible_to_accepted_followers(self,
                                                                        client: TestClient):
        """
        An accepted follower SHOULD be able to see the followers list
        of a private account they follow.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        make_private(client, bob["access_token"])

        follow(client, alice["access_token"], bob["user_id"])
        requests = client.get("/users/me/follow-requests",
                              headers=auth_headers(bob["access_token"])).json()
        client.post(f"/users/me/follow-requests/{requests[0]['follow_id']}/accept",
                    headers=auth_headers(bob["access_token"]))

        # Alice is accepted — she should see the list
        response = client.get(
            f"/users/{bob['user_id']}/followers",
            headers=auth_headers(alice["access_token"]),
        )
        assert response.status_code == 200

    def test_private_account_owner_can_see_own_followers_list(self,
                                                                client: TestClient):
        """
        The account owner should always be able to see their own followers list,
        even if the account is private.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")
        make_private(client, bob["access_token"])

        # Bob can see his own followers list
        response = client.get(
            f"/users/{bob['user_id']}/followers",
            headers=auth_headers(bob["access_token"]),
        )
        assert response.status_code == 200
