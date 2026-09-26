"""
test_transit_segments.py — Tests for transit segment and transport leg endpoints.

Coverage:
  Class 1: CreateSegment        — POST /itineraries/{id}/segments
  Class 2: ListSegments         — GET  /itineraries/{id}/segments
  Class 3: UpdateSegment        — PATCH /itineraries/{id}/segments/{segment_id}
  Class 4: DeleteSegment        — DELETE /itineraries/{id}/segments/{segment_id}
  Class 5: LegCRUD              — POST/PATCH/DELETE legs within a segment
  Class 6: TotalRecalculation   — itinerary total_cost / total_duration_min
"""

import pytest
from fastapi.testclient import TestClient

from conftest import auth_headers, register_user


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def create_itinerary(client, token, *, title="Trip", visibility="only_me"):
    r = client.post(
        "/itineraries/",
        json={"title": title, "visibility": visibility},
        headers=auth_headers(token),
    )
    assert r.status_code == 201, r.json()
    return r.json()


def write_headers(client, token, itinerary_id):
    """Auth + If-Match, plus an edit claim when this caller may hold one.

    A non-editor cannot claim, and the guard answers their 403 before it ever
    looks at the claim — so the 403 tests still exercise the real check."""
    hdrs = auth_headers(token)
    etag = client.get(f"/itineraries/{itinerary_id}", headers=hdrs).headers.get("etag", '"none"')
    claim = client.post(f"/itineraries/{itinerary_id}/lock",
                        json={"takeover": True}, headers=hdrs)
    if claim.status_code != 200:
        return {**hdrs, "If-Match": etag}
    return {**hdrs, "If-Match": etag, "X-Edit-Lock": claim.json()["token"]}


def add_stop(client, token, itinerary_id, position, stop_type="waypoint"):
    r = client.post(
        f"/itineraries/{itinerary_id}/stops",
        # `position` is only a label now: stops are ranked, and role is derived
        # client-side — neither is ever sent.
        json={"place_name": f"Stop {position}"},
        headers=write_headers(client, token, itinerary_id),
    )
    assert r.status_code == 201, r.json()
    return r.json()


def create_segment(client, token, itinerary_id, from_stop_id, to_stop_id, legs=None):
    if legs is None:
        legs = [{"position": 1, "mode": "metro"}]
    return client.post(
        f"/itineraries/{itinerary_id}/segments",
        json={"from_stop_id": from_stop_id, "to_stop_id": to_stop_id, "legs": legs},
        headers=write_headers(client, token, itinerary_id),
    )


def setup_two_stops(client, token):
    """Create an itinerary with two stops and return (itinerary_id, stop_a, stop_b)."""
    itin = create_itinerary(client, token)
    stop_a = add_stop(client, token, itin["id"], 1, "origin")
    stop_b = add_stop(client, token, itin["id"], 2, "arrival")
    return itin["id"], stop_a, stop_b


# ---------------------------------------------------------------------------
# Class 1: CreateSegment
# ---------------------------------------------------------------------------

class TestCreateSegment:

    def test_create_basic_segment(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])

        r = create_segment(client, user["access_token"], itin_id,
                           stop_a["id"], stop_b["id"])
        assert r.status_code == 201
        data = r.json()
        assert data["from_stop_id"] == stop_a["id"]
        assert data["to_stop_id"] == stop_b["id"]
        assert len(data["legs"]) == 1
        assert data["legs"][0]["mode"] == "metro"
        assert data["legs"][0]["position"] == 1

    def test_create_segment_multiple_legs(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])

        legs = [
            {"position": 1, "mode": "walk", "duration_min": 5},
            {"position": 2, "mode": "bus", "duration_min": 15, "line": "42"},
        ]
        r = create_segment(client, user["access_token"], itin_id,
                           stop_a["id"], stop_b["id"], legs=legs)
        assert r.status_code == 201
        data = r.json()
        assert len(data["legs"]) == 2
        assert data["total_duration_min"] == 20

    def test_duplicate_segment_returns_409(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])

        create_segment(client, user["access_token"], itin_id,
                       stop_a["id"], stop_b["id"])
        r = create_segment(client, user["access_token"], itin_id,
                           stop_a["id"], stop_b["id"])
        assert r.status_code == 409

    def test_stop_not_in_itinerary_returns_400(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, _ = setup_two_stops(client, user["access_token"])

        # Create a second itinerary with its own stop.
        itin2 = create_itinerary(client, user["access_token"], title="Other")
        foreign_stop = add_stop(client, user["access_token"], itin2["id"], 1)

        r = create_segment(client, user["access_token"], itin_id,
                           stop_a["id"], foreign_stop["id"])
        assert r.status_code == 400

    def test_non_owner_cannot_create_segment(self, client):
        owner = register_user(client, "owner", "owner@test.com")
        other = register_user(client, "other", "other@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, owner["access_token"])

        r = create_segment(client, other["access_token"], itin_id,
                           stop_a["id"], stop_b["id"])
        assert r.status_code == 403

    def test_leg_positions_must_be_contiguous(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])

        legs = [{"position": 1, "mode": "walk"}, {"position": 3, "mode": "bus"}]
        r = create_segment(client, user["access_token"], itin_id,
                           stop_a["id"], stop_b["id"], legs=legs)
        assert r.status_code == 422

    def test_segment_appears_in_itinerary_detail(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])
        create_segment(client, user["access_token"], itin_id,
                       stop_a["id"], stop_b["id"])

        r = client.get(f"/itineraries/{itin_id}",
                       headers=auth_headers(user["access_token"]))
        assert r.status_code == 200
        assert len(r.json()["segments"]) == 1


