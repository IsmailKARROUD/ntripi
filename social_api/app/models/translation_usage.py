"""
models/translation_usage.py — what translation has cost, per reader and per
engine.

Two counters, both written only by an atomic conditional upsert
(services/translation_usage.py) — never read into Python and written back,
which would lose concurrent increments under READ COMMITTED:

  translation_user_usage      fields a reader sent to an engine, per clock hour
  translation_provider_usage  characters sent to each engine, per UTC day

Neither holds text. The per-reader row goes with the account (CASCADE); the
per-engine row names no one. The sweep purges both once they are old.
"""

import uuid
from datetime import date, datetime

from sqlalchemy import BigInteger, Date, DateTime, ForeignKey, Integer, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class TranslationUserUsage(Base):
    __tablename__ = "translation_user_usage"

    # Leading PK column, so it also serves as the FK's index.
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    # The start of the clock hour (UTC) the fields count against.
    hour_start: Mapped[datetime] = mapped_column(DateTime(timezone=True), primary_key=True)
    fields: Mapped[int] = mapped_column(Integer, nullable=False, default=0)


class TranslationProviderUsage(Base):
    __tablename__ = "translation_provider_usage"

    provider: Mapped[str] = mapped_column(Text, primary_key=True)
    day: Mapped[date] = mapped_column(Date, primary_key=True)  # UTC
    chars: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
