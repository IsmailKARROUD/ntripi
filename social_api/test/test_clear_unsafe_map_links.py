"""
test_clear_unsafe_map_links.py — the one-off clean-up of map links stored
before the check was tightened (scripts/clear_unsafe_map_links.py).

Coverage:
  a dry run lists and counts the refused links, then changes nothing
  a real run clears the link, the place ID read from it, place_source and the
    refresh stamps — and nothing else: good links stay, the stop keeps its
    name, and the itinerary's updated_at (the concurrency ETag) never moves
  a second run finds nothing left to clear
"""

import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).parent.parent))

from scripts.clear_unsafe_map_links import clear
from conftest import TestingSessionLocal, auth_headers, edit_now, register_user
from app.models.itinerary import Itinerary
from app.models.stop import Stop

GOOD = "https://maps.app.goo.gl/abc123"
BAD = "https://maps.google.com/url?q=https://phish.example&place_id=ChIJLU7jZClu5kcR4PcOOO6p3I0"
PLACE_ID = "ChIJLU7jZClu5kcR4PcOOO6p3I0"


def _world(client: TestClient):
    """A trip with two link stops; one link is then rewritten in the database
    to a redirect the API would refuse today — as it was stored before."""
    user = register_user(client, "alice", "alice@example.com")
    hdrs = auth_headers(user["access_token"])
    r = client.post("/itineraries/", json={"title": "Old links", "currency": "EUR"},
                    headers=hdrs)
    assert r.status_code == 201, r.text
    itin_id = r.json()["id"]
    ids = []
    for name in ("Kept", "Trap"):
        r = client.post(f"/itineraries/{itin_id}/stops",
                        json={"place_name": name, "map_url": GOOD},
                        headers=edit_now(client, itin_id, hdrs))
        assert r.status_code == 201, r.text
        ids.append(r.json()["id"])

    db = TestingSessionLocal()
    try:
        trap = db.get(Stop, uuid.UUID(ids[1]))
        trap.map_url = BAD
        trap.place_source = "link"
        trap.google_place_id = PLACE_ID
        trap.google_place_checked_at = datetime.now(timezone.utc)
        db.commit()
    finally:
        db.close()
    return itin_id, ids[0], ids[1]


def _stop(stop_id):
    db = TestingSessionLocal()
    try:
        return db.get(Stop, uuid.UUID(stop_id))
    finally:
        db.close()


def _updated_at(itin_id):
    db = TestingSessionLocal()
    try:
        return db.get(Itinerary, uuid.UUID(itin_id)).updated_at
    finally:
        db.close()


def _run(*, dry_run: bool) -> tuple[int, list[str]]:
    lines: list[str] = []
    db = TestingSessionLocal()
    try:
        return clear(db, dry_run=dry_run, report=lines.append), lines
    finally:
        db.close()


def test_a_dry_run_lists_and_counts_but_changes_nothing(client: TestClient):
    _itin, _kept, trap_id = _world(client)

    count, lines = _run(dry_run=True)

    assert count == 1
    assert len(lines) == 1 and trap_id in lines[0] and "phish.example" in lines[0]
    trap = _stop(trap_id)
    assert trap.map_url == BAD and trap.google_place_id == PLACE_ID


def test_a_run_clears_the_refused_link_and_only_that(client: TestClient):
    itin_id, kept_id, trap_id = _world(client)
    before = _updated_at(itin_id)

    count, _ = _run(dry_run=False)

    assert count == 1
    trap = _stop(trap_id)
    assert trap.map_url is None
    assert trap.google_place_id is None  # read from the hostile link's text
    assert trap.place_source is None
    assert trap.google_place_checked_at is None
    assert trap.google_place_missing_at is None
    assert trap.place_name == "Trap"
    kept = _stop(kept_id)
    assert kept.map_url == GOOD and kept.place_source == "link"
    assert _updated_at(itin_id) == before


def test_a_second_run_finds_nothing(client: TestClient):
    _world(client)
    _run(dry_run=False)

    count, lines = _run(dry_run=False)

    assert count == 0 and lines == []
