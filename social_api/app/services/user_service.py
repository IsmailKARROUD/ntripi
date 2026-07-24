"""
services/user_service.py — Shared user + follow-relationship helpers.

These small queries were duplicated across the users, follows, and itineraries
routers. Centralizing them keeps the 404 shapes, the `username_lower` lookup
rule, and the denormalized follow-counter invariant in one place.
"""

from __future__ import annotations

import uuid

from starlette import status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.errors import ApiError
from app.models.follow import Follow, FollowStatus
from app.models.user import User


def _user_not_found() -> ApiError:
    return ApiError(status_code=status.HTTP_404_NOT_FOUND,
                    code="user_not_found", detail="User not found.")


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


def bump_follow_counters(follower: User | None, followed: User | None,
                         delta: int) -> None:
    # follower gains/loses one `following`; followed gains/loses one `follower`.
    # None args are skipped so callers can pass a possibly-deleted counterpart.
    # Counters never go negative (invariant documented in routers/follows.py).
    if follower is not None:
        follower.following_count = max(0, follower.following_count + delta)
    if followed is not None:
        followed.followers_count = max(0, followed.followers_count + delta)
