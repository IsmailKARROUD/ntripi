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

import uuid

import pytest
from fastapi.testclient import TestClient

from app.services.ordering import key_between, n_keys_between
from conftest import (
    auth_headers, concurrency_part, etag_from_updated_at, locked_headers,
    register_user,
)


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

    def test_tail_appends_never_saturate(self):
        """Past 'z' the old code returned a fixed "zV", so the 28th append to
        the end of a column collided with the 27th forever."""
        k = key_between(None, None)
        for _ in range(500):
            nxt = key_between(k, None)
            assert nxt > k
            k = nxt

    def test_head_prepends_stay_ordered(self):
        k = key_between(None, None)
        for _ in range(500):
            prev = key_between(None, k)
            assert prev < k
            k = prev

    def test_random_inserts_stay_strictly_ordered(self):
        import random
        rng = random.Random(7)
        keys = [key_between(None, None)]
        for _ in range(2000):
            j = rng.randrange(len(keys) + 1)
            lo = keys[j - 1] if j > 0 else None
            hi = keys[j] if j < len(keys) else None
            k = key_between(lo, hi)
            assert (lo is None or lo < k) and (hi is None or k < hi)
            keys.insert(j, k)
        assert keys == sorted(set(keys))

    def test_n_keys_after_a_maxed_digit(self):
        ks = n_keys_between("zV", None, 5)
        assert ks == sorted(set(ks))
        assert ks[0] > "zV"


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
        etag = etag_from_updated_at(etag_val)

        # --- Add stop 1 → creates track 1 ---
        r = client.post(
            f"/itineraries/{itin_id}/stops",
            json={"place_name": "Paris", "is_free": True},
            headers=locked_headers(client, itin_id, hdrs, etag),
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
            headers=locked_headers(client, itin_id, hdrs, etag),
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
            headers=locked_headers(client, itin_id, hdrs, etag),
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
            headers=locked_headers(client, itin_id, hdrs, etag),
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
            headers=locked_headers(client, itin_id, hdrs, etag),
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
            headers=locked_headers(client, itin_id, hdrs,
                                   '"2000-01-01T00:00:00+00:00"'),
        )
        assert r.status_code == 412

    def test_map_url_google_maps_link_accepted_and_returned(self, client: TestClient):
        itin_id, hdrs, etag_val = self._setup(client)
        etag = etag_from_updated_at(etag_val)
        link = "https://maps.app.goo.gl/abc123"
        r = client.post(
            f"/itineraries/{itin_id}/stops",
            json={"place_name": "Hidden gem", "map_url": link, "is_free": True},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 201, r.text
        assert r.json()["map_url"] == link  # round-trips through StopResponse

    def test_map_url_rejects_non_google_maps_link(self, client: TestClient):
        itin_id, hdrs, etag_val = self._setup(client)
        etag = etag_from_updated_at(etag_val)
        r = client.post(
            f"/itineraries/{itin_id}/stops",
            json={"place_name": "Nope", "map_url": "https://youtube.com/watch?v=x"},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 422, r.text


# ---------------------------------------------------------------------------
# Within-track reorder + rebalance defense
# ---------------------------------------------------------------------------

class TestReorderAndRebalance:
    """Cover the new use cases for the move endpoint and the >32-char defense."""

    def _three_stops(self, client: TestClient):
        """Create an itinerary with three stops in one track (A → B → C)."""
        user = register_user(client, "alice", "alice@example.com")
        hdrs = auth_headers(user["access_token"])
        r = client.post("/itineraries/", json={"title": "Trip", "currency": "EUR"},
                        headers=hdrs)
        itin = r.json()
        etag = etag_from_updated_at(itin["updated_at"])

        ids = []
        prev = None
        for name in ("A", "B", "C"):
            payload = {"place_name": name, "is_free": True}
            if ids:
                payload["track_id"] = track_id  # noqa: F821 — set after first iter
                payload["after_stop_id"] = prev
            r = client.post(f"/itineraries/{itin['id']}/stops",
                            json=payload,
                            headers=locked_headers(client, itin['id'], hdrs, etag))
            assert r.status_code == 201, r.text
            stop = r.json()
            ids.append(stop["id"])
            track_id = stop["track_id"]
            prev = stop["id"]
            etag = r.headers["etag"]

        return itin["id"], hdrs, etag, track_id, ids  # ids = [A, B, C]

    def test_reorder_within_track(self, client: TestClient):
        """PATCH with after/before stop IDs reorders within a track."""
        itin_id, hdrs, etag, track_id, ids = self._three_stops(client)
        a_id, b_id, c_id = ids

        # Move C between A and B → final order A < C < B.
        r = client.patch(
            f"/itineraries/{itin_id}/stops/{c_id}",
            json={"after_stop_id": a_id, "before_stop_id": b_id},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 200, r.text

        # Verify by ranks.
        r = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        track = next(t for t in r.json()["tracks"] if t["id"] == track_id)
        by_id = {s["id"]: s["rank"] for s in track["stops"]}
        assert by_id[a_id] < by_id[c_id] < by_id[b_id]
        # The track stops list is server-sorted by rank.
        assert [s["id"] for s in track["stops"]] == [a_id, c_id, b_id]

    def test_cross_track_move(self, client: TestClient):
        """PATCH with track_id moves a stop into a different track."""
        itin_id, hdrs, etag, track1_id, ids = self._three_stops(client)
        a_id, _, c_id = ids

        # Add a fourth stop in a brand-new track 2.
        r = client.post(
            f"/itineraries/{itin_id}/stops",
            json={"track_id": None, "after_track_id": track1_id,
                  "place_name": "D", "is_free": True},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 201, r.text
        d = r.json()
        track2_id = d["track_id"]
        etag = r.headers["etag"]

        # Move C from track1 into track2 (after D).
        r = client.patch(
            f"/itineraries/{itin_id}/stops/{c_id}",
            json={"track_id": track2_id, "after_stop_id": d["id"]},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 200, r.text

        r = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        tracks = {t["id"]: t for t in r.json()["tracks"]}
        assert [s["id"] for s in tracks[track1_id]["stops"]] == [a_id, ids[1]]
        assert [s["id"] for s in tracks[track2_id]["stops"]] == [d["id"], c_id]

    def test_rebalance_kicks_in_when_rank_would_exceed_max(
        self, client: TestClient,
    ):
        """If `_resolve_stop_rank` would produce >MAX_RANK_LENGTH chars the track
        gets renumbered transparently and the move still succeeds."""
        from app.services.ordering import MAX_RANK_LENGTH
        from app.models.stop import Stop
        from conftest import TestingSessionLocal
        import uuid as _uuid

        itin_id, hdrs, etag, track_id, ids = self._three_stops(client)
        a_id, b_id, c_id = ids

        # Force pathological adjacent ranks on A and B so any midpoint would
        # exceed MAX_RANK_LENGTH. Bisecting "0"*(L) and "0"*(L-1)+"1" gives a
        # key of length L+1 — picking L = MAX_RANK_LENGTH+1 guarantees overflow.
        long_len = MAX_RANK_LENGTH + 1
        rank_a = "0" * long_len
        rank_b = "0" * (long_len - 1) + "1"
        # Also put C above B so its rank stays valid relative to the new A/B.
        rank_c = "1"

        db = TestingSessionLocal()
        try:
            db.get(Stop, _uuid.UUID(a_id)).rank = rank_a
            db.get(Stop, _uuid.UUID(b_id)).rank = rank_b
            db.get(Stop, _uuid.UUID(c_id)).rank = rank_c
            db.commit()
        finally:
            db.close()

        # Refresh ETag — direct DB writes didn't bump it; reload the itinerary
        # so the next PATCH matches the current updated_at.
        r = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        etag = r.headers.get("etag") or r.headers["ETag"]

        # Trigger a move that lands between A and B → would require a >32-char
        # rank → must rebalance instead. Move C between A and B.
        r = client.patch(
            f"/itineraries/{itin_id}/stops/{c_id}",
            json={"after_stop_id": a_id, "before_stop_id": b_id},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 200, r.text

        # Every rank in the track should now be short again.
        r = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        track = next(t for t in r.json()["tracks"] if t["id"] == track_id)
        for s in track["stops"]:
            assert len(s["rank"]) <= MAX_RANK_LENGTH, \
                f"rank still long after rebalance: {s['rank']!r}"
        # Order preserved: A < C < B.
        assert [s["id"] for s in track["stops"]] == [a_id, c_id, b_id]


# ---------------------------------------------------------------------------
# POST /itineraries/{id}/reorder — batch reorder endpoint (Phase 2a)
# ---------------------------------------------------------------------------

class TestBatchReorder:
    """Cover the new POST /reorder endpoint for batch parallels reorder."""

    def _three_stops_one_track(self, client: TestClient):
        """Three stops A→B→C in a single track. Returns (itin_id, hdrs, etag,
        track_id, [a_id, b_id, c_id])."""
        user = register_user(client, "alice", "alice@example.com")
        hdrs = auth_headers(user["access_token"])
        r = client.post("/itineraries/", json={"title": "Trip", "currency": "EUR"},
                        headers=hdrs)
        itin = r.json()
        etag = etag_from_updated_at(itin["updated_at"])

        ids = []
        track_id = None
        prev = None
        for name in ("A", "B", "C"):
            payload = {"place_name": name, "is_free": True}
            if ids:
                payload["track_id"] = track_id
                payload["after_stop_id"] = prev
            r = client.post(f"/itineraries/{itin['id']}/stops",
                            json=payload,
                            headers=locked_headers(client, itin['id'], hdrs, etag))
            assert r.status_code == 201, r.text
            stop = r.json()
            ids.append(stop["id"])
            track_id = stop["track_id"]
            prev = stop["id"]
            etag = r.headers["etag"]

        return itin["id"], hdrs, etag, track_id, ids

    def test_reorder_happy_path(self, client: TestClient):
        """Reverse the stop order of one track via POST /reorder."""
        itin_id, hdrs, etag, track_id, ids = self._three_stops_one_track(client)
        a_id, b_id, c_id = ids

        # Reverse order: A, B, C → C, B, A.
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"stop_orders": {track_id: [c_id, b_id, a_id]}},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 200, r.text

        body = r.json()
        track = next(t for t in body["tracks"] if t["id"] == track_id)
        assert [s["id"] for s in track["stops"]] == [c_id, b_id, a_id]

        # Re-fetch — same answer.
        r = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        track = next(t for t in r.json()["tracks"] if t["id"] == track_id)
        assert [s["id"] for s in track["stops"]] == [c_id, b_id, a_id]

    def test_reorder_missing_if_match_returns_428(self, client: TestClient):
        itin_id, hdrs, _, track_id, ids = self._three_stops_one_track(client)
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"stop_orders": {track_id: ids[::-1]}},
            headers=hdrs,  # no If-Match
        )
        assert r.status_code == 428

    def test_reorder_stale_if_match_returns_412(self, client: TestClient):
        itin_id, hdrs, _, track_id, ids = self._three_stops_one_track(client)
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"stop_orders": {track_id: ids[::-1]}},
            headers=locked_headers(client, itin_id, hdrs,
                                   '"2000-01-01T00:00:00+00:00"'),
        )
        assert r.status_code == 412

    def test_reorder_non_owner_returns_403(self, client: TestClient):
        itin_id, owner_hdrs, etag, track_id, ids = self._three_stops_one_track(client)
        # Register a second user and try to reorder as them.
        other = register_user(client, "bobby", "bobby@example.com")
        other_hdrs = auth_headers(other["access_token"])
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"stop_orders": {track_id: ids[::-1]}},
            # No claim: a non-owner cannot obtain one, and the 403 is the point.
            headers={**other_hdrs, "If-Match": etag},
        )
        assert r.status_code == 403

    def test_reorder_stop_from_different_track_returns_422(self, client: TestClient):
        itin_id, hdrs, etag, track_id, ids = self._three_stops_one_track(client)
        a_id, b_id, c_id = ids

        # Add a stop in a brand-new track 2.
        r = client.post(
            f"/itineraries/{itin_id}/stops",
            json={"track_id": None, "after_track_id": track_id,
                  "place_name": "D", "is_free": True},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        d = r.json()
        etag = r.headers["etag"]

        # Include D in track 1's stop_orders → must 422 (D belongs to track 2).
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"stop_orders": {track_id: [a_id, b_id, c_id, d["id"]]}},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 422, r.text

    def test_reorder_missing_stop_returns_422(self, client: TestClient):
        itin_id, hdrs, etag, track_id, ids = self._three_stops_one_track(client)
        a_id, b_id, _ = ids
        # Only two of the three current stops — set mismatch.
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"stop_orders": {track_id: [a_id, b_id]}},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 422, r.text

    def test_reorder_duplicate_stop_returns_422(self, client: TestClient):
        itin_id, hdrs, etag, track_id, ids = self._three_stops_one_track(client)
        a_id, b_id, _ = ids
        # Three IDs, but one duplicate — count matches but is_set != current_set.
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"stop_orders": {track_id: [a_id, b_id, b_id]}},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 422, r.text

    def test_reorder_two_tracks_atomically(self, client: TestClient):
        """Single POST reorders parallels in two tracks at once."""
        itin_id, hdrs, etag, track1_id, ids = self._three_stops_one_track(client)
        a_id, b_id, c_id = ids

        # Add a second track with two parallel stops D, E.
        r = client.post(
            f"/itineraries/{itin_id}/stops",
            json={"track_id": None, "after_track_id": track1_id,
                  "place_name": "D", "is_free": True},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        d = r.json()
        etag = r.headers["etag"]
        track2_id = d["track_id"]

        r = client.post(
            f"/itineraries/{itin_id}/stops",
            json={"track_id": track2_id, "after_stop_id": d["id"],
                  "place_name": "E", "is_free": True},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        e = r.json()
        etag = r.headers["etag"]

        # One POST reorders BOTH tracks.
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"stop_orders": {
                track1_id: [c_id, a_id, b_id],
                track2_id: [e["id"], d["id"]],
            }},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 200, r.text

        body = r.json()
        tracks = {t["id"]: t for t in body["tracks"]}
        assert [s["id"] for s in tracks[track1_id]["stops"]] == [c_id, a_id, b_id]
        assert [s["id"] for s in tracks[track2_id]["stops"]] == [e["id"], d["id"]]


def _three_tracks(client: TestClient):
    """Three tracks, each with a single stop: A → B → C. Returns
    (itin_id, hdrs, etag, [track_a, track_b, track_c], [stop_a, stop_b, stop_c])."""
    user = register_user(client, "alice", "alice@example.com")
    hdrs = auth_headers(user["access_token"])
    r = client.post("/itineraries/", json={"title": "Trip", "currency": "EUR"},
                    headers=hdrs)
    itin = r.json()
    etag = etag_from_updated_at(itin["updated_at"])

    track_ids = []
    stop_ids = []
    prev_track = None
    for name in ("A", "B", "C"):
        payload = {"place_name": name, "is_free": True}
        if prev_track is not None:
            payload["after_track_id"] = prev_track
        r = client.post(f"/itineraries/{itin['id']}/stops",
                        json=payload,
                        headers=locked_headers(client, itin['id'], hdrs, etag))
        assert r.status_code == 201, r.text
        stop = r.json()
        track_ids.append(stop["track_id"])
        stop_ids.append(stop["id"])
        prev_track = stop["track_id"]
        etag = r.headers["etag"]

    return itin["id"], hdrs, etag, track_ids, stop_ids


# ---------------------------------------------------------------------------
# Track reorder + segment deletion via POST /reorder (Phase 2b)
# ---------------------------------------------------------------------------

class TestTrackReorder:
    """Cover the extended POST /reorder that also accepts track_order + segments_to_delete."""

    def test_track_order_reverse(self, client: TestClient):
        """Reverse the track order via POST /reorder with track_order."""
        itin_id, hdrs, etag, track_ids, stop_ids = _three_tracks(client)
        a_t, b_t, c_t = track_ids

        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"track_order": [c_t, b_t, a_t]},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 200, r.text

        # GET to confirm the server-sorted order matches.
        r = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        assert [t["id"] for t in r.json()["tracks"]] == [c_t, b_t, a_t]

    def test_track_order_with_segment_deletion(self, client: TestClient):
        """Combine track_order + segments_to_delete in one atomic call."""
        itin_id, hdrs, etag, track_ids, stop_ids = _three_tracks(client)
        a_t, b_t, c_t = track_ids
        a_s, b_s, c_s = stop_ids

        # Create a segment A→B (adjacent today). Segment writes go through the
        # same guard as stop writes now, so they carry both preconditions.
        r = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        etag = r.headers.get("etag") or r.headers["ETag"]
        r = client.post(
            f"/itineraries/{itin_id}/segments",
            json={
                "from_stop_id": a_s,
                "to_stop_id": b_s,
                "legs": [{"position": 1, "mode": "train"}],
            },
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 201, r.text
        seg_id = r.json()["id"]
        # ETag bumped by segment creation; reload.
        r = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        etag = r.headers.get("etag") or r.headers["ETag"]

        # Move B to the end → A→B is orphaned. Delete the segment in the same call.
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={
                "track_order": [a_t, c_t, b_t],
                "segments_to_delete": [seg_id],
            },
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 200, r.text

        body = r.json()
        assert [t["id"] for t in body["tracks"]] == [a_t, c_t, b_t]
        # Segment is gone.
        assert all(s["id"] != seg_id for s in body["segments"])

    def test_track_order_plus_stop_orders_atomic(self, client: TestClient):
        """track_order + stop_orders in the same call both apply."""
        itin_id, hdrs, etag, track_ids, stop_ids = _three_tracks(client)
        a_t, b_t, c_t = track_ids

        # Add a parallel to track B so we can reorder its stops.
        r = client.post(
            f"/itineraries/{itin_id}/stops",
            json={"track_id": b_t, "after_stop_id": stop_ids[1],
                  "place_name": "B2", "is_free": True},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 201, r.text
        b2_id = r.json()["id"]
        etag = r.headers["etag"]

        # Reverse track order AND reverse B's parallels.
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={
                "track_order": [c_t, b_t, a_t],
                "stop_orders": {b_t: [b2_id, stop_ids[1]]},
            },
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 200, r.text

        body = r.json()
        assert [t["id"] for t in body["tracks"]] == [c_t, b_t, a_t]
        b_track = next(t for t in body["tracks"] if t["id"] == b_t)
        assert [s["id"] for s in b_track["stops"]] == [b2_id, stop_ids[1]]

    def test_track_order_missing_track_returns_422(self, client: TestClient):
        itin_id, hdrs, etag, track_ids, _ = _three_tracks(client)
        a_t, b_t, _ = track_ids
        # Only two of three tracks listed.
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"track_order": [a_t, b_t]},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 422, r.text

    def test_track_order_duplicate_returns_422(self, client: TestClient):
        itin_id, hdrs, etag, track_ids, _ = _three_tracks(client)
        a_t, b_t, _ = track_ids
        # Duplicated id, count matches but set doesn't.
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"track_order": [a_t, b_t, b_t]},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 422, r.text

    def test_track_order_foreign_track_returns_422(self, client: TestClient):
        """A track id from another itinerary in track_order must fail."""
        itin_id, hdrs, etag, track_ids, _ = _three_tracks(client)
        a_t, b_t, c_t = track_ids

        # Create a second itinerary (same user) to get a track id from elsewhere.
        r = client.post("/itineraries/",
                        json={"title": "Trip 2", "currency": "EUR"},
                        headers=hdrs)
        other_itin_id = r.json()["id"]
        other_etag = etag_from_updated_at(r.json()["updated_at"])
        r = client.post(
            f"/itineraries/{other_itin_id}/stops",
            json={"place_name": "X", "is_free": True},
            headers=locked_headers(client, other_itin_id, hdrs, other_etag),
        )
        foreign_track_id = r.json()["track_id"]

        # Use the foreign id in place of c_t — same count, but mismatched set.
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"track_order": [a_t, b_t, foreign_track_id]},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 422, r.text

    def test_segments_to_delete_foreign_segment_returns_422(self, client: TestClient):
        import uuid as _uuid
        itin_id, hdrs, etag, _, _ = _three_tracks(client)
        # A random uuid that won't match any segment.
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"segments_to_delete": [str(_uuid.uuid4())]},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 422, r.text

    def test_empty_payload_returns_422(self, client: TestClient):
        itin_id, hdrs, etag, _, _ = _three_tracks(client)
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 422, r.text

    def test_phase_2a_payload_still_works(self, client: TestClient):
        """A request with only stop_orders (Phase 2a shape) still succeeds."""
        itin_id, hdrs, etag, track_ids, stop_ids = _three_tracks(client)
        a_t = track_ids[0]
        a_s = stop_ids[0]

        # Add a parallel so stop_orders has something to reorder.
        r = client.post(
            f"/itineraries/{itin_id}/stops",
            json={"track_id": a_t, "after_stop_id": a_s,
                  "place_name": "A2", "is_free": True},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        a2 = r.json()["id"]
        etag = r.headers["etag"]

        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"stop_orders": {a_t: [a2, a_s]}},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 200, r.text
        body = r.json()
        a_track = next(t for t in body["tracks"] if t["id"] == a_t)
        assert [s["id"] for s in a_track["stops"]] == [a2, a_s]