# ---------------------------------------------------------------------------
# Class 2: ListSegments
# ---------------------------------------------------------------------------

class TestListSegments:

    def test_list_empty(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, _, _ = setup_two_stops(client, user["access_token"])

        r = client.get(f"/itineraries/{itin_id}/segments",
                       headers=auth_headers(user["access_token"]))
        assert r.status_code == 200
        assert r.json() == []

    def test_list_returns_segments(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])
        create_segment(client, user["access_token"], itin_id,
                       stop_a["id"], stop_b["id"])

        r = client.get(f"/itineraries/{itin_id}/segments",
                       headers=auth_headers(user["access_token"]))
        assert r.status_code == 200
        assert len(r.json()) == 1

    def test_non_viewer_cannot_list(self, client):
        owner = register_user(client, "owner", "owner@test.com")
        other = register_user(client, "other", "other@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, owner["access_token"])
        create_segment(client, owner["access_token"], itin_id,
                       stop_a["id"], stop_b["id"])

        r = client.get(f"/itineraries/{itin_id}/segments",
                       headers=auth_headers(other["access_token"]))
        assert r.status_code == 403


# ---------------------------------------------------------------------------
# Class 3: UpdateSegment
# ---------------------------------------------------------------------------

class TestUpdateSegment:

    def test_update_segment_stops(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])
        stop_c = add_stop(client, user["access_token"], itin_id, 3)

        seg = create_segment(client, user["access_token"], itin_id,
                              stop_a["id"], stop_b["id"]).json()

        r = client.patch(
            f"/itineraries/{itin_id}/segments/{seg['id']}",
            json={
                "from_stop_id": stop_a["id"],
                "to_stop_id": stop_c["id"],
                "legs": [{"position": 1, "mode": "tram"}],
            },
            headers=write_headers(client, user["access_token"], itin_id),
        )
        assert r.status_code == 200
        assert r.json()["to_stop_id"] == stop_c["id"]

    def test_update_replaces_legs(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])
        seg = create_segment(
            client, user["access_token"], itin_id,
            stop_a["id"], stop_b["id"],
            legs=[{"position": 1, "mode": "walk"}, {"position": 2, "mode": "bus"}],
        ).json()

        r = client.patch(
            f"/itineraries/{itin_id}/segments/{seg['id']}",
            json={
                "from_stop_id": stop_a["id"],
                "to_stop_id": stop_b["id"],
                "legs": [{"position": 1, "mode": "taxi"}],
            },
            headers=write_headers(client, user["access_token"], itin_id),
        )
        assert r.status_code == 200
        assert len(r.json()["legs"]) == 1
        assert r.json()["legs"][0]["mode"] == "taxi"

    def test_non_owner_cannot_update(self, client):
        owner = register_user(client, "owner", "owner@test.com")
        other = register_user(client, "other", "other@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, owner["access_token"])
        seg = create_segment(client, owner["access_token"], itin_id,
                              stop_a["id"], stop_b["id"]).json()

        r = client.patch(
            f"/itineraries/{itin_id}/segments/{seg['id']}",
            json={
                "from_stop_id": stop_a["id"],
                "to_stop_id": stop_b["id"],
                "legs": [{"position": 1, "mode": "walk"}],
            },
            headers=write_headers(client, other["access_token"], itin_id),
        )
        assert r.status_code == 403

    def test_update_nonexistent_segment_returns_404(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])

        r = client.patch(
            f"/itineraries/{itin_id}/segments/00000000-0000-0000-0000-000000000000",
            json={
                "from_stop_id": stop_a["id"],
                "to_stop_id": stop_b["id"],
                "legs": [{"position": 1, "mode": "walk"}],
            },
            headers=write_headers(client, user["access_token"], itin_id),
        )
        assert r.status_code == 404


