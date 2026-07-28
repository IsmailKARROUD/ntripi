"""
services/appeal_service.py — User appeals against moderation actions.

Two entry points feed the same rules (create_appeal):
  - authenticated API (POST /appeals) for users who can still log in, and
  - the public token form (/appeal/{token}) for banned users, who cannot.

Rules: a written reason is mandatory, only one appeal may be open per moderated
item, and a rejected (upheld) appeal locks that item for 30 days. Operators then
restore / uphold / reduce, which reverses the original action to the matching
degree and emails the outcome.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.models.appeal import Appeal
from app.models.itinerary import Itinerary
from app.models.moderation_log import ModerationLog
from app.models.user import User
from app.services import admin_service, email_service
from app.services.admin_service import TARGET_ITINERARY, TARGET_USER

# Only penalties a user can meaningfully contest. A `hide` is surfaced on the
# violations page for transparency but isn't appealable on its own — the in-app
# banner already explains it, and `reduce` converts deletes into hides.
APPEALABLE_ACTIONS = ("delete", "warn", "ban")
VISIBLE_ACTIONS = ("hide", "delete", "warn", "ban")

REAPPEAL_COOLDOWN = timedelta(days=30)
MAX_REASON_LEN = 2000

DECISIONS = ("restore", "uphold", "reduce")


class AppealError(Exception):
    """Rule violation surfaced as an ApiError by the router / web form."""

    def __init__(self, message: str, code: str, http_status: int = 400) -> None:
        super().__init__(message)
        self.message = message
        self.code = code
        self.http_status = http_status


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _as_aware(value: datetime) -> datetime:
    # SQLite (tests) returns naive datetimes; PostgreSQL is tz-aware.
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


# ---------------------------------------------------------------------------
# Submission
# ---------------------------------------------------------------------------

def _owned_itinerary_ids(db: Session, user: User) -> list[uuid.UUID]:
    # Soft-deleted rows still carry user_id, so a removed itinerary stays
    # attributable to (and appealable by) its author.
    return list(db.execute(
        select(Itinerary.id).where(Itinerary.user_id == user.id)
    ).scalars().all())


def find_action(
    db: Session, user: User, target_type: str, target_id: uuid.UUID,
) -> ModerationLog | None:
    """The most recent appealable action against this user or their content.
    Returns None when the target isn't theirs — callers treat that as 404."""
    if target_type == TARGET_USER:
        if target_id != user.id:
            return None
    elif target_type == TARGET_ITINERARY:
        if target_id not in _owned_itinerary_ids(db, user):
            return None
    else:
        return None

    return db.execute(
        select(ModerationLog)
        .where(
            ModerationLog.target_type == target_type,
            ModerationLog.target_id == target_id,
            ModerationLog.action.in_(APPEALABLE_ACTIONS),
        )
        .order_by(ModerationLog.created_at.desc())
    ).scalars().first()


def create_appeal(
    db: Session,
    user: User,
    target_type: str,
    target_id: uuid.UUID,
    reason: str,
    log_id: uuid.UUID | None = None,
) -> Appeal:
    """Validate the appeal rules and open an appeal. Commits."""
    reason = (reason or "").strip()
    if not reason:
        raise AppealError(
            "Please explain why you believe this decision was incorrect.",
            code="appeal_reason_required", http_status=422,
        )
    if len(reason) > MAX_REASON_LEN:
        raise AppealError(
            f"Your explanation must be {MAX_REASON_LEN} characters or fewer.",
            code="appeal_reason_too_long", http_status=422,
        )

    action = find_action(db, user, target_type, target_id)
    if action is None:
        raise AppealError(
            "There is no moderation action to appeal here.",
            code="appeal_target_not_found", http_status=404,
        )

    existing = db.execute(
        select(Appeal).where(
            Appeal.user_id == user.id,
            Appeal.target_type == target_type,
            Appeal.target_id == target_id,
        ).order_by(Appeal.updated_at.desc())
    ).scalars().all()

    # One open appeal per item.
    if any(a.status == "pending" for a in existing):
        raise AppealError(
            "You already have an appeal pending for this item.",
            code="appeal_already_pending", http_status=409,
        )

    # A rejected appeal locks the item for 30 days.
    cutoff = _now() - REAPPEAL_COOLDOWN
    if any(a.status == "upheld" and _as_aware(a.updated_at) > cutoff for a in existing):
        raise AppealError(
            "You can only appeal this item again 30 days after a rejected appeal.",
            code="appeal_cooldown", http_status=429,
        )

    appeal = Appeal(
        user_id=user.id,
        moderation_log_id=log_id or action.id,
        target_type=target_type,
        target_id=target_id,
        status="pending",
        user_reason=reason,
    )
    db.add(appeal)
    db.commit()
    db.refresh(appeal)
    return appeal


# ---------------------------------------------------------------------------
# Violations feed (in-app "Account status" page)
# ---------------------------------------------------------------------------

