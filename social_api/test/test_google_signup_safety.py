"""
test_google_signup_safety.py — what a Google sign-up takes from Google is
checked like what a person types.

Two things arrive without anyone typing them: the username, built from the
e-mail address's local part, and the profile photo, a URL on Google's servers.
Until 2026-11-09 the username was never scanned or held to the link rule, and
the photo URL was stored as it was — no image scan, no EXIF strip, served from
outside our CDN. Now (services/auth_service.py, services/google_avatar.py):

  - the username is held to the link rule — `anna.paris` is a site name, so its
    dots become underscores — and scanned with the Google name in one request;
    on a reject the name is dropped and the username kept only if it passes
    alone, else it is the `traveler` fallback. A sign-up is never refused.
  - the photo is fetched once from Google's photo host (https, no redirect,
    under the upload limit), at 800 px, and stored like an upload; refused,
    unreachable or not Google's → no photo.

Coverage:
  the username: the link rule, a reject in it, a reject in the name only, a
    name holding a link, moderation off
  photo_source: only Google's photo host, over https, asked for at 800 px
  _fetch: a 200 is the photo; a redirect, an error answer, a network error or
    a body past the limit is nothing
  the sign-up copies the photo into the account's avatar, scanned; a refused,
    unreachable or foreign photo leaves none; a returning sign-in fetches nothing
"""

from __future__ import annotations

import io
import uuid
from unittest.mock import patch

import pytest
import requests
from PIL import Image
from sqlalchemy import select

import conftest
from test_image_moderation import _enable_moderation, _make_jpeg, _stub_rekognition
from app.config import get_settings
from app.models.text_moderation_decision import TextModerationDecision
from app.models.user import User
from app.services import google_avatar
from app.services import text_moderation_service as tms
from app.services.text_moderation_providers import ProviderResult
from app.storage.filesystem import FilesystemStorage

PHOTO = "https://lh3.googleusercontent.com/a/ACg8ocJxYz123=s96-c"
REJECT = {"hate": 0.9}


class WordProvider:
    """Rejects any text holding `word`; records every text it is sent."""

    name = "stub"
    model = "stub-model"

    def __init__(self, word: str):
        self.word = word
        self.calls: list[str] = []

    def score(self, text: str) -> ProviderResult:
        self.calls.append(text)
        scores = REJECT if self.word in text else {}
        return ProviderResult(scores=scores, provider=self.name, model=self.model)


@pytest.fixture()
def provider(monkeypatch):
    monkeypatch.setattr(get_settings(), "TEXT_MODERATION_PROVIDER", "openai")
    monkeypatch.setattr(get_settings(), "OPENAI_API_KEY", "test-key")
    stub = WordProvider("vile")
    monkeypatch.setattr(tms, "get_provider_chain", lambda settings: [stub])
    return stub


@pytest.fixture()
def store(tmp_path):
    """Avatars stored on disk under tmp_path, which the fixture yields."""
    storage = FilesystemStorage(str(tmp_path), "/uploads")
    with patch("app.services.image_service.storage", return_value=storage):
        yield tmp_path


@pytest.fixture()
def fetched(monkeypatch):
    """Google's photo host, answering with a 96 px photo; records each fetch."""
    calls: list[str] = []

    def fake_fetch(source: str) -> bytes | None:
        calls.append(source)
        return _make_jpeg(96, 96)

    monkeypatch.setattr(google_avatar, "_fetch", fake_fetch)
    return calls


def _patch_google(monkeypatch, *, email, name=None, picture=None, sub=None):
    import app.routers.auth as auth_router
    monkeypatch.setattr(
        auth_router, "verify_google_id_token",
        lambda token: {
            "sub": sub or f"g-{email}", "email": email, "email_verified": True,
            "name": name, "picture": picture,
        },
    )


def _google(client):
    r = client.post("/auth/google", json={
        "id_token": "fake", "tos_accepted": True, "date_of_birth": "2000-01-01",
    })
    assert r.status_code == 200, r.text
    return r.json()


def _user(email: str) -> User:
    db = conftest.TestingSessionLocal()
    try:
        return db.execute(select(User).where(User.email == email)).scalar_one()
    finally:
        db.close()


def _decisions(user_id: str) -> int:
    db = conftest.TestingSessionLocal()
    try:
        return len(db.execute(select(TextModerationDecision).where(
            TextModerationDecision.target_id == uuid.UUID(user_id))).scalars().all())
    finally:
        db.close()