# ---------------------------------------------------------------------------
# A whole new layout via POST /reorder — the app's arrange mode
# ---------------------------------------------------------------------------

def _add_parallel(client: TestClient, itin_id, hdrs, etag, track_id, after_stop_id, name):
    """A second stop in `track_id`. Returns (stop_id, etag)."""
    r = client.post(
        f"/itineraries/{itin_id}/stops",
        json={"track_id": track_id, "after_stop_id": after_stop_id,
              "place_name": name, "is_free": True},
        headers=locked_headers(client, itin_id, hdrs, etag),
    )
    assert r.status_code == 201, r.text
    return r.json()["id"], r.headers["etag"]


def _layout(*tracks):
    """(track_id or None, [stop_ids]) pairs → the request's `layout`."""
    return [{"track_id": t, "stop_ids": list(s)} for t, s in tracks]


def _shape(trip: dict) -> list[tuple[str, list[str]]]:
    return [(t["id"], [s["id"] for s in t["stops"]]) for t in trip["tracks"]]


class TestLayoutReorder:
    """`layout` saves everything arrange mode can do in one request."""

    def test_a_lone_stop_joins_another_track(self, client: TestClient):
        itin_id, hdrs, etag, (a_t, b_t, c_t), (a_s, b_s, c_s) = _three_tracks(client)

        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"layout": _layout((b_t, [b_s, a_s]), (c_t, [c_s]))},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )

        assert r.status_code == 200, r.text
        # A held nothing any more, so it went; its stop lives on as B's alternative.
        assert _shape(r.json()) == [(b_t, [b_s, a_s]), (c_t, [c_s])]
        moved = r.json()["tracks"][0]["stops"][1]
        assert (moved["place_name"], moved["track_id"]) == ("A", b_t)

    def test_an_alternative_gets_a_track_of_its_own_where_it_was_put(
            self, client: TestClient):
        itin_id, hdrs, etag, (a_t, b_t, c_t), (a_s, b_s, c_s) = _three_tracks(client)
        a2_s, etag = _add_parallel(client, itin_id, hdrs, etag, a_t, a_s, "A2")

        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"layout": _layout(
                (a_t, [a_s]), (None, [a2_s]), (b_t, [b_s]), (c_t, [c_s]))},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )

        assert r.status_code == 200, r.text
        shape = _shape(r.json())
        assert [stops for _, stops in shape] == [[a_s], [a2_s], [b_s], [c_s]]
        new_track = shape[1][0]
        assert new_track not in (a_t, b_t, c_t)

    def test_tracks_and_alternatives_reorder_together(self, client: TestClient):
        itin_id, hdrs, etag, (a_t, b_t, c_t), (a_s, b_s, c_s) = _three_tracks(client)
        a2_s, etag = _add_parallel(client, itin_id, hdrs, etag, a_t, a_s, "A2")

        r = client.post(
            f"/itineraries/{itin_id}/reorder?return=itinerary",
            json={"layout": _layout((c_t, [c_s]), (a_t, [a2_s, a_s]), (b_t, [b_s]))},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )

        assert r.status_code == 200, r.text
        after = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        assert r.json()["itinerary"] == after.json()
        assert _shape(after.json()) == [(c_t, [c_s]), (a_t, [a2_s, a_s]), (b_t, [b_s])]
        assert concurrency_part(r.headers["etag"]) == concurrency_part(after.headers["etag"])
        assert concurrency_part(r.headers["etag"]) != etag

    def test_a_layout_deletes_the_transport_it_breaks(self, client: TestClient):
        itin_id, hdrs, etag, (a_t, b_t, c_t), (a_s, b_s, c_s) = _three_tracks(client)
        r = client.post(
            f"/itineraries/{itin_id}/segments",
            json={"from_stop_id": a_s, "to_stop_id": b_s,
                  "legs": [{"position": 1, "mode": "train"}]},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 201, r.text
        seg_id = r.json()["id"]
        etag = client.get(f"/itineraries/{itin_id}", headers=hdrs).headers["etag"]

        # B before A: the A → B transport no longer runs forwards.
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"layout": _layout((b_t, [b_s]), (a_t, [a_s]), (c_t, [c_s])),
                  "segments_to_delete": [seg_id]},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )

        assert r.status_code == 200, r.text
        assert _shape(r.json()) == [(b_t, [b_s]), (a_t, [a_s]), (c_t, [c_s])]
        assert r.json()["segments"] == []

    @pytest.mark.parametrize("case", [
        "missing_stop", "duplicate_stop", "foreign_stop", "foreign_track",
        "duplicate_track", "empty_track", "with_track_order", "with_stop_orders",
    ])
    def test_a_refused_layout_writes_nothing(self, client: TestClient, case):
        itin_id, hdrs, etag, (a_t, b_t, c_t), (a_s, b_s, c_s) = _three_tracks(client)
        stranger = str(uuid.uuid4())
        whole = _layout((a_t, [a_s]), (b_t, [b_s]), (c_t, [c_s]))
        body = {
            "missing_stop": {"layout": _layout((a_t, [a_s, b_s]))},
            "duplicate_stop": {"layout": _layout((a_t, [a_s, b_s]), (c_t, [c_s, a_s]))},
            "foreign_stop": {"layout": whole + _layout((None, [stranger]))},
            "foreign_track": {"layout": _layout(
                (stranger, [a_s]), (b_t, [b_s]), (c_t, [c_s]))},
            "duplicate_track": {"layout": _layout((a_t, [a_s]), (a_t, [b_s]), (c_t, [c_s]))},
            "empty_track": {"layout": _layout((a_t, [a_s, b_s, c_s]), (None, []))},
            "with_track_order": {"layout": whole, "track_order": [a_t, b_t, c_t]},
            "with_stop_orders": {"layout": whole, "stop_orders": {a_t: [a_s]}},
        }[case]
        before = client.get(f"/itineraries/{itin_id}", headers=hdrs)

        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json=body,
            headers=locked_headers(client, itin_id, hdrs, etag),
        )

        assert r.status_code == 422, r.text
        after = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        assert after.json() == before.json()
        assert concurrency_part(after.headers["etag"]) == concurrency_part(before.headers["etag"])

    def test_a_loaded_track_does_not_take_its_moved_stop_with_it(
            self, client: TestClient):
        """Track.stops cascades delete-orphan: a collection loaded before the
        move would delete the stop together with the track it just left."""
        from sqlalchemy import select
        from sqlalchemy.orm import selectinload

        from app.models.stop import Stop
        from app.models.track import Track
        from app.routers.itineraries import _apply_layout, _validate_layout
        from app.schemas.itinerary import TrackLayout
        from conftest import TestingSessionLocal

        itin_id, _, _, (a_t, b_t, c_t), (a_s, b_s, c_s) = _three_tracks(client)
        trip = uuid.UUID(itin_id)
        db = TestingSessionLocal()
        try:
            # Held: the identity map is weak, and a dropped track is loaded afresh.
            loaded = db.execute(
                select(Track).options(selectinload(Track.stops))
                .where(Track.itinerary_id == trip)
            ).scalars().all()
            assert all("stops" in t.__dict__ for t in loaded)
            layout = [TrackLayout(track_id=b_t, stop_ids=[b_s, a_s]),
                      TrackLayout(track_id=c_t, stop_ids=[c_s])]
            tracks, stops = _validate_layout(trip, layout, db)
            _apply_layout(trip, layout, tracks, stops, db)
            db.commit()

            left = db.execute(
                select(Stop.track_id).where(Stop.id == uuid.UUID(a_s))
            ).scalar_one_or_none()
            assert left == uuid.UUID(b_t)
            assert db.execute(
                select(Track.id).where(Track.id == uuid.UUID(a_t))
            ).scalar_one_or_none() is None
        finally:
            db.close()


