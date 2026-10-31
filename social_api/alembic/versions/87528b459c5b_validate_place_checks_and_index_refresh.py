"""validate place checks and index refresh

The second half of 70035c01ad25, outside a transaction: VALIDATE CONSTRAINT
scans stops under a SHARE UPDATE EXCLUSIVE lock (writes keep flowing), and the
refresh index is built CONCURRENTLY, so a deploy against a populated table holds
no write lock for the length of either. Its own revision so a failed concurrent
build cannot leave the column revision half-applied; an INVALID index left
behind is dropped by hand (SELECT * FROM pg_index WHERE NOT indisvalid).

The non-Postgres branch exists only for completeness — the test suite builds
its schema with create_all and never reaches this file.

Revision ID: 87528b459c5b
Revises: 70035c01ad25
Create Date: 2026-10-31 15:02:07.610960+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '87528b459c5b'
down_revision: Union[str, None] = '70035c01ad25'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


_CHECKS = ("ck_stops_place_source", "ck_stops_place_id_no_coords", "ck_stops_link_no_coords")
_INDEX = "ix_stops_google_place_refresh"
_INDEX_WHERE = "google_place_id IS NOT NULL AND google_place_missing_at IS NULL"


def _is_postgres() -> bool:
    return op.get_context().dialect.name == "postgresql"


def upgrade() -> None:
    if _is_postgres():
        with op.get_context().autocommit_block():
            for name in _CHECKS:
                op.execute(f"ALTER TABLE stops VALIDATE CONSTRAINT {name}")
            op.create_index(
                _INDEX, 'stops', ['google_place_checked_at'],
                postgresql_where=sa.text(_INDEX_WHERE),
                postgresql_concurrently=True,
            )
    else:
        op.create_index(
            _INDEX, 'stops', ['google_place_checked_at'],
            sqlite_where=sa.text(_INDEX_WHERE),
        )


def downgrade() -> None:
    # A validated CHECK cannot be made NOT VALID again; dropping the index is
    # the whole downgrade, and the previous revision drops the constraints.
    if _is_postgres():
        with op.get_context().autocommit_block():
            op.drop_index(_INDEX, table_name='stops', postgresql_concurrently=True)
    else:
        op.drop_index(_INDEX, table_name='stops')
