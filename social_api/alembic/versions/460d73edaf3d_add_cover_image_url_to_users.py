"""add cover_image_url to users

Revision ID: 460d73edaf3d
Revises: 340e256514b7
Create Date: 2026-06-15 11:34:47.830533+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '460d73edaf3d'
down_revision: Union[str, None] = '340e256514b7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("cover_image_url", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("users", "cover_image_url")
