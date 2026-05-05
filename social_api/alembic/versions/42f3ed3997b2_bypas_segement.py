"""bypas_segement

Revision ID: 42f3ed3997b2
Revises: b0c1d2e3f4a5, f1e2d3c4b5a6
Create Date: 2026-05-05 18:30:36.687048+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '42f3ed3997b2'
down_revision: Union[str, None] = ('b0c1d2e3f4a5', 'f1e2d3c4b5a6')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