# ---------------------------------------------------------------------------
# Class 4: DeleteSegment
# ---------------------------------------------------------------------------

class TestDeleteSegment:

    def test_delete_segment(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])
        seg = create_segment(client, user["access_token"], itin_id,
                              stop_a["id"], stop_b["id"]).json()

        r = client.delete(
            f"/itineraries/{itin_id}/segments/{seg['id']}",
            headers=write_headers(client, user["access_token"], itin_id),
        )
        assert r.status_code == 204

        # Confirm it's gone.
        r2 = client.get(f"/itineraries/{itin_id}/segments",
                        headers=auth_headers(user["access_token"]))
        assert r2.json() == []

    def test_delete_segment_removes_legs(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])
        seg = create_segment(
            client, user["access_token"], itin_id,
            stop_a["id"], stop_b["id"],
            legs=[{"position": 1, "mode": "walk"}, {"position": 2, "mode": "bus"}],
        ).json()

        client.delete(
            f"/itineraries/{itin_id}/segments/{seg['id']}",
            headers=write_headers(client, user["access_token"], itin_id),
        )

        # Detail should have no segments.
        detail = client.get(f"/itineraries/{itin_id}",
                            headers=auth_headers(user["access_token"])).json()
        assert len(detail["segments"]) == 0

    def test_delete_nonexistent_segment_returns_404(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, _, _ = setup_two_stops(client, user["access_token"])

        r = client.delete(
            f"/itineraries/{itin_id}/segments/00000000-0000-0000-0000-000000000000",
            headers=write_headers(client, user["access_token"], itin_id),
        )
        assert r.status_code == 404

    def test_non_owner_cannot_delete(self, client):
        owner = register_user(client, "owner", "owner@test.com")
        other = register_user(client, "other", "other@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, owner["access_token"])
        seg = create_segment(client, owner["access_token"], itin_id,
                              stop_a["id"], stop_b["id"]).json()

        r = client.delete(
            f"/itineraries/{itin_id}/segments/{seg['id']}",
            headers=write_headers(client, other["access_token"], itin_id),
        )
        assert r.status_code == 403


# ---------------------------------------------------------------------------
# Class 5: LegCRUD
# ---------------------------------------------------------------------------

class TestLegCRUD:

    def _create_seg(self, client, token, itin_id, stop_a_id, stop_b_id):
        return create_segment(
            client, token, itin_id, stop_a_id, stop_b_id,
            legs=[{"position": 1, "mode": "walk", "duration_min": 5}],
        ).json()

    def test_add_leg(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])
        seg = self._create_seg(client, user["access_token"],
                               itin_id, stop_a["id"], stop_b["id"])

        r = client.post(
            f"/itineraries/{itin_id}/segments/{seg['id']}/legs",
            json={"position": 2, "mode": "bus", "duration_min": 10},
            headers=write_headers(client, user["access_token"], itin_id),
        )
        assert r.status_code == 201
        assert r.json()["mode"] == "bus"

    def test_add_duplicate_leg_position_returns_409(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])
        seg = self._create_seg(client, user["access_token"],
                               itin_id, stop_a["id"], stop_b["id"])

        r = client.post(
            f"/itineraries/{itin_id}/segments/{seg['id']}/legs",
            json={"position": 1, "mode": "bus"},
            headers=write_headers(client, user["access_token"], itin_id),
        )
        assert r.status_code == 409

    def test_update_leg(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])
        seg = self._create_seg(client, user["access_token"],
                               itin_id, stop_a["id"], stop_b["id"])
        leg_id = seg["legs"][0]["id"]

        r = client.patch(
            f"/itineraries/{itin_id}/segments/{seg['id']}/legs/{leg_id}",
            json={"mode": "tram", "duration_min": 20},
            headers=write_headers(client, user["access_token"], itin_id),
        )
        assert r.status_code == 200
        assert r.json()["mode"] == "tram"
        assert r.json()["duration_min"] == 20

    def test_delete_leg(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])
        legs = [
            {"position": 1, "mode": "walk"},
            {"position": 2, "mode": "metro"},
        ]
        seg = create_segment(client, user["access_token"], itin_id,
                             stop_a["id"], stop_b["id"], legs=legs).json()
        leg_id = seg["legs"][0]["id"]

        r = client.delete(
            f"/itineraries/{itin_id}/segments/{seg['id']}/legs/{leg_id}",
            headers=write_headers(client, user["access_token"], itin_id),
        )
        assert r.status_code == 204

    def test_delete_leg_nonexistent_returns_404(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])
        seg = self._create_seg(client, user["access_token"],
                               itin_id, stop_a["id"], stop_b["id"])

        r = client.delete(
            f"/itineraries/{itin_id}/segments/{seg['id']}/legs/00000000-0000-0000-0000-000000000000",
            headers=write_headers(client, user["access_token"], itin_id),
        )
        assert r.status_code == 404

    def test_invalid_mode_returns_422(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])
        seg = self._create_seg(client, user["access_token"],
                               itin_id, stop_a["id"], stop_b["id"])

        r = client.post(
            f"/itineraries/{itin_id}/segments/{seg['id']}/legs",
            json={"position": 2, "mode": "helicopter"},
            headers=write_headers(client, user["access_token"], itin_id),
        )
        assert r.status_code == 422


