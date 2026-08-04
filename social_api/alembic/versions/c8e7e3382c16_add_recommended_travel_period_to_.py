"""add recommended travel period to itineraries

Revision ID: c8e7e3382c16
Revises: e17d93969953
Create Date: 2026-08-04 19:24:05.870862+00:00

The author's answer to "when should I go?", in three optional parts:

  recommended_periods      list of {from_month, from_day, to_month, to_day}
                           windows. No year — a window is a recurring annual
                           span, so from_month=9/to_month=3 is a wrap-around
                           rather than reversed input. A list because the good
                           months are often not contiguous.
  recommended_weekdays     ISO-8601 weekday numbers, 1 = Monday … 7 = Sunday.
  recommended_period_note  the one-line "why", capped at 200 chars in Pydantic.

Generic JSON, not JSONB: the test suite builds its schema from ORM metadata on
SQLite, and a Postgres-only type would diverge the two. Shape, day validity and
the non-overlap rule live in schemas/itinerary.py — no JSON column in this
codebase carries a DB-level constraint.

All three are nullable. Additive only: no backfill, and every existing row
reads as "the author did not say".
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c8e7e3382c16'
down_revision: Union[str, None] = 'e17d93969953'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('itineraries', sa.Column('recommended_periods', sa.JSON(), nullable=True))
    op.add_column('itineraries', sa.Column('recommended_weekdays', sa.JSON(), nullable=True))
    op.add_column('itineraries', sa.Column('recommended_period_note', sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column('itineraries', 'recommended_period_note')
    op.drop_column('itineraries', 'recommended_weekdays')
    op.drop_column('itineraries', 'recommended_periods')
