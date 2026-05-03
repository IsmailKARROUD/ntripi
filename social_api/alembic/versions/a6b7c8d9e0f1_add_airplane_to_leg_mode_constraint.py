"""add airplane to transport_legs mode constraint

Revision ID: a6b7c8d9e0f1
Revises: f5a2b3c4d1e0
Create Date: 2026-05-03 00:00:00.000000+00:00

The original migration omitted 'airplane' from ck_leg_mode.
The ORM model already includes it; this migration brings the DB in sync.
"""
from typing import Sequence, Union

from alembic import op


revision: str = 'a6b7c8d9e0f1'
down_revision: Union[str, None] = 'f5a2b3c4d1e0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_constraint('ck_leg_mode', 'transport_legs', type_='check')
    op.create_check_constraint(
        'ck_leg_mode',
        'transport_legs',
        "mode IN ('walk','bus','tram','metro','train','taxi','uber','bike','ferry','car','airplane')",
    )


def downgrade() -> None:
    op.drop_constraint('ck_leg_mode', 'transport_legs', type_='check')
    op.create_check_constraint(
        'ck_leg_mode',
        'transport_legs',
        "mode IN ('walk','bus','tram','metro','train','taxi','uber','bike','ferry','car')",
    )