# ---------------------------------------------------------------------------
# The username
# ---------------------------------------------------------------------------

def test_a_site_name_username_loses_its_dots(client, monkeypatch):
    _patch_google(monkeypatch, email="anna.paris@gmail.com")
    assert _google(client)["username"] == "anna_paris"


def test_a_taken_underscore_name_gets_a_number(client, monkeypatch):
    """The underscore name is generated like any other: taken → the next free
    number, never someone else's account."""
    conftest.register_user(client, "anna_paris", "anna@example.com")
    _patch_google(monkeypatch, email="anna.paris@gmail.com", sub="g-anna-1")
    assert _google(client)["username"] == "anna_paris1"
    _patch_google(monkeypatch, email="anna.paris@outlook.com", sub="g-anna-2")
    assert _google(client)["username"] == "anna_paris2"


def test_an_ordinary_dotted_username_is_kept(client, monkeypatch):
    _patch_google(monkeypatch, email="jane.doe@gmail.com")
    assert _google(client)["username"] == "jane.doe"


def test_a_rejected_username_falls_back_and_the_sign_up_goes_through(
    client, monkeypatch, provider,
):
    _patch_google(monkeypatch, email="vile.person@gmail.com")
    body = _google(client)
    assert body["username"] == "traveler"
    assert provider.calls == ["vile.person"]
    user = _user("vile.person@gmail.com")
    assert user.moderation_status == "approved"  # nothing refused was stored
    assert _decisions(body["user_id"]) == 1  # the reject is on the record


def test_a_rejected_name_is_dropped_and_the_username_kept(client, monkeypatch, provider):
    _patch_google(monkeypatch, email="jane@gmail.com", name="vile name")
    body = _google(client)
    assert body["username"] == "jane"
    assert provider.calls == ["jane\n\nvile name", "jane"]
    user = _user("jane@gmail.com")
    assert user.display_name is None
    assert user.moderation_status == "approved"
    assert _decisions(body["user_id"]) == 2


def test_a_reject_in_both_drops_the_name_and_the_username(client, monkeypatch, provider):
    _patch_google(monkeypatch, email="vile@gmail.com", name="Jane")
    body = _google(client)
    assert body["username"] == "traveler"
    assert provider.calls == ["vile\n\nJane", "vile"]
    assert _user("vile@gmail.com").display_name is None


def test_a_name_holding_a_link_is_dropped(client, monkeypatch, provider):
    _patch_google(monkeypatch, email="anna@gmail.com", name="Anna anna.paris")
    _google(client)
    assert _user("anna@gmail.com").display_name is None
    assert provider.calls == ["anna"]


def test_a_clean_sign_up_costs_one_request(client, monkeypatch, provider):
    _patch_google(monkeypatch, email="jane@gmail.com", name="Jane Doe")
    _google(client)
    assert provider.calls == ["jane\n\nJane Doe"]
    assert _user("jane@gmail.com").display_name == "Jane Doe"


def test_moderation_off_scans_nothing(client, monkeypatch):
    _patch_google(monkeypatch, email="jane@gmail.com", name="Jane Doe")
    body = _google(client)
    assert body["username"] == "jane"
    assert _decisions(body["user_id"]) == 0


# ---------------------------------------------------------------------------
# photo_source and _fetch
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("url, source", [
    (PHOTO, "https://lh3.googleusercontent.com/a/ACg8ocJxYz123=s800-c"),
    ("https://lh5.googleusercontent.com/a-/AOh14Gh7", "https://lh5.googleusercontent.com/a-/AOh14Gh7=s800-c"),
    ("https://lh3.googleusercontent.com/-XdUI/AAAAAAAAAAI/AAAA/4252/s96-c/photo.jpg",
     "https://lh3.googleusercontent.com/-XdUI/AAAAAAAAAAI/AAAA/4252/s96-c/photo.jpg"),
])
def test_photo_source_asks_googles_host_for_800_px(url, source):
    assert google_avatar.photo_source(url) == source


