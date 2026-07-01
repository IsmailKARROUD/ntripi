import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class PasswordHistory(Base):
    """
    One row per bcrypt hash a user has ever had. Used to block reuse of a
    recent password on change/reset — the newest ~5 rows are compared against
    the candidate password. We store the hash (not the plaintext), so the
    reuse check runs bcrypt.checkpw against each retained row.
    """

    __tablename__ = "password_history"

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

    # A previous value of users.password_hash (bcrypt). Same width as the source.
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    def __repr__(self) -> str:
        return f"<PasswordHistory id={self.id} user_id={self.user_id}>"
