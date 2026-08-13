"""
models/device_token.py — One FCM registration token for one install.

The delivery address for push. A row here says "this account, on this device,
in this language" — nothing else. No device name, no model, no OS version:
none of it would change what we send, and all of it is a fingerprint.

`token` is UNIQUE rather than (user_id, token): FCM reuses a token when an
install changes hands, so the same string can arrive under a second account.
The unique constraint is what turns that into a reassignment instead of a
duplicate that would push one person's notifications to the other.

`locale` lives here rather than on `users` because a push carries rendered
text and the OS shows it before our code runs. Per-device is also simply more
correct — one account can be a phone in French and a tablet in English.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    String,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# What we can actually deliver to. Web push needs a service worker and a VAPID
# key that this build does not ship, so it is deliberately not accepted.
DEVICE_PLATFORMS = ("ios", "android")

_PLATFORMS_SQL = ",".join(f"'{value}'" for value in DEVICE_PLATFORMS)


class DeviceToken(Base):
    __tablename__ = "device_tokens"
    __table_args__ = (
        CheckConstraint(
            f"platform IN ({_PLATFORMS_SQL})", name="ck_device_token_platform"
        ),
        # The only query the send path runs: every token for one recipient.
        Index("ix_device_tokens_user", "user_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    # CASCADE: a delivery address is not evidence, and a deleted account must
    # stop receiving push immediately rather than at the next sweep.
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    # FCM tokens have no documented maximum and have grown over the years;
    # String() with no length avoids a migration the next time they do.
    token: Mapped[str] = mapped_column(String, nullable=False, unique=True)

    platform: Mapped[str] = mapped_column(String(10), nullable=False)

    # Language tag for the rendered push body. Falls back to English in
    # push_i18n when unrecognised, so an unexpected value is never fatal.
    locale: Mapped[str] = mapped_column(String(10), nullable=False, default="en")

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
        server_default=func.now(),
    )

    # Refreshed on every register. The sweep prunes rows that go quiet — an
    # uninstall never tells us, it just stops checking in.
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
        server_default=func.now(),
    )
