"""recommended duration on itineraries

itineraries.recommended_duration_min — the author's recommended minimum time to
spend on the trip, in minutes (1 … 527,039: the days/hours/minutes wheel's
365 d 23 h 59 min). NULL = not set, and the app then shows the length it
computes from the stops and transport, as before. The range is the request
schema's to enforce, as for a stop's duration_min.

One nullable column without a default is a catalogue change in PostgreSQL (no
table rewrite), so nothing here needs CONCURRENTLY.

Revision ID: 3b31cf3670bd
Revises: e24b3c5c59ba
Create Date: 2026-11-09 01:19:31.183955+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '3b31cf3670bd'
down_revision: Union[str, None] = 'e24b3c5c59ba'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'itineraries',
        sa.Column('recommended_duration_min', sa.Integer(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('itineraries', 'recommended_duration_min')