def violations_feed(db: Session, user: User) -> list[dict]:
    """Moderation actions taken against this user or their content, newest first,
    each annotated with whether it can be appealed right now."""
    itinerary_ids = _owned_itinerary_ids(db, user)

    conditions = [
        (ModerationLog.target_type == TARGET_USER) & (ModerationLog.target_id == user.id)
    ]
    if itinerary_ids:
        conditions.append(
            (ModerationLog.target_type == TARGET_ITINERARY)
            & (ModerationLog.target_id.in_(itinerary_ids))
        )

    rows = db.execute(
        select(ModerationLog)
        .where(ModerationLog.action.in_(VISIBLE_ACTIONS), or_(*conditions))
        .order_by(ModerationLog.created_at.desc())
    ).scalars().all()

    appeals = db.execute(
        select(Appeal).where(Appeal.user_id == user.id)
        .order_by(Appeal.updated_at.desc())
    ).scalars().all()

    items: list[dict] = []
    for row in rows:
        latest = next(
            (a for a in appeals
             if a.target_type == row.target_type and a.target_id == row.target_id),
            None,
        )
        active = _action_still_active(db, row, user)
        cooldown_until: datetime | None = None
        if latest is not None and latest.status == "upheld":
            until = _as_aware(latest.updated_at) + REAPPEAL_COOLDOWN
            if until > _now():
                cooldown_until = until

        appealable = (
            row.action in APPEALABLE_ACTIONS
            and active
            and (latest is None or latest.status != "pending")
            and cooldown_until is None
        )

        snapshot = row.content_snapshot or {}
        items.append({
            "id": row.id,
            "action": row.action,
            "target_type": row.target_type,
            "target_id": row.target_id,
            # Title only — never the moderated content itself.
            "item_title": snapshot.get("title") or snapshot.get("username"),
            "created_at": row.created_at,
            "active": active,
            "appealable": appealable,
            "appeal_status": latest.status if latest else None,
            "cooldown_until": cooldown_until,
        })
    return items


def _action_still_active(db: Session, row: ModerationLog, user: User) -> bool:
    """False once the penalty has been lifted (unhide / unban / appeal restore)."""
    if row.action == "ban":
        return not user.is_active
    if row.action in ("delete", "hide"):
        itinerary = db.get(Itinerary, row.target_id) if row.target_id else None
        if itinerary is None:
            return False
        return (
            itinerary.deleted_at is not None if row.action == "delete"
            else itinerary.hidden_at is not None
        )
    # A warning is a permanent record — it stays contestable until appealed.
    return True


# ---------------------------------------------------------------------------
# Operator decisions
# ---------------------------------------------------------------------------

def decide_appeal(
    db: Session, admin: User, appeal: Appeal, decision: str, admin_response: str,
) -> None:
    """Apply an operator decision: reverse, confirm, or soften the penalty."""
    if decision not in DECISIONS:
        raise ValueError(f"unsupported appeal decision: {decision}")
    if appeal.status != "pending":
        raise AppealError(
            "This appeal has already been decided.",
            code="appeal_already_decided", http_status=409,
        )

    admin_response = (admin_response or "").strip()
    user = db.get(User, appeal.user_id)
    itinerary = (
        db.get(Itinerary, appeal.target_id)
        if appeal.target_type == TARGET_ITINERARY else None
    )
    original = (
        db.get(ModerationLog, appeal.moderation_log_id)
        if appeal.moderation_log_id else None
    )
    original_action = original.action if original else None

    heading = ""
    body = ""

    if decision == "restore":
        if itinerary is not None:
            # Reversing a takedown also clears the cover-scan rejection that
            # would otherwise keep the itinerary marked as bad content.
            fields: dict = {"deleted_at": None, "hidden_at": None}
            if itinerary.moderation_status == "rejected":
                fields["moderation_status"] = "approved"
            admin_service.set_preserving_etag(itinerary, **fields)
        if original_action == "ban" and user is not None:
            user.is_active = True
        appeal.status = "restored"
        heading = "Your appeal was accepted"
        body = "We reviewed your appeal and reversed the action."

    elif decision == "uphold":
        appeal.status = "upheld"
        heading = "Your appeal was reviewed"
        body = "We reviewed your appeal and the original decision stands."

    else:  # reduce — ban becomes a warning, a removal becomes a hide
        if original_action == "ban" and user is not None:
            user.is_active = True
            body = "Your suspension was lifted and replaced with a warning."
        elif itinerary is not None:
            admin_service.set_preserving_etag(
                itinerary, deleted_at=None, hidden_at=_now(),
            )
            body = ("Your content was restored but remains hidden from other "
                    "users while it is under review.")
        appeal.status = "reduced"
        heading = "Your appeal was partially accepted"

    if admin_response:
        appeal.admin_response = admin_response
        body = f"{body} Moderator note: {admin_response}"

    # updated_at is the cooldown clock — bump it explicitly so SQLite (which has
    # no onupdate trigger semantics for a no-op UPDATE) matches PostgreSQL.
    appeal.updated_at = _now()

    admin_service.log_action(
        db, admin, appeal.target_type, appeal.target_id,
        f"appeal_{decision}",
        # The user's own words are the reason of record for an appeal decision.
        admin_response or appeal.user_reason,
        {"appeal_id": str(appeal.id), "original_action": original_action},
    )
    db.commit()

    if user is not None:
        _send_decision_email(user, heading, body)


def _send_decision_email(user: User, heading: str, body: str) -> None:
    from app.config import get_settings
    from app.services.auth_service import _email_html

    email_service.send_email(
        to=user.email,
        subject=f"Ntripi — {heading}",
        html=_email_html(
            heading, body, "Open Ntripi", f"{get_settings().share_base_url}/app/",
        ),
    )
