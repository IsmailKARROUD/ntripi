"""add itinerary tables

Revision ID: b2f1a3c9e4d0
Revises: ea3c09f172f1
Create Date: 2026-03-14 10:00:00.000000+00:00

Adds three new tables:
  - itineraries: top-level travel plan owned by a user
  - stops: ordered waypoints inside an itinerary
  - annotations: user-written notes attached to a stop
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'b2f1a3c9e4d0'
down_revision: Union[str, None] = 'ea3c09f172f1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ------------------------------------------------------------------ #
    # itineraries
    # ------------------------------------------------------------------ #
    op.create_table(
        'itineraries',
        sa.Column(
            'id',
            sa.UUID(),
            server_default=sa.text('gen_random_uuid()'),
            nullable=False,
        ),
        sa.Column('user_id', sa.UUID(), nullable=False),
        sa.Column('title', sa.String(length=200), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('cover_image_url', sa.Text(), nullable=True),
        sa.Column(
            'total_duration_min',
            sa.Integer(),
            server_default=sa.text('0'),
            nullable=False,
        ),
        sa.Column(
            'total_cost',
            sa.Numeric(precision=10, scale=2),
            server_default=sa.text('0.00'),
            nullable=False,
        ),
        sa.Column(
            'currency',
            sa.String(length=3),
            server_default=sa.text("'EUR'"),
            nullable=False,
        ),
        sa.Column('safety_rating', sa.SmallInteger(), nullable=True),
        sa.Column(
            'is_public',
            sa.Boolean(),
            server_default=sa.text('false'),
            nullable=False,
        ),
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
            'safety_rating IS NULL OR safety_rating BETWEEN 1 AND 5',
            name='ck_itinerary_safety_rating',
        ),
        sa.ForeignKeyConstraint(
            ['user_id'],
            ['users.id'],
            ondelete='CASCADE',
        ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        op.f('ix_itineraries_user_id'),
        'itineraries',
        ['user_id'],
        unique=False,
    )

    # ------------------------------------------------------------------ #
    # stops
    # ------------------------------------------------------------------ #
    op.create_table(
        'stops',
        sa.Column(
            'id',
            sa.UUID(),
            server_default=sa.text('gen_random_uuid()'),
            nullable=False,
        ),
        sa.Column('itinerary_id', sa.UUID(), nullable=False),
        sa.Column('position', sa.SmallInteger(), nullable=False),
        sa.Column('type', sa.String(length=20), nullable=False),
        sa.Column('place_name', sa.String(length=200), nullable=True),
        sa.Column('place_address', sa.Text(), nullable=True),
        sa.Column('lat', sa.Numeric(precision=9, scale=6), nullable=True),
        sa.Column('lng', sa.Numeric(precision=9, scale=6), nullable=True),
        sa.Column('place_type', sa.String(length=50), nullable=True),
        sa.Column('transport_mode', sa.String(length=20), nullable=True),
        sa.Column('transport_line', sa.String(length=30), nullable=True),
        sa.Column('transport_direction', sa.Text(), nullable=True),
        sa.Column('duration_min', sa.Integer(), nullable=True),
        sa.Column(
            'cost',
            sa.Numeric(precision=10, scale=2),
            server_default=sa.text('0.00'),
            nullable=False,
        ),
        sa.Column(
            'is_free',
            sa.Boolean(),
            server_default=sa.text('false'),
            nullable=False,
        ),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column(
            'created_at',
            sa.DateTime(timezone=True),
            server_default=sa.text('now()'),
            nullable=False,
        ),
        sa.CheckConstraint(
            "type IN ('origin', 'waypoint', 'transit', 'destination')",
            name='ck_stop_type',
        ),
        sa.ForeignKeyConstraint(
            ['itinerary_id'],
            ['itineraries.id'],
            ondelete='CASCADE',
        ),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('itinerary_id', 'position', name='uq_stop_position'),
    )
    op.create_index(
        op.f('ix_stops_itinerary_id'),
        'stops',
        ['itinerary_id'],
        unique=False,
    )

    # ------------------------------------------------------------------ #
    # annotations
    # ------------------------------------------------------------------ #
    op.create_table(
        'annotations',
        sa.Column(
            'id',
            sa.UUID(),
            server_default=sa.text('gen_random_uuid()'),
            nullable=False,
        ),
        sa.Column('stop_id', sa.UUID(), nullable=False),
        sa.Column('type', sa.String(length=20), nullable=False),
        sa.Column('content', sa.Text(), nullable=False),
        sa.Column(
            'created_at',
            sa.DateTime(timezone=True),
            server_default=sa.text('now()'),
            nullable=False,
        ),
        sa.CheckConstraint(
            "type IN ('advice', 'caution', 'avoid', 'info')",
            name='ck_annotation_type',
        ),
        sa.ForeignKeyConstraint(
            ['stop_id'],
            ['stops.id'],
            ondelete='CASCADE',
        ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        op.f('ix_annotations_stop_id'),
        'annotations',
        ['stop_id'],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f('ix_annotations_stop_id'), table_name='annotations')
    op.drop_table('annotations')
    op.drop_index(op.f('ix_stops_itinerary_id'), table_name='stops')
    op.drop_table('stops')
    op.drop_index(op.f('ix_itineraries_user_id'), table_name='itineraries')
    op.drop_table('itineraries')
