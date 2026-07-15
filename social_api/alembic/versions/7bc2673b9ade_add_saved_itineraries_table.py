"""add saved itineraries table

Revision ID: 7bc2673b9ade
Revises: c78a28a2e02f
Create Date: 2026-07-15 14:53:13.805910+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7bc2673b9ade'
down_revision: Union[str, None] = 'c78a28a2e02f'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'saved_itineraries',
        sa.Column('itinerary_id', sa.UUID(), nullable=False),
        sa.Column('user_id', sa.UUID(), nullable=False),
        sa.Column(
            'saved_at',
            sa.DateTime(timezone=True),
            server_default=sa.text('now()'),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ['itinerary_id'],
            ['itineraries.id'],
            ondelete='CASCADE',
        ),
        sa.ForeignKeyConstraint(
            ['user_id'],
            ['users.id'],
            ondelete='CASCADE',
        ),
        sa.PrimaryKeyConstraint('itinerary_id', 'user_id'),
    )
    # The "Saved" screen reads WHERE user_id ORDER BY saved_at DESC; the PK index
    # leads with itinerary_id so it can't serve this query — add a dedicated one.
    op.create_index(
        "ix_saved_itineraries_user_recent",
        "saved_itineraries",
        [sa.text("user_id"), sa.text("saved_at DESC")],
    )


def downgrade() -> None:
    op.drop_index("ix_saved_itineraries_user_recent", table_name="saved_itineraries")
    op.drop_table('saved_itineraries')
