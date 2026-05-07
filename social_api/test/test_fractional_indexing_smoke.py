"""
test_fractional_indexing_smoke.py — Happy-path smoke test for the new
track + fractional-indexing stop system.

Tests:
  1. ordering.key_between basics
  2. Create itinerary → add stop (creates track 1) → add second stop in same
     track → add third stop in new track → verify GET structure
  3. Move second stop from track 1 to track 2 → verify track 1 still has one stop
  4. Delete last stop in track 1 → verify track 1 is deleted
  5. Verify ETag: 428 when missing, 412 when stale, 201 when correct
"""

import pytest
from fastapi.testclient import TestClient

from app.services.ordering import key_between, n_keys_between
from conftest import register_user, auth_headers


# ---------------------------------------------------------------------------
# Ordering unit tests
# ---------------------------------------------------------------------------

class TestOrdering:
    def test_both_none(self):
        k = key_between(None, None)
        assert isinstance(k, str) and len(k) > 0

    def test_after(self):
        k = key_between(None, None)
        k2 = key_between(k, None)
        assert k < k2

    def test_before(self):
        k = key_between(None, None)
        k0 = key_between(None, k)
        assert k0 < k

    def test_between(self):
        a = key_between(None, None)
        b = key_between(a, None)
        mid = key_between(a, b)
        assert a < mid < b

    def test_adjacent_digits(self):
        mid = key_between("a0", "a1")
        assert "a0" < mid < "a1"

    def test_repeated_bisection(self):
        prev = None
        keys = []
        for _ in range(10):
            k = key_between(prev, None)
            if prev:
                assert prev < k
            keys.append(k)
            prev = k

    def test_n_keys(self):
        ks = n_keys_between(None, None, 5)
        assert len(ks) == 5
        for i in range(len(ks) - 1):
            assert ks[i] < ks[i + 1]

    def test_n_keys_between_bounds(self):
        a = "a0"
        b = "z"
        ks = n_keys_between(a, b, 3)
        assert len(ks) == 3
        for k in ks:
            assert a < k < b
        for i in range(len(ks) - 1):
            assert ks[i] < ks[i + 1]

    def test_invalid_order_raises(self):
        with pytest.raises(ValueError):
            key_between("b", "a")


# ---------------------------------------------------------------------------
# API smoke test
# ---------------------------------------------------------------------------

class TestTrackAndStopSmoke:
    def _setup(self, client: TestClient):
        user = register_user(client, "alice", "alice@example.com")
        token = user["access_token"]
        hdrs = auth_headers(token)

        r = client.post("/itineraries/", json={
            "title": "Smoke Trip",
            "currency": "EUR",
        }, headers=hdrs)
        assert r.status_code == 201
        itin = r.json()
        return itin["id"], hdrs, itin["updated_at"]

    def test_full_smoke(self, client: TestClient):
        itin_id, hdrs, etag_val = self._setup(client)
        etag = f'"{etag_val}"'

        # --- Add stop 1 → creates track 1 ---
        r = client.post(
            f"/itineraries/{itin_id}/stops",
            json={"place_name": "Paris", "is_free": True},
            headers={**hdrs, "If-Match": etag},
        )
        assert r.status_code == 201, r.text
        stop1 = r.json()
        etag = r.headers["etag"]
        track1_id = stop1["track_id"]
        assert stop1["rank"] != ""

        # --- Add stop 2 in same track, after stop 1 ---
        r = client.post(
            f"/itineraries/{itin_id}/stops",
            json={
                "track_id": track1_id,
                "after_stop_id": stop1["id"],
                "place_name": "Lyon",
                "is_free": True,
            },
            headers={**hdrs, "If-Match": etag},
        )
        assert r.status_code == 201, r.text
        stop2 = r.json()
        etag = r.headers["etag"]
        assert stop2["track_id"] == track1_id
        assert stop2["rank"] > stop1["rank"]

        # --- Add stop 3 in NEW track (after track1) ---
        r = client.post(
            f"/itineraries/{itin_id}/stops",
            json={
                "track_id": None,
                "after_track_id": track1_id,
                "place_name": "Marseille",
                "is_free": True,
            },
            headers={**hdrs, "If-Match": etag},
        )
        assert r.status_code == 201, r.text
        stop3 = r.json()
        etag = r.headers["etag"]
        track2_id = stop3["track_id"]
        assert track2_id != track1_id

        # --- Verify GET structure ---
        r = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        assert r.status_code == 200
        data = r.json()
        assert "ETag" in r.headers or "etag" in r.headers
        tracks = data["tracks"]
        assert len(tracks) == 2
        track1_data = next(t for t in tracks if t["id"] == track1_id)
        track2_data = next(t for t in tracks if t["id"] == track2_id)
        assert len(track1_data["stops"]) == 2
        assert len(track2_data["stops"]) == 1
        assert track1_data["rank"] < track2_data["rank"]

        # --- Move stop2 from track1 to track2 ---
        r = client.patch(
            f"/itineraries/{itin_id}/stops/{stop2['id']}",
            json={"track_id": track2_id},
            headers={**hdrs, "If-Match": etag},
        )
        assert r.status_code == 200, r.text
        etag = r.headers["etag"]

        # --- Verify track1 now has 1 stop, track2 has 2 ---
        r = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        data = r.json()
        tracks = {t["id"]: t for t in data["tracks"]}
        assert len(tracks[track1_id]["stops"]) == 1
        assert len(tracks[track2_id]["stops"]) == 2

        # --- Delete stop1 (track1's last stop → track1 should be deleted) ---
        r = client.delete(
            f"/itineraries/{itin_id}/stops/{stop1['id']}",
            headers={**hdrs, "If-Match": etag},
        )
        assert r.status_code == 204, r.text
        etag = r.headers["etag"]

        r = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        data = r.json()
        remaining_track_ids = [t["id"] for t in data["tracks"]]
        assert track1_id not in remaining_track_ids, "Track 1 should be deleted"
        assert track2_id in remaining_track_ids

    def test_missing_if_match_returns_428(self, client: TestClient):
        itin_id, hdrs, _ = self._setup(client)
        r = client.post(
            f"/itineraries/{itin_id}/stops",
            json={"place_name": "Rome", "is_free": True},
            headers=hdrs,  # no If-Match
        )
        assert r.status_code == 428

    def test_stale_if_match_returns_412(self, client: TestClient):
        itin_id, hdrs, _ = self._setup(client)
        r = client.post(
            f"/itineraries/{itin_id}/stops",
            json={"place_name": "Rome", "is_free": True},
            headers={**hdrs, "If-Match": '"2000-01-01T00:00:00+00:00"'},
        )
        assert r.status_code == 412
