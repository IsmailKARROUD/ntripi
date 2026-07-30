"""
services/block_service.py — user blocking.

Blocking cuts visibility and interaction in BOTH directions. That is deliberate:
a block that only hid the blocker's view would let the blocked user keep reading,
quoting and reacting to someone who asked to be left alone, which is the exact
harassment pattern the feature exists to stop.

Blocking also severs any existing follow relationship, both ways — leaving a
follow in place would keep delivering the blocked user's content through the
feed and keep their name on the follower list.

The blocked user is never notified and cannot tell a block from an ordinary
absence: profile and content reads 404 exactly as they would for a deleted
account.
"""

from __future__ import annotations

import uuid

from sqlalchemy import delete, or_, select
from sqlalchemy.orm import Session

from app.models.follow import Follow, FollowStatus
from app.models.user import User
from app.models.user_block import UserBlock
from app.services.user_service import bump_follow_counters


def is_blocked_either_way(
    db: Session, user_a: uuid.UUID | None, user_b: uuid.UUID | None
) -> bool:
    """True if either user has blocked the other. The single predicate every
    read path consults — direction never matters for visibility."""
    if user_a is None or user_b is None or user_a == user_b:
        return False
    return db.execute(
        select(UserBlock.id).where(
            or_(
                (UserBlock.blocker_user_id == user_a) & (UserBlock.blocked_user_id == user_b),
                (UserBlock.blocker_user_id == user_b) & (UserBlock.blocked_user_id == user_a),
            )
        ).limit(1)
    ).first() is not None


def blocked_user_ids(db: Session, viewer_id: uuid.UUID | None) -> list[uuid.UUID]:
    """Everyone invisible to `viewer_id` in either direction. Used to filter
    list queries in one pass instead of a per-row check."""
    if viewer_id is None:
        return []
    rows = db.execute(
        select(UserBlock.blocker_user_id, UserBlock.blocked_user_id).where(
            or_(
                UserBlock.blocker_user_id == viewer_id,
                UserBlock.blocked_user_id == viewer_id,
            )
        )
    ).all()
    return [
        blocked if blocker == viewer_id else blocker
        for blocker, blocked in rows
    ]


def create_block(db: Session, blocker: User, blocked: User) -> UserBlock:
    """Block `blocked`, tearing down any follow relationship in either
    direction. Idempotent — blocking twice returns the existing row. Commits."""
    existing = db.execute(
        select(UserBlock).where(
            UserBlock.blocker_user_id == blocker.id,
            UserBlock.blocked_user_id == blocked.id,
        )
    ).scalar_one_or_none()
    if existing is not None:
        return existing

    _sever_follows(db, blocker, blocked)

    block = UserBlock(blocker_user_id=blocker.id, blocked_user_id=blocked.id)
    db.add(block)
    db.commit()
    db.refresh(block)
    return block


def delete_block(db: Session, blocker: User, blocked_id: uuid.UUID) -> bool:
    """Lift a block. Returns False if there wasn't one. Following is NOT
    restored — the user can follow again if they want to. Commits."""
    result = db.execute(
        delete(UserBlock).where(
            UserBlock.blocker_user_id == blocker.id,
            UserBlock.blocked_user_id == blocked_id,
        )
    )
    db.commit()
    return (result.rowcount or 0) > 0


def list_blocks(db: Session, blocker: User) -> list[User]:
    """Accounts this user has blocked, newest first — the settings screen."""
    return list(db.execute(
        select(User)
        .join(UserBlock, UserBlock.blocked_user_id == User.id)
        .where(UserBlock.blocker_user_id == blocker.id)
        .order_by(UserBlock.created_at.desc())
    ).scalars().all())


def _sever_follows(db: Session, blocker: User, blocked: User) -> None:
    """Delete follows in both directions, keeping the denormalized counters
    honest. Only accepted follows ever incremented them."""
    follows = db.execute(
        select(Follow).where(
            or_(
                (Follow.follower_id == blocker.id) & (Follow.following_id == blocked.id),
                (Follow.follower_id == blocked.id) & (Follow.following_id == blocker.id),
            )
        )
    ).scalars().all()

    for follow in follows:
        if follow.status == FollowStatus.accepted:
            follower = blocker if follow.follower_id == blocker.id else blocked
            followed = blocked if follow.following_id == blocked.id else blocker
            bump_follow_counters(follower, followed, -1)
        db.delete(follow)
