"""add itinerary_annotations table

Revision ID: c0d1e2f3a4b5
Revises: b9c0d1e2f3a4
Create Date: 2026-05-05
"""

from typing import Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision: str = 'c0d1e2f3a4b5'
down_revision: Union[str, None] = 'b9c0d1e2f3a4'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'itinerary_annotations',
        sa.Column(
            'id',
            UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text('gen_random_uuid()'),
            nullable=False,
        ),
        sa.Column(
            'itinerary_id',
            UUID(as_uuid=True),
            sa.ForeignKey('itineraries.id', ondelete='CASCADE'),
            nullable=False,
        ),
        sa.Column('type', sa.String(20), nullable=False),
        sa.Column('content', sa.Text, nullable=False),
        sa.Column(
            'created_at',
            sa.DateTime(timezone=True),
            server_default=sa.text('now()'),
            nullable=False,
        ),
        sa.Column(
            'updated_at',
            sa.DateTime(timezone=True),
            server_default=sa.text('now()'),
            nullable=False,
        ),
        sa.CheckConstraint(
            "type IN ('advice', 'caution', 'avoid', 'info')",
            name='ck_itinerary_annotation_type',
        ),
    )
    op.create_index(
        'ix_itinerary_annotations_itinerary_id',
        'itinerary_annotations',
        ['itinerary_id'],
    )


def downgrade() -> None:
    op.drop_index('ix_itinerary_annotations_itinerary_id', 'itinerary_annotations')
    op.drop_table('itinerary_annotations')
