"""
services/user_service.py — Shared user + follow-relationship helpers.

These small queries were duplicated across the users, follows, and itineraries
routers. Centralizing them keeps the 404 shapes, the `username_lower` lookup
rule, and the denormalized follow-counter invariant in one place.
"""

from __future__ import annotations

import uuid

from starlette import status
from sqlalchemy import case, select, update
from sqlalchemy.orm import Session

from app.errors import ApiError
from app.models.follow import Follow, FollowStatus
from app.models.user import User


def _user_not_found() -> ApiError:
    return ApiError(status_code=status.HTTP_404_NOT_FOUND,
                    code="user_not_found", detail="User not found.")


def public_profile_text(user: User, viewer_id: uuid.UUID | None) -> tuple[str | None, str | None]:
    """(display_name, bio) as `viewer_id` may see them.

    Moderated profile text is blanked for everyone but its author — the client
    already falls back to @username when display_name is None, so a hidden
    display name degrades to the handle rather than to an empty header. The
    account itself is untouched; bans are is_active.
    """
    if user.moderation_status in ("hidden", "rejected") and user.id != viewer_id:
        return None, None
    return user.display_name, user.bio


def get_active_user_or_404(db: Session, user_id: uuid.UUID) -> User:
    user = db.get(User, user_id)
    if not user or not user.is_active:
        raise _user_not_found()
    return user


def get_active_user_by_username_or_404(db: Session, username: str) -> User:
    # username_lower is the lookup key — never query User.username directly.
    user = db.execute(
        select(User).where(User.username_lower == username.lower())
    ).scalar_one_or_none()
    if not user or not user.is_active:
        raise _user_not_found()
    return user


def get_follow(db: Session, follower_id: uuid.UUID,
               following_id: uuid.UUID) -> Follow | None:
    """The follow row (any status) from follower_id → following_id, if present."""
    return db.execute(
        select(Follow).where(
            Follow.follower_id == follower_id,
            Follow.following_id == following_id,
        )
    ).scalar_one_or_none()


def is_accepted_follower(db: Session, follower_id: uuid.UUID,
                         following_id: uuid.UUID) -> bool:
    follow = db.execute(
        select(Follow).where(
            Follow.follower_id == follower_id,
            Follow.following_id == following_id,
            Follow.status == FollowStatus.accepted,
        )
    ).scalar_one_or_none()
    return follow is not None


def bump_follow_counters(db: Session, follower: User | None,
                         followed: User | None, delta: int) -> None:
    # follower gains/loses one `following`; followed gains/loses one `follower`.
    # None args are skipped so callers can pass a possibly-deleted counterpart.
    #
    # The arithmetic runs in SQL, never in Python: reading the count into an int
    # and writing it back is a lost update under READ COMMITTED — two people
    # following one account concurrently both read N and both write N+1, and the
    # count drifts low permanently. An UPDATE re-evaluates the column against the
    # latest committed row, so it cannot.
    for user, column in ((follower, User.following_count),
                         (followed, User.followers_count)):
        if user is None:
            continue
        bumped = column + delta
        db.execute(
            update(User)
            .where(User.id == user.id)
            # case(), not GREATEST() — the suite runs on SQLite, which has no
            # GREATEST. Counters never go negative (see routers/follows.py).
            .values({column: case((bumped < 0, 0), else_=bumped)})
            # synchronize_session='auto' would reconcile the identity map for us,
            # but only by re-SELECTing the row it just wrote. The expire() below
            # does the same job for free — the next read reloads either way.
            .execution_options(synchronize_session=False)
        )
        # Nothing has reconciled the loaded object, so its counter is now stale;
        # drop it rather than let a later read in this request serve the old value.
        db.expire(user, [column.key])
