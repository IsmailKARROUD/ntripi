"""add visibility and allowlist

Revision ID: c3d2e1f0a9b8
Revises: b2f1a3c9e4d0
Create Date: 2026-03-15 12:00:00.000000+00:00

Replaces itineraries.is_public (BOOLEAN) with itineraries.visibility (VARCHAR)
supporting four levels: public, followers, restricted, only_me.

Also adds itinerary_allowed_users table for the 'restricted' allowlist.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'c3d2e1f0a9b8'
down_revision: Union[str, None] = 'b2f1a3c9e4d0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Step 1 — Add the new column with a safe default.
    op.add_column(
        'itineraries',
        sa.Column(
            'visibility',
            sa.String(20),
            nullable=False,
            server_default='only_me',
        ),
    )

    # Step 2 — Migrate existing data: preserve intent from is_public.
    op.execute(
        """
        UPDATE itineraries
        SET visibility = CASE
            WHEN is_public = true THEN 'public'
            ELSE 'only_me'
        END
        """
    )

    # Step 3 — Drop the old column.
    op.drop_column('itineraries', 'is_public')

    # Step 4 — Create the restricted allowlist table.
    op.create_table(
        'itinerary_allowed_users',
        sa.Column('itinerary_id', sa.UUID(), nullable=False),
        sa.Column('user_id', sa.UUID(), nullable=False),
        sa.Column(
            'created_at',
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

    # Step 5 — Add CHECK constraint on visibility values.
    op.create_check_constraint(
        'visibility_check',
        'itineraries',
        "visibility IN ('public', 'followers', 'restricted', 'only_me')",
    )


def downgrade() -> None:
    # Reverse step 5 — drop CHECK constraint.
    op.drop_constraint('visibility_check', 'itineraries', type_='check')

    # Reverse step 4 — drop allowlist table.
    op.drop_table('itinerary_allowed_users')

    # Reverse step 3 — restore is_public column.
    op.add_column(
        'itineraries',
        sa.Column(
            'is_public',
            sa.Boolean(),
            nullable=False,
            server_default=sa.text('false'),
        ),
    )

    # Reverse step 2 — migrate visibility back to is_public.
    op.execute(
        """
        UPDATE itineraries
        SET is_public = CASE
            WHEN visibility = 'public' THEN true
            ELSE false
        END
        """
    )

    # Reverse step 1 — drop the visibility column.
    op.drop_column('itineraries', 'visibility')
