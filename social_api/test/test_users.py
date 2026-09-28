"""
tests/test_users.py — Tests for user profile endpoints.

Endpoints covered:
  GET  /users/me          — view your own profile
  PATCH /users/me         — update your own profile
  GET  /users/search      — search for users
  GET  /users/{user_id}   — view another user's public profile
"""

import pytest
from fastapi.testclient import TestClient

from conftest import auth_headers, register_user


class TestMyProfile:

    def test_get_my_profile(self, client: TestClient):
        """
        GET /users/me should return the authenticated user's full profile,
        including sensitive fields like email that are hidden from others.
        """
        data = register_user(client, "alice1", "alice@test.com",
                             display_name="Alice")
        token = data["access_token"]

        response = client.get("/users/me", headers=auth_headers(token))

        assert response.status_code == 200
        profile = response.json()

        # Core identity fields
        assert profile["username"] == "alice1"
        assert profile["display_name"] == "Alice"
        assert profile["email"] == "alice@test.com"  # Visible to owner only

        # New accounts start with zero connections
        assert profile["followers_count"] == 0
        assert profile["following_count"] == 0

        # New accounts default to private
        assert profile["is_private"] is True

    def test_update_profile_display_name(self, client: TestClient):
        """
        PATCH /users/me should update only the provided fields.
        This is a true partial update — other fields must remain unchanged.
        """
        data = register_user(client, "alice1", "alice@test.com",
                             display_name="Alice")
        token = data["access_token"]

        response = client.patch(
            "/users/me",
            headers=auth_headers(token),
            json={"display_name": "Alice Updated"},
        )

        assert response.status_code == 200
        assert response.json()["display_name"] == "Alice Updated"
        # Email must not have changed — we didn't update it
        assert response.json()["email"] == "alice@test.com"

    def test_update_profile_bio(self, client: TestClient):
        """Setting a bio should work independently of other fields."""
        data = register_user(client, "alice1", "alice@test.com")
        token = data["access_token"]

        response = client.patch(
            "/users/me",
            headers=auth_headers(token),
            json={"bio": "Software engineer based in Belgium."},
        )

        assert response.status_code == 200
        assert response.json()["bio"] == "Software engineer based in Belgium."

    def test_toggle_account_to_private(self, client: TestClient):
        """
        Setting is_private to True should make the account private.
        The response should reflect the change immediately.
        """
        data = register_user(client, "alice1", "alice@test.com")
        token = data["access_token"]

        response = client.patch(
            "/users/me",
            headers=auth_headers(token),
            json={"is_private": True},
        )

        assert response.status_code == 200
        assert response.json()["is_private"] is True

    def test_switch_to_public_auto_accepts_pending_requests(self, client: TestClient):
        """
        This tests one of the most important business rules:
        When a private user switches to public, ALL their pending follow
        requests should be automatically accepted.

        Flow:
          1. Alice goes private
          2. Bob sends a follow request (pending)
          3. Charlie sends a follow request (pending)
          4. Alice switches back to public
          5. Both Bob and Charlie should now be accepted followers
          6. Alice's followers_count should be 2
        """
        # Step 1: Alice registers and goes private
        alice = register_user(client, "alice1", "alice@test.com")
        alice_token = alice["access_token"]
        alice_id = alice["user_id"]

        client.patch("/users/me", headers=auth_headers(alice_token),
                     json={"is_private": True})

        # Step 2 & 3: Bob and Charlie send follow requests
        bob = register_user(client, "bob1", "bob@test.com")
        charlie = register_user(client, "charlie1", "charlie@test.com")

        bob_follow = client.post(
            f"/users/{alice_id}/follow",
            headers=auth_headers(bob["access_token"]),
        )
        charlie_follow = client.post(
            f"/users/{alice_id}/follow",
            headers=auth_headers(charlie["access_token"]),
        )
        assert bob_follow.json()["status"] == "pending"
        assert charlie_follow.json()["status"] == "pending"

        # Step 4: Alice switches to public
        client.patch("/users/me", headers=auth_headers(alice_token),
                     json={"is_private": False})

        # Step 5 & 6: Alice's followers_count should now be 2
        me_response = client.get("/users/me", headers=auth_headers(alice_token))
        assert me_response.json()["followers_count"] == 2
        assert me_response.json()["is_private"] is False


