"""
test_account_service.py — the one erase function, called directly.

account_service.erase_account is what DELETE /users/me, the /delete-account web
flow and the sweep all hand an account to. These tests build their rows in the
ORM (no bcrypt-slow registrations) and call it as the routes do:

  TestEraseAccount        — counters on both sides, ratings kept with their text,
                            images erased except evidence, the suspended
                            account's sign-up block, a second erasure a no-op.
  TestErasureBlocked      — the open-escalation predicate, each target kind.
  TestDeferredErasures    — the sweep's half: only free accounts, never starved.
  TestSignupBlock         — the keyed hash, case-insensitive, liftable.
"""

import asyncio
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select

from app.models.follow import Follow, FollowStatus
from app.models.itinerary import Itinerary
from app.models.itinerary_rating import ItineraryRating
from app.models.legal_escalation import LegalEscalation
from app.models.signup_block import SignupBlock
from app.models.user import User
from app.services import account_service
from app.storage.factory import storage

from conftest import TestingSessionLocal


@pytest.fixture()
def db(client):
    """A session on the per-test database (the client fixture creates it)."""
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()


def _user(db, name: str, **fields) -> User:
    user = User(username=name, username_lower=name, email=f"{name}@x.com", **fields)
    db.add(user)
    db.flush()
    return user


def _follow(db, follower: User, followed: User, status=FollowStatus.accepted) -> None:
    db.add(Follow(follower_id=follower.id, following_id=followed.id, status=status))


def _trip(db, owner: User, **fields) -> Itinerary:
    trip = Itinerary(user_id=owner.id, title="Trip", **fields)
    db.add(trip)
    db.flush()
    return trip


def _escalate(db, target_type: str, target_id, *, closed=False) -> LegalEscalation:
    row = LegalEscalation(
        target_type=target_type, target_id=target_id, source="report",
        closed_at=datetime.now(timezone.utc) if closed else None,
    )
    db.add(row)
    db.flush()
    return row


def _store(key: str) -> None:
    asyncio.run(storage().save(key, b"jpeg-bytes", "image/jpeg"))


def _stored(key: str) -> bool:
    return asyncio.run(storage().read(key)) is not None


def _gone(db, user_id) -> bool:
    db.expire_all()
    return db.get(User, user_id) is None


# ---------------------------------------------------------------------------
# The erasure
# ---------------------------------------------------------------------------

