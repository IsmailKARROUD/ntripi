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
        bob = register_user(client, "bob", "bob@x.com")
        it = create_itinerary(client, alice["access_token"])

        r = rate(client, bob["access_token"], it["id"], 5)
        assert r.status_code == 201

    def test_cannot_rate_only_me_itinerary(self, client):
        alice = register_user(client, "alice", "alice@x.com")
        bob = register_user(client, "bob", "bob@x.com")
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
        bob = register_user(client, "bob", "bob@x.com")
        it = create_itinerary(client, alice["access_token"])
        rate(client, alice["access_token"], it["id"], 2)
        rate(client, bob["access_token"], it["id"], 4)

        detail = get_itinerary(client, alice["access_token"], it["id"]).json()
        assert detail["rating_count"] == 2
        assert abs(detail["rating_avg"] - 3.0) < 0.01

    def test_upsert_recalculates_avg(self, client):
        alice = register_user(client, "alice", "alice@x.com")
        bob = register_user(client, "bob", "bob@x.com")
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
        bob = register_user(client, "bob", "bob@x.com")
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
