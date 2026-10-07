"""
test_backfill_source_lang.py — the one-off source_lang backfill.

Rows written before detection existed have source_lang NULL; the script fills
them. It must not move updated_at while doing it: on itineraries that column IS
the If-Match ETag, and on reviews it is the date the ratings page shows and
sorts by.
"""

import sys
from datetime import datetime
from pathlib import Path

from fastapi.testclient import TestClient
from sqlalchemy import select, update

sys.path.insert(0, str(Path(__file__).parent.parent))

from scripts.backfill_source_lang import backfill
from conftest import TestingSessionLocal, auth_headers, edit_now, register_user
from app.services.translation_service import REGISTRY

# A fixed, old timestamp the backfill must leave exactly where it is.
_FROZEN = datetime(2026, 1, 2, 3, 4, 5)

_EXPECTED = {
    "itinerary": "en",
    "stop": "fr",
    "stop_annotation": "de",
    "itinerary_annotation": "es",
    "rating": "en",
    "transport_leg": "it",
}


def _build_world(client: TestClient) -> None:
    """One row of every translatable type, plus one annotation that carries no
    language at all."""
    alice = register_user(client, "alice", "alice@example.com")
    bob = register_user(client, "bobby", "bob@example.com")
    token = alice["access_token"]

    trip_id = client.post(
        "/itineraries/",
        json={"title": "A slow weekend walking around the old harbour",
              "description": "Two quiet days walking along the water and eating fresh fish.",
              "visibility": "public"},
        headers=auth_headers(token),
    ).json()["id"]

    def write(method, path, body):
        r = client.request(method, path, json=body,
                           headers=edit_now(client, trip_id, auth_headers(token)))
        assert r.status_code in (200, 201), r.text
        return r.json()

    stop_a = write("POST", f"/itineraries/{trip_id}/stops", {
        "place_name": "Le Vieux-Port",
        "notes": "Arrivez tôt le matin pour éviter la foule, le marché ferme à midi.",
    })
    stop_b = write("POST", f"/itineraries/{trip_id}/stops", {"place_name": "La Corniche"})
    write("POST", f"/itineraries/{trip_id}/stops/{stop_a['id']}/annotations", {
        "type": "advice",
        "content": "Die Fähre fährt sonntags nur zweimal, also plant genug Zeit ein.",
    })
    write("POST", f"/itineraries/{trip_id}/stops/{stop_a['id']}/annotations", {
        "type": "info", "content": "👍👍",
    })
    write("POST", f"/itineraries/{trip_id}/annotations", {
        "type": "info",
        "content": "Llevad agua y crema solar, no hay sombra en todo el camino.",
    })
    write("POST", f"/itineraries/{trip_id}/segments", {
        "from_stop_id": stop_a["id"], "to_stop_id": stop_b["id"],
        "legs": [{"position": 1, "mode": "metro",
                  "notes": "Prendete la metro verde e scendete alla fermata del centro."}],
    })
    r = client.post(f"/itineraries/{trip_id}/ratings",
                    json={"stars": 4, "note": "Beautiful route, but far too long for children."},
                    headers=auth_headers(bob["access_token"]))
    assert r.status_code == 201, r.text


def _forget_languages() -> None:
    """Put every row back in its pre-detection state: no language, and an old
    updated_at to watch."""
    db = TestingSessionLocal()
    try:
        for spec in REGISTRY:
            values = {"source_lang": None}
            if hasattr(spec.model, "updated_at"):
                values["updated_at"] = _FROZEN
            db.execute(update(spec.model).values(**values))
        db.commit()
    finally:
        db.close()


def _state() -> dict[str, list]:
    db = TestingSessionLocal()
    try:
        return {
            spec.content_type: sorted(
                db.execute(select(spec.model.source_lang)).scalars().all(),
                key=lambda lang: lang or "",
            )
            for spec in REGISTRY
        }
    finally:
        db.close()


def _updated_ats() -> list[datetime]:
    db = TestingSessionLocal()
    try:
        return [
            stamp.replace(tzinfo=None)
            for spec in REGISTRY if hasattr(spec.model, "updated_at")
            for stamp in db.execute(select(spec.model.updated_at)).scalars().all()
        ]
    finally:
        db.close()


def _run(*, dry_run: bool) -> tuple[dict[str, int], list[str]]:
    lines: list[str] = []
    db = TestingSessionLocal()
    try:
        counts = backfill(db, dry_run=dry_run, batch_size=2, out=lines.append)
    finally:
        db.close()
    return counts, lines


def test_dry_run_counts_and_writes_nothing(client: TestClient):
    _build_world(client)
    _forget_languages()

    counts, lines = _run(dry_run=True)

    assert counts == {content_type: 1 for content_type in _EXPECTED}
    assert len(lines) == len(REGISTRY)
    assert all(langs == [None] * len(langs) for langs in _state().values())


def test_backfill_detects_every_type_and_keeps_updated_at(client: TestClient):
    _build_world(client)
    _forget_languages()

    counts, _ = _run(dry_run=False)

    assert counts == {content_type: 1 for content_type in _EXPECTED}
    state = _state()
    for content_type, lang in _EXPECTED.items():
        assert lang in state[content_type], (content_type, state[content_type])
    # The emoji-only annotation has no language and stays NULL.
    assert state["stop_annotation"] == [None, "de"]
    # The ETag and the review date did not move.
    assert set(_updated_ats()) == {_FROZEN}


def test_a_second_run_finds_nothing_new(client: TestClient):
    _build_world(client)
    _forget_languages()
    _run(dry_run=False)
    before = _state()

    counts, _ = _run(dry_run=False)

    assert counts == {content_type: 0 for content_type in _EXPECTED}
    assert _state() == before