class TestEraseAccount:
    def test_counters_drop_on_both_sides_and_never_below_zero(self, db):
        leaving = _user(db, "leaving", followers_count=1, following_count=2)
        followed = _user(db, "followed", followers_count=3)
        drifted = _user(db, "drifted", followers_count=0)  # already wrong
        follower = _user(db, "follower", following_count=1)
        asking = _user(db, "asking", following_count=0)
        _follow(db, leaving, followed)
        _follow(db, leaving, drifted)
        _follow(db, follower, leaving)
        _follow(db, asking, leaving, status=FollowStatus.pending)  # never counted
        db.commit()

        assert account_service.erase_account(db, leaving) is True

        db.expire_all()
        assert db.get(User, followed.id).followers_count == 2
        assert db.get(User, drifted.id).followers_count == 0
        assert db.get(User, follower.id).following_count == 0
        assert db.get(User, asking.id).following_count == 0
        assert db.execute(select(Follow)).scalars().all() == []

    def test_ratings_survive_without_their_author_but_with_their_text(self, db):
        owner = _user(db, "owner")
        rater = _user(db, "rater")
        trip = _trip(db, owner)
        db.add(ItineraryRating(
            itinerary_id=trip.id, user_id=rater.id, stars=4, note="Lovely walk",
        ))
        db.commit()

        account_service.erase_account(db, rater)

        rating = db.execute(select(ItineraryRating)).scalar_one()
        assert rating.user_id is None
        assert (rating.stars, rating.note) == (4, "Lovely walk")

    def test_the_accounts_images_are_erased(self, db):
        user = _user(db, "pictured", avatar_url="/uploads/a.jpg", cover_image_url="/uploads/c.jpg")
        trip = _trip(db, user, cover_image_url="/uploads/t.jpg")
        db.commit()
        keys = (f"avatars/{user.id}.jpg", f"covers/{user.id}.jpg", f"itineraries/{trip.id}.jpg")
        for key in keys:
            _store(key)

        account_service.erase_account(db, user)

        assert [_stored(key) for key in keys] == [False, False, False]

    def test_nothing_is_erased_while_the_account_itself_is_escalated(self, db):
        user = _user(db, "evidence", avatar_url="/uploads/a.jpg")
        trip = _trip(db, user, cover_image_url="/uploads/t.jpg")
        _escalate(db, "user", user.id)
        db.commit()
        keys = (f"avatars/{user.id}.jpg", f"itineraries/{trip.id}.jpg")
        for key in keys:
            _store(key)

        account_service.erase_account(db, user)

        assert [_stored(key) for key in keys] == [True, True]
        for key in keys:
            asyncio.run(storage().delete(key))

    def test_a_taken_down_or_escalated_trip_keeps_its_cover(self, db):
        user = _user(db, "mixed")
        plain = _trip(db, user, cover_image_url="/uploads/p.jpg")
        hidden = _trip(db, user, cover_image_url="/uploads/h.jpg", moderation_status="hidden")
        escalated = _trip(db, user, cover_image_url="/uploads/e.jpg")
        _escalate(db, "itinerary", escalated.id)
        db.commit()
        # Keys first: the rows are gone (and their attributes unloadable) after.
        plain_key, *kept_keys = (
            f"itineraries/{trip.id}.jpg" for trip in (plain, hidden, escalated)
        )
        for key in (plain_key, *kept_keys):
            _store(key)

        account_service.erase_account(db, user)

        assert not _stored(plain_key)
        for key in kept_keys:
            assert _stored(key)
            asyncio.run(storage().delete(key))

    def test_a_suspended_account_leaves_a_signup_block(self, db):
        user = _user(db, "banned", is_active=False)
        db.commit()

        account_service.erase_account(db, user)

        assert account_service.is_signup_blocked(db, "banned@x.com")
        # The block holds a keyed hash, never the address.
        stored = db.execute(select(SignupBlock.email_hash)).scalar_one()
        assert "banned" not in stored and len(stored) == 64

    def test_an_active_account_leaves_no_block(self, db):
        user = _user(db, "leaver")
        db.commit()

        account_service.erase_account(db, user)

        assert db.execute(select(SignupBlock)).scalars().all() == []

    def test_a_second_erasure_of_the_same_account_changes_nothing(self, db):
        leaving = _user(db, "twice")
        followed = _user(db, "star", followers_count=1)
        _follow(db, leaving, followed)
        db.commit()
        stale = TestingSessionLocal()
        try:
            stale_user = stale.get(User, leaving.id)  # loaded before the first erasure
            assert account_service.erase_account(db, leaving) is True
            assert account_service.erase_account(stale, stale_user) is False
        finally:
            stale.close()

        db.expire_all()
        assert db.get(User, followed.id).followers_count == 0  # once, not twice


# ---------------------------------------------------------------------------
# The open-escalation predicate
# ---------------------------------------------------------------------------

class TestErasureBlocked:
    def test_an_escalation_on_the_account_holds_it(self, db):
        user = _user(db, "held")
        _escalate(db, "user", user.id)
        assert account_service.erasure_blocked(db, user)

    def test_an_escalation_on_a_trip_it_owns_holds_it(self, db):
        user = _user(db, "owner")
        _escalate(db, "itinerary", _trip(db, user).id)
        assert account_service.erasure_blocked(db, user)

    def test_an_escalation_on_a_review_it_wrote_holds_it(self, db):
        author = _user(db, "reviewer")
        rating = ItineraryRating(itinerary_id=_trip(db, _user(db, "host")).id,
                                 user_id=author.id, stars=1)
        db.add(rating)
        db.flush()
        _escalate(db, "rating", rating.id)
        assert account_service.erasure_blocked(db, author)

    def test_a_closed_escalation_holds_nothing(self, db):
        user = _user(db, "cleared")
        _escalate(db, "user", user.id, closed=True)
        assert not account_service.erasure_blocked(db, user)

    def test_someone_elses_escalated_trip_holds_nothing(self, db):
        """The regression: an uncorrelated inner EXISTS matched any owner."""
        user = _user(db, "bystander")
        other = _user(db, "other")
        _escalate(db, "itinerary", _trip(db, other).id)
        db.commit()
        assert not account_service.erasure_blocked(db, user)

        user.erasure_requested_at = datetime.now(timezone.utc)
        db.commit()
        assert account_service.pending_erasures(db) == [(user, False)]


