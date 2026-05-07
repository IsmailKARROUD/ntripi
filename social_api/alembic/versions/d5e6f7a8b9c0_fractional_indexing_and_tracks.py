"""fractional indexing and tracks

Replaces integer position/parallel_position on stops with fractional-index
rank strings and a new tracks table. Existing stop/annotation data is wiped
(no production data to preserve — clean-slate migration per spec).

Revision ID: d5e6f7a8b9c0
Revises: c5d6e7f8a9b0
Create Date: 2026-05-07
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = 'd5e6f7a8b9c0'
down_revision: str = 'c5d6e7f8a9b0'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Wipe data in FK order (annotations → stops; tracks doesn't exist yet).
    op.execute("DELETE FROM annotations")
    op.execute("DELETE FROM transit_segments")
    op.execute("DELETE FROM stops")

    # 2. Create the tracks table with COLLATE "C" on rank.
    op.create_table(
        'tracks',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('itinerary_id', postgresql.UUID(as_uuid=True),
                  sa.ForeignKey('itineraries.id', ondelete='CASCADE'),
                  nullable=False),
        sa.Column('rank', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('NOW()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True),
                  server_default=sa.text('NOW()'), nullable=False),
        sa.UniqueConstraint('itinerary_id', 'rank', name='uq_track_rank'),
    )
    op.create_index('idx_tracks_itinerary', 'tracks', ['itinerary_id', 'rank'])

    # Apply COLLATE "C" to tracks.rank so PostgreSQL sorts byte-wise.
    op.execute('ALTER TABLE tracks ALTER COLUMN rank TYPE TEXT COLLATE "C"')

    # 3. Add track_id and rank to stops; drop position and parallel_position.
    op.drop_constraint('uq_stop_position_parallel', 'stops', type_='unique')
    op.drop_column('stops', 'position')
    op.drop_column('stops', 'parallel_position')

    op.add_column('stops', sa.Column(
        'track_id', postgresql.UUID(as_uuid=True), nullable=False
    ))
    op.add_column('stops', sa.Column('rank', sa.Text(), nullable=False))

    op.create_foreign_key(
        'fk_stop_track',
        'stops', 'tracks',
        ['track_id'], ['id'],
        ondelete='CASCADE',
    )
    op.create_unique_constraint('uq_stop_rank', 'stops', ['track_id', 'rank'])
    op.create_index('idx_stops_track', 'stops', ['track_id', 'rank'])

    # Apply COLLATE "C" to stops.rank.
    op.execute('ALTER TABLE stops ALTER COLUMN rank TYPE TEXT COLLATE "C"')

    # 4. Ensure itineraries.updated_at auto-updates (add onupdate trigger if missing).
    # The column already exists; we just confirm it has server_default.
    # (The ORM handles onupdate=func.now() at the Python level; no DB trigger needed.)


def downgrade() -> None:
    # Best-effort: restore old columns (data is gone).
    op.drop_index('idx_stops_track', table_name='stops')
    op.drop_constraint('uq_stop_rank', 'stops', type_='unique')
    op.drop_constraint('fk_stop_track', 'stops', type_='foreignkey')
    op.drop_column('stops', 'rank')
    op.drop_column('stops', 'track_id')

    op.add_column('stops', sa.Column(
        'position', sa.SmallInteger(), nullable=False, server_default='1'
    ))
    op.add_column('stops', sa.Column(
        'parallel_position', sa.SmallInteger(), nullable=False, server_default='0'
    ))
    op.create_unique_constraint(
        'uq_stop_position_parallel',
        'stops',
        ['itinerary_id', 'position', 'parallel_position'],
    )

    op.drop_index('idx_tracks_itinerary', table_name='tracks')
    op.drop_table('tracks')
