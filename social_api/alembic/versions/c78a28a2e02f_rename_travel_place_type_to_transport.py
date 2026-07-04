"""rename travel place_type to transport

Revision ID: c78a28a2e02f
Revises: 72e6d3947e49
Create Date: 2026-07-04 13:19:29.621661+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c78a28a2e02f'
down_revision: Union[str, None] = '72e6d3947e49'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Data-only: the 'travel' place-type category was renamed to 'transport'.
    op.execute("UPDATE stops SET place_type='transport' WHERE place_type='travel'")


def downgrade() -> None:
    op.execute("UPDATE stops SET place_type='travel' WHERE place_type='transport'")