@pytest.mark.parametrize("url", [
    None, "",
    "http://lh3.googleusercontent.com/a/ACg8oc=s96-c",
    "https://lh3.example/p.png",
    "https://lh3.googleusercontent.com.evil.example/a/x",
    "https://evil.example/lh3.googleusercontent.com/a/x",
    "https://user@lh3.googleusercontent.com/a/x",
    "https://lh3.googleusercontent.com:8443/a/x",
    "https://lh3.googleusercontent.com/a/x?u=https://evil.example",
    "https://images.ntripi.app/avatars/x.jpg",
])
def test_photo_source_refuses_anything_else(url):
    assert google_avatar.photo_source(url) is None


class _Answer:
    def __init__(self, status: int, body: bytes = b"", raises: Exception | None = None):
        self.status_code = status
        self._body = body
        self._raises = raises

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def iter_content(self, size):
        if self._raises:
            raise self._raises
        for start in range(0, len(self._body), size):
            yield self._body[start:start + size]


def _answer(monkeypatch, answer: _Answer) -> list[dict]:
    calls: list[dict] = []

    def fake_get(url, **kwargs):
        calls.append({"url": url, **kwargs})
        return answer

    monkeypatch.setattr(google_avatar.requests, "get", fake_get)
    return calls


def test_fetch_reads_a_200_without_following_a_redirect(monkeypatch):
    calls = _answer(monkeypatch, _Answer(200, b"photo"))
    assert google_avatar._fetch("https://lh3.googleusercontent.com/a/x=s800-c") == b"photo"
    assert calls[0]["allow_redirects"] is False
    assert calls[0]["timeout"] == google_avatar.FETCH_TIMEOUT_SECONDS


@pytest.mark.parametrize("answer", [
    _Answer(302), _Answer(404), _Answer(500),
    _Answer(200, b"x" * (10 * 1024 * 1024 + 1)),
])
def test_fetch_gives_nothing_for_anything_but_a_photo(monkeypatch, answer):
    _answer(monkeypatch, answer)
    assert google_avatar._fetch("https://lh3.googleusercontent.com/a/x") is None


def test_fetch_gives_nothing_on_a_network_error(monkeypatch):
    def broken(url, **kwargs):
        raise requests.ConnectionError("down")

    monkeypatch.setattr(google_avatar.requests, "get", broken)
    assert google_avatar._fetch("https://lh3.googleusercontent.com/a/x") is None


# ---------------------------------------------------------------------------
# The sign-up's photo
# ---------------------------------------------------------------------------

def test_the_photo_is_copied_in_as_an_800_px_avatar(client, monkeypatch, store, fetched):
    _patch_google(monkeypatch, email="jane@gmail.com", picture=PHOTO)
    body = _google(client)

    assert fetched == ["https://lh3.googleusercontent.com/a/ACg8ocJxYz123=s800-c"]
    avatar = _user("jane@gmail.com").avatar_url
    assert avatar.startswith(f"/uploads/avatars/{body['user_id']}.jpg?v=")
    stored = Image.open(io.BytesIO(
        (store / "avatars" / f"{body['user_id']}.jpg").read_bytes()))
    assert stored.size == (800, 800)


def test_a_refused_photo_leaves_no_avatar(client, monkeypatch, store, fetched):
    _enable_moderation(monkeypatch)
    _stub_rekognition(monkeypatch, labels=[
        {"Name": "Explicit Nudity", "ParentName": "", "Confidence": 95.0},
    ])
    _patch_google(monkeypatch, email="jane@gmail.com", picture=PHOTO)
    body = _google(client)

    assert body["username"] == "jane"
    assert _user("jane@gmail.com").avatar_url is None
    assert not (store / "avatars" / f"{body['user_id']}.jpg").exists()


def test_an_unreachable_photo_leaves_no_avatar(client, monkeypatch, store):
    monkeypatch.setattr(google_avatar, "_fetch", lambda source: None)
    _patch_google(monkeypatch, email="jane@gmail.com", picture=PHOTO)
    _google(client)
    assert _user("jane@gmail.com").avatar_url is None


def test_a_photo_off_googles_host_is_never_fetched(client, monkeypatch, store, fetched):
    _patch_google(monkeypatch, email="jane@gmail.com", picture="https://evil.example/p.png")
    _google(client)
    assert fetched == []
    assert _user("jane@gmail.com").avatar_url is None


def test_a_returning_sign_in_fetches_nothing(client, monkeypatch, store, fetched):
    _patch_google(monkeypatch, email="jane@gmail.com", picture=PHOTO, sub="g-jane")
    _google(client)
    fetched.clear()
    _google(client)
    assert fetched == []
