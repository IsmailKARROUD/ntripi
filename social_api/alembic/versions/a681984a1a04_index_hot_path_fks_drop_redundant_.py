"""index hot-path FKs; drop redundant notification index

Revision ID: a681984a1a04
Revises: cc4e95613bad
Create Date: 2026-08-29 20:57:50.455286+00:00

Postgres does not create an index for a foreign key. Without one the join is a
seq scan, and — worse for these four — a DELETE on the parent locks the child
table and scans it whole, which is what every CASCADE below would do on account
or stop deletion.

saved_itineraries.user_id is the one with a live read behind it: the PK is
(itinerary_id, user_id), so its index cannot answer the Saved tab's
"WHERE user_id = me". itinerary_editors already carries the same trailing-column
index for exactly this reason.

The notifications index goes the other way: ix_notifications_user_id is a strict
prefix of ix_notifications_user_created (user_id, created_at), so it can never be
chosen over the wider one and only costs write throughput.

CONCURRENTLY (and therefore autocommit_block) so a deploy against a populated
table does not hold a write lock for the length of the build. It cannot run
inside a transaction, which is why the non-Postgres branch exists at all — the
test suite builds its schema with create_all and never reaches this file.
"""
from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = 'a681984a1a04'
down_revision: Union[str, None] = 'cc4e95613bad'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


# (index name, table, column)
_FK_INDEXES = (
    ("ix_saved_itineraries_user_id", "saved_itineraries", "user_id"),
    ("ix_itinerary_allowed_users_user_id", "itinerary_allowed_users", "user_id"),
    ("ix_itinerary_edit_locks_user_id", "itinerary_edit_locks", "user_id"),
    ("ix_transit_segments_to_stop_id", "transit_segments", "to_stop_id"),
)

_REDUNDANT = ("ix_notifications_user_id", "notifications")


def _is_postgres() -> bool:
    return op.get_context().dialect.name == "postgresql"


def upgrade() -> None:
    if _is_postgres():
        with op.get_context().autocommit_block():
            for name, table, column in _FK_INDEXES:
                op.create_index(name, table, [column], postgresql_concurrently=True)
            op.drop_index(_REDUNDANT[0], table_name=_REDUNDANT[1],
                          postgresql_concurrently=True)
    else:
        for name, table, column in _FK_INDEXES:
            op.create_index(name, table, [column])
        op.drop_index(_REDUNDANT[0], table_name=_REDUNDANT[1])


def downgrade() -> None:
    if _is_postgres():
        with op.get_context().autocommit_block():
            op.create_index(_REDUNDANT[0], _REDUNDANT[1], ["user_id"],
                            postgresql_concurrently=True)
            for name, table, _ in _FK_INDEXES:
                op.drop_index(name, table_name=table, postgresql_concurrently=True)
    else:
        op.create_index(_REDUNDANT[0], _REDUNDANT[1], ["user_id"])
        for name, table, _ in _FK_INDEXES:
            op.drop_index(name, table_name=table)
