"""
test_feed_smoke.py — Smoke tests for the public discovery feed
(GET /itineraries/feed): visibility filtering, Top min-rating threshold,
owner attribution, pagination, and auth gating.
"""

from fastapi.testclient import TestClient

from conftest import register_user, auth_headers


def _create_itinerary(client: TestClient, token: str, title: str,
                      visibility: str) -> str:
    r = client.post(
        "/itineraries/",
        json={"title": title, "currency": "EUR", "visibility": visibility},
        headers=auth_headers(token),
    )
    assert r.status_code == 201, r.json()
    return r.json()["id"]


class TestFeed:
    def test_recent_returns_public_only_with_owner(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com",
                              display_name="Alice")
        pub_id = _create_itinerary(client, alice["access_token"],
                                   "Public Trip", "public")
        _create_itinerary(client, alice["access_token"], "Secret", "only_me")

        bobby = register_user(client, "bobby", "bobby@example.com")
        r = client.get("/itineraries/feed?sort=recent",
                       headers=auth_headers(bobby["access_token"]))
        assert r.status_code == 200, r.json()
        items = r.json()

        # only public surfaces — the only_me trip must never leak
        assert all(i["visibility"] == "public" for i in items)
        pub = next(i for i in items if i["id"] == pub_id)
        # owner attribution is present and correct
        assert pub["owner"]["username"] == "alice"
        assert pub["owner"]["display_name"] == "Alice"
        # feed-card fields exist
        for key in ("stops_count", "rating_avg", "rating_count", "cover_image_url"):
            assert key in pub

    def test_top_excludes_itineraries_below_min_ratings(self, client: TestClient):
        carol = register_user(client, "carol", "carol@example.com")
        pub_id = _create_itinerary(client, carol["access_token"],
                                   "Unrated", "public")
        # 0 ratings < default threshold of 3 → excluded from Top
        r = client.get("/itineraries/feed?sort=top",
                       headers=auth_headers(carol["access_token"]))
        assert r.status_code == 200
        assert pub_id not in [i["id"] for i in r.json()]

    def test_top_includes_after_three_ratings(self, client: TestClient):
        dave = register_user(client, "dave", "dave@example.com")
        pub_id = _create_itinerary(client, dave["access_token"],
                                   "Rated Trip", "public")
        for i in range(3):
            rater = register_user(client, f"rater{i}", f"rater{i}@example.com")
            rr = client.post(
                f"/itineraries/{pub_id}/ratings",
                json={"stars": 5},
                headers=auth_headers(rater["access_token"]),
            )
            assert rr.status_code == 201, rr.json()

        r = client.get("/itineraries/feed?sort=top",
                       headers=auth_headers(dave["access_token"]))
        assert r.status_code == 200
        top = next(i for i in r.json() if i["id"] == pub_id)
        assert top["rating_count"] == 3
        assert abs(top["rating_avg"] - 5.0) < 0.01

    def test_pagination_limit(self, client: TestClient):
        erin = register_user(client, "erin", "erin@example.com")
        for n in range(3):
            _create_itinerary(client, erin["access_token"], f"Trip {n}", "public")
        r = client.get("/itineraries/feed?sort=recent&limit=2",
                       headers=auth_headers(erin["access_token"]))
        assert r.status_code == 200
        assert len(r.json()) == 2

    def test_requires_auth(self, client: TestClient):
        r = client.get("/itineraries/feed")
        assert r.status_code in (401, 403)
