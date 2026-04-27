"""add_annotation_updated_at

Add updated_at column to the annotations table to support editing.
Backfilled from created_at for existing rows.

Revision ID: e7f8a9b0c1d2
Revises: d4e5f6a7b8c9
Create Date: 2026-04-28 00:00:00.000000+00:00
"""

from alembic import op
import sqlalchemy as sa

revision = 'e7f8a9b0c1d2'
down_revision = 'd4e5f6a7b8c9'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Step 1 — Add nullable initially so backfill can run.
    op.add_column(
        'annotations',
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
    )

    # Step 2 — Backfill from created_at.
    op.execute(
        "UPDATE annotations SET updated_at = created_at WHERE updated_at IS NULL"
    )

    # Step 3 — Make non-null with a server default for future inserts.
    op.alter_column(
        'annotations',
        'updated_at',
        nullable=False,
        server_default=sa.text("now()"),
    )


def downgrade() -> None:
    op.drop_column('annotations', 'updated_at')
