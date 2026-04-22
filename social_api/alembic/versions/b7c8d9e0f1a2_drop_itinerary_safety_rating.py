"""drop_itinerary_safety_rating

Remove the owner-declared safety_rating column from itineraries.
The community rating system (itinerary_ratings.safety_stars) replaces it.

Revision ID: b7c8d9e0f1a2
Revises: a1b2c3d4e5f6
Create Date: 2026-04-22 00:00:00.000000+00:00
"""

from alembic import op
import sqlalchemy as sa

revision = 'b7c8d9e0f1a2'
down_revision = 'a1b2c3d4e5f6'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_constraint('ck_itinerary_safety_rating', 'itineraries',
                       type_='check')
    op.drop_column('itineraries', 'safety_rating')


def downgrade() -> None:
    op.add_column(
        'itineraries',
        sa.Column('safety_rating', sa.SmallInteger(), nullable=True),
    )
    op.create_check_constraint(
        'ck_itinerary_safety_rating',
        'itineraries',
        'safety_rating IS NULL OR safety_rating BETWEEN 1 AND 5',
    )