class TestExplicitNulls:
    """An explicit null on a NOT NULL column used to reach setattr and 500 at
    commit; omitting the key is how a client leaves a field alone."""

    def test_profile_flags(self, client: TestClient):
        user = register_user(client, "nullish", "nullish@example.com")
        hdrs = auth_headers(user["access_token"])
        for key in ("is_private", "notify_ratings", "notify_saves", "notify_follow_accepted"):
            r = client.patch("/users/me", json={key: None}, headers=hdrs)
            assert r.status_code == 422, (key, r.text)

    def test_itinerary_stop_and_leg_fields(self, client: TestClient):
        from conftest import edit_now
        user = register_user(client, "nullish2", "nullish2@example.com")
        hdrs = auth_headers(user["access_token"])
        itin = client.post("/itineraries/", json={"title": "Trip"}, headers=hdrs).json()["id"]
        for key in ("title", "currency", "visibility"):
            r = client.patch(f"/itineraries/{itin}", json={key: None},
                             headers=edit_now(client, itin, hdrs))
            assert r.status_code == 422, (key, r.text)

        a = client.post(f"/itineraries/{itin}/stops", json={"place_name": "A"},
                        headers=edit_now(client, itin, hdrs)).json()
        for key in ("cost", "is_free"):
            r = client.patch(f"/itineraries/{itin}/stops/{a['id']}", json={key: None},
                             headers=edit_now(client, itin, hdrs))
            assert r.status_code == 422, (key, r.text)

        b = client.post(f"/itineraries/{itin}/stops",
                        json={"place_name": "B", "after_track_id": a["track_id"]},
                        headers=edit_now(client, itin, hdrs)).json()
        seg = client.post(f"/itineraries/{itin}/segments",
                          json={"from_stop_id": a["id"], "to_stop_id": b["id"],
                                "legs": [{"position": 1, "mode": "metro"}]},
                          headers=edit_now(client, itin, hdrs)).json()
        leg = seg["legs"][0]["id"]
        for key in ("mode", "cost", "is_free"):
            r = client.patch(f"/itineraries/{itin}/segments/{seg['id']}/legs/{leg}",
                             json={key: None}, headers=edit_now(client, itin, hdrs))
            assert r.status_code == 422, (key, r.text)

    def test_waitlist_whatsapp_is_bounded(self, client: TestClient):
        # Past String(50) Postgres raises DataError — a 500 SQLite cannot show.
        r = client.post("/waitlist/join", json={"whatsapp": "1" * 51})
        assert r.status_code == 422
        r = client.post("/waitlist/join", json={"whatsapp": "+33 6 12 34 56 78"})
        assert r.status_code == 201


