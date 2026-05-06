"""add parallel_position to stops

Revision ID: c5d6e7f8a9b0
Revises: f1e2d3c4b5a6
Create Date: 2026-05-06

Adds parallel_position (0–2) to stops so multiple stops can share the same
itinerary position (i.e. parallel route alternatives). The unique constraint
changes from (itinerary_id, position) to (itinerary_id, position, parallel_position).
"""
import sqlalchemy as sa
from alembic import op

revision: str = 'c5d6e7f8a9b0'
down_revision: str = '42f3ed3997b2'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'stops',
        sa.Column(
            'parallel_position',
            sa.SmallInteger(),
            nullable=False,
            server_default='0',
        ),
    )
    op.drop_constraint('uq_stop_position', 'stops', type_='unique')
    op.create_unique_constraint(
        'uq_stop_position_parallel',
        'stops',
        ['itinerary_id', 'position', 'parallel_position'],
    )


def downgrade() -> None:
    op.drop_constraint('uq_stop_position_parallel', 'stops', type_='unique')
    op.drop_column('stops', 'parallel_position')
    op.create_unique_constraint(
        'uq_stop_position',
        'stops',
        ['itinerary_id', 'position'],
    )
