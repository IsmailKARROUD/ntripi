"""
test_text_moderation_service.py — the text-moderation orchestrator.

Exercises the service directly against the SQLite test DB (no HTTP): cache
behaviour, the provider fallback chain, the four content states, and the
privacy guarantees that make the audit trail safe to keep.

Providers are stubbed by monkeypatching get_provider_chain as imported into
text_moderation_service — the same idiom test_image_moderation uses for the
Rekognition client, so no network is ever touched.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from conftest import TestingSessionLocal, register_user
from app.config import get_settings
from app.models.text_moderation_cache import TextModerationCache
from app.models.text_moderation_decision import TextModerationDecision
from app.models.user import User
from app.services import text_moderation_service as tms
from app.services.moderation_policy import POLICY_VERSION
from app.services.text_moderation_providers import (
    ProviderResult, ProviderUnavailableError,
)


# ---------------------------------------------------------------------------
# Fixtures and helpers
# ---------------------------------------------------------------------------

@pytest.fixture()
def db(client):
    """A session against the same fresh in-memory DB the client fixture built.
    Depending on `client` gets table creation and teardown for free."""
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture()
def author(client, db) -> User:
    register_user(client, username="writer", email="writer@example.com")
    return db.query(User).filter(User.username_lower == "writer").one()


@pytest.fixture(autouse=True)
def reset_degradation_throttle():
    """The cooldown map is module-global; clear it so one test's alert doesn't
    suppress the next test's."""
    tms._last_degradation_notice.clear()
    yield
    tms._last_degradation_notice.clear()


class StubProvider:
    """Returns canned scores, or raises to simulate an outage. Records how many
    times it was called so cache-hit assertions are exact."""

    def __init__(self, scores=None, *, name="stub", model="stub-model", raises=False):
        self.scores = scores or {}
        self.name = name
        self.model = model
        self._raises = raises
        self.calls: list[str] = []

    def score(self, text: str) -> ProviderResult:
        self.calls.append(text)
        if self._raises:
            raise ProviderUnavailableError("simulated outage")
        return ProviderResult(scores=self.scores, provider=self.name, model=self.model)


def _use_chain(monkeypatch, *providers) -> None:
    monkeypatch.setattr(tms, "get_provider_chain", lambda settings: list(providers))


def _enable(monkeypatch, provider: str = "openai") -> None:
    s = get_settings()
    monkeypatch.setattr(s, "TEXT_MODERATION_PROVIDER", provider)
    monkeypatch.setattr(s, "OPENAI_API_KEY", "test-key")


def _capture_emails(monkeypatch) -> list[dict]:
    sent: list[dict] = []
    monkeypatch.setattr(
        "app.services.text_moderation_service.send_email",
        lambda to, subject, html: sent.append(
            {"to": to, "subject": subject, "html": html}
        ),
    )
    return sent


def _ctx(db, author, **kwargs) -> tms.TextModerationContext:
    return tms.TextModerationContext(
        db=db, settings=get_settings(), target_type="itinerary", author=author, **kwargs
    )


# ---------------------------------------------------------------------------
# Disabled by default
# ---------------------------------------------------------------------------

def test_disabled_provider_scans_nothing(client, db, author, monkeypatch):
    """The default configuration must behave exactly as before this feature."""
    monkeypatch.setattr(get_settings(), "TEXT_MODERATION_PROVIDER", "disabled")
    stub = StubProvider({"hate": 0.99})
    _use_chain(monkeypatch, stub)

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": "anything at all"}, ctx)

    assert ctx.status == "approved"
    assert stub.calls == []
    assert db.query(TextModerationDecision).count() == 0
    assert db.query(TextModerationCache).count() == 0


def test_empty_fields_skip_the_provider(client, db, author, monkeypatch):
    """A PATCH that only clears a field has nothing to scan and must not burn
    a paid call."""
    _enable(monkeypatch)
    stub = StubProvider()
    _use_chain(monkeypatch, stub)

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": None, "description": "   "}, ctx)

    assert ctx.status == "approved"
    assert stub.calls == []


# ---------------------------------------------------------------------------
# The four outcomes
# ---------------------------------------------------------------------------

