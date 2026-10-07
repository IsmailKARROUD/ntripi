"""
services/translation_usage.py — what a reader and an engine may still spend.

Every reservation is ONE statement: an upsert whose UPDATE only fires while the
new total stays within the limit, returning the total when it did. No row back
means refused, and nothing was counted. Reading the count into Python and
writing it back would lose concurrent increments under READ COMMITTED — the
same reason the follow counters are SQL (user_service.bump_follow_counters).
Works on SQLite too, so the suite exercises the real statement.

The caller owns the commit, and commits straight away: spend is spend even if
the request fails afterwards.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import case, delete
from sqlalchemy.orm import Session

from app.database import upsert_insert
from app.models.translation_usage import TranslationProviderUsage, TranslationUserUsage

# Old enough that no limit can still read them.
_USER_ROWS_KEPT = timedelta(days=2)
# Kept a while as a cost history an operator can look back on.
_PROVIDER_ROWS_KEPT = timedelta(days=90)


def hour_start(now: datetime) -> datetime:
    return now.replace(minute=0, second=0, microsecond=0)


def reserve_user_fields(
    db: Session, user_id: uuid.UUID, count: int, limit: int, now: datetime,
) -> bool:
    """Count `count` fields against the reader's hour if they fit under `limit`."""
    if count <= 0:
        return True
    if count > limit:
        return False
    stmt = upsert_insert(db, TranslationUserUsage).values(
        user_id=user_id, hour_start=hour_start(now), fields=count,
    )
    stmt = stmt.on_conflict_do_update(
        index_elements=[TranslationUserUsage.user_id, TranslationUserUsage.hour_start],
        set_={"fields": TranslationUserUsage.fields + stmt.excluded.fields},
        where=TranslationUserUsage.fields + stmt.excluded.fields <= limit,
    ).returning(TranslationUserUsage.fields)
    return db.execute(stmt).first() is not None


def reserve_provider_chars(
    db: Session, provider: str, chars: int, budget: int | None, today: date,
) -> bool:
    """Count `chars` against the engine's day if they fit under `budget`
    (None = unlimited, nothing recorded)."""
    if budget is None:
        return True
    if chars > budget:
        return False
    stmt = upsert_insert(db, TranslationProviderUsage).values(
        provider=provider, day=today, chars=chars,
    )
    stmt = stmt.on_conflict_do_update(
        index_elements=[TranslationProviderUsage.provider, TranslationProviderUsage.day],
        set_={"chars": TranslationProviderUsage.chars + stmt.excluded.chars},
        where=TranslationProviderUsage.chars + stmt.excluded.chars <= budget,
    ).returning(TranslationProviderUsage.chars)
    return db.execute(stmt).first() is not None


def mark_provider_exhausted(
    db: Session, provider: str, budget: int | None, today: date,
) -> None:
    """The engine said its own quota is gone: fill today's budget so it is not
    asked again before midnight UTC. Without a budget there is nothing to fill —
    the next request asks and is refused by the engine itself."""
    if budget is None:
        return
    stmt = upsert_insert(db, TranslationProviderUsage).values(
        provider=provider, day=today, chars=budget,
    )
    stmt = stmt.on_conflict_do_update(
        index_elements=[TranslationProviderUsage.provider, TranslationProviderUsage.day],
        # case(), not GREATEST(): the suite runs on SQLite.
        set_={"chars": case(
            (TranslationProviderUsage.chars < budget, budget),
            else_=TranslationProviderUsage.chars,
        )},
    )
    db.execute(stmt)


def purge(db: Session, now: datetime) -> int:
    """Delete counters no limit can still read. Returns how many rows went."""
    users = db.execute(
        delete(TranslationUserUsage).where(
            TranslationUserUsage.hour_start < now - _USER_ROWS_KEPT
        )
    ).rowcount or 0
    providers = db.execute(
        delete(TranslationProviderUsage).where(
            TranslationProviderUsage.day < (now - _PROVIDER_ROWS_KEPT).date()
        )
    ).rowcount or 0
    return users + providers


def utc_now() -> datetime:
    return datetime.now(timezone.utc)
