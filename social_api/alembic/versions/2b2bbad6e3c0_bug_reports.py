"""bug reports

bug_reports: a user telling us the app itself is broken, filed by shaking the
phone. Deliberately not a content_reports row — that table is moderation
evidence with hide thresholds and escalation paths, this one is a support ticket
with a screenshot and device diagnostics.

Both user FKs are SET NULL rather than CASCADE: a bug report keeps its
diagnostic value after the reporter deletes their account, and closed_by_admin
must survive an operator leaving. screenshot_key holds the storage key, not a
URL, because the retention purge needs it to delete the object.

Revision ID: 2b2bbad6e3c0
Revises: c8e7e3382c16
Create Date: 2026-08-05 12:29:54.256895+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '2b2bbad6e3c0'
down_revision: Union[str, None] = 'c8e7e3382c16'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'bug_reports',
        sa.Column('id', sa.UUID(), server_default=sa.text('gen_random_uuid()'),
                  nullable=False),
        sa.Column('user_id', sa.UUID(), nullable=True),
        sa.Column('message', sa.Text(), nullable=False),
        sa.Column('category', sa.String(length=16), nullable=True),
        sa.Column('screenshot_key', sa.String(length=255), nullable=True),
        sa.Column('app_version', sa.String(length=32), nullable=True),
        sa.Column('platform', sa.String(length=16), nullable=True),
        sa.Column('os_version', sa.String(length=64), nullable=True),
        sa.Column('device_model', sa.String(length=96), nullable=True),
        sa.Column('route', sa.String(length=255), nullable=True),
        sa.Column('locale', sa.String(length=8), nullable=True),
        sa.Column('theme_mode', sa.String(length=8), nullable=True),
        sa.Column('status', sa.String(length=16), server_default='open',
                  nullable=False),
        sa.Column('resolution_note', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('now()'), nullable=False),
        sa.Column('closed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('closed_by_admin_id', sa.UUID(), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['closed_by_admin_id'], ['users.id'],
                                ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.CheckConstraint(
            "category IS NULL OR category IN "
            "('crash','visual','data','slow','other')",
            name='ck_bug_report_category',
        ),
        sa.CheckConstraint(
            "platform IS NULL OR platform IN "
            "('ios','android','web','macos','windows','linux')",
            name='ck_bug_report_platform',
        ),
        sa.CheckConstraint(
            "status IN ('open','closed')", name='ck_bug_report_status',
        ),
    )
    # The only query the admin lane runs: open reports, oldest first.
    op.create_index(
        'ix_bug_reports_status_created', 'bug_reports', ['status', 'created_at'],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index('ix_bug_reports_status_created', table_name='bug_reports')
    op.drop_table('bug_reports')
