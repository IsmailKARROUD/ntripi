"""device tokens for push notifications

Adds the FCM delivery-address table. Nothing else changes: the notifications
table, its retention, and the client's poll are all untouched, and with the
FCM_* env vars unset no row here is ever read.

  * `token` is UNIQUE, not (user_id, token). FCM hands the same token to a new
    account when an install changes hands, so the constraint is what makes
    that a reassignment rather than a duplicate that would deliver one user's
    notifications to another.

Revision ID: dfb62a1759d8
Revises: 2ddec1197cc9
Create Date: 2026-08-12 18:58:21.129210+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'dfb62a1759d8'
down_revision: Union[str, None] = '2ddec1197cc9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'device_tokens',
        sa.Column(
            'id', sa.UUID(), primary_key=True,
            server_default=sa.text('gen_random_uuid()'),
        ),
        sa.Column('user_id', sa.UUID(), nullable=False),
        # No length: FCM documents no maximum and the tokens have grown.
        sa.Column('token', sa.String(), nullable=False),
        sa.Column('platform', sa.String(length=10), nullable=False),
        sa.Column(
            'locale', sa.String(length=10), nullable=False,
            server_default='en',
        ),
        sa.Column(
            'created_at', sa.DateTime(timezone=True), nullable=False,
            server_default=sa.text('now()'),
        ),
        sa.Column(
            'last_seen_at', sa.DateTime(timezone=True), nullable=False,
            server_default=sa.text('now()'),
        ),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.CheckConstraint(
            "platform IN ('ios','android')",
            name='ck_device_token_platform',
        ),
    )
    # Reassignment guard — see the module docstring.
    op.create_unique_constraint(
        'uq_device_tokens_token', 'device_tokens', ['token']
    )
    # The only query the send path runs: every token for one recipient.
    op.create_index('ix_device_tokens_user', 'device_tokens', ['user_id'])


def downgrade() -> None:
    op.drop_index('ix_device_tokens_user', table_name='device_tokens')
    op.drop_constraint(
        'uq_device_tokens_token', 'device_tokens', type_='unique'
    )
    op.drop_table('device_tokens')
