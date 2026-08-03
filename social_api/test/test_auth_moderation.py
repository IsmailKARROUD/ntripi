"""
test_auth_moderation.py — text moderation on the account-creation paths.

`PATCH /users/me` has always scanned display_name and bio, but the text a user
supplies at signup was never scanned, and `username` is immutable — an abusive
handle chosen at registration was permanent. These cover both signup paths, and
the asymmetry between them: a password signup is text the user typed and can
retype, so it is rejectable; a Google signup's name comes from the Google
profile, so rejecting it would lock a real person out with no way to fix it.

The provider chain is stubbed at the service module (no network, no API key).
"""

from __future__ import annotations

import pytest
from sqlalchemy import select

from conftest import TestingSessionLocal
from app.config import get_settings
from app.models.legal_escalation import LegalEscalation
from app.models.text_moderation_decision import TextModerationDecision
from app.models.user import User
from app.services import text_moderation_service as tms
from app.services.text_moderation_providers import ProviderResult


class CountingProvider:
    """Canned scores plus a call counter — "was the provider hit, and how many
    times?" is an exact assertion rather than an inference."""

    name = "stub"
    model = "stub-model"

    def __init__(self, scores: dict[str, float] | None = None):
        self.scores = scores or {}
        self.calls: list[str] = []

    def score(self, text: str) -> ProviderResult:
        self.calls.append(text)
        return ProviderResult(scores=self.scores, provider=self.name, model=self.model)


@pytest.fixture()
def provider(monkeypatch):
    monkeypatch.setattr(get_settings(), "TEXT_MODERATION_PROVIDER", "openai")
    monkeypatch.setattr(get_settings(), "OPENAI_API_KEY", "test-key")
    stub = CountingProvider()
    monkeypatch.setattr(tms, "get_provider_chain", lambda settings: [stub])
    return stub


CLEAN = {"hate": 0.01}
REVIEW = {"harassment": 0.6}
REJECT = {"hate": 0.9}
MINORS = {"sexual/minors": 0.15}


def _register(client, username="newbie", email="newbie@example.com",
              display_name="Newbie", password="test1234"):
    return client.post("/auth/register", json={
        "username": username,
        "email": email,
        "password": password,
        "display_name": display_name,
        "tos_accepted": True,
    })


def _user_or_none(email: str) -> User | None:
    db = TestingSessionLocal()
    try:
        row = db.execute(
            select(User).where(User.email == email.strip().lower())
        ).scalar_one_or_none()
        if row is not None:
            db.expunge(row)
        return row
    finally:
        db.close()


def _decisions() -> list[TextModerationDecision]:
    db = TestingSessionLocal()
    try:
        return db.query(TextModerationDecision).all()
    finally:
        db.close()


def _escalations() -> list[LegalEscalation]:
    db = TestingSessionLocal()
    try:
        return db.query(LegalEscalation).all()
    finally:
        db.close()


def _patch_google(monkeypatch, *, sub, email, name=None, email_verified=True):
    """Patch the verifier to return canned claims. It is imported into
    app.routers.auth via `from ... import`, so the name is patched there."""
    import app.routers.auth as auth_router
    monkeypatch.setattr(
        auth_router, "verify_google_id_token",
        lambda token: {
            "sub": sub, "email": email,
            "email_verified": email_verified, "name": name, "picture": None,
        },
    )


def _google(client):
    return client.post("/auth/google", json={"id_token": "fake", "tos_accepted": True})


# ---------------------------------------------------------------------------
# Default-off behaviour
# ---------------------------------------------------------------------------

def test_moderation_disabled_leaves_registration_untouched(client):
    """The shipped default must behave exactly as it did before this change."""
    response = _register(client)

    assert response.status_code == 201
    assert _user_or_none("newbie@example.com") is not None
    assert _decisions() == []


# ---------------------------------------------------------------------------
# POST /auth/register
# ---------------------------------------------------------------------------

def test_rejected_display_name_blocks_the_account(client, provider):
    """The regression guard for the ordering rule: create_user commits, so a
    rejection found afterwards could not undo the account it just made."""
    provider.scores = REJECT
    response = _register(client, display_name="vile")

    assert response.status_code == 422
    assert response.json()["code"] == "text_moderation_rejected"
    assert _user_or_none("newbie@example.com") is None


def test_rejected_username_blocks_the_account(client, provider):
    """username is immutable after signup, so registration is the only chance
    to catch it."""
    provider.scores = REJECT
    response = _register(client, username="vileword")

    assert response.status_code == 422
    assert _user_or_none("newbie@example.com") is None


def test_rejection_names_categories_without_echoing_the_text(client, provider):
    provider.scores = REJECT
    response = _register(client, display_name="something vile")

    body = response.json()
    assert "hate" in body["categories"]
    assert "vile" not in str(body)


def test_flagged_display_name_still_creates_the_account(client, provider):
    """'review' is a queue entry, not a gate — the account is created and the
    moderator decides later."""
    provider.scores = REVIEW
    response = _register(client, display_name="borderline")

    assert response.status_code == 201
    user = _user_or_none("newbie@example.com")
    assert user is not None
    assert user.moderation_status == "flagged"


