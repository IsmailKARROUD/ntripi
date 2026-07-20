"""add map_url to stops

Revision ID: 5a1d7e20ab52
Revises: 7bc2673b9ade
Create Date: 2026-07-20 12:38:43.045984+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '5a1d7e20ab52'
down_revision: Union[str, None] = '7bc2673b9ade'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('stops', sa.Column('map_url', sa.String(length=500), nullable=True))


def downgrade() -> None:
    op.drop_column('stops', 'map_url')
