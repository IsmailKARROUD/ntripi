"""translation usage counters

Two counters for translation cost, both written only by an atomic conditional
upsert (services/translation_usage.py):

  * `translation_user_usage` — fields one reader sent to an engine per clock
    hour. `user_id` leads the primary key, so the key doubles as the FK index;
    the row goes with the account (CASCADE).
  * `translation_provider_usage` — characters sent to each engine per UTC day.
    Names no one.

Both tables are new and empty, so nothing here needs CONCURRENTLY.

Revision ID: 1afc3c26511a
Revises: f05c373d1b6c
Create Date: 2026-10-07 17:57:46.597382+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '1afc3c26511a'
down_revision: Union[str, None] = 'f05c373d1b6c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'translation_user_usage',
        sa.Column('user_id', sa.UUID(), nullable=False),
        sa.Column('hour_start', sa.DateTime(timezone=True), nullable=False),
        sa.Column('fields', sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('user_id', 'hour_start'),
    )
    op.create_table(
        'translation_provider_usage',
        sa.Column('provider', sa.Text(), nullable=False),
        sa.Column('day', sa.Date(), nullable=False),
        sa.Column('chars', sa.BigInteger(), nullable=False),
        sa.PrimaryKeyConstraint('provider', 'day'),
    )


def downgrade() -> None:
    op.drop_table('translation_provider_usage')
    op.drop_table('translation_user_usage')
