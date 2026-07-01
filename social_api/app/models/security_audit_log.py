import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class SecurityAuditLog(Base):
    """
    Append-only trail of account-security events (currently password changes,
    successful and failed). Captures IP + user-agent so support can triage a
    "was I hacked?" report. Never store secrets here.
    """

    __tablename__ = "security_audit_log"

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

    # e.g. "password_change", "password_change_failed". Free-form string so new
    # event types can be added without a schema migration.
    event_type: Mapped[str] = mapped_column(String(64), nullable=False)

    # Real client IP — ProxyHeadersMiddleware rewrites X-Forwarded-For into
    # request.client.host before we read it (see CLAUDE.md middleware stack).
    ip_address: Mapped[str | None] = mapped_column(String(64), nullable=True)
    user_agent: Mapped[str | None] = mapped_column(String(255), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    def __repr__(self) -> str:
        return f"<SecurityAuditLog id={self.id} user_id={self.user_id} event={self.event_type}>"
