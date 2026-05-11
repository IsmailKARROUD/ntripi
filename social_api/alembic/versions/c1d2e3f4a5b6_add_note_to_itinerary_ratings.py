"""add_note_to_itinerary_ratings

Add optional `note` TEXT column to itinerary_ratings. Users can leave a
short Markdown-formatted review along with their stars. Rendered client-side
with link-inert config to keep public itineraries free of clickable
user-supplied URLs (phishing surface).

Revision ID: c1d2e3f4a5b6
Revises: d5e6f7a8b9c0
Create Date: 2026-05-11 00:00:00.000000+00:00
"""

from alembic import op
import sqlalchemy as sa

revision = 'c1d2e3f4a5b6'
down_revision = 'd5e6f7a8b9c0'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'itinerary_ratings',
        sa.Column('note', sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('itinerary_ratings', 'note')
