"""add feed sort indexes

Revision ID: 98fa3c7b7229
Revises: 460d73edaf3d
Create Date: 2026-06-18 11:55:03.785197+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '98fa3c7b7229'
down_revision: Union[str, None] = '460d73edaf3d'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Partial indexes scoped to public itineraries — the discovery feed only ever
    # reads visibility='public', so the predicate keeps the indexes small and lets
    # Postgres skip the filesort on the Recent/Top ORDER BY clauses.
    op.create_index(
        "ix_itineraries_feed_recent",
        "itineraries",
        [sa.text("created_at DESC"), sa.text("id DESC")],
        postgresql_where=sa.text("visibility = 'public'"),
    )
    op.create_index(
        "ix_itineraries_feed_top",
        "itineraries",
        [
            sa.text("rating_avg DESC"),
            sa.text("rating_count DESC"),
            sa.text("created_at DESC"),
            sa.text("id DESC"),
        ],
        postgresql_where=sa.text("visibility = 'public'"),
    )


def downgrade() -> None:
    op.drop_index("ix_itineraries_feed_top", table_name="itineraries")
    op.drop_index("ix_itineraries_feed_recent", table_name="itineraries")
