"""
models/text_moderation_cache.py — cached text-moderation verdicts.

Stops identical text being re-submitted to a paid API. Lives in PostgreSQL
rather than memory so it survives container restarts (Railway redeploys are
frequent) and needs no Redis.

PRIVACY: a row holds a hash, a verdict, and category scores — no raw text and
no user reference. The hash is one-way, so this table cannot reconstruct what
anyone wrote.

INVALIDATION is by construction, not by deletion: the key is
sha256(text + model + POLICY_VERSION), so changing the model or the threshold
policy makes every existing row unreachable. The TTL purge then collects them.
"""

from datetime import datetime, timezone

from sqlalchemy import JSON, CheckConstraint, DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# Kept in sync with the check constraint below and moderation_policy outcomes.
TEXT_MODERATION_OUTCOMES = ("approve", "review", "reject", "hide_escalate")


class TextModerationCache(Base):
    __tablename__ = "text_moderation_cache"
    __table_args__ = (
        CheckConstraint(
            "outcome IN ('approve','review','reject','hide_escalate')",
            name="ck_text_moderation_cache_outcome",
        ),
    )

    # sha256(text + "\x00" + model + "\x00" + policy_version) — the PK, so an
    # identical submission is a single indexed lookup.
    cache_key: Mapped[str] = mapped_column(String(64), primary_key=True)

    outcome: Mapped[str] = mapped_column(String(16), nullable=False)

    # {category: score} as returned by the provider, already normalized to the
    # policy's category names.
    scores: Mapped[dict] = mapped_column(JSON, default=dict, nullable=False)

    provider: Mapped[str] = mapped_column(String(32), nullable=False)
    model: Mapped[str] = mapped_column(String(64), nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        # Python-side default keeps SQLite (tests) aware and comparable.
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    # Indexed: the TTL purge filters on it.
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True
    )

    def __repr__(self) -> str:
        return f"<TextModerationCache key={self.cache_key[:12]}… outcome={self.outcome!r}>"