def test_clean_text_is_approved_and_logged(client, db, author, monkeypatch):
    _enable(monkeypatch)
    _use_chain(monkeypatch, StubProvider({"hate": 0.01}))

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": "A walk in Ghent"}, ctx)
    db.commit()

    assert ctx.status == "approved"
    row = db.query(TextModerationDecision).one()
    assert row.outcome == "approve"
    assert row.policy_version == POLICY_VERSION
    assert row.source == "write"


def test_review_outcome_flags_and_queues(client, db, author, monkeypatch):
    _enable(monkeypatch)
    _use_chain(monkeypatch, StubProvider({"harassment": 0.6}))

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"description": "borderline"}, ctx)
    db.commit()

    assert ctx.status == "flagged"
    row = db.query(TextModerationDecision).one()
    assert row.outcome == "review"
    assert row.reviewed_at is None  # NULL = sitting in the moderator queue


def test_self_harm_review_carries_its_queue_label(client, db, author, monkeypatch):
    _enable(monkeypatch)
    _use_chain(monkeypatch, StubProvider({"self-harm/intent": 0.4}))

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"description": "..."}, ctx)
    db.commit()

    assert ctx.status == "flagged"
    assert db.query(TextModerationDecision).one().queue_label == "self_harm"


def test_minors_score_sets_hidden_and_escalate_flag(client, db, author, monkeypatch):
    _enable(monkeypatch)
    _use_chain(monkeypatch, StubProvider({"sexual/minors": 0.15}))

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"description": "..."}, ctx)
    db.commit()

    assert ctx.status == "hidden"
    assert ctx.escalate is True
    assert db.query(TextModerationDecision).one().outcome == "hide_escalate"


def test_reject_raises_and_survives_caller_rollback(client, db, author, monkeypatch):
    """The decision row is committed before the raise, so the router's 422
    rollback cannot erase the evidence that we blocked the write."""
    _enable(monkeypatch)
    _use_chain(monkeypatch, StubProvider({"hate": 0.9}))

    ctx = _ctx(db, author)
    with pytest.raises(tms.TextModerationRejectedError) as excinfo:
        tms.moderate_fields_or_raise({"description": "vile"}, ctx)

    assert "hate" in excinfo.value.categories
    assert ctx.status == "rejected"

    db.rollback()  # what the router does on its way to a 422
    verify = TestingSessionLocal()
    try:
        row = verify.query(TextModerationDecision).one()
        assert row.outcome == "reject"
    finally:
        verify.close()


def test_rejection_error_carries_categories_not_text(client, db, author, monkeypatch):
    _enable(monkeypatch)
    _use_chain(monkeypatch, StubProvider({"hate": 0.9}))

    secret = "the offending sentence"
    ctx = _ctx(db, author)
    with pytest.raises(tms.TextModerationRejectedError) as excinfo:
        tms.moderate_fields_or_raise({"description": secret}, ctx)

    assert secret not in str(excinfo.value)
    assert secret not in repr(excinfo.value.categories)


# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------

def test_identical_text_is_not_resubmitted(client, db, author, monkeypatch):
    _enable(monkeypatch)
    stub = StubProvider({"hate": 0.01})
    _use_chain(monkeypatch, stub)

    for _ in range(3):
        ctx = _ctx(db, author)
        tms.moderate_fields_or_raise({"title": "Same trip title"}, ctx)
        db.commit()
        assert ctx.status == "approved"

    assert len(stub.calls) == 1  # one paid call for three identical writes
    assert db.query(TextModerationDecision).count() == 3  # every scan still audited


def test_cache_row_holds_no_text_and_no_user_reference(client, db, author, monkeypatch):
    _enable(monkeypatch)
    _use_chain(monkeypatch, StubProvider({"hate": 0.01}))

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": "Bruges in October"}, ctx)
    db.commit()

    row = db.query(TextModerationCache).one()
    serialized = f"{row.cache_key}{row.outcome}{row.scores}{row.provider}{row.model}"
    assert "Bruges" not in serialized
    assert str(author.id) not in serialized
    assert not hasattr(row, "author_user_id")


