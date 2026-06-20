"""add google_sub, email_verified, nullable password_hash

Revision ID: 0a2c5b2f918e
Revises: 98fa3c7b7229
Create Date: 2026-06-18 22:27:52.820970+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '0a2c5b2f918e'
down_revision: Union[str, None] = '98fa3c7b7229'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Google account id (ID token `sub`) — stable per-user key, unique when set.
    op.add_column("users", sa.Column("google_sub", sa.String(length=255), nullable=True))
    op.create_index(op.f("ix_users_google_sub"), "users", ["google_sub"], unique=True)

    # Verified-email gate. Existing rows default to false ("require everyone to
    # verify" — no grandfathering); users verify by signing in with Google.
    op.add_column(
        "users",
        sa.Column("email_verified", sa.Boolean(), nullable=False, server_default=sa.false()),
    )

    # Google-only accounts have no password.
    op.alter_column("users", "password_hash", existing_type=sa.String(length=255), nullable=True)


def downgrade() -> None:
    # Note: re-applying NOT NULL fails if any Google-only rows (null password_hash) exist.
    op.alter_column("users", "password_hash", existing_type=sa.String(length=255), nullable=False)
    op.drop_column("users", "email_verified")
    op.drop_index(op.f("ix_users_google_sub"), table_name="users")
    op.drop_column("users", "google_sub")
