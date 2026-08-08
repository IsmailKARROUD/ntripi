import uuid
from datetime import date, datetime, timezone

from sqlalchemy import (
    Boolean, CheckConstraint, Date, Integer, JSON, String, Text, DateTime, func,
    false, true,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class User(Base):
    __tablename__ = "users"

    __table_args__ = (
        CheckConstraint(
            "moderation_status IN ('approved','pending','flagged','hidden','rejected')",
            name="ck_user_moderation_status",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    # Display form: preserves the user's original capitalization ("Ismail").
    # NOT unique — uniqueness lives on username_lower instead.
    username: Mapped[str] = mapped_column(
        String(30), nullable=False, index=True
    )

    # Canonical form for lookups and uniqueness checks (always lowercase).
    username_lower: Mapped[str] = mapped_column(
        String(30), nullable=False, unique=True, index=True
    )

    email: Mapped[str] = mapped_column(
        String(255), unique=True, nullable=False, index=True
    )

    # Nullable: Google-only accounts have no password. Password login against
    # such an account is handled timing-safely in auth_service.authenticate_user.
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)

    # Google account id (the ID token `sub` claim) — stable per-user key for
    # "Sign in with Google". Null for password-only accounts.
    google_sub: Mapped[str | None] = mapped_column(
        String(255), unique=True, nullable=True, index=True
    )

    # True once the user's email is proven (currently only via Google's
    # email_verified claim). Gates high-value actions — see require_verified_email.
    email_verified: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=false(), default=False
    )

    # Optional free-form display name (Unicode-friendly, up to 50 chars).
    display_name: Mapped[str | None] = mapped_column(String(50), nullable=True)

    bio: Mapped[str | None] = mapped_column(Text, nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    cover_image_url: Mapped[str | None] = mapped_column(Text, nullable=True)

    passport_countries: Mapped[list | None] = mapped_column(JSON, nullable=True)
    resident_country: Mapped[str | None] = mapped_column(String(2), nullable=True)
    languages: Mapped[list | None] = mapped_column(JSON, nullable=True)

    is_private: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    followers_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    following_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    # Grants access to the /admin moderation dashboard. Set manually via SQL —
    # there is no API or UI to promote a user (single-operator model).
    is_admin: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=false(), default=False
    )

    # ── Optional in-app notification types (see models/notification.py).
    # Checked at WRITE time by notification_service.notify — off means no row is
    # ever created. Default on: a notification nobody opted into is still the
    # only way most of these events are discoverable. The mandatory types
    # (follow requests, moderation actions) deliberately have no switch.
    notify_ratings: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=true(), default=True
    )
    notify_saves: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=true(), default=True
    )
    notify_follow_accepted: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=true(), default=True
    )

    tos_accepted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, default=None
    )

    # Which ToS revision they agreed to. Without it, "they accepted the terms"
    # is unprovable the moment the terms change.
    tos_accepted_version: Mapped[str | None] = mapped_column(
        String(16), nullable=True, default=None
    )

    # Nullable: accounts created before the age gate declared nothing, and are
    # never backfilled with a date nobody gave us. The 16+ rule lives in
    # age_service, not a DB constraint, so those NULLs remain storable.
    date_of_birth: Mapped[date | None] = mapped_column(
        Date, nullable=True, default=None
    )

    # 'google' when the People API supplied it, 'self' when the user typed it.
    # Which source stands behind an account's age is what a store reviewer or a
    # regulator asks, and it cannot be reconstructed from the date alone.
    dob_source: Mapped[str | None] = mapped_column(
        String(16), nullable=True, default=None
    )

    # Moderation state of this profile's free text (display_name + bio).
    # 'hidden'/'rejected' means other viewers see the @username fallback and no
    # bio; the account itself is unaffected (bans use is_active).
    moderation_status: Mapped[str] = mapped_column(
        String(20), default="approved", server_default="'approved'", nullable=False
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

    sent_follows: Mapped[list["Follow"]] = relationship(
        "Follow",
        foreign_keys="Follow.follower_id",
        back_populates="follower",
        cascade="all, delete-orphan",
    )
    received_follows: Mapped[list["Follow"]] = relationship(
        "Follow",
        foreign_keys="Follow.following_id",
        back_populates="following_user",
        cascade="all, delete-orphan",
    )

    @property
    def has_password(self) -> bool:
        """True when this account can log in with a password. Google-only
        accounts have no password_hash — the frontend uses this to decide
        whether to offer 'Change password'."""
        return self.password_hash is not None

    @property
    def has_google(self) -> bool:
        """True when a Google login is linked (google_sub set). An account can
        have both a password and Google — the delete flow offers either as a
        re-auth credential when both are present."""
        return self.google_sub is not None

    @property
    def tos_current(self) -> bool:
        """True when they have accepted the ToS revision currently in force.

        Imported lazily: app.constants.tos is a leaf module, but importing it
        at module scope would put a constants import inside the model layer
        that every other model then pulls in transitively.
        """
        from app.constants.tos import TOS_VERSION

        return self.tos_accepted_version == TOS_VERSION

    @property
    def name_for_display(self) -> str:
        """Returns display_name if set, else falls back to @username."""
        return self.display_name or f"@{self.username}"

    @property
    def handle(self) -> str:
        """Returns the @username form regardless of display_name."""
        return f"@{self.username}"

    def __repr__(self) -> str:
        return f"<User id={self.id} username={self.username}>"