# ---------------------------------------------------------------------------
# Class 6: TotalRecalculation
# ---------------------------------------------------------------------------

class TestTotalRecalculation:

    def test_segment_cost_included_in_itinerary_total(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])

        legs = [{"position": 1, "mode": "bus", "cost": "3.50"}]
        create_segment(client, user["access_token"], itin_id,
                       stop_a["id"], stop_b["id"], legs=legs)

        itin = client.get(f"/itineraries/{itin_id}",
                          headers=auth_headers(user["access_token"])).json()
        assert float(itin["total_cost"]) == pytest.approx(3.50)

    def test_segment_duration_included_in_itinerary_total(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])

        # Give the stops some duration too.
        client.patch(f"/itineraries/{itin_id}/stops/{stop_a['id']}",
                     json={"duration_min": 30},
                     headers=write_headers(client, user["access_token"], itin_id))

        legs = [{"position": 1, "mode": "metro", "duration_min": 20}]
        create_segment(client, user["access_token"], itin_id,
                       stop_a["id"], stop_b["id"], legs=legs)

        itin = client.get(f"/itineraries/{itin_id}",
                          headers=auth_headers(user["access_token"])).json()
        assert itin["total_duration_min"] == 50  # 30 (stop) + 20 (leg)

    def test_free_leg_cost_excluded(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])

        legs = [{"position": 1, "mode": "walk", "cost": "2.00", "is_free": True}]
        create_segment(client, user["access_token"], itin_id,
                       stop_a["id"], stop_b["id"], legs=legs)

        itin = client.get(f"/itineraries/{itin_id}",
                          headers=auth_headers(user["access_token"])).json()
        assert float(itin["total_cost"]) == 0.0

    def test_totals_recalculated_after_segment_delete(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])

        legs = [{"position": 1, "mode": "taxi", "cost": "12.00", "duration_min": 10}]
        seg = create_segment(client, user["access_token"], itin_id,
                             stop_a["id"], stop_b["id"], legs=legs).json()

        client.delete(f"/itineraries/{itin_id}/segments/{seg['id']}",
                      headers=write_headers(client, user["access_token"], itin_id))

        itin = client.get(f"/itineraries/{itin_id}",
                          headers=auth_headers(user["access_token"])).json()
        assert float(itin["total_cost"]) == 0.0
        assert itin["total_duration_min"] == 0

    def test_totals_recalculated_after_leg_update(self, client):
        user = register_user(client, "alice", "alice@test.com")
        itin_id, stop_a, stop_b = setup_two_stops(client, user["access_token"])

        legs = [{"position": 1, "mode": "bus", "cost": "2.00", "duration_min": 15}]
        seg = create_segment(client, user["access_token"], itin_id,
                             stop_a["id"], stop_b["id"], legs=legs).json()
        leg_id = seg["legs"][0]["id"]

        client.patch(
            f"/itineraries/{itin_id}/segments/{seg['id']}/legs/{leg_id}",
            json={"cost": "5.00", "duration_min": 30},
            headers=write_headers(client, user["access_token"], itin_id),
        )

        itin = client.get(f"/itineraries/{itin_id}",
                          headers=auth_headers(user["access_token"])).json()
        assert float(itin["total_cost"]) == pytest.approx(5.0)
        assert itin["total_duration_min"] == 30
