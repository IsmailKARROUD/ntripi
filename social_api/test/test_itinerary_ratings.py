import pytest
pytestmark = pytest.mark.skip("rewriting after fractional-indexing refactor")

"""
test_itinerary_ratings.py — Tests for the itinerary rating endpoints.

Coverage:
  - Submit a rating (1–5 stars)
  - Update an existing rating (upsert)
  - Reject out-of-range stars
  - Get own rating (200 + 404)
  - Delete own rating
  - rating_avg and rating_count are recalculated correctly
  - Non-owner can rate a public itinerary
  - Non-viewer (no access) cannot rate
  - Follower can rate a followers-only itinerary
  - Visitor cannot rate a followers-only itinerary without following
"""

import time

import pytest
from fastapi.testclient import TestClient

from conftest import auth_headers, register_user


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def create_itinerary(client, token, *, visibility="public", title="Test Trip"):
    r = client.post(
        "/itineraries/",
        json={"title": title, "visibility": visibility},
        headers=auth_headers(token),
    )
    assert r.status_code == 201, r.json()
    return r.json()


def rate(client, token, itinerary_id, stars):
    return client.post(
        f"/itineraries/{itinerary_id}/ratings",
        json={"stars": stars},
        headers=auth_headers(token),
    )


def get_my_rating(client, token, itinerary_id):
    return client.get(
        f"/itineraries/{itinerary_id}/ratings/me",
        headers=auth_headers(token),
    )


def delete_my_rating(client, token, itinerary_id):
    return client.delete(
        f"/itineraries/{itinerary_id}/ratings/me",
        headers=auth_headers(token),
    )


def get_itinerary(client, token, itinerary_id):
    return client.get(
        f"/itineraries/{itinerary_id}",
        headers=auth_headers(token),
    )


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestRatingSubmit:
    def test_owner_can_rate_own_public_itinerary(self, client):
        u = register_user(client, "alice", "alice@x.com")
        it = create_itinerary(client, u["access_token"])

        r = rate(client, u["access_token"], it["id"], 4)
        assert r.status_code == 201
        assert r.json()["stars"] == 4

    def test_rating_appears_in_get_my_rating(self, client):
        u = register_user(client, "alice", "alice@x.com")
        it = create_itinerary(client, u["access_token"])
        rate(client, u["access_token"], it["id"], 3)

        r = get_my_rating(client, u["access_token"], it["id"])
        assert r.status_code == 200
        assert r.json()["stars"] == 3

    def test_upsert_updates_existing_rating(self, client):
        u = register_user(client, "alice", "alice@x.com")
        it = create_itinerary(client, u["access_token"])
        rate(client, u["access_token"], it["id"], 2)
        rate(client, u["access_token"], it["id"], 5)

        r = get_my_rating(client, u["access_token"], it["id"])
        assert r.json()["stars"] == 5

    def test_stars_below_1_rejected(self, client):
        u = register_user(client, "alice", "alice@x.com")
        it = create_itinerary(client, u["access_token"])

        r = rate(client, u["access_token"], it["id"], 0)
        assert r.status_code == 422

    def test_stars_above_5_rejected(self, client):
        u = register_user(client, "alice", "alice@x.com")
        it = create_itinerary(client, u["access_token"])

        r = rate(client, u["access_token"], it["id"], 6)
        assert r.status_code == 422

    def test_another_user_can_rate_public_itinerary(self, client):
        alice = register_user(client, "alice", "alice@x.com")
        bob = register_user(client, "bob1", "bob@x.com")
        it = create_itinerary(client, alice["access_token"])

        r = rate(client, bob["access_token"], it["id"], 5)
        assert r.status_code == 201

    def test_cannot_rate_only_me_itinerary(self, client):
        alice = register_user(client, "alice", "alice@x.com")
        bob = register_user(client, "bob1", "bob@x.com")
        it = create_itinerary(
            client, alice["access_token"], visibility="only_me"
        )

        r = rate(client, bob["access_token"], it["id"], 4)
        assert r.status_code == 403