# ---------------------------------------------------------------------------
# The sweep's half
# ---------------------------------------------------------------------------

class TestDeferredErasures:
    def test_only_accounts_no_escalation_holds_are_erased_and_told(self, db, monkeypatch):
        sent = []
        monkeypatch.setattr(
            "app.services.email_service.send_email",
            lambda to, subject, html: sent.append((to, subject, html)),
        )
        now = datetime.now(timezone.utc)
        held = _user(db, "held", erasure_requested_at=now, erasure_request_lang="en")
        free = _user(db, "free", erasure_requested_at=now, erasure_request_lang="fr")
        _escalate(db, "user", held.id)
        db.commit()

        from app.config import get_settings
        assert account_service.erase_deferred(db, get_settings()) == 1

        assert not _gone(db, held.id)
        assert _gone(db, free.id)
        [(to, subject, html)] = sent
        assert to == "free@x.com"
        assert subject == "Votre compte Ntripi a été supprimé"
        assert "/help/your-data-and-privacy?lang=fr#what-deletion-keeps" in html

    def test_images_go_on_the_thread_the_in_process_sweep_runs_on(self, db):
        """main.py runs the sweep through asyncio.to_thread, where
        anyio.from_thread.run raises — with it, every deferred erasure kept every
        image, silently. This is why the deletes go through delete_from_sync."""
        user = _user(db, "swept", avatar_url="/uploads/a.jpg",
                     erasure_requested_at=datetime.now(timezone.utc))
        db.commit()
        key = f"avatars/{user.id}.jpg"
        _store(key)

        from app.config import get_settings
        erased = asyncio.run(asyncio.to_thread(
            account_service.erase_deferred, db, get_settings(),
        ))

        assert erased == 1
        assert not _stored(key)

    def test_held_accounts_never_starve_the_batch(self, db, monkeypatch):
        monkeypatch.setattr(account_service, "DEFERRED_ERASURE_BATCH", 1)
        oldest = datetime.now(timezone.utc) - timedelta(days=30)
        held = _user(db, "held", erasure_requested_at=oldest)
        free = _user(db, "free", erasure_requested_at=oldest + timedelta(days=1))
        _escalate(db, "user", held.id)
        db.commit()

        from app.config import get_settings
        assert account_service.erase_deferred(db, get_settings()) == 1
        assert _gone(db, free.id)


# ---------------------------------------------------------------------------
# The sign-up block
# ---------------------------------------------------------------------------

class TestSignupBlock:
    def test_the_block_ignores_case_and_spaces_and_lifts(self, db):
        user = _user(db, "gone", is_active=False)
        db.commit()
        account_service.erase_account(db, user)

        assert account_service.is_signup_blocked(db, "  GONE@x.com ")
        assert account_service.lift_signup_block(db, "gone@X.com") is True
        db.commit()
        assert not account_service.is_signup_blocked(db, "gone@x.com")
        assert account_service.lift_signup_block(db, "gone@x.com") is False

    def test_a_repeated_block_is_not_an_error(self, db):
        for _ in range(2):
            user = _user(db, "again", is_active=False)
            db.commit()
            account_service.erase_account(db, user)
        assert db.execute(select(SignupBlock)).scalars().all() != []
        assert len(db.execute(select(SignupBlock)).scalars().all()) == 1
