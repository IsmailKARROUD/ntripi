"""
services/edit_lock_service.py — the only module that reads or writes the
itinerary edit lock.

The problem this solves is not "two people editing at once" — the ETag already
catches that after the fact. It is that a *device* can be ejected from a claim
and must find out on its next save, not on its next reload.

That is why the claim is identified by a rotating opaque token rather than by
user_id. Every takeover mints a fresh token; the ejected device still holds the
old one, still believes it is editing, and fails closed the moment it tries to
write. A user_id comparison could not express this — the same person on a second
device would look identical to the first — and a check performed only at acquire
time could not express it at all.

Nothing here trusts the client. The raw token is server-minted, returned exactly
once, and stored only as a SHA-256 hash (token_util, same treatment as refresh
and email tokens). The activity state ("active" / "idle" / "takeable") is
computed here and shipped as a word; the client renders it and counts down
against absolute timestamps, and never derives it.

Callers own the transaction: nothing here commits.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from fastapi import status
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.errors import ApiError
from app.models.itinerary import Itinerary
from app.models.itinerary_edit_lock import ItineraryEditLock
from app.models.user import User
from app.services.token_util import as_aware_utc, hash_token, new_raw_token
from app.services.user_service import public_profile_text

# The header every guarded mutation must carry. Named here so the dependency,
# the routers and the tests cannot drift apart on the spelling.
LOCK_HEADER = "X-Edit-Lock"

# Activity states, weakest claim last.
STATE_ACTIVE = "active"      # heartbeat is current
STATE_IDLE = "idle"          # gone quiet, but the claim still stands
STATE_TAKEABLE = "takeable"  # silent past the TTL — any editor may take over

# A row this far past its TTL cannot be resurrected by anyone and is only taking
# up space. The sweep deletes it; correctness never depends on that happening,
# since staleness is derived at read time.
PURGE_TTL_MULTIPLE = 24


@dataclass(frozen=True)
class LockView:
    """What an editor is allowed to know about a claim — theirs or someone
    else's. Deliberately absolute timestamps and no remaining-seconds field:
    the GET body then stays byte-identical while nothing changes, so
    ETagMiddleware answers polls with a cheap 304. A countdown integer would
    change on every request and defeat that."""

    holder_id: uuid.UUID
    holder_username: str
    holder_display_name: str | None
    holder_avatar_url: str | None
    is_you: bool
    state: str
    acquired_at: datetime
    last_heartbeat_at: datetime
    idle_at: datetime
    takeover_available_at: datetime


# ---------------------------------------------------------------------------
# Errors — one place, so the router and the write guard answer identically
# ---------------------------------------------------------------------------

def locked_error(view: LockView) -> ApiError:
    """423 — you asked to claim and someone else has it. Distinct from
    edit_lock_lost on purpose: this one is answerable by waiting or taking
    over, so the UI shows the holder and a countdown."""
    return ApiError(
        status_code=status.HTTP_423_LOCKED,
        code="itinerary_locked",
        detail="Someone else is editing this itinerary right now.",
        extra={"lock": _view_payload(view)},
    )


def lost_error(view: LockView | None) -> ApiError:
    """409 — you believed you held the claim and you do not. The client must
    protect unsaved input here, which is why it is not the same code as 423."""
    return ApiError(
        status_code=status.HTTP_409_CONFLICT,
        code="edit_lock_lost",
        detail="Your editing session was taken over. Your changes were not saved.",
        extra={"lock": _view_payload(view) if view is not None else None},
    )


def required_error() -> ApiError:
    """428 — no claim was presented at all. Mirrors if_match_required: a
    precondition the client simply failed to supply."""
    return ApiError(
        status_code=status.HTTP_428_PRECONDITION_REQUIRED,
        code="edit_lock_required",
        detail="Start an editing session before saving changes.",
    )


def _view_payload(view: LockView) -> dict:
    return {
        "holder_id": str(view.holder_id),
        "holder_username": view.holder_username,
        "holder_display_name": view.holder_display_name,
        "holder_avatar_url": view.holder_avatar_url,
        "is_you": view.is_you,
        "state": view.state,
        "acquired_at": view.acquired_at.isoformat(),
        "last_heartbeat_at": view.last_heartbeat_at.isoformat(),
        "idle_at": view.idle_at.isoformat(),
        "takeover_available_at": view.takeover_available_at.isoformat(),
    }


# ---------------------------------------------------------------------------
# State derivation
# ---------------------------------------------------------------------------

def _now() -> datetime:
    return datetime.now(timezone.utc)


def takeover_available_at(lock: ItineraryEditLock, settings) -> datetime:
    return as_aware_utc(lock.last_heartbeat_at) + timedelta(
        seconds=settings.EDIT_LOCK_TTL_SECONDS
    )


def state_of(lock: ItineraryEditLock, settings, now: datetime | None = None) -> str:
    now = now or _now()
    silent_for = now - as_aware_utc(lock.last_heartbeat_at)
    if silent_for >= timedelta(seconds=settings.EDIT_LOCK_TTL_SECONDS):
        return STATE_TAKEABLE
    if silent_for >= timedelta(seconds=settings.EDIT_LOCK_IDLE_SECONDS):
        return STATE_IDLE
    return STATE_ACTIVE


def is_live(lock: ItineraryEditLock, settings, now: datetime | None = None) -> bool:
    """A claim still standing — nobody but the owner may take it."""
    return state_of(lock, settings, now) != STATE_TAKEABLE


def to_view(
    db: Session, lock: ItineraryEditLock, viewer_id: uuid.UUID, settings,
) -> LockView:
    holder = db.get(User, lock.user_id)
    display_name, _ = public_profile_text(holder, viewer_id) if holder else (None, None)
    return LockView(
        holder_id=lock.user_id,
        holder_username=holder.username if holder else "",
        holder_display_name=display_name,
        holder_avatar_url=holder.avatar_url if holder else None,
        is_you=lock.user_id == viewer_id,
        state=state_of(lock, settings),
        acquired_at=as_aware_utc(lock.acquired_at),
        last_heartbeat_at=as_aware_utc(lock.last_heartbeat_at),
        idle_at=as_aware_utc(lock.last_heartbeat_at)
        + timedelta(seconds=settings.EDIT_LOCK_IDLE_SECONDS),
        takeover_available_at=takeover_available_at(lock, settings),
    )


# ---------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------

def get_lock(
    db: Session, itinerary_id: uuid.UUID, *, for_update: bool = False,
) -> ItineraryEditLock | None:
    stmt = select(ItineraryEditLock).where(
        ItineraryEditLock.itinerary_id == itinerary_id
    )
    if for_update:
        try:
            stmt = stmt.with_for_update()
        except Exception:
            pass  # SQLite (tests) has no FOR UPDATE — single-writer anyway
    return db.execute(stmt).scalar_one_or_none()


# ---------------------------------------------------------------------------
# Writes
# ---------------------------------------------------------------------------

def claim(
    db: Session, itinerary: Itinerary, user: User, settings, *, takeover: bool,
) -> tuple[ItineraryEditLock, str]:
    """Take the editing claim. Returns (row, RAW token) — the only time the raw
    token exists outside the client that requested it.

    `takeover` is a deliberate second call, never a default: every path that
    displaces an existing claim requires it, so a steal is always something the
    UI confirmed rather than something a retry did by accident.

    Callers must already have established that `user` may edit `itinerary`.
    """
    now = _now()
    existing = get_lock(db, itinerary.id, for_update=True)

    if existing is not None:
        may_displace = (
            not is_live(existing, settings, now)      # nobody is there any more
            or existing.user_id == user.id            # same person, other device
            or itinerary.user_id == user.id           # owner never waits
        )
        if not may_displace or not takeover:
            raise locked_error(to_view(db, existing, user.id, settings))
        db.delete(existing)
        # The new row shares the PK, so the delete has to reach the database
        # before the insert or the unique violation fires on flush.
        db.flush()

    raw = new_raw_token()
    lock = ItineraryEditLock(
        itinerary_id=itinerary.id,
        user_id=user.id,
        token_hash=hash_token(raw),
        acquired_at=now,
        last_heartbeat_at=now,
    )
    db.add(lock)
    db.flush()
    return lock, raw


def assert_holder(
    db: Session, itinerary: Itinerary, user: User, raw_token: str | None, settings,
) -> ItineraryEditLock:
    """The write path's gate. Returns the claim, or raises.

    A token that matches but whose heartbeat is past the TTL is honoured, and
    its heartbeat refreshed. Nobody took the claim, so refusing would throw away
    real work to enforce a deadline that was not holding anyone up.
    """
    if not raw_token:
        raise required_error()

    lock = get_lock(db, itinerary.id, for_update=True)
    if lock is None:
        raise lost_error(None)

    if lock.token_hash != hash_token(raw_token):
        # Whoever holds it now, this caller does not. Same answer whether they
        # were taken over or are replaying a token from a released session.
        raise lost_error(to_view(db, lock, user.id, settings))

    # The token is the identity, but a rotated-away user must never keep writing
    # through a row that outlived their grant.
    if lock.user_id != user.id:
        raise lost_error(to_view(db, lock, user.id, settings))

    return lock


def heartbeat(
    db: Session, itinerary: Itinerary, user: User, raw_token: str | None, settings,
) -> ItineraryEditLock:
    """Keep the claim alive. Same gate as a save — a ping that could not save is
    a ping that must not reassure the client."""
    lock = assert_holder(db, itinerary, user, raw_token, settings)
    touch(lock)
    return lock


def touch(lock: ItineraryEditLock) -> None:
    """Mark activity. Deliberately separate from Itinerary.updated_at: that
    column IS the concurrency ETag, and a heartbeat that moved it would 412
    every open client once a minute."""
    lock.last_heartbeat_at = _now()


def release(
    db: Session, itinerary: Itinerary, user: User, raw_token: str | None, settings,
) -> bool:
    """Give up the claim. Returns whether a row was removed.

    Idempotent and never raises for a missing or foreign claim: the client fires
    this from teardown, so a retry, or a claim the TTL already gave to somebody
    else, must not surface an error for something the user has finished with.
    The owner may release without a token — that is the "unlock it from my other
    device" path.
    """
    lock = get_lock(db, itinerary.id, for_update=True)
    if lock is None:
        return False

    is_owner = itinerary.user_id == user.id
    holds_token = bool(raw_token) and lock.token_hash == hash_token(raw_token)
    if not (is_owner or holds_token):
        return False

    db.delete(lock)
    return True


def release_for_user(db: Session, itinerary_id: uuid.UUID, user_id: uuid.UUID) -> None:
    """Drop `user_id`'s claim on this itinerary, if they hold it. Used when a
    grant is revoked: leaving a removed editor's claim standing would block
    everyone else until the TTL ran out."""
    db.execute(
        delete(ItineraryEditLock).where(
            ItineraryEditLock.itinerary_id == itinerary_id,
            ItineraryEditLock.user_id == user_id,
        )
    )


def purge_expired(db: Session, settings) -> int:
    """Delete claims long past any possible revival. Housekeeping only — a row
    that survives this is still correctly reported as `takeable`. Does not
    commit; the sweep owns the transaction."""
    cutoff = _now() - timedelta(
        seconds=settings.EDIT_LOCK_TTL_SECONDS * PURGE_TTL_MULTIPLE
    )
    result = db.execute(
        delete(ItineraryEditLock).where(
            ItineraryEditLock.last_heartbeat_at < cutoff
        )
    )
    return result.rowcount or 0