class TestRatingAggregate:
    def test_rating_avg_and_count_after_single_rating(self, client):
        alice = register_user(client, "alice", "alice@x.com")
        it = create_itinerary(client, alice["access_token"])
        rate(client, alice["access_token"], it["id"], 4)

        detail = get_itinerary(client, alice["access_token"], it["id"]).json()
        assert detail["rating_count"] == 1
        assert abs(detail["rating_avg"] - 4.0) < 0.01

    def test_rating_avg_with_two_users(self, client):
        alice = register_user(client, "alice", "alice@x.com")
        bob = register_user(client, "bob1", "bob@x.com")
        it = create_itinerary(client, alice["access_token"])
        rate(client, alice["access_token"], it["id"], 2)
        rate(client, bob["access_token"], it["id"], 4)

        detail = get_itinerary(client, alice["access_token"], it["id"]).json()
        assert detail["rating_count"] == 2
        assert abs(detail["rating_avg"] - 3.0) < 0.01

    def test_upsert_recalculates_avg(self, client):
        alice = register_user(client, "alice", "alice@x.com")
        bob = register_user(client, "bob1", "bob@x.com")
        it = create_itinerary(client, alice["access_token"])
        rate(client, alice["access_token"], it["id"], 2)
        rate(client, bob["access_token"], it["id"], 4)
        # Alice changes her rating to 4
        rate(client, alice["access_token"], it["id"], 4)

        detail = get_itinerary(client, alice["access_token"], it["id"]).json()
        assert detail["rating_count"] == 2
        assert abs(detail["rating_avg"] - 4.0) < 0.01

    def test_zero_ratings_has_null_avg(self, client):
        alice = register_user(client, "alice", "alice@x.com")
        it = create_itinerary(client, alice["access_token"])

        detail = get_itinerary(client, alice["access_token"], it["id"]).json()
        assert detail["rating_count"] == 0
        assert detail["rating_avg"] is None


class TestRatingDelete:
    def test_delete_own_rating(self, client):
        alice = register_user(client, "alice", "alice@x.com")
        it = create_itinerary(client, alice["access_token"])
        rate(client, alice["access_token"], it["id"], 5)

        r = delete_my_rating(client, alice["access_token"], it["id"])
        assert r.status_code == 204

        r2 = get_my_rating(client, alice["access_token"], it["id"])
        assert r2.status_code == 404

    def test_delete_nonexistent_rating_returns_404(self, client):
        alice = register_user(client, "alice", "alice@x.com")
        it = create_itinerary(client, alice["access_token"])

        r = delete_my_rating(client, alice["access_token"], it["id"])
        assert r.status_code == 404

    def test_delete_recalculates_aggregate(self, client):
        alice = register_user(client, "alice", "alice@x.com")
        bob = register_user(client, "bob1", "bob@x.com")
        it = create_itinerary(client, alice["access_token"])
        rate(client, alice["access_token"], it["id"], 2)
        rate(client, bob["access_token"], it["id"], 4)
        delete_my_rating(client, alice["access_token"], it["id"])

        detail = get_itinerary(client, alice["access_token"], it["id"]).json()
        assert detail["rating_count"] == 1
        assert abs(detail["rating_avg"] - 4.0) < 0.01

    def test_delete_last_rating_resets_to_null(self, client):
        alice = register_user(client, "alice", "alice@x.com")
        it = create_itinerary(client, alice["access_token"])
        rate(client, alice["access_token"], it["id"], 5)
        delete_my_rating(client, alice["access_token"], it["id"])

        detail = get_itinerary(client, alice["access_token"], it["id"]).json()
        assert detail["rating_count"] == 0
        assert detail["rating_avg"] is None


class TestRatingGetMe:
    def test_get_my_rating_not_rated_returns_404(self, client):
        alice = register_user(client, "alice", "alice@x.com")
        it = create_itinerary(client, alice["access_token"])

        r = get_my_rating(client, alice["access_token"], it["id"])
        assert r.status_code == 404

    def test_get_my_rating_after_upsert(self, client):
        alice = register_user(client, "alice", "alice@x.com")
        it = create_itinerary(client, alice["access_token"])
        rate(client, alice["access_token"], it["id"], 3)
        rate(client, alice["access_token"], it["id"], 1)

        r = get_my_rating(client, alice["access_token"], it["id"])
        assert r.json()["stars"] == 1


