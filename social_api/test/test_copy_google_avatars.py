"""
test_copy_google_avatars.py — the one-off copy of profile photos linked from
outside our storage (scripts/copy_google_avatars.py).

Until 2026-11-09 a Google sign-up stored Google's photo URL as its avatar. The
script copies each such photo in as a new sign-up's is copied
(google_avatar.copy_photo) and clears any other photo linked from elsewhere.

Coverage:
  a dry run lists the accounts by id and host, fetches nothing, changes nothing
  a real run copies a Google photo into the account's avatar, clears a refused,
    unreachable or foreign one, and leaves our own avatars alone
  a second run finds nothing left to do
"""

import sys
import uuid
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from scripts.copy_google_avatars import copy_all
from conftest import TestingSessionLocal, register_user
from test_image_moderation import _make_jpeg
from app.models.user import User
from app.services import google_avatar
from app.storage.filesystem import FilesystemStorage

GOOGLE = "https://lh3.googleusercontent.com/a/ACg8ocJxYz123=s96-c"
GONE = "https://lh3.googleusercontent.com/a/Gone456=s96-c"
FOREIGN = "https://elsewhere.example/me.png"
OURS = "/uploads/avatars/ours.jpg?v=1"


@pytest.fixture()
def photos(tmp_path, monkeypatch):
    """Google's photo host: GOOGLE answers with a photo, anything else with
    nothing. Records each fetch."""
    fetched: list[str] = []

    def fake_fetch(source: str) -> bytes | None:
        fetched.append(source)
        return _make_jpeg(96, 96) if "ACg8ocJxYz123" in source else None

    monkeypatch.setattr(google_avatar, "_fetch", fake_fetch)
    storage = FilesystemStorage(str(tmp_path), "/uploads")
    with patch("app.services.image_service.storage", return_value=storage):
        yield fetched


def _accounts(client) -> dict[str, uuid.UUID]:
    """Four accounts, each with a photo stored the way it could be today."""
    ids = {}
    for name, avatar in (("google", GOOGLE), ("gone", GONE),
                         ("foreign", FOREIGN), ("ours", OURS)):
        user = register_user(client, f"{name}user", f"{name}@example.com")
        ids[name] = uuid.UUID(user["user_id"])
    db = TestingSessionLocal()
    try:
        for name, avatar in (("google", GOOGLE), ("gone", GONE),
                             ("foreign", FOREIGN), ("ours", OURS)):
            db.get(User, ids[name]).avatar_url = avatar
        db.commit()
    finally:
        db.close()
    return ids


def _avatar(user_id: uuid.UUID) -> str | None:
    db = TestingSessionLocal()
    try:
        return db.get(User, user_id).avatar_url
    finally:
        db.close()


def _run(*, dry_run: bool) -> tuple[tuple[int, int], list[str]]:
    lines: list[str] = []
    db = TestingSessionLocal()
    try:
        result = copy_all(db, dry_run=dry_run, report=lines.append)
    finally:
        db.close()
    return result, lines


def test_a_dry_run_lists_and_changes_nothing(client, photos):
    ids = _accounts(client)
    (found, _), lines = _run(dry_run=True)

    assert found == 3
    assert photos == []  # nothing fetched
    assert any(str(ids["foreign"]) in line and "elsewhere.example" in line
               for line in lines)
    # The address names the person's Google photo: never printed.
    assert not any("ACg8oc" in line for line in lines)
    assert _avatar(ids["google"]) == GOOGLE
    assert _avatar(ids["ours"]) == OURS


def test_a_real_run_copies_googles_photo_and_clears_the_rest(client, photos):
    ids = _accounts(client)
    (copied, cleared), _ = _run(dry_run=False)

    assert (copied, cleared) == (1, 2)
    assert _avatar(ids["google"]).startswith(f"/uploads/avatars/{ids['google']}.jpg?v=")
    assert _avatar(ids["gone"]) is None
    assert _avatar(ids["foreign"]) is None
    assert _avatar(ids["ours"]) == OURS

    (copied, cleared), lines = _run(dry_run=False)
    assert (copied, cleared) == (0, 0)
    assert lines == []
