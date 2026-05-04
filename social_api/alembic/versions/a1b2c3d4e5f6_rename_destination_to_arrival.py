"""rename stop type destination to arrival

Revision ID: a1b2c3d4e5f6
Revises: f5a2b3c4d1e0
Create Date: 2026-05-04

"""
from alembic import op

revision: str = 'a1b2c3d4e5f6'
down_revision: str = 'f5a2b3c4d1e0'
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
