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
from conftest import (
    auth_headers, etag_from_updated_at, locked_headers, register_user,
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


# ---------------------------------------------------------------------------
# Track reorder + segment deletion via POST /reorder (Phase 2b)
# ---------------------------------------------------------------------------

class TestTrackReorder:
    """Cover the extended POST /reorder that also accepts track_order + segments_to_delete."""

    def _three_tracks(self, client: TestClient):
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

    def test_track_order_reverse(self, client: TestClient):
        """Reverse the track order via POST /reorder with track_order."""
        itin_id, hdrs, etag, track_ids, stop_ids = self._three_tracks(client)
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
        itin_id, hdrs, etag, track_ids, stop_ids = self._three_tracks(client)
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
        itin_id, hdrs, etag, track_ids, stop_ids = self._three_tracks(client)
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
        itin_id, hdrs, etag, track_ids, _ = self._three_tracks(client)
        a_t, b_t, _ = track_ids
        # Only two of three tracks listed.
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"track_order": [a_t, b_t]},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 422, r.text

    def test_track_order_duplicate_returns_422(self, client: TestClient):
        itin_id, hdrs, etag, track_ids, _ = self._three_tracks(client)
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
        itin_id, hdrs, etag, track_ids, _ = self._three_tracks(client)
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
        itin_id, hdrs, etag, _, _ = self._three_tracks(client)
        # A random uuid that won't match any segment.
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={"segments_to_delete": [str(_uuid.uuid4())]},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 422, r.text

    def test_empty_payload_returns_422(self, client: TestClient):
        itin_id, hdrs, etag, _, _ = self._three_tracks(client)
        r = client.post(
            f"/itineraries/{itin_id}/reorder",
            json={},
            headers=locked_headers(client, itin_id, hdrs, etag),
        )
        assert r.status_code == 422, r.text

    def test_phase_2a_payload_still_works(self, client: TestClient):
        """A request with only stop_orders (Phase 2a shape) still succeeds."""
        itin_id, hdrs, etag, track_ids, stop_ids = self._three_tracks(client)
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

    def test_moderation_status_is_the_last_json_key(self, client: TestClient):
        """Field order is JSON key order and part of the API contract — a new
        field has to be appended, never inserted."""
        alice, _, itinerary_id = self._setup(client)

        page = self._page(client, alice["access_token"], itinerary_id)
        keys = list(page.json()["ratings"][0].keys())
        assert keys[-1] == "moderation_status"
        assert keys[-2] == "id"
