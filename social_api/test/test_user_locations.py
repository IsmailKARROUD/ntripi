"""
test_user_locations.py — GET /users/{user_id}/locations tests.

Validates aggregation of stop coordinates across a user's itineraries and
verifies that per-itinerary visibility rules are honored — locations from
non-visible itineraries must never leak.
"""

import pytest
from fastapi.testclient import TestClient

from conftest import auth_headers, locked_headers, register_user


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _create_itinerary(client: TestClient, hdrs: dict, visibility: str = "public") -> dict:
    r = client.post(
        "/itineraries/",
        json={"title": f"Trip {visibility}", "visibility": visibility},
        headers=hdrs,
    )
    assert r.status_code == 201, r.text
    return r.json()


def _add_stop(client: TestClient, hdrs: dict, itin_id: str, etag: str,
              place_name: str, lat: float | None, lng: float | None,
              track_id: str | None = None,
              after_stop_id: str | None = None) -> tuple[dict, str]:
    body = {"place_name": place_name, "is_free": True}
    if lat is not None:
        body["lat"] = lat
    if lng is not None:
        body["lng"] = lng
    if track_id is not None:
        body["track_id"] = track_id
    if after_stop_id is not None:
        body["after_stop_id"] = after_stop_id

    r = client.post(
        f"/itineraries/{itin_id}/stops",
        json=body,
        headers=locked_headers(client, itin_id, hdrs, etag),
    )
    assert r.status_code == 201, r.text
    return r.json(), r.headers["etag"]


# ---------------------------------------------------------------------------
# Empty / 404
# ---------------------------------------------------------------------------

class TestEmptyAndNotFound:

    def test_user_with_no_itineraries_returns_empty(self, client: TestClient):
        alice = register_user(client, "alice_loc", "alice@example.com")
        hdrs = auth_headers(alice["access_token"])
        r = client.get(f"/users/{alice['user_id']}/locations", headers=hdrs)
        assert r.status_code == 200
        assert r.json() == {"locations": []}

    def test_unknown_user_id_returns_404(self, client: TestClient):
        alice = register_user(client, "alice_loc_u", "alice2@example.com")
        hdrs = auth_headers(alice["access_token"])
        bogus = "00000000-0000-0000-0000-000000000000"
        r = client.get(f"/users/{bogus}/locations", headers=hdrs)
        assert r.status_code == 404

    def test_bad_uuid_returns_422(self, client: TestClient):
        alice = register_user(client, "alice_loc_b", "alice3@example.com")
        hdrs = auth_headers(alice["access_token"])
        r = client.get("/users/not-a-uuid/locations", headers=hdrs)
        assert r.status_code == 422


# ---------------------------------------------------------------------------
# Owner sees their stops; NULL coords skipped
# ---------------------------------------------------------------------------

class TestOwnerLocations:

    def test_returns_stops_with_coords(self, client: TestClient):
        alice = register_user(client, "alice_own", "alice@example.com")
        hdrs = auth_headers(alice["access_token"])
        itin = _create_itinerary(client, hdrs, "only_me")

        stop1, etag = _add_stop(client, hdrs, itin["id"], itin["updated_at"],
                                "Paris", 48.8566, 2.3522)
        _add_stop(client, hdrs, itin["id"], etag,
                  "Lyon", 45.7640, 4.8357,
                  track_id=stop1["track_id"], after_stop_id=stop1["id"])

        r = client.get(f"/users/{alice['user_id']}/locations", headers=hdrs)
        assert r.status_code == 200
        locs = r.json()["locations"]
        assert len(locs) == 2
        names = {l["place_name"] for l in locs}
        assert names == {"Paris", "Lyon"}

    def test_stops_with_null_coords_skipped(self, client: TestClient):
        alice = register_user(client, "alice_own_n", "alice2@example.com")
        hdrs = auth_headers(alice["access_token"])
        itin = _create_itinerary(client, hdrs, "only_me")

        stop1, etag = _add_stop(client, hdrs, itin["id"], itin["updated_at"],
                                "WithCoords", 10.0, 20.0)
        # Add a stop with NO coords
        _add_stop(client, hdrs, itin["id"], etag,
                  "NoCoords", None, None,
                  track_id=stop1["track_id"], after_stop_id=stop1["id"])

        r = client.get(f"/users/{alice['user_id']}/locations", headers=hdrs)
        locs = r.json()["locations"]
        assert len(locs) == 1
        assert locs[0]["place_name"] == "WithCoords"


# ---------------------------------------------------------------------------
# Visibility — strangers see public, never see only_me
# ---------------------------------------------------------------------------

class TestVisibility:

    def test_stranger_sees_public_stops(self, client: TestClient):
        alice = register_user(client, "alice_pub", "alice@example.com")
        a_hdrs = auth_headers(alice["access_token"])
        itin = _create_itinerary(client, a_hdrs, "public")
        _add_stop(client, a_hdrs, itin["id"], itin["updated_at"],
                  "Berlin", 52.52, 13.405)

        bob = register_user(client, "bob_pub", "bob@example.com")
        b_hdrs = auth_headers(bob["access_token"])
        r = client.get(f"/users/{alice['user_id']}/locations", headers=b_hdrs)
        assert r.status_code == 200
        assert len(r.json()["locations"]) == 1

    def test_stranger_does_not_see_only_me_stops(self, client: TestClient):
        alice = register_user(client, "alice_priv", "alice@example.com")
        a_hdrs = auth_headers(alice["access_token"])
        itin = _create_itinerary(client, a_hdrs, "only_me")
        _add_stop(client, a_hdrs, itin["id"], itin["updated_at"],
                  "Madrid", 40.4168, -3.7038)

        bob = register_user(client, "bob_priv", "bob@example.com")
        b_hdrs = auth_headers(bob["access_token"])
        r = client.get(f"/users/{alice['user_id']}/locations", headers=b_hdrs)
        assert r.status_code == 200
        assert r.json()["locations"] == []

    def test_mixed_visibility_only_returns_visible(self, client: TestClient):
        alice = register_user(client, "alice_mix", "alice@example.com")
        a_hdrs = auth_headers(alice["access_token"])

        pub = _create_itinerary(client, a_hdrs, "public")
        _add_stop(client, a_hdrs, pub["id"], pub["updated_at"],
                  "Rome", 41.9028, 12.4964)

        priv = _create_itinerary(client, a_hdrs, "only_me")
        _add_stop(client, a_hdrs, priv["id"], priv["updated_at"],
                  "Tokyo", 35.6762, 139.6503)

        # Owner sees both
        r_owner = client.get(f"/users/{alice['user_id']}/locations", headers=a_hdrs)
        assert len(r_owner.json()["locations"]) == 2

        # Stranger sees only the public one
        bob = register_user(client, "bob_mix", "bob@example.com")
        b_hdrs = auth_headers(bob["access_token"])
        r_stranger = client.get(f"/users/{alice['user_id']}/locations", headers=b_hdrs)
        assert len(r_stranger.json()["locations"]) == 1
        assert r_stranger.json()["locations"][0]["place_name"] == "Rome"
