"""user blocks and tos version

user_blocks: one user blocking another. Both FKs CASCADE, unlike the moderation
tables — a block is a personal preference, not evidence, so it should disappear
with either account.

users.tos_accepted_version: which revision of the terms was agreed to. The
existing tos_accepted_at records THAT they agreed; without the version, "they
accepted these terms" becomes unprovable the moment the terms change. Existing
rows stay NULL rather than being backfilled with a version they never saw.

Revision ID: 9dcbd2b7d34c
Revises: cc74b2080cbf
Create Date: 2026-07-30 08:05:13.563734+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '9dcbd2b7d34c'
down_revision: Union[str, None] = 'cc74b2080cbf'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'user_blocks',
        sa.Column('id', sa.UUID(), server_default=sa.text('gen_random_uuid()'),
                  nullable=False),
        sa.Column('blocker_user_id', sa.UUID(), nullable=False),
        sa.Column('blocked_user_id', sa.UUID(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['blocker_user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['blocked_user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('blocker_user_id', 'blocked_user_id', name='uq_user_block'),
        sa.CheckConstraint('blocker_user_id <> blocked_user_id', name='ck_no_self_block'),
    )
    op.create_index(
        op.f('ix_user_blocks_blocker_user_id'), 'user_blocks', ['blocker_user_id'],
        unique=False,
    )
    op.create_index(
        op.f('ix_user_blocks_blocked_user_id'), 'user_blocks', ['blocked_user_id'],
        unique=False,
    )

    op.add_column(
        'users', sa.Column('tos_accepted_version', sa.String(length=16), nullable=True)
    )


def downgrade() -> None:
    op.drop_column('users', 'tos_accepted_version')
    op.drop_index(op.f('ix_user_blocks_blocked_user_id'), table_name='user_blocks')
    op.drop_index(op.f('ix_user_blocks_blocker_user_id'), table_name='user_blocks')
    op.drop_table('user_blocks')
