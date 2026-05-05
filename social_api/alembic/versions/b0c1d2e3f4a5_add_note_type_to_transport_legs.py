"""add note_type to transport_legs

Revision ID: b0c1d2e3f4a5
Revises: b9c0d1e2f3a4
Create Date: 2026-05-05
"""

from typing import Union
from alembic import op
import sqlalchemy as sa

revision: str = 'b0c1d2e3f4a5'
down_revision: Union[str, None] = 'b9c0d1e2f3a4'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'transport_legs',
        sa.Column('note_type', sa.String(10), nullable=True),
    )
    op.create_check_constraint(
        'ck_leg_note_type',
        'transport_legs',
        "note_type IS NULL OR note_type IN ('advice','caution','avoid','info')",
    )


def downgrade() -> None:
    op.drop_constraint('ck_leg_note_type', 'transport_legs', type_='check')
    op.drop_column('transport_legs', 'note_type')
