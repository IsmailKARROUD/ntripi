"""rename stop type destination to arrival

Revision ID: b9c0d1e2f3a4
Revises: a6b7c8d9e0f1
Create Date: 2026-05-04

"""
from alembic import op

revision: str = 'b9c0d1e2f3a4'
down_revision: str = 'a6b7c8d9e0f1'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_constraint('ck_stop_type', 'stops', type_='check')
    op.execute("UPDATE stops SET type = 'arrival' WHERE type = 'destination'")
    op.create_check_constraint(
        'ck_stop_type',
        'stops',
        "type IN ('origin', 'waypoint', 'arrival')",
    )


def downgrade() -> None:
    op.drop_constraint('ck_stop_type', 'stops', type_='check')
    op.execute("UPDATE stops SET type = 'destination' WHERE type = 'arrival'")
    op.create_check_constraint(
        'ck_stop_type',
        'stops',
        "type IN ('origin', 'waypoint', 'destination')",
    )