def test_decision_row_holds_no_text_email_or_display_name(client, db, author, monkeypatch):
    _enable(monkeypatch)
    _use_chain(monkeypatch, StubProvider({"hate": 0.01}))

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": "Antwerp diamond district"}, ctx)
    db.commit()

    row = db.query(TextModerationDecision).one()
    dumped = " ".join(
        str(getattr(row, column.name)) for column in row.__table__.columns
    )
    assert "Antwerp" not in dumped
    assert author.email not in dumped
    assert author.username not in dumped


def test_model_change_invalidates_cached_verdicts(client, db, author, monkeypatch):
    """Swapping the model must not reuse the old model's verdicts."""
    _enable(monkeypatch)
    stub = StubProvider({"hate": 0.01})
    _use_chain(monkeypatch, stub)

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": "Same text"}, ctx)
    db.commit()

    monkeypatch.setattr(get_settings(), "TEXT_MODERATION_MODEL", "some-newer-model")
    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": "Same text"}, ctx)
    db.commit()

    assert len(stub.calls) == 2


def test_policy_version_change_invalidates_cached_verdicts(
    client, db, author, monkeypatch
):
    """Bumping POLICY_VERSION is the documented way to invalidate the cache
    after a threshold edit — prove the key actually moves."""
    _enable(monkeypatch)
    stub = StubProvider({"hate": 0.01})
    _use_chain(monkeypatch, stub)

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": "Same text"}, ctx)
    db.commit()

    monkeypatch.setattr(tms, "POLICY_VERSION", "99")
    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": "Same text"}, ctx)
    db.commit()

    assert len(stub.calls) == 2


def test_expired_cache_entries_are_purged_and_not_reused(client, db, author, monkeypatch):
    _enable(monkeypatch)
    stub = StubProvider({"hate": 0.01})
    _use_chain(monkeypatch, stub)

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": "Cached text"}, ctx)
    db.commit()

    row = db.query(TextModerationCache).one()
    row.expires_at = datetime.now(timezone.utc) - timedelta(days=1)
    db.commit()

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": "Cached text"}, ctx)
    db.commit()

    assert len(stub.calls) == 2
    assert db.query(TextModerationCache).count() == 1  # stale row gone, fresh one stored


def test_fields_written_together_are_one_call(client, db, author, monkeypatch):
    _enable(monkeypatch)
    stub = StubProvider({"hate": 0.01})
    _use_chain(monkeypatch, stub)

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise(
        {"place_name": "Grote Markt", "place_address": "Brussels", "notes": "Go early"},
        ctx,
    )

    assert len(stub.calls) == 1
    assert "Grote Markt" in stub.calls[0] and "Go early" in stub.calls[0]


# ---------------------------------------------------------------------------
# Provider chain degradation
# ---------------------------------------------------------------------------

def test_primary_failure_falls_back_to_the_next_provider(client, db, author, monkeypatch):
    _enable(monkeypatch)
    primary = StubProvider(name="openai", raises=True)
    fallback = StubProvider({"hate": 0.01}, name="local", model="alt-profanity-check")
    _use_chain(monkeypatch, primary, fallback)

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": "Ordinary text"}, ctx)
    db.commit()

    assert ctx.status == "approved"
    assert db.query(TextModerationDecision).one().provider == "local"


def test_fallback_notifies_the_operator(client, db, author, monkeypatch):
    """A silent permanent downgrade to the wordlist would be worse than the
    outage itself."""
    _enable(monkeypatch)
    monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", "ops@ntripi.app")
    sent = _capture_emails(monkeypatch)
    _use_chain(
        monkeypatch,
        StubProvider(name="openai", raises=True),
        StubProvider({"hate": 0.01}, name="local"),
    )

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": "Ordinary text"}, ctx)

    assert len(sent) == 1
    assert "fallback" in sent[0]["subject"].lower()


def test_total_outage_publishes_as_pending_never_approved(client, db, author, monkeypatch):
    _enable(monkeypatch)
    _use_chain(
        monkeypatch,
        StubProvider(name="openai", raises=True),
        StubProvider(name="local", raises=True),
    )

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": "Ordinary text"}, ctx)  # must not raise
    db.commit()

    assert ctx.status == "pending"
    row = db.query(TextModerationDecision).one()
    assert row.outcome == "pending"
    assert row.provider is None
    assert row.scores == {}