class TestSearchUsers:

    def test_search_by_username(self, client: TestClient):
        """Search should find users whose username contains the query string."""
        alice = register_user(client, "alice1", "alice@test.com")
        register_user(client, "bob1", "bob@test.com")

        response = client.get(
            "/users/search?q=bob",
            headers=auth_headers(alice["access_token"]),
        )

        assert response.status_code == 200
        results = response.json()
        assert len(results) == 1
        assert results[0]["username"] == "bob1"

    def test_search_treats_wildcards_literally(self, client: TestClient):
        """'_' is an ILIKE wildcard: q="_" matched every account."""
        alice = register_user(client, "alice1", "alice@test.com")
        register_user(client, "ab_cd", "abcd@test.com")
        register_user(client, "abxcd", "abxcd@test.com")
        hdrs = auth_headers(alice["access_token"])

        names = [u["username"] for u in client.get("/users/search?q=b_c", headers=hdrs).json()]
        assert names == ["ab_cd"]
        assert client.get("/users/search?q=%25", headers=hdrs).json() == []

    def test_search_excludes_current_user(self, client: TestClient):
        """
        Search results should never include the user making the request.
        It would be confusing to see yourself in search results.
        """
        alice = register_user(client, "alice1", "alice@test.com")

        # Searching for 'alice' as Alice should return no results
        response = client.get(
            "/users/search?q=alice",
            headers=auth_headers(alice["access_token"]),
        )

        assert response.status_code == 200
        assert len(response.json()) == 0

    def test_search_is_case_insensitive(self, client: TestClient):
        """Search should work regardless of case — 'ALICE' should find 'alice1'."""
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")

        response = client.get(
            "/users/search?q=ALICE",
            headers=auth_headers(bob["access_token"]),
        )

        assert response.status_code == 200
        results = response.json()
        assert len(results) == 1
        assert results[0]["username"] == "alice1"

    def test_search_returns_empty_for_no_match(self, client: TestClient):
        """A query that matches nobody should return an empty list, not an error."""
        alice = register_user(client, "alice1", "alice@test.com")

        response = client.get(
            "/users/search?q=zzznomatch",
            headers=auth_headers(alice["access_token"]),
        )

        assert response.status_code == 200
        assert response.json() == []


class TestViewUserProfile:

    def test_view_public_user_profile(self, client: TestClient):
        """
        Viewing a public user's profile should succeed and return
        the computed follow status fields (is_following, follow_is_pending).
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")

        response = client.get(
            f"/users/{bob['user_id']}",
            headers=auth_headers(alice["access_token"]),
        )

        assert response.status_code == 200
        profile = response.json()
        assert profile["username"] == "bob1"

        # Alice doesn't follow Bob yet
        assert profile["is_following"] is False
        assert profile["follow_is_pending"] is False

        # Email must NOT be visible when viewing someone else's profile
        assert "email" not in profile

    def test_view_profile_shows_following_status_after_follow(self, client: TestClient):
        """
        After Alice follows Bob, viewing Bob's profile should show
        is_following=True. This computed field is critical for the
        Flutter UI to render the correct button state.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")

        # Bob must be public so Alice's follow is auto-accepted
        client.patch("/users/me", headers=auth_headers(bob["access_token"]),
                     json={"is_private": False})

        # Alice follows Bob
        client.post(f"/users/{bob['user_id']}/follow",
                    headers=auth_headers(alice["access_token"]))

        # Now view Bob's profile as Alice
        response = client.get(
            f"/users/{bob['user_id']}",
            headers=auth_headers(alice["access_token"]),
        )

        assert response.json()["is_following"] is True
        assert response.json()["follow_is_pending"] is False

    def test_view_profile_shows_pending_status(self, client: TestClient):
        """
        After Alice sends a follow request to private Bob, viewing Bob's profile
        should show follow_is_pending=True and is_following=False.
        """
        alice = register_user(client, "alice1", "alice@test.com")
        bob = register_user(client, "bob1", "bob@test.com")

        # Bob goes private
        client.patch("/users/me", headers=auth_headers(bob["access_token"]),
                     json={"is_private": True})

        # Alice sends a follow request
        client.post(f"/users/{bob['user_id']}/follow",
                    headers=auth_headers(alice["access_token"]))

        # View Bob's profile as Alice
        response = client.get(
            f"/users/{bob['user_id']}",
            headers=auth_headers(alice["access_token"]),
        )

        assert response.json()["is_following"] is False
        assert response.json()["follow_is_pending"] is True

    def test_view_nonexistent_user_returns_404(self, client: TestClient):
        """Requesting a profile for a UUID that doesn't exist should return 404."""
        alice = register_user(client, "alice1", "alice@test.com")
        fake_uuid = "00000000-0000-0000-0000-000000000000"

        response = client.get(
            f"/users/{fake_uuid}",
            headers=auth_headers(alice["access_token"]),
        )

        assert response.status_code == 404
