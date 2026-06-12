import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class RefreshToken(Base):
    """
    Server-side record of a refresh token. The raw token is never stored —
    only its SHA-256 hash. Each row represents one issued refresh token.

    Rotation chain: every refresh request consumes one token and issues a
    successor in the same `family_id`. If a revoked token is ever replayed,
    we revoke the whole family (theft detection).
    """

    __tablename__ = "refresh_tokens"

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

    # SHA-256 hex of the opaque raw token — 64 chars. Unique because the raw
    # token is generated via secrets.token_urlsafe and we treat collisions as
    # impossible; the constraint catches programming errors.
    token_hash: Mapped[str] = mapped_column(
        String(64), nullable=False, unique=True, index=True
    )

    # Tokens in the same rotation lineage share a family_id. Mass-revoking
    # the whole family on theft detection is O(1) on this index.
    family_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), nullable=False, index=True
    )

    issued_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )

    # Null = active. Set on rotation, logout, or family revocation.
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # Forensics only — points to the successor token's id. Not a FK to avoid
    # cascade-delete coupling; the column is informational.
    rotated_to: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True
    )

    # Captured at issue time for future "list active sessions" UI and for
    # logging the replayer's user-agent on theft detection.
    user_agent: Mapped[str | None] = mapped_column(String(255), nullable=True)

    def __repr__(self) -> str:
        return f"<RefreshToken id={self.id} user_id={self.user_id} revoked={self.revoked_at is not None}>"
