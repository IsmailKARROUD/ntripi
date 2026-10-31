"""
models/place_search_usage.py — Google place-search requests per user per hour.

Places Autocomplete is billed per request, so each user has an hourly budget
(GOOGLE_PLACES_USER_HOURLY_LIMIT). Written only by the atomic conditional upsert
in database.reserve_within_limit — never read into Python and written back,
which would lose concurrent increments under READ COMMITTED. Holds no search
text. The row goes with the account (CASCADE); the sweep purges old hours.
"""

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class PlaceSearchUsage(Base):
    __tablename__ = "place_search_usage"

    # Leading PK column, so it also serves as the FK's index.
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    # The start of the clock hour (UTC) the requests count against.
    hour_start: Mapped[datetime] = mapped_column(DateTime(timezone=True), primary_key=True)
    requests: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
