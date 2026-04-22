"""add_sub_ratings_to_itinerary_ratings

Add four optional sub-rating columns (safety, experience, accessibility,
family_friendly) to itinerary_ratings. All nullable — collected via the
"Want to share more?" section of the rating dialog.

Revision ID: a1b2c3d4e5f6
Revises: e493ea56a71b
Create Date: 2026-04-22 00:00:00.000000+00:00
"""

from alembic import op
import sqlalchemy as sa

revision = 'a1b2c3d4e5f6'
down_revision = 'f5a2b3c4d1e0'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'itinerary_ratings',
        sa.Column('safety_stars', sa.SmallInteger(), nullable=True),
    )
    op.add_column(
        'itinerary_ratings',
        sa.Column('experience_stars', sa.SmallInteger(), nullable=True),
    )
    op.add_column(
        'itinerary_ratings',
        sa.Column('accessibility_stars', sa.SmallInteger(), nullable=True),
    )
    op.add_column(
        'itinerary_ratings',
        sa.Column('family_friendly_stars', sa.SmallInteger(), nullable=True),
    )

    op.create_check_constraint(
        'ck_rating_safety_stars',
        'itinerary_ratings',
        'safety_stars IS NULL OR safety_stars BETWEEN 1 AND 5',
    )
    op.create_check_constraint(
        'ck_rating_experience_stars',
        'itinerary_ratings',
        'experience_stars IS NULL OR experience_stars BETWEEN 1 AND 5',
    )
    op.create_check_constraint(
        'ck_rating_accessibility_stars',
        'itinerary_ratings',
        'accessibility_stars IS NULL OR accessibility_stars BETWEEN 1 AND 5',
    )
    op.create_check_constraint(
        'ck_rating_family_friendly_stars',
        'itinerary_ratings',
        'family_friendly_stars IS NULL OR family_friendly_stars BETWEEN 1 AND 5',
    )


def downgrade() -> None:
    op.drop_constraint('ck_rating_family_friendly_stars', 'itinerary_ratings')
    op.drop_constraint('ck_rating_accessibility_stars', 'itinerary_ratings')
    op.drop_constraint('ck_rating_experience_stars', 'itinerary_ratings')
    op.drop_constraint('ck_rating_safety_stars', 'itinerary_ratings')

    op.drop_column('itinerary_ratings', 'family_friendly_stars')
    op.drop_column('itinerary_ratings', 'accessibility_stars')
    op.drop_column('itinerary_ratings', 'experience_stars')
    op.drop_column('itinerary_ratings', 'safety_stars')
