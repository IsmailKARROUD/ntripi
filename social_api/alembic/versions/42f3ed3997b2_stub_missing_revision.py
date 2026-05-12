"""stub: re-register revision applied to production

Revision ID: 42f3ed3997b2
Revises: f1e2d3c4b5a6
Create Date: 2026-05-06

This revision was applied to the production database but the original
migration file was never committed to the repository. The stub registers
the revision ID so Alembic can locate it and resume the chain. No schema
changes are made here — the database is already in the correct state.
"""
from alembic import op

revision: str = '42f3ed3997b2'
down_revision: str = 'f1e2d3c4b5a6'
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
