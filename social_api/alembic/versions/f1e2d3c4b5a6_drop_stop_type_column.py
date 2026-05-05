"""drop stop type column

Revision ID: f1e2d3c4b5a6
Revises: c0d1e2f3a4b5
Create Date: 2026-05-05

Stop type (origin/waypoint/arrival) is now derived from position order
on the client side. The column is no longer needed in the database.
"""
from alembic import op

revision: str = 'f1e2d3c4b5a6'
down_revision: str = 'c0d1e2f3a4b5'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_constraint('ck_stop_type', 'stops', type_='check')
    op.drop_column('stops', 'type')


def downgrade() -> None:
    import sqlalchemy as sa
    op.add_column('stops', sa.Column('type', sa.String(20), nullable=True))
    op.execute("UPDATE stops SET type = 'waypoint'")
    op.alter_column('stops', 'type', nullable=False)
    op.create_check_constraint(
        'ck_stop_type',
        'stops',
        "type IN ('origin', 'waypoint', 'arrival')",
    )
