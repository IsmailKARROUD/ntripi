"""google place stops

A stop can now be a Google place found with Places Autocomplete. Google's terms
let us keep only its place ID, so that is all a stop holds from Google, with
the user's own search text beside it (what finds the place again if the ID
dies) and the two timestamps of the yearly refresh. place_source records where
every location comes from: osm, google, link or typed.

place_search_usage is the per-user hourly budget for the billed Autocomplete
calls (same shape as translation_user_usage).

Data step: coordinates are never stored beside a Google Maps link any more —
they were read out of Google's link or its fetched page, which is Google's
content. Every existing link stop loses them here and is marked 'link'. The
cleared coordinates cannot be restored by the downgrade.

The three CHECKs are added NOT VALID, so adding them takes no long lock;
validating them, and building the refresh index CONCURRENTLY, happen in the
next revision outside this transaction.

Revision ID: 70035c01ad25
Revises: a989b5ce5994
Create Date: 2026-10-31 15:01:45.743869+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = '70035c01ad25'
down_revision: Union[str, None] = 'a989b5ce5994'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


# (name, condition) — mirrored in Stop.__table_args__ for create_all.
_CHECKS = (
    ("ck_stops_place_source", "place_source IN ('osm','google','link','typed')"),
    ("ck_stops_place_id_no_coords",
     "google_place_id IS NULL OR (lat IS NULL AND lng IS NULL)"),
    ("ck_stops_link_no_coords", "map_url IS NULL OR (lat IS NULL AND lng IS NULL)"),
)


def _is_postgres() -> bool:
    return op.get_context().dialect.name == "postgresql"


def upgrade() -> None:
    op.add_column('stops', sa.Column('place_source', sa.String(length=10), nullable=True))
    op.add_column('stops', sa.Column('google_place_id', sa.Text(), nullable=True))
    op.add_column('stops', sa.Column('google_place_query', sa.String(length=200), nullable=True))
    op.add_column('stops', sa.Column(
        'google_place_checked_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('stops', sa.Column(
        'google_place_missing_at', sa.DateTime(timezone=True), nullable=True))

    # Before the CHECKs that this makes true.
    op.execute(
        "UPDATE stops SET lat = NULL, lng = NULL, place_source = 'link' "
        "WHERE map_url IS NOT NULL"
    )

    for name, condition in _CHECKS:
        if _is_postgres():
            op.execute(f"ALTER TABLE stops ADD CONSTRAINT {name} CHECK ({condition}) NOT VALID")
        else:
            op.create_check_constraint(name, 'stops', condition)

    op.create_table(
        'place_search_usage',
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('hour_start', sa.DateTime(timezone=True), nullable=False),
        sa.Column('requests', sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('user_id', 'hour_start'),
    )


def downgrade() -> None:
    # The coordinates the upgrade cleared beside links are gone for good.
    op.drop_table('place_search_usage')
    for name, _ in reversed(_CHECKS):
        op.drop_constraint(name, 'stops', type_='check')
    op.drop_column('stops', 'google_place_missing_at')
    op.drop_column('stops', 'google_place_checked_at')
    op.drop_column('stops', 'google_place_query')
    op.drop_column('stops', 'google_place_id')
    op.drop_column('stops', 'place_source')
