"""
test_translation_orphans.py — the sweep's translation clean-up, and the script
that runs it by hand.

The safety net behind every delete path's own purge_orphans: translations
whose content row is gone, translations of trips a moderator removed, and usage
counters no limit can still read.
"""

import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi.testclient import TestClient
from sqlalchemy import func, select

sys.path.insert(0, str(Path(__file__).parent.parent))

from scripts.purge_translation_orphans import purge
from conftest import TestingSessionLocal, register_user
from app.config import get_settings
from app.models.content_translation import ContentTranslation
from app.models.itinerary import Itinerary
from app.models.translation_usage import TranslationUserUsage
from app.services import sweep_service, translation_usage
from translation_helpers import make_trip, set_row


def _seed(trip_id, content_type, content_id, field="content"):
    db = TestingSessionLocal()
    try:
        db.add(ContentTranslation(
            itinerary_id=uuid.UUID(trip_id), content_type=content_type,
            content_id=uuid.UUID(content_id), field=field, target_lang="fr",
            source_hash="h", translated_text="x", provider="fake",
        ))
        db.commit()
    finally:
        db.close()


def _count() -> int:
    db = TestingSessionLocal()
    try:
        return db.execute(select(func.count(ContentTranslation.id))).scalar_one()
    finally:
        db.close()


def _world(client):
    owner = register_user(client, "owner", "owner@example.com")
    live = make_trip(client, owner["access_token"])
    removed = make_trip(client, owner["access_token"])
    _seed(live, "itinerary", live, field="title")                  # kept
    _seed(live, "stop_annotation", str(uuid.uuid4()))               # orphan: no such note
    _seed(removed, "itinerary", removed, field="title")             # trip removed by a moderator
    set_row(Itinerary, removed, deleted_at=datetime.now(timezone.utc))
    db = TestingSessionLocal()
    try:  # a usage counter far past any limit's window
        translation_usage.reserve_user_fields(
            db, uuid.UUID(owner["user_id"]), 1, 10,
            datetime.now(timezone.utc) - timedelta(days=5))
        db.commit()
    finally:
        db.close()


def test_the_sweep_purges_what_the_cache_no_longer_needs(client: TestClient):
    _world(client)
    db = TestingSessionLocal()
    try:
        counters = sweep_service.run_moderation_sweep(db, get_settings())
    finally:
        db.close()

    assert counters["translations_purged"] == 3
    assert _count() == 1
    db = TestingSessionLocal()
    try:
        assert db.execute(select(TranslationUserUsage)).first() is None
    finally:
        db.close()


def test_the_script_dry_run_counts_and_deletes_nothing(client: TestClient):
    _world(client)
    db = TestingSessionLocal()
    try:
        assert purge(db, dry_run=True) == 3
    finally:
        db.close()
    assert _count() == 3

    db = TestingSessionLocal()
    try:
        assert purge(db, dry_run=False) == 3
    finally:
        db.close()
    assert _count() == 1
