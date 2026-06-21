import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class EmailToken(Base):
    """
    Single-use, expiring token sent by email — for password reset and email
    verification. Like refresh tokens, the raw value is never stored, only its
    SHA-256 hash (same threat model as password storage).

    `purpose` distinguishes the two flows so a reset token can't be replayed as
    a verification token (or vice versa).
    """

    __tablename__ = "email_tokens"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # SHA-256 hex of the opaque raw token (64 chars). Unique — collisions are
    # treated as impossible; the constraint only catches programming errors.
    token_hash: Mapped[str] = mapped_column(
        String(64), nullable=False, unique=True, index=True
    )

    # "password_reset" | "email_verify".
    purpose: Mapped[str] = mapped_column(String(20), nullable=False)

    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )

    # Null = unused. Set the moment the token is consumed (single-use).
    used_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, default=None
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
