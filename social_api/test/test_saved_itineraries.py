"""
test_saved_itineraries.py — Smoke tests for the save (bookmark) feature:
POST/DELETE /itineraries/{id}/save and GET /itineraries/saved. Covers
idempotency, ownership/visibility gating, saved_at ordering, visibility-flip
filtering, FK cascade on delete, and auth gating.
"""

import time

from fastapi.testclient import TestClient

from conftest import register_user, auth_headers


def _create_itinerary(client: TestClient, token: str, title: str,
                      visibility: str = "public") -> str:
    r = client.post(
        "/itineraries/",
        json={"title": title, "currency": "EUR", "visibility": visibility},
        headers=auth_headers(token),
    )
    assert r.status_code == 201, r.json()
    return r.json()["id"]


def _saved_ids(client: TestClient, token: str) -> list[str]:
    r = client.get("/itineraries/saved", headers=auth_headers(token))
    assert r.status_code == 200, r.json()
    return [i["id"] for i in r.json()]


class TestSaveItinerary:
    def test_save_then_appears_in_list(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        it_id = _create_itinerary(client, alice["access_token"], "Public Trip")

        bobby = register_user(client, "bobby", "bobby@example.com")
        r = client.post(f"/itineraries/{it_id}/save",
                        headers=auth_headers(bobby["access_token"]))
        assert r.status_code == 204, r.text

        saved = client.get("/itineraries/saved",
                           headers=auth_headers(bobby["access_token"])).json()
        assert [i["id"] for i in saved] == [it_id]
        # ItinerarySummary card fields are present
        card = saved[0]
        for key in ("id", "user_id", "title", "stops_count", "visibility"):
            assert key in card

    def test_duplicate_save_is_idempotent(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        it_id = _create_itinerary(client, alice["access_token"], "Public Trip")
        bobby = register_user(client, "bobby", "bobby@example.com")

        for _ in range(2):
            r = client.post(f"/itineraries/{it_id}/save",
                            headers=auth_headers(bobby["access_token"]))
            assert r.status_code == 204, r.text

        assert _saved_ids(client, bobby["access_token"]) == [it_id]

    def test_cannot_save_own_itinerary(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        it_id = _create_itinerary(client, alice["access_token"], "My Trip")

        r = client.post(f"/itineraries/{it_id}/save",
                        headers=auth_headers(alice["access_token"]))
        assert r.status_code == 400, r.text
        assert r.json()["code"] == "cannot_save_own_itinerary"

    def test_cannot_save_inaccessible_itinerary(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        it_id = _create_itinerary(client, alice["access_token"], "Secret",
                                  visibility="only_me")
        bobby = register_user(client, "bobby", "bobby@example.com")

        r = client.post(f"/itineraries/{it_id}/save",
                        headers=auth_headers(bobby["access_token"]))
        assert r.status_code == 403, r.text

    def test_save_missing_itinerary_returns_404(self, client: TestClient):
        bobby = register_user(client, "bobby", "bobby@example.com")
        # A well-formed but non-existent UUID.
        r = client.post("/itineraries/00000000-0000-0000-0000-000000000000/save",
                        headers=auth_headers(bobby["access_token"]))
        assert r.status_code == 404, r.text


class TestUnsaveItinerary:
    def test_unsave_removes_from_list(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        it_id = _create_itinerary(client, alice["access_token"], "Public Trip")
        bobby = register_user(client, "bobby", "bobby@example.com")

        client.post(f"/itineraries/{it_id}/save",
                    headers=auth_headers(bobby["access_token"]))
        r = client.delete(f"/itineraries/{it_id}/save",
                          headers=auth_headers(bobby["access_token"]))
        assert r.status_code == 204, r.text
        assert _saved_ids(client, bobby["access_token"]) == []

    def test_unsave_not_saved_is_idempotent(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        it_id = _create_itinerary(client, alice["access_token"], "Public Trip")
        bobby = register_user(client, "bobby", "bobby@example.com")

        # Never saved — unsave still succeeds (idempotent).
        r = client.delete(f"/itineraries/{it_id}/save",
                          headers=auth_headers(bobby["access_token"]))
        assert r.status_code == 204, r.text


class TestSavedListBehavior:
    def test_visibility_flip_hides_then_restores(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        it_id = _create_itinerary(client, alice["access_token"], "Public Trip")
        bobby = register_user(client, "bobby", "bobby@example.com")

        client.post(f"/itineraries/{it_id}/save",
                    headers=auth_headers(bobby["access_token"]))
        assert _saved_ids(client, bobby["access_token"]) == [it_id]

        # Owner makes it private — it must drop out of Bobby's saved list...
        client.patch(f"/itineraries/{it_id}", json={"visibility": "only_me"},
                     headers=auth_headers(alice["access_token"]))
        assert _saved_ids(client, bobby["access_token"]) == []

        # ...but the row is preserved: making it public again restores it.
        client.patch(f"/itineraries/{it_id}", json={"visibility": "public"},
                     headers=auth_headers(alice["access_token"]))
        assert _saved_ids(client, bobby["access_token"]) == [it_id]

    def test_delete_itinerary_cascades_saved_row(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        it_id = _create_itinerary(client, alice["access_token"], "Public Trip")
        bobby = register_user(client, "bobby", "bobby@example.com")

        client.post(f"/itineraries/{it_id}/save",
                    headers=auth_headers(bobby["access_token"]))
        client.delete(f"/itineraries/{it_id}",
                      headers=auth_headers(alice["access_token"]))

        # FK CASCADE removes the saved row; list is empty and still 200.
        assert _saved_ids(client, bobby["access_token"]) == []

    def test_saved_list_orders_newest_first(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        first = _create_itinerary(client, alice["access_token"], "First")
        second = _create_itinerary(client, alice["access_token"], "Second")
        bobby = register_user(client, "bobby", "bobby@example.com")

        client.post(f"/itineraries/{first}/save",
                    headers=auth_headers(bobby["access_token"]))
        # SQLite CURRENT_TIMESTAMP has 1-second resolution — sleep so saved_at differs.
        time.sleep(1.1)
        client.post(f"/itineraries/{second}/save",
                    headers=auth_headers(bobby["access_token"]))

        assert _saved_ids(client, bobby["access_token"]) == [second, first]

    def test_saved_requires_auth(self, client: TestClient):
        # Also proves the literal /saved path is not swallowed by the
        # /{itinerary_id} UUID route (which would 422 on "saved").
        r = client.get("/itineraries/saved")
        assert r.status_code in (401, 403)
