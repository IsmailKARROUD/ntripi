"""transit_segments and transport_legs

Revision ID: f5a2b3c4d1e0
Revises: e493ea56a71b
Create Date: 2026-04-20 10:00:00.000000+00:00

Migration steps:
  1. Create transit_segments table.
  2. Create transport_legs table.
  3. Migrate existing transit stops into segment + leg rows.
  4. Drop transit columns from stops (transport_mode, transport_line,
     transport_direction).
  5. Update the stop type CHECK constraint to remove 'transit'.

Transit stop conversion logic:
  For each stop of type='transit', create:
    - A TransitSegment from the previous stop (position-1) to the next
      stop (position+1) within the same itinerary.
    - A single TransportLeg using the stop's transport_mode/line/direction.
  If a transit stop has no adjacent stops on one or both sides it is
  simply deleted — it cannot be migrated without valid from/to references.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql


revision: str = 'f5a2b3c4d1e0'
down_revision: Union[str, None] = 'e493ea56a71b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ------------------------------------------------------------------
    # 1. Create transit_segments
    # ------------------------------------------------------------------
    op.create_table(
        'transit_segments',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text('gen_random_uuid()')),
        sa.Column('itinerary_id', postgresql.UUID(as_uuid=True),
                  sa.ForeignKey('itineraries.id', ondelete='CASCADE'),
                  nullable=False),
        sa.Column('from_stop_id', postgresql.UUID(as_uuid=True),
                  sa.ForeignKey('stops.id', ondelete='CASCADE'),
                  nullable=False),
        sa.Column('to_stop_id', postgresql.UUID(as_uuid=True),
                  sa.ForeignKey('stops.id', ondelete='CASCADE'),
                  nullable=False),
        sa.Column('total_duration_min', sa.Integer(), nullable=False,
                  server_default='0'),
        sa.Column('total_cost', sa.Numeric(10, 2), nullable=False,
                  server_default='0.00'),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('now()'), nullable=False),
        sa.UniqueConstraint('from_stop_id', 'to_stop_id',
                            name='uq_segment_stops'),
        sa.CheckConstraint('from_stop_id != to_stop_id',
                           name='ck_segment_different_stops'),
    )
    op.create_index('ix_transit_segments_itinerary_id',
                    'transit_segments', ['itinerary_id'])

    # ------------------------------------------------------------------
    # 2. Create transport_legs
    # ------------------------------------------------------------------
    op.create_table(
        'transport_legs',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text('gen_random_uuid()')),
        sa.Column('segment_id', postgresql.UUID(as_uuid=True),
                  sa.ForeignKey('transit_segments.id', ondelete='CASCADE'),
                  nullable=False),
        sa.Column('position', sa.SmallInteger(), nullable=False),
        sa.Column('mode', sa.String(20), nullable=False),
        sa.Column('line', sa.String(30), nullable=True),
        sa.Column('direction', sa.Text(), nullable=True),
        sa.Column('duration_min', sa.Integer(), nullable=True),
        sa.Column('cost', sa.Numeric(10, 2), nullable=False,
                  server_default='0.00'),
        sa.Column('is_free', sa.Boolean(), nullable=False,
                  server_default='false'),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('now()'), nullable=False),
        sa.UniqueConstraint('segment_id', 'position', name='uq_leg_position'),
        sa.CheckConstraint(
            "mode IN ('walk','bus','tram','metro','train','taxi','uber','bike','ferry','car')",
            name='ck_leg_mode',
        ),
    )
    op.create_index('ix_transport_legs_segment_id',
                    'transport_legs', ['segment_id'])

    # ------------------------------------------------------------------
    # 3. Migrate existing transit stops → segments + legs
    # ------------------------------------------------------------------
    conn = op.get_bind()

    # Fetch all transit stops with their neighbours.
    transit_stops = conn.execute(sa.text("""
        SELECT
            ts.id           AS stop_id,
            ts.itinerary_id,
            ts.position,
            ts.transport_mode,
            ts.transport_line,
            ts.transport_direction,
            ts.duration_min,
            ts.cost,
            ts.is_free,
            prev_s.id       AS from_stop_id,
            next_s.id       AS to_stop_id
        FROM stops ts
        LEFT JOIN stops prev_s
            ON  prev_s.itinerary_id = ts.itinerary_id
            AND prev_s.position = ts.position - 1
        LEFT JOIN stops next_s
            ON  next_s.itinerary_id = ts.itinerary_id
            AND next_s.position = ts.position + 1
        WHERE ts.type = 'transit'
        ORDER BY ts.itinerary_id, ts.position
    """)).fetchall()

    for row in transit_stops:
        if row.from_stop_id is None or row.to_stop_id is None:
            # Cannot create a valid segment — skip (stop will be deleted below).
            continue

        # Insert segment (ignore if the pair already exists from a previous
        # transit stop — duplicate from_stop/to_stop pairs are silently skipped).
        existing = conn.execute(sa.text("""
            SELECT id FROM transit_segments
            WHERE from_stop_id = :from_id AND to_stop_id = :to_id
        """), {"from_id": row.from_stop_id, "to_id": row.to_stop_id}).fetchone()

        if existing:
            segment_id = existing.id
        else:
            segment_id = conn.execute(sa.text("""
                INSERT INTO transit_segments
                    (itinerary_id, from_stop_id, to_stop_id,
                     total_duration_min, total_cost)
                VALUES
                    (:itin_id, :from_id, :to_id,
                     COALESCE(:dur, 0), COALESCE(:cost, 0.00))
                RETURNING id
            """), {
                "itin_id": row.itinerary_id,
                "from_id": row.from_stop_id,
                "to_id": row.to_stop_id,
                "dur": row.duration_min,
                "cost": row.cost if not row.is_free else 0,
            }).fetchone().id

            # Insert the single leg for this transit stop.
            conn.execute(sa.text("""
                INSERT INTO transport_legs
                    (segment_id, position, mode, line, direction,
                     duration_min, cost, is_free)
                VALUES
                    (:seg_id, 1, :mode, :line, :direction,
                     :dur, :cost, :is_free)
            """), {
                "seg_id": segment_id,
                "mode": row.transport_mode or 'walk',
                "line": row.transport_line,
                "direction": row.transport_direction,
                "dur": row.duration_min,
                "cost": row.cost,
                "is_free": row.is_free,
            })

    # Delete all transit stops (their annotations cascade automatically).
    conn.execute(sa.text("DELETE FROM stops WHERE type = 'transit'"))

    # ------------------------------------------------------------------
    # 4. Drop transit-only columns from stops
    # ------------------------------------------------------------------
    op.drop_column('stops', 'transport_mode')
    op.drop_column('stops', 'transport_line')
    op.drop_column('stops', 'transport_direction')

    # ------------------------------------------------------------------
    # 5. Update stop type CHECK constraint (remove 'transit')
    # ------------------------------------------------------------------
    op.drop_constraint('ck_stop_type', 'stops', type_='check')
    op.create_check_constraint(
        'ck_stop_type',
        'stops',
        "type IN ('origin', 'waypoint', 'destination')",
    )


def downgrade() -> None:
    # ------------------------------------------------------------------
    # 5. Restore original CHECK constraint on stops.type
    # ------------------------------------------------------------------
    op.drop_constraint('ck_stop_type', 'stops', type_='check')
    op.create_check_constraint(
        'ck_stop_type',
        'stops',
        "type IN ('origin', 'waypoint', 'destination', 'transit')",
    )

    # ------------------------------------------------------------------
    # 4. Re-add transit columns to stops
    # ------------------------------------------------------------------
    op.add_column('stops', sa.Column('transport_mode', sa.String(20),
                                     nullable=True))
    op.add_column('stops', sa.Column('transport_line', sa.String(50),
                                     nullable=True))
    op.add_column('stops', sa.Column('transport_direction', sa.Text(),
                                     nullable=True))

    # ------------------------------------------------------------------
    # 3. Migrate transit segments back to transit stops (best-effort)
    # ------------------------------------------------------------------
    conn = op.get_bind()

    segments = conn.execute(sa.text("""
        SELECT
            ts.id           AS segment_id,
            ts.itinerary_id,
            ts.total_duration_min,
            ts.total_cost,
            from_s.position AS from_pos,
            tl.mode,
            tl.line,
            tl.direction
        FROM transit_segments ts
        JOIN stops from_s ON from_s.id = ts.from_stop_id
        LEFT JOIN transport_legs tl
            ON tl.segment_id = ts.id AND tl.position = 1
    """)).fetchall()

    for row in segments:
        transit_pos = row.from_pos + 1

        # Shift all stops at transit_pos and above up by one to make room.
        conn.execute(sa.text("""
            UPDATE stops
            SET position = position + 1
            WHERE itinerary_id = :itin_id AND position >= :pos
        """), {"itin_id": row.itinerary_id, "pos": transit_pos})

        conn.execute(sa.text("""
            INSERT INTO stops
                (itinerary_id, position, type, transport_mode,
                 transport_line, transport_direction, duration_min,
                 cost, is_free)
            VALUES
                (:itin_id, :pos, 'transit', :mode,
                 :line, :direction, :dur, :cost, false)
        """), {
            "itin_id": row.itinerary_id,
            "pos": transit_pos,
            "mode": row.mode or 'walk',
            "line": row.line,
            "direction": row.direction,
            "dur": row.total_duration_min or None,
            "cost": row.total_cost,
        })

    # ------------------------------------------------------------------
    # 2 & 1. Drop transport_legs and transit_segments
    # ------------------------------------------------------------------
    op.drop_index('ix_transport_legs_segment_id', 'transport_legs')
    op.drop_table('transport_legs')
    op.drop_index('ix_transit_segments_itinerary_id', 'transit_segments')
    op.drop_table('transit_segments')
