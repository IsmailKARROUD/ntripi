"""add_travel_identity

Revision ID: a1b2c3d4e5f6
Revises: f5a2b3c4d1e0
Create Date: 2026-05-14 00:00:00.000000+00:00

Adds three travel-identity fields to users:
  passport_countries — JSON array of ISO alpha-2 codes (multiple nationalities)
  resident_country   — single ISO alpha-2 code (where the user lives)
  languages          — JSON array of ISO 639-1 codes (spoken languages)
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, None] = 'f5a2b3c4d1e0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('users', sa.Column('passport_countries', sa.JSON(), nullable=True))
    op.add_column('users', sa.Column('resident_country', sa.String(2), nullable=True))
    op.add_column('users', sa.Column('languages', sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'languages')
    op.drop_column('users', 'resident_country')
    op.drop_column('users', 'passport_countries')
