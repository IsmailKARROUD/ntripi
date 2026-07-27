"""add content_reports table

Revision ID: acd2209b7778
Revises: 5a1d7e20ab52
Create Date: 2026-07-27 09:56:32.120223+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'acd2209b7778'
down_revision: Union[str, None] = '5a1d7e20ab52'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'content_reports',
        sa.Column(
            'id',
            sa.UUID(),
            server_default=sa.text('gen_random_uuid()'),
            nullable=False,
        ),
        # Nullable + SET NULL: the audit row outlives itinerary/account deletion.
        sa.Column('reported_itinerary_id', sa.UUID(), nullable=True),
        sa.Column('reporter_user_id', sa.UUID(), nullable=True),
        sa.Column('reason', sa.String(length=32), nullable=False),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('reporter_ip_hash', sa.String(length=64), nullable=True),
        sa.Column(
            'created_at',
            sa.DateTime(timezone=True),
            server_default=sa.text('now()'),
            nullable=False,
        ),
        sa.Column('resolved_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            'resolution',
            sa.String(length=32),
            server_default=sa.text("'pending'"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ['reported_itinerary_id'],
            ['itineraries.id'],
            ondelete='SET NULL',
        ),
        sa.ForeignKeyConstraint(
            ['reporter_user_id'],
            ['users.id'],
            ondelete='SET NULL',
        ),
        sa.PrimaryKeyConstraint('id'),
        sa.CheckConstraint(
            "reason IN ('spam','nsfw','violence','hate_speech','harassment','copyright','other')",
            name='ck_report_reason',
        ),
        sa.CheckConstraint(
            "resolution IN ('pending','dismissed','content_removed','user_warned','user_banned')",
            name='ck_report_resolution',
        ),
    )
    op.create_index(
        'ix_content_reports_reported_itinerary_id',
        'content_reports',
        ['reported_itinerary_id'],
    )
    op.create_index(
        'ix_content_reports_reporter_user_id',
        'content_reports',
        ['reporter_user_id'],
    )
    op.create_index(
        'ix_content_reports_reporter_ip_hash',
        'content_reports',
        ['reporter_ip_hash'],
    )


def downgrade() -> None:
    op.drop_index('ix_content_reports_reporter_ip_hash', table_name='content_reports')
    op.drop_index('ix_content_reports_reporter_user_id', table_name='content_reports')
    op.drop_index('ix_content_reports_reported_itinerary_id', table_name='content_reports')
    op.drop_table('content_reports')