# ---------------------------------------------------------------------------
# PATCH /stops/{id} with new-track anchors — Phase 2c
# ---------------------------------------------------------------------------

class TestMoveToNewTrack:
    """Cover the extended PATCH /stops/{id} that creates a brand-new track
    when track_id is null and at least one of after_track_id/before_track_id
    is provided."""

    def _three_single_stop_tracks(self, client: TestClient):
        """Three tracks A, B, C, each with a single stop. Returns
        (itin_id, hdrs, etag, [t_a, t_b, t_c], [s_a, s_b, s_c])."""
        user = register_user(client, "alice", "alice@example.com")
        hdrs = auth_headers(user["access_token"])
        r = client.post("/itineraries/", json={"title": "Trip", "currency": "EUR"},
                        headers=hdrs)
        itin = r.json()
        etag = etag_from_updated_at(itin["updated_at"])

        track_ids = []
        stop_ids = []
        prev_track = None
        for name in ("A", "B", "C"):
            payload = {"place_name": name, "is_free": True}
            if prev_track is not None:
                payload["after_track_id"] = prev_track
            r = client.post(f"/itineraries/{itin['id']}/stops",
                            json=payload,
                            headers=locked_headers(client, itin['id'], hdrs, etag))
            assert r.status_code == 201, r.text
            stop = r.json()
            track_ids.append(stop["track_id"])
            stop_ids.append(stop["id"])
            prev_track = stop["track_id"]
            etag = r.headers["etag"]

        return itin["id"], hdrs, etag, track_ids, stop_ids

    def test_new_track_between_two_existing(self, client: TestClient):
        """Move C's stop to a new track between A and B. Source C is deleted."""
        itin_id, hdrs, etag, track_ids, stop_ids = self._three_single_stop_tracks(client)
        t_a, t_b, t_c = track_ids
        s_c = stop_ids[2]

        r = client.patch(
            f"/itineraries/{itin_id}/stops/{s_c}",
            json={"track_id": None,
                  "after_track_id": t_a,
                  "before_track_id": t_b},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 200, r.text
        new_track_id = r.json()["track_id"]
        # The new track is freshly created so its id differs from every original.
        assert new_track_id not in {t_a, t_b, t_c}

        r = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        order = [t["id"] for t in r.json()["tracks"]]
        # Original C track is deleted (was only this one stop).
        assert t_c not in order
        # Final order: A → NewTrack → B.
        assert order == [t_a, new_track_id, t_b]
        new_track = next(t for t in r.json()["tracks"] if t["id"] == new_track_id)
        assert [s["id"] for s in new_track["stops"]] == [s_c]

    def test_extract_parallel(self, client: TestClient):
        """Track with [X, Y, Z]; extract Y to a new track right after source."""
        user = register_user(client, "alice", "alice@example.com")
        hdrs = auth_headers(user["access_token"])
        r = client.post("/itineraries/", json={"title": "Trip", "currency": "EUR"},
                        headers=hdrs)
        itin = r.json()
        etag = etag_from_updated_at(itin["updated_at"])

        # Track 1 with three parallels X, Y, Z.
        ids = []
        prev = None
        track_id = None
        for name in ("X", "Y", "Z"):
            payload = {"place_name": name, "is_free": True}
            if ids:
                payload["track_id"] = track_id
                payload["after_stop_id"] = prev
            r = client.post(f"/itineraries/{itin['id']}/stops",
                            json=payload,
                            headers=locked_headers(client, itin['id'], hdrs, etag))
            stop = r.json()
            ids.append(stop["id"])
            track_id = stop["track_id"]
            prev = stop["id"]
            etag = r.headers["etag"]

        x_id, y_id, z_id = ids

        # Extract Y: new track right after source track.
        r = client.patch(
            f"/itineraries/{itin['id']}/stops/{y_id}",
            json={"track_id": None, "after_track_id": track_id},
            headers=locked_headers(client, itin['id'], hdrs, etag),
        )
        assert r.status_code == 200, r.text
        new_track_id = r.json()["track_id"]
        assert new_track_id != track_id

        r = client.get(f"/itineraries/{itin['id']}", headers=hdrs)
        tracks = r.json()["tracks"]
        assert [t["id"] for t in tracks] == [track_id, new_track_id]
        # Source track keeps X and Z.
        source = next(t for t in tracks if t["id"] == track_id)
        assert {s["id"] for s in source["stops"]} == {x_id, z_id}
        # New track has only Y.
        new = next(t for t in tracks if t["id"] == new_track_id)
        assert [s["id"] for s in new["stops"]] == [y_id]

    def test_new_track_at_the_start(self, client: TestClient):
        """before_track_id only → new track at the head of the list."""
        itin_id, hdrs, etag, track_ids, stop_ids = self._three_single_stop_tracks(client)
        t_a, t_b, t_c = track_ids
        s_c = stop_ids[2]

        r = client.patch(
            f"/itineraries/{itin_id}/stops/{s_c}",
            json={"track_id": None, "before_track_id": t_a},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 200, r.text
        new_track_id = r.json()["track_id"]

        r = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        order = [t["id"] for t in r.json()["tracks"]]
        assert order[0] == new_track_id
        assert t_c not in order  # source deleted

    def test_new_track_at_the_end(self, client: TestClient):
        """after_track_id of the last existing track → new track at the tail."""
        itin_id, hdrs, etag, track_ids, stop_ids = self._three_single_stop_tracks(client)
        t_a, t_b, t_c = track_ids
        s_a = stop_ids[0]

        r = client.patch(
            f"/itineraries/{itin_id}/stops/{s_a}",
            json={"track_id": None, "after_track_id": t_c},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 200, r.text
        new_track_id = r.json()["track_id"]

        r = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        order = [t["id"] for t in r.json()["tracks"]]
        # Original A track is deleted (had only one stop).
        assert t_a not in order
        assert order[-1] == new_track_id

    def test_source_track_deleted_when_empties(self, client: TestClient):
        """Move A's only stop to a new track between B and C → source A deleted."""
        itin_id, hdrs, etag, track_ids, stop_ids = self._three_single_stop_tracks(client)
        t_a, t_b, t_c = track_ids
        s_a = stop_ids[0]

        r = client.patch(
            f"/itineraries/{itin_id}/stops/{s_a}",
            json={"track_id": None,
                  "after_track_id": t_b,
                  "before_track_id": t_c},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 200, r.text
        new_track_id = r.json()["track_id"]

        r = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        order = [t["id"] for t in r.json()["tracks"]]
        assert t_a not in order
        assert order == [t_b, new_track_id, t_c]

    def test_conflicting_anchors_with_track_id_returns_422(self, client: TestClient):
        """Sending both track_id and new-track anchors is ambiguous → 422."""
        itin_id, hdrs, etag, track_ids, stop_ids = self._three_single_stop_tracks(client)
        t_a, t_b, _ = track_ids
        s_c = stop_ids[2]

        r = client.patch(
            f"/itineraries/{itin_id}/stops/{s_c}",
            json={"track_id": str(t_a), "after_track_id": str(t_b)},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        # Pydantic validator → 422 with a clear message.
        assert r.status_code == 422, r.text

    def test_foreign_anchor_track_id_returns_422(self, client: TestClient):
        """after_track_id referencing a different itinerary's track → 422."""
        itin_id, hdrs, etag, track_ids, stop_ids = self._three_single_stop_tracks(client)
        s_c = stop_ids[2]

        # Second itinerary owned by the same user.
        r = client.post("/itineraries/",
                        json={"title": "Trip 2", "currency": "EUR"},
                        headers=hdrs)
        other_itin_id = r.json()["id"]
        other_etag = etag_from_updated_at(r.json()["updated_at"])
        r = client.post(
            f"/itineraries/{other_itin_id}/stops",
            json={"place_name": "X", "is_free": True},
            headers=locked_headers(client, other_itin_id, hdrs, other_etag),
        )
        foreign_track_id = r.json()["track_id"]

        r = client.patch(
            f"/itineraries/{itin_id}/stops/{s_c}",
            json={"track_id": None, "after_track_id": foreign_track_id},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 422, r.text

    def test_segment_remains_in_db_when_new_track_orphans_it(
        self, client: TestClient,
    ):
        """Backend does not auto-delete segments orphaned by a new-track move.
        Orphan cleanup is client-driven via the delete-then-move pattern in
        the move sheet (same convention as the Phase 1 cross-track move)."""
        itin_id, hdrs, etag, track_ids, stop_ids = self._three_single_stop_tracks(client)
        t_a, t_b, t_c = track_ids
        s_a, s_b, _ = stop_ids

        # Create segment A → B (currently adjacent).
        r = client.post(
            f"/itineraries/{itin_id}/segments",
            json={
                "from_stop_id": s_a,
                "to_stop_id": s_b,
                "legs": [{"position": 1, "mode": "train"}],
            },
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        seg_id = r.json()["id"]
        r = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        etag = r.headers.get("etag") or r.headers["ETag"]

        # Insert a new track between A and B → segment endpoints no longer adjacent.
        r = client.patch(
            f"/itineraries/{itin_id}/stops/{stop_ids[2]}",
            json={"track_id": None,
                  "after_track_id": t_a,
                  "before_track_id": t_b},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 200, r.text

        # Segment still exists in the DB — client is responsible for cleanup.
        r = client.get(f"/itineraries/{itin_id}", headers=hdrs)
        assert any(s["id"] == seg_id for s in r.json()["segments"])


# ---------------------------------------------------------------------------
# Rating moderation status on the ratings page.
#
# Lives here rather than in test_itinerary_ratings.py, which is skipped wholesale
# pending the fractional-indexing rewrite.
# ---------------------------------------------------------------------------

class TestRatingModerationStatusExposure:
    """The author of a hidden review needs to learn it is hidden — but nobody
    else may learn anything about anyone's moderation state."""

    def _setup(self, client: TestClient):
        """An itinerary owned by alice with one review by bob."""
        alice = register_user(client, "alice", "alice@example.com")
        r = client.post(
            "/itineraries/",
            json={"title": "Rated Trip", "currency": "EUR", "visibility": "public"},
            headers=auth_headers(alice["access_token"]),
        )
        assert r.status_code == 201, r.text
        itinerary_id = r.json()["id"]

        bob = register_user(client, "bobby", "bob@example.com")
        r = client.post(
            f"/itineraries/{itinerary_id}/ratings",
            json={"stars": 1, "note": "harsh"},
            headers=auth_headers(bob["access_token"]),
        )
        assert r.status_code in (200, 201), r.text
        return alice, bob, itinerary_id

    def _set_status(self, status: str) -> None:
        from app.models.itinerary_rating import ItineraryRating
        from conftest import TestingSessionLocal

        db = TestingSessionLocal()
        try:
            db.query(ItineraryRating).one().moderation_status = status
            db.commit()
        finally:
            db.close()

    def _page(self, client: TestClient, token: str, itinerary_id: str):
        return client.get(
            f"/itineraries/{itinerary_id}/ratings", headers=auth_headers(token)
        )

    def test_author_sees_their_own_hidden_status(self, client: TestClient):
        _, bob, itinerary_id = self._setup(client)
        self._set_status("hidden")

        page = self._page(client, bob["access_token"], itinerary_id)
        assert page.status_code == 200, page.text
        ratings = page.json()["ratings"]
        assert len(ratings) == 1
        assert ratings[0]["moderation_status"] == "hidden"

    def test_other_viewers_never_see_the_hidden_review_at_all(self, client: TestClient):
        alice, _, itinerary_id = self._setup(client)
        self._set_status("hidden")

        page = self._page(client, alice["access_token"], itinerary_id)
        assert page.json()["ratings"] == []

    def test_internal_states_are_not_leaked_to_other_viewers(self, client: TestClient):
        """A 'flagged' review stays visible, so its status is the one that could
        actually leak — it must read 'approved' to everyone but its author."""
        alice, _, itinerary_id = self._setup(client)
        self._set_status("flagged")

        page = self._page(client, alice["access_token"], itinerary_id)
        assert page.json()["ratings"][0]["moderation_status"] == "approved"

    def test_new_fields_are_appended_in_order(self, client: TestClient):
        """Field order is JSON key order and part of the API contract — a new
        field has to be appended, never inserted. Each addition lands after the
        previous one: id, then moderation_status, then source_lang."""
        alice, _, itinerary_id = self._setup(client)

        page = self._page(client, alice["access_token"], itinerary_id)
        keys = list(page.json()["ratings"][0].keys())
        assert keys[-3:] == ["id", "moderation_status", "source_lang"]


# ---------------------------------------------------------------------------
# A rating is not an edit: it must not move the owner's If-Match ETag
# ---------------------------------------------------------------------------

class TestRatingDoesNotStaleTheEditor:
    """rating_count / rating_avg live on the itinerary row, whose updated_at IS
    the concurrency ETag. A stranger's rating landing while the owner has the
    editor open must not 412 the owner's next save."""

    @staticmethod
    def _backdate(itinerary_id: str) -> None:
        # SQLite's now() has one-second resolution, so without this a rating
        # in the same second as the create could not move updated_at at all.
        import uuid
        from datetime import datetime, timedelta, timezone
        from app.models.itinerary import Itinerary
        from conftest import TestingSessionLocal

        db = TestingSessionLocal()
        try:
            row = db.get(Itinerary, uuid.UUID(itinerary_id))
            row.updated_at = datetime.now(timezone.utc) - timedelta(minutes=5)
            db.commit()
        finally:
            db.close()

    def _setup(self, client: TestClient):
        owner = register_user(client, "owner", "owner@example.com")
        rater = register_user(client, "rater", "rater@example.com")
        created = client.post(
            "/itineraries/", json={"title": "Trip", "visibility": "public"},
            headers=auth_headers(owner["access_token"]),
        )
        assert created.status_code == 201, created.text
        itinerary_id = created.json()["id"]
        self._backdate(itinerary_id)
        etag = client.get(f"/itineraries/{itinerary_id}",
                          headers=auth_headers(owner["access_token"])).headers["etag"]
        return owner, rater, itinerary_id, etag

    def test_owner_can_still_save_after_a_stranger_rates(self, client: TestClient):
        owner, rater, itinerary_id, etag = self._setup(client)
        hdrs = locked_headers(client, itinerary_id,
                              auth_headers(owner["access_token"]), etag)

        rated = client.post(f"/itineraries/{itinerary_id}/ratings", json={"stars": 5},
                            headers=auth_headers(rater["access_token"]))
        assert rated.status_code == 201, rated.text

        saved = client.patch(f"/itineraries/{itinerary_id}", json={"title": "Renamed"},
                             headers=hdrs)
        assert saved.status_code == 200, saved.text

    def test_the_aggregate_still_updates(self, client: TestClient):
        owner, rater, itinerary_id, _ = self._setup(client)
        client.post(f"/itineraries/{itinerary_id}/ratings", json={"stars": 4},
                    headers=auth_headers(rater["access_token"]))

        detail = client.get(f"/itineraries/{itinerary_id}",
                            headers=auth_headers(owner["access_token"])).json()
        assert detail["rating_count"] == 1
        assert detail["rating_avg"] == 4.0

    def test_deleting_a_rating_does_not_stale_the_editor_either(self, client: TestClient):
        owner, rater, itinerary_id, _ = self._setup(client)
        client.post(f"/itineraries/{itinerary_id}/ratings", json={"stars": 4},
                    headers=auth_headers(rater["access_token"]))
        self._backdate(itinerary_id)
        etag = client.get(f"/itineraries/{itinerary_id}",
                          headers=auth_headers(owner["access_token"])).headers["etag"]
        hdrs = locked_headers(client, itinerary_id,
                              auth_headers(owner["access_token"]), etag)

        assert client.delete(f"/itineraries/{itinerary_id}/ratings/me",
                             headers=auth_headers(rater["access_token"])).status_code == 204

        saved = client.patch(f"/itineraries/{itinerary_id}", json={"title": "Renamed"},
                             headers=hdrs)
        assert saved.status_code == 200, saved.text


# ---------------------------------------------------------------------------
# API-only edges: an unanchored new track, and the last leg of a segment
# ---------------------------------------------------------------------------

class TestUnanchoredTrackAndLastLeg:

    def _itinerary(self, client: TestClient):
        user = register_user(client, "owner", "owner@example.com")
        hdrs = auth_headers(user["access_token"])
        r = client.post("/itineraries/", json={"title": "Trip"}, headers=hdrs)
        assert r.status_code == 201, r.text
        return hdrs, r.json()["id"]

    def _add_stop(self, client: TestClient, hdrs: dict, itinerary_id: str, name: str):
        from conftest import edit_now
        r = client.post(f"/itineraries/{itinerary_id}/stops",
                        json={"place_name": name},
                        headers=edit_now(client, itinerary_id, hdrs))
        assert r.status_code == 201, r.text
        return r.json()

    def test_a_new_track_without_anchors_is_appended(self, client: TestClient):
        """key_between(None, None) is a fixed midpoint — without the append
        fallback every second unanchored track answered 409 rank_collision."""
        hdrs, itinerary_id = self._itinerary(client)
        for name in ("A", "B", "C"):
            self._add_stop(client, hdrs, itinerary_id, name)

        detail = client.get(f"/itineraries/{itinerary_id}", headers=hdrs).json()
        names = [t["stops"][0]["place_name"] for t in detail["tracks"]]
        assert names == ["A", "B", "C"]

    def test_thirty_tail_appends_all_land_in_order(self, client: TestClient):
        """The 28th append used to answer 409 rank_collision on every retry."""
        from conftest import edit_now
        hdrs, itinerary_id = self._itinerary(client)
        last_track = None
        names = [f"S{i:02d}" for i in range(30)]
        for name in names:
            body = {"place_name": name}
            if last_track is not None:
                body["after_track_id"] = last_track
            r = client.post(f"/itineraries/{itinerary_id}/stops", json=body,
                            headers=edit_now(client, itinerary_id, hdrs))
            assert r.status_code == 201, r.text
            last_track = r.json()["track_id"]

        detail = client.get(f"/itineraries/{itinerary_id}", headers=hdrs).json()
        assert [t["stops"][0]["place_name"] for t in detail["tracks"]] == names

    def test_deleting_the_last_leg_deletes_its_segment(self, client: TestClient):
        from conftest import edit_now
        hdrs, itinerary_id = self._itinerary(client)
        a = self._add_stop(client, hdrs, itinerary_id, "A")
        b = self._add_stop(client, hdrs, itinerary_id, "B")
        seg = client.post(
            f"/itineraries/{itinerary_id}/segments",
            json={"from_stop_id": a["id"], "to_stop_id": b["id"],
                  "legs": [{"position": 1, "mode": "metro"}]},
            headers=edit_now(client, itinerary_id, hdrs),
        )
        assert seg.status_code == 201, seg.text
        segment = seg.json()

        r = client.delete(
            f"/itineraries/{itinerary_id}/segments/{segment['id']}/legs/{segment['legs'][0]['id']}",
            headers=edit_now(client, itinerary_id, hdrs),
        )
        assert r.status_code == 204, r.text

        listed = client.get(f"/itineraries/{itinerary_id}/segments", headers=hdrs)
        assert listed.json() == []


# ---------------------------------------------------------------------------
# Where a stop's location comes from (place_source, Google places, links)
# ---------------------------------------------------------------------------

class TestPlaceSource:
    """The only Google data a stop keeps is a place ID; services/stop_location
    holds every client to that, installed builds included."""

    PLACE_ID = "ChIJLU7jZClu5kcR4PcOOO6p3I0"

    def _trip(self, client: TestClient):
        user = register_user(client, "alice", "alice@example.com")
        hdrs = auth_headers(user["access_token"])
        r = client.post("/itineraries/", json={"title": "Places", "currency": "EUR"},
                        headers=hdrs)
        assert r.status_code == 201, r.text
        return r.json()["id"], hdrs

    def _add(self, client, itin_id, hdrs, body):
        from conftest import edit_now
        return client.post(f"/itineraries/{itin_id}/stops", json=body,
                           headers=edit_now(client, itin_id, hdrs))

    def _patch(self, client, itin_id, hdrs, stop_id, body):
        from conftest import edit_now
        return client.patch(f"/itineraries/{itin_id}/stops/{stop_id}", json=body,
                            headers=edit_now(client, itin_id, hdrs))

    def _row(self, stop_id):
        from conftest import TestingSessionLocal
        from app.models.stop import Stop
        db = TestingSessionLocal()
        try:
            return db.get(Stop, uuid.UUID(stop_id))
        finally:
            db.close()

    def test_a_google_place_keeps_only_its_id_and_the_search_text(self, client):
        itin_id, hdrs = self._trip(client)
        r = self._add(client, itin_id, hdrs, {
            "place_name": "Lunch", "place_source": "google",
            "google_place_id": self.PLACE_ID, "google_place_query": "chez marcel",
        })
        assert r.status_code == 201, r.text
        stop = r.json()
        assert stop["place_source"] == "google"
        assert stop["google_place_id"] == self.PLACE_ID
        assert stop["google_place_query"] == "chez marcel"
        assert stop["google_place_missing"] is False
        assert stop["lat"] is None and stop["lng"] is None
        assert stop["place_address"] is None and stop["map_url"] is None
        assert self._row(stop["id"]).google_place_checked_at is not None

    def test_the_new_keys_come_after_every_existing_one(self, client):
        itin_id, hdrs = self._trip(client)
        r = self._add(client, itin_id, hdrs, {"place_name": "Paris"})
        keys = list(r.json())
        assert keys[keys.index("source_lang") + 1:] == [
            "place_source", "google_place_id", "google_place_query",
            "google_place_missing",
        ]

    def test_a_link_never_keeps_coordinates_even_from_an_installed_build(self, client):
        # Installed builds unfurl the link and send what they found beside it.
        itin_id, hdrs = self._trip(client)
        r = self._add(client, itin_id, hdrs, {
            "place_name": "Gem", "map_url": "https://maps.app.goo.gl/abc123",
            "lat": 48.85, "lng": 2.35, "place_address": "Paris",
        })
        assert r.status_code == 201, r.text
        stop = r.json()
        assert stop["place_source"] == "link"
        assert (stop["lat"], stop["lng"], stop["place_address"]) == (None, None, None)
        assert stop["google_place_id"] is None

    def test_a_place_id_written_in_a_link_is_kept(self, client):
        itin_id, hdrs = self._trip(client)
        link = ("https://www.google.com/maps/search/?api=1&query=Eiffel"
                f"&query_place_id={self.PLACE_ID}")
        r = self._add(client, itin_id, hdrs, {
            "place_name": "Tower", "place_source": "link", "map_url": link,
        })
        assert r.status_code == 201, r.text
        assert r.json()["google_place_id"] == self.PLACE_ID
        assert r.json()["place_source"] == "link"

    def test_the_hex_feature_id_of_a_long_link_is_not_a_place_id(self, client):
        itin_id, hdrs = self._trip(client)
        link = ("https://www.google.com/maps/place/Eiffel+Tower/@48.858,2.294,17z/"
                "data=!4m6!3m5!1s0x47e66e2964e34e2d:0x8ddca9ee380ef7e0!8m2"
                "!3d48.8583701!4d2.2944813")
        r = self._add(client, itin_id, hdrs, {"place_name": "Tower", "map_url": link})
        assert r.status_code == 201, r.text
        assert r.json()["google_place_id"] is None
        assert r.json()["lat"] is None

    @pytest.mark.parametrize("body", [
        # Google fields without saying it is a Google place.
        {"google_place_id": "ChIJLU7jZClu5kcR4PcOOO6p3I0", "google_place_query": "x"},
        # A Google place needs both halves.
        {"place_source": "google", "google_place_id": "ChIJLU7jZClu5kcR4PcOOO6p3I0"},
        # ... and nothing else that locates it.
        {"place_source": "google", "google_place_id": "ChIJLU7jZClu5kcR4PcOOO6p3I0",
         "google_place_query": "x", "lat": 1.0, "lng": 2.0},
        {"place_source": "link"},
        {"place_source": "link", "map_url": "https://maps.app.goo.gl/x", "lat": 1.0},
        {"place_source": "osm", "map_url": "https://maps.app.goo.gl/x"},
        {"place_source": "somewhere"},
        {"place_source": "google", "google_place_id": "not/an/id",
         "google_place_query": "x"},
    ])
    def test_a_location_the_rules_forbid_is_refused(self, client, body):
        itin_id, hdrs = self._trip(client)
        r = self._add(client, itin_id, hdrs, {"place_name": "Nope", **body})
        assert r.status_code == 422, r.text

    def test_an_installed_build_saving_a_google_stop_keeps_it_google(self, client):
        itin_id, hdrs = self._trip(client)
        stop = self._add(client, itin_id, hdrs, {
            "place_name": "Lunch", "place_source": "google",
            "google_place_id": self.PLACE_ID, "google_place_query": "chez marcel",
        }).json()
        # What an installed build's form sends: every location key, no source.
        r = self._patch(client, itin_id, hdrs, stop["id"], {
            "place_name": "Long lunch", "place_address": None,
            "lat": None, "lng": None, "map_url": None,
        })
        assert r.status_code == 200, r.text
        assert r.json()["place_source"] == "google"
        assert r.json()["google_place_id"] == self.PLACE_ID

    def test_coordinates_turn_a_google_stop_into_an_ordinary_one(self, client):
        itin_id, hdrs = self._trip(client)
        stop = self._add(client, itin_id, hdrs, {
            "place_name": "Lunch", "place_source": "google",
            "google_place_id": self.PLACE_ID, "google_place_query": "chez marcel",
        }).json()
        r = self._patch(client, itin_id, hdrs, stop["id"], {
            "lat": 48.85, "lng": 2.35, "map_url": None,
        })
        assert r.status_code == 200, r.text
        assert r.json()["google_place_id"] is None
        assert r.json()["google_place_query"] is None
        assert r.json()["place_source"] is None  # a build that cannot say where from
        assert r.json()["lat"] == pytest.approx(48.85)

    def test_an_osm_pick_replaces_a_link(self, client):
        itin_id, hdrs = self._trip(client)
        stop = self._add(client, itin_id, hdrs, {
            "place_name": "Gem", "map_url": "https://maps.app.goo.gl/abc123",
        }).json()
        r = self._patch(client, itin_id, hdrs, stop["id"], {
            "place_source": "osm", "lat": 50.85, "lng": 4.35,
            "place_address": "Grand-Place, Brussels", "map_url": None,
        })
        assert r.status_code == 200, r.text
        assert r.json()["place_source"] == "osm"
        assert r.json()["map_url"] is None

    def test_a_re_sent_id_keeps_its_refresh_stamps_and_a_new_one_resets_them(self, client):
        from datetime import datetime, timedelta, timezone
        from conftest import TestingSessionLocal
        from app.models.stop import Stop

        itin_id, hdrs = self._trip(client)
        stop = self._add(client, itin_id, hdrs, {
            "place_name": "Lunch", "place_source": "google",
            "google_place_id": self.PLACE_ID, "google_place_query": "chez marcel",
        }).json()
        long_ago = datetime.now(timezone.utc) - timedelta(days=400)
        db = TestingSessionLocal()
        row = db.get(Stop, uuid.UUID(stop["id"]))
        row.google_place_checked_at = long_ago
        row.google_place_missing_at = long_ago
        db.commit()
        db.close()

        same = self._patch(client, itin_id, hdrs, stop["id"], {
            "place_source": "google", "google_place_id": self.PLACE_ID,
            "google_place_query": "chez marcel again",
        })
        assert same.status_code == 200, same.text
        assert same.json()["google_place_missing"] is True
        assert self._row(stop["id"]).google_place_checked_at.replace(
            tzinfo=timezone.utc) == long_ago

        other = self._patch(client, itin_id, hdrs, stop["id"], {
            "place_source": "google", "google_place_id": "ChIJN1t_tDeuEmsRUsoyG83frY4",
            "google_place_query": "chez paul",
        })
        assert other.status_code == 200, other.text
        assert other.json()["google_place_missing"] is False
        assert self._row(stop["id"]).google_place_checked_at.replace(
            tzinfo=timezone.utc) > long_ago
