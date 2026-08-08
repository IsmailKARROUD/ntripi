"""user date of birth

Revision ID: 2ddec1197cc9
Revises: 87495daa26f9
Create Date: 2026-08-08 12:52:07.020128+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '2ddec1197cc9'
down_revision: Union[str, None] = '87495daa26f9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Both nullable and deliberately not backfilled: accounts created before the
    # age gate never declared a date, and inventing one would fake the very
    # record the gate exists to produce. They are collected at the ToS
    # re-acceptance gate instead.
    op.add_column('users', sa.Column('date_of_birth', sa.Date(), nullable=True))
    op.add_column('users', sa.Column('dob_source', sa.String(length=16), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'dob_source')
    op.drop_column('users', 'date_of_birth')
