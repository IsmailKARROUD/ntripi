"""account erasure requests and sign-up blocks

Account deletion without the app (/delete-account):

- users.erasure_requested_at / users.erasure_request_lang — a deletion asked for
  while the account, a trip it owns or a review it wrote is under an open legal
  escalation. The account is evidence until then; the moderation sweep erases it
  once every escalation is closed, and emails the address in that language.
- signup_blocks — keyed hashes (HMAC on SECRET_KEY) of the addresses of erased
  suspended accounts, which may not sign up again until an operator lifts the
  block. No user reference: the account is gone by design.

Two nullable columns without a default are a catalogue change in PostgreSQL (no
table rewrite), and the new table starts empty, so nothing here needs
CONCURRENTLY.

Revision ID: e24b3c5c59ba
Revises: 87528b459c5b
Create Date: 2026-11-03 19:47:00.681969+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e24b3c5c59ba'
down_revision: Union[str, None] = '87528b459c5b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'users',
        sa.Column('erasure_requested_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        'users',
        sa.Column('erasure_request_lang', sa.String(length=8), nullable=True),
    )
    op.create_table(
        'signup_blocks',
        sa.Column('email_hash', sa.String(length=64), nullable=False),
        sa.Column(
            'created_at', sa.DateTime(timezone=True),
            server_default=sa.text('now()'), nullable=False,
        ),
        sa.PrimaryKeyConstraint('email_hash'),
    )


def downgrade() -> None:
    op.drop_table('signup_blocks')
    op.drop_column('users', 'erasure_request_lang')
    op.drop_column('users', 'erasure_requested_at')