def test_the_decision_points_at_the_new_account(client, provider):
    """The scan runs before the user exists, so without the backfill the queue
    would show a flag with nothing to review."""
    provider.scores = REVIEW
    _register(client)

    user = _user_or_none("newbie@example.com")
    decisions = _decisions()
    assert len(decisions) == 1
    assert decisions[0].target_type == "user"
    assert decisions[0].target_id == user.id


def test_username_and_display_name_cost_one_call(client, provider):
    _register(client, username="traveller", display_name="Jane Traveller")

    assert len(provider.calls) == 1
    assert "traveller" in provider.calls[0]
    assert "Jane Traveller" in provider.calls[0]


def test_clean_registration_is_approved(client, provider):
    provider.scores = CLEAN
    assert _register(client).status_code == 201
    assert _user_or_none("newbie@example.com").moderation_status == "approved"


def test_minors_score_at_registration_escalates(client, provider):
    provider.scores = MINORS
    response = _register(client, display_name="...")

    assert response.status_code == 201
    user = _user_or_none("newbie@example.com")
    assert user.moderation_status == "hidden"

    escalations = _escalations()
    assert len(escalations) == 1
    assert escalations[0].target_type == "user"
    assert escalations[0].target_id == user.id


def test_provider_outage_does_not_block_signup(client, monkeypatch):
    """A vendor outage must never stop people creating accounts."""
    monkeypatch.setattr(get_settings(), "TEXT_MODERATION_PROVIDER", "openai")
    monkeypatch.setattr(get_settings(), "OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(tms, "get_provider_chain", lambda settings: [])

    assert _register(client).status_code == 201
    assert _user_or_none("newbie@example.com").moderation_status == "pending"


def test_a_duplicate_username_is_still_rejected(client, provider):
    """Moderation runs first, so the ordinary 409 must still get through."""
    _register(client, username="taken", email="first@example.com")
    response = _register(client, username="taken", email="second@example.com")

    assert response.status_code == 409


# ---------------------------------------------------------------------------
# POST /auth/google — scanned, but never rejected
# ---------------------------------------------------------------------------

def test_google_name_that_would_be_rejected_drops_the_name(client, provider, monkeypatch):
    """The name is Google's, not something the user typed here — dropping it is
    the same fallback validate_display_name already uses."""
    provider.scores = REJECT
    _patch_google(monkeypatch, sub="g-vile", email="vile@gmail.com", name="vile")

    response = _google(client)

    assert response.status_code == 200, response.json()
    user = _user_or_none("vile@gmail.com")
    assert user is not None
    assert user.display_name is None
    # The offending text was never stored, so the profile itself is clean.
    assert user.moderation_status == "approved"
    # It is still on the record.
    assert len(_decisions()) == 1


def test_google_flagged_name_is_kept_and_queued(client, provider, monkeypatch):
    provider.scores = REVIEW
    _patch_google(monkeypatch, sub="g-bord", email="bord@gmail.com", name="Borderline")

    assert _google(client).status_code == 200
    user = _user_or_none("bord@gmail.com")
    assert user.display_name == "Borderline"
    assert user.moderation_status == "flagged"


def test_google_clean_name_is_approved(client, provider, monkeypatch):
    provider.scores = CLEAN
    _patch_google(monkeypatch, sub="g-ok", email="ok@gmail.com", name="Jane Doe")

    assert _google(client).status_code == 200
    user = _user_or_none("ok@gmail.com")
    assert user.display_name == "Jane Doe"
    assert user.moderation_status == "approved"


def test_returning_google_user_costs_no_call(client, provider, monkeypatch):
    """Only the brand-new-account branch writes display_name, so a sign-in must
    never spend a paid moderation call."""
    _patch_google(monkeypatch, sub="g-repeat", email="repeat@gmail.com", name="Jane")
    _google(client)
    provider.calls.clear()

    assert _google(client).status_code == 200
    assert provider.calls == []


def test_google_signup_without_a_name_costs_no_call(client, provider, monkeypatch):
    _patch_google(monkeypatch, sub="g-noname", email="noname@gmail.com", name=None)

    assert _google(client).status_code == 200
    assert provider.calls == []
    assert _user_or_none("noname@gmail.com").moderation_status == "approved"


def test_linking_google_to_an_existing_account_costs_no_call(client, provider):
    """Branch 2 never touches display_name either."""
    _register(client, email="link@example.com", username="linkme")
    provider.calls.clear()

    import app.routers.auth as auth_router
    original = auth_router.verify_google_id_token
    auth_router.verify_google_id_token = lambda token: {
        "sub": "g-link", "email": "link@example.com",
        "email_verified": True, "name": "Renamed", "picture": None,
    }
    try:
        assert _google(client).status_code == 200
    finally:
        auth_router.verify_google_id_token = original

    assert provider.calls == []
