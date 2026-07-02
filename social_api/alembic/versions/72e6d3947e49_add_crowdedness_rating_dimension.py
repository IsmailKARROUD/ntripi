"""add_crowdedness_rating_dimension

Add the optional crowdedness_stars column to itinerary_ratings — nullable,
collected via the "Want to share more?" section of the rating dialog.

Revision ID: 72e6d3947e49
Revises: 1b3aeb06f54f
Create Date: 2026-07-02 19:33:57.336543+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '72e6d3947e49'
down_revision: Union[str, None] = '1b3aeb06f54f'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'itinerary_ratings',
        sa.Column('crowdedness_stars', sa.SmallInteger(), nullable=True),
    )
    op.create_check_constraint(
        'ck_rating_crowdedness_stars',
        'itinerary_ratings',
        'crowdedness_stars IS NULL OR crowdedness_stars BETWEEN 1 AND 5',
    )


def downgrade() -> None:
    op.drop_constraint('ck_rating_crowdedness_stars', 'itinerary_ratings')
    op.drop_column('itinerary_ratings', 'crowdedness_stars')
