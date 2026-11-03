"""
models/signup_block.py — email addresses that may not open a new account.

Written when a suspended account is erased (account_service.erase_account), so
deleting a banned account is not a way back in under the same address. Holds a
keyed hash of the address (token_util.keyed_hash on SECRET_KEY), never the
address itself: sign-up hashes the address it is given and looks it up, and a
leaked or browsed table reveals nothing without the key. No user reference — the
account it came from is gone by design.

Kept until an operator lifts it (/admin/suspended); there is no expiry, as a
ban has none. Rotating SECRET_KEY changes every hash, which lifts every block.
"""

from datetime import datetime

from sqlalchemy import DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class SignupBlock(Base):
    __tablename__ = "signup_blocks"

    # HMAC-SHA256 hex of the lowercased address (64 chars).
    email_hash: Mapped[str] = mapped_column(String(64), primary_key=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