def test_outage_notifies_the_operator(client, db, author, monkeypatch):
    _enable(monkeypatch)
    monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", "ops@ntripi.app")
    sent = _capture_emails(monkeypatch)
    _use_chain(monkeypatch, StubProvider(name="openai", raises=True))

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": "Ordinary text"}, ctx)

    assert len(sent) == 1
    assert "pending" in sent[0]["subject"].lower()


def test_degradation_alerts_are_throttled(client, db, author, monkeypatch):
    """An outage during a busy hour must send one email, not one per write."""
    _enable(monkeypatch)
    monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", "ops@ntripi.app")
    sent = _capture_emails(monkeypatch)
    _use_chain(monkeypatch, StubProvider(name="openai", raises=True))

    for index in range(5):
        ctx = _ctx(db, author)
        tms.moderate_fields_or_raise({"title": f"Distinct text {index}"}, ctx)

    assert len(sent) == 1


def test_degradation_email_contains_no_user_text(client, db, author, monkeypatch):
    _enable(monkeypatch)
    monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", "ops@ntripi.app")
    sent = _capture_emails(monkeypatch)
    _use_chain(monkeypatch, StubProvider(name="openai", raises=True))

    secret = "my private travel notes"
    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"description": secret}, ctx)

    assert secret not in sent[0]["html"]


def test_missing_operator_email_does_not_break_the_write(client, db, author, monkeypatch):
    _enable(monkeypatch)
    monkeypatch.setattr(get_settings(), "OPERATOR_EMAIL", None)
    _use_chain(monkeypatch, StubProvider(name="openai", raises=True))

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": "Ordinary text"}, ctx)

    assert ctx.status == "pending"


def test_provider_raising_an_unexpected_error_is_still_survivable(
    client, db, author, monkeypatch
):
    """A provider bug (not just a network error) must degrade, not 500."""
    class ExplodingProvider(StubProvider):
        def score(self, text):
            raise ValueError("bug in provider code")

    _enable(monkeypatch)
    _use_chain(monkeypatch, ExplodingProvider(name="openai"))

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": "Ordinary text"}, ctx)

    assert ctx.status == "pending"


# ---------------------------------------------------------------------------
# Status merge
# ---------------------------------------------------------------------------

class _Record:
    def __init__(self, status="approved"):
        self.moderation_status = status


@pytest.mark.parametrize("current,incoming,expected", [
    ("approved", "flagged", "flagged"),
    ("approved", "pending", "pending"),
    ("flagged", "approved", "flagged"),   # a clean edit must not clear a flag
    ("pending", "approved", "pending"),
    ("hidden", "flagged", "hidden"),
    ("flagged", "hidden", "hidden"),
    ("rejected", "flagged", "rejected"),
])
def test_apply_moderation_status_only_escalates(current, incoming, expected):
    record = _Record(current)
    tms.apply_moderation_status(record, incoming)
    assert record.moderation_status == expected


def test_apply_moderation_status_handles_missing_value():
    record = _Record(None)
    tms.apply_moderation_status(record, "flagged")
    assert record.moderation_status == "flagged"


# ---------------------------------------------------------------------------
# Retention
# ---------------------------------------------------------------------------

def test_retention_purge_never_empties_the_moderator_queue(
    client, db, author, monkeypatch
):
    """Old rows are dropped for data minimization, but an unreviewed row is a
    queue item — losing it would silently drop a pending case."""
    _enable(monkeypatch)
    _use_chain(monkeypatch, StubProvider({"hate": 0.01}))

    old = datetime.now(timezone.utc) - timedelta(days=400)
    db.add_all([
        TextModerationDecision(
            content_hash="a" * 64, target_type="itinerary", outcome="review",
            scores={}, policy_version="1", source="write", created_at=old,
            reviewed_at=None,
        ),
        TextModerationDecision(
            content_hash="b" * 64, target_type="itinerary", outcome="review",
            scores={}, policy_version="1", source="write", created_at=old,
            reviewed_at=old,
        ),
    ])
    db.commit()

    ctx = _ctx(db, author)
    tms.moderate_fields_or_raise({"title": "Triggers the purge"}, ctx)
    db.commit()

    hashes = {row.content_hash for row in db.query(TextModerationDecision).all()}
    assert "a" * 64 in hashes       # unreviewed: kept
    assert "b" * 64 not in hashes   # reviewed and expired: purged
