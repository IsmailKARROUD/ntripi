"""
models/itinerary.py — SQLAlchemy ORM model for the itineraries table.

Design decisions:
  - UUID primary key, same pattern as User and Follow models.
  - total_duration_min and total_cost are denormalized on the itinerary row
    for fast summary reads. They are recalculated by the router after every
    stop add/update/delete — never modified directly by callers.
  - visibility defaults to 'only_me': safest option. Users explicitly open
    up access; they never accidentally expose content.
  - cover_image_url is stored as a plain URL to a file hosted on our own server.
    No external provider URLs are persisted here.
"""

import uuid
from decimal import Decimal
from datetime import datetime

from sqlalchemy import (
    JSON, CheckConstraint, DateTime, ForeignKey, Integer,
    Numeric, String, Text, func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class Itinerary(Base):
    __tablename__ = "itineraries"

    # Declared here so the SQLite test schema enforces the same five values as
    # Postgres: the migration-only version of this constraint silently drifted
    # (it never gained 'hidden') and the whole suite stayed green while every
    # production auto-hide 500'd.
    __table_args__ = (
        CheckConstraint(
            "moderation_status IN ('approved','pending','flagged','hidden','rejected')",
            name="ck_itinerary_moderation_status",
        ),
    )

    # UUID primary key, same pattern as User model.
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    # FK to the owning user. CASCADE ensures itineraries are deleted
    # automatically when a user account is deleted.
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,  # Used in GET /itineraries/me — must be fast
    )

    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)

    # URL to a user-uploaded cover image stored on our own infrastructure.
    cover_image_url: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Denormalized aggregates — recalculated on every stop mutation.
    total_duration_min: Mapped[int] = mapped_column(
        Integer, default=0, server_default="0", nullable=False
    )
    total_cost: Mapped[Decimal] = mapped_column(
        Numeric(10, 2), default=Decimal("0.00"), server_default="0.00", nullable=False
    )

    # ISO 4217 currency code, 3 characters (EUR, USD, GBP, …)
    currency: Mapped[str] = mapped_column(
        String(3), default="EUR", server_default="'EUR'", nullable=False
    )

    # Denormalized community-rating aggregates — recalculated by
    # recalculate_rating() in services/itinerary_access.py after every
    # ItineraryRating insert/update/delete.
    rating_avg: Mapped[float | None] = mapped_column(
        Numeric(3, 2), nullable=True, default=None
    )
    rating_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )

    # Four-level visibility system. Defaults to 'only_me' — the safest option.
    # Valid values: 'public' | 'followers' | 'restricted' | 'only_me'
    # Logic is enforced by can_view_itinerary() in services/itinerary_access.py.
    visibility: Mapped[str] = mapped_column(
        String(20), default="only_me", server_default="'only_me'", nullable=False
    )

    # Author's answer to "when should I go?" — all three parts optional.
    #
    # recommended_periods holds a list of {from_month, from_day, to_month, to_day}
    # windows. There is no year: a window is a RECURRING ANNUAL span, so
    # from_month=9 to_month=3 is a legitimate wrap-around, not reversed input.
    # Days are optional refinements of the window's first/last month. A list
    # rather than one range because the good months are often not contiguous
    # (Jan–Mar and Sep–Dec). Shape and non-overlap are enforced in
    # schemas/itinerary.py — JSON columns take no DB constraint here or anywhere
    # else in this codebase.
    #
    # Generic JSON, never JSONB/ARRAY: the test suite builds its schema from this
    # metadata on SQLite (test/conftest.py).
    recommended_periods: Mapped[list | None] = mapped_column(JSON, nullable=True)
    # ISO-8601 weekday numbers, 1 = Monday … 7 = Sunday.
    recommended_weekdays: Mapped[list | None] = mapped_column(JSON, nullable=True)
    # The "why" — one line, moderated like any other stored user prose.
    recommended_period_note: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Combined moderation state for this itinerary's cover image AND its text
    # (title, description, and its stops / annotations / transport legs, which
    # roll up here because hiding is itinerary-level):
    #   'approved' — clean, or moderation off
    #   'pending'  — a provider was down; stored unscanned, sweep re-checks
    #   'flagged'  — stored, sitting in the moderator queue
    #   'hidden'   — taken down after publication (see hidden_at)
    #   'rejected' — blocked at write time
    # Both tiers write this column, so automated writes only ever RAISE severity
    # (text_moderation_service.apply_moderation_status): a clean caption edit
    # must not clear an unresolved image flag. Moderator/appeal paths assign
    # directly to lower it.
    moderation_status: Mapped[str] = mapped_column(
        String(20), default="approved", server_default="'approved'", nullable=False
    )

    # Moderator soft-state (set from the /admin dashboard, never by the owner):
    #   hidden_at  — visible ONLY to the owner (banner shown); excluded from feed,
    #                search, share, and other users' views. Owner can still edit.
    #   deleted_at — soft delete: invisible to EVERYONE incl. the owner (404), but
    #                the row + files are preserved as legal/safety evidence.
    # Both are enforced centrally in can_view_itinerary() + the raw list/share paths.
    hidden_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # Tracks ordered by rank (fractional index). Each track contains stops.
    tracks: Mapped[list["Track"]] = relationship(
        "Track",
        back_populates="itinerary",
        cascade="all, delete-orphan",
        order_by="Track.rank",
    )

    # Flat stop list via itinerary_id FK (for totals recalculation).
    stops: Mapped[list["Stop"]] = relationship(
        "Stop",
        back_populates="itinerary",
        cascade="all, delete-orphan",
        viewonly=True,
    )

    # Transit segments for this itinerary (order maintained in Python by
    # from_stop track+rank after eager loading — see _sort_segments in router).
    segments: Mapped[list["TransitSegment"]] = relationship(
        "TransitSegment",
        back_populates="itinerary",
        cascade="all, delete-orphan",
    )

    # Itinerary-level annotations (general notes about the trip as a whole).
    annotations: Mapped[list["ItineraryAnnotation"]] = relationship(
        "ItineraryAnnotation",
        back_populates="itinerary",
        cascade="all, delete-orphan",
        order_by="ItineraryAnnotation.created_at",
    )

    @property
    def hidden(self) -> bool:
        """True when a moderator has hidden this itinerary. Surfaced in the
        detail response (from_attributes) so the owner's client shows a banner."""
        return self.hidden_at is not None

    @property
    def stops_count(self) -> int:
        return sum(len(t.stops) for t in self.tracks) if self.tracks else len(self.stops)

    def __repr__(self) -> str:
        return f"<Itinerary id={self.id} title={self.title!r}>"
