"""add travel identity fields to users

Adds three new nullable columns to the users table:
  passport_countries — JSON list of ISO 3166-1 alpha-2 codes (e.g. ["MA","FR"])
  resident_country   — VARCHAR(2) ISO code for country of residence (e.g. "BE")
  languages          — JSON list of ISO 639-1 codes (e.g. ["FR","AR","EN"])

passport_countries is a list because users can hold multiple nationalities.
resident_country is a single code (one primary residence).
languages is a list with no fixed maximum (validated to 10 in the API layer).

Revision ID: 95a44d78f959
Revises: c1d2e3f4a5b6
Create Date: 2026-05-14
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '95a44d78f959'
down_revision: Union[str, None] = 'c1d2e3f4a5b6'
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