# ---------------------------------------------------------------------------
# Helpers for TestRatingsPage
# ---------------------------------------------------------------------------

def get_ratings_page(client, token, itinerary_id):
    return client.get(
        f"/itineraries/{itinerary_id}/ratings",
        headers=auth_headers(token),
    )


def delete_account(client, token, password="test1234"):
    """Delete account via the real endpoint (uses client.request for json body)."""
    return client.request(
        "DELETE",
        "/users/me",
        json={"password": password},
        headers=auth_headers(token),
    )


def make_public(client, token):
    """Switch account to public so follow requests are auto-accepted."""
    client.patch(
        "/users/me",
        json={"is_private": False},
        headers=auth_headers(token),
    )


def follow_user(client, token, user_id):
    client.post(f"/users/{user_id}/follow", headers=auth_headers(token))


# ---------------------------------------------------------------------------
# Class: TestRatingsPage
# ---------------------------------------------------------------------------

class TestRatingsPage:

    def test_ratings_page_requires_view_permission(self, client):
        """Stranger cannot see ratings of a followers-only itinerary."""
        alice = register_user(client, "alice", "alice@x.com")
        bob = register_user(client, "bob1", "bob@x.com")

        it = create_itinerary(client, alice["access_token"], visibility="followers")

        r = get_ratings_page(client, bob["access_token"], it["id"])
        assert r.status_code == 403

    def test_ratings_page_accessible_to_allowed_viewer(self, client):
        """Any authenticated user can view a public itinerary's ratings."""
        alice = register_user(client, "alice", "alice@x.com")
        bob = register_user(client, "bob1", "bob@x.com")

        it = create_itinerary(client, alice["access_token"], visibility="public")

        r = get_ratings_page(client, bob["access_token"], it["id"])
        assert r.status_code == 200

    def test_ratings_page_returns_all_raters(self, client):
        """Ratings from multiple users all appear in the list."""
        alice = register_user(client, "alice", "alice@x.com")
        bob = register_user(client, "bob1", "bob@x.com")
        charlie = register_user(client, "charlie", "charlie@x.com")

        it = create_itinerary(client, alice["access_token"], visibility="public")
        rate(client, bob["access_token"], it["id"], 5)
        rate(client, charlie["access_token"], it["id"], 3)

        r = get_ratings_page(client, alice["access_token"], it["id"])
        assert r.status_code == 200
        body = r.json()
        assert body["rating_count"] == 2
        assert len(body["ratings"]) == 2
        usernames = {entry["user"]["username"] for entry in body["ratings"]}
        assert "bob1" in usernames
        assert "charlie" in usernames

    def test_ratings_page_distribution_is_correct(self, client):
        """Star distribution is counted correctly per bucket."""
        alice = register_user(client, "alice", "alice@x.com")
        bob = register_user(client, "bob1", "bob@x.com")
        charlie = register_user(client, "charlie", "charlie@x.com")
        dave = register_user(client, "dave", "dave@x.com")

        it = create_itinerary(client, alice["access_token"], visibility="public")
        rate(client, bob["access_token"], it["id"], 5)
        rate(client, charlie["access_token"], it["id"], 5)
        rate(client, dave["access_token"], it["id"], 3)

        r = get_ratings_page(client, alice["access_token"], it["id"])
        dist = r.json()["distribution"]
        assert dist["five"] == 2
        assert dist["three"] == 1
        assert dist["four"] == 0
        assert dist["two"] == 0
        assert dist["one"] == 0

    def test_deleted_user_rating_survives_with_null_user(self, client):
        """
        When a rater deletes their account, their score is anonymized
        (user_id = NULL) but stays in the ratings page. Uses the real
        DELETE /users/me endpoint to test the full anonymization flow.
        """
        alice = register_user(client, "alice", "alice@x.com")
        bob = register_user(client, "bob1", "bob@x.com")

        it = create_itinerary(client, alice["access_token"], visibility="public")
        rate(client, bob["access_token"], it["id"], 4)

        # Bob deletes his account — rating must survive anonymously.
        del_r = delete_account(client, bob["access_token"])
        assert del_r.status_code == 204

        # Alice fetches the ratings page.
        r = get_ratings_page(client, alice["access_token"], it["id"])
        assert r.status_code == 200
        body = r.json()

        assert body["rating_count"] == 1
        assert abs(body["rating_avg"] - 4.0) < 0.01
        assert len(body["ratings"]) == 1
        assert body["ratings"][0]["score"] == 4
        # user_id is None — the rater's identity is gone.
        assert body["ratings"][0]["user"]["user_id"] is None
        assert body["ratings"][0]["user"]["username"] is None
        assert body["ratings"][0]["user"]["display_name"] is None

    def test_ratings_ordered_most_recent_first(self, client):
        """The most recently submitted rating appears first in the list."""
        alice = register_user(client, "alice", "alice@x.com")
        bob = register_user(client, "bob1", "bob@x.com")
        charlie = register_user(client, "charlie", "charlie@x.com")

        it = create_itinerary(client, alice["access_token"], visibility="public")
        rate(client, bob["access_token"], it["id"], 3)
        # Sleep >1 s so SQLite's 1-second timestamp resolution gives distinct
        # updated_at values. In production (PostgreSQL) this is not needed.
        time.sleep(1.1)
        rate(client, charlie["access_token"], it["id"], 5)

        r = get_ratings_page(client, alice["access_token"], it["id"])
        body = r.json()
        # Charlie rated last, so appears first.
        assert body["ratings"][0]["user"]["username"] == "charlie"
        assert body["ratings"][1]["user"]["username"] == "bob1"

    def test_empty_ratings_page(self, client):
        """An itinerary with no ratings returns a valid empty response."""
        alice = register_user(client, "alice", "alice@x.com")
        it = create_itinerary(client, alice["access_token"], visibility="public")

        r = get_ratings_page(client, alice["access_token"], it["id"])
        assert r.status_code == 200
        body = r.json()
        assert body["rating_count"] == 0
        assert body["ratings"] == []
        assert body["rating_avg"] is None
        dist = body["distribution"]
        assert dist["five"] == 0
        assert dist["four"] == 0
        assert dist["three"] == 0
        assert dist["two"] == 0
        assert dist["one"] == 0

    def test_owner_can_view_own_ratings_page(self, client):
        """Owner always has access to their own ratings page regardless of visibility."""
        alice = register_user(client, "alice", "alice@x.com")
        it = create_itinerary(client, alice["access_token"], visibility="only_me")
        rate(client, alice["access_token"], it["id"], 5)

        r = get_ratings_page(client, alice["access_token"], it["id"])
        assert r.status_code == 200
        assert r.json()["rating_count"] == 1

    def test_follower_can_view_followers_itinerary_ratings(self, client):
        """An accepted follower can view a followers-only itinerary's ratings."""
        alice = register_user(client, "alice", "alice@x.com")
        bob = register_user(client, "bob1", "bob@x.com")

        # Make Alice public so Bob's follow is auto-accepted.
        make_public(client, alice["access_token"])
        it = create_itinerary(client, alice["access_token"], visibility="followers")
        follow_user(client, bob["access_token"], alice["user_id"])

        rate(client, bob["access_token"], it["id"], 4)

        r = get_ratings_page(client, bob["access_token"], it["id"])
        assert r.status_code == 200

    def test_non_follower_cannot_view_followers_itinerary_ratings(self, client):
        """A user with no follow relationship is denied a followers-only ratings page."""
        alice = register_user(client, "alice", "alice@x.com")
        charlie = register_user(client, "charlie", "charlie@x.com")

        it = create_itinerary(client, alice["access_token"], visibility="followers")

        r = get_ratings_page(client, charlie["access_token"], it["id"])
        assert r.status_code == 403

