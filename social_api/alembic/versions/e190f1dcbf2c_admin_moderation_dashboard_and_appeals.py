"""admin moderation dashboard and appeals

Adds the internal moderation dashboard + user-appeals infrastructure:
  - users.is_admin — grants /admin access (manual SQL only).
  - itineraries.hidden_at / deleted_at — moderator soft-state (owner-visible
    hide vs. everyone-invisible soft delete; row + files preserved as evidence).
  - image_moderation_logs.reviewed_at — flagged-queue "done" marker.
  - content_reports resolution CHECK gains 'content_hidden'.
  - moderation_log — append-only operator-action audit trail with snapshots.
  - appeals — user appeals of delete/warn/ban actions.

Revision ID: e190f1dcbf2c
Revises: b858424a1092
Create Date: 2026-07-28 11:39:22.214503+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e190f1dcbf2c'
down_revision: Union[str, None] = 'b858424a1092'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # --- column additions ---------------------------------------------------
    op.add_column(
        'users',
        sa.Column('is_admin', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    )
    op.add_column(
        'itineraries',
        sa.Column('hidden_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        'itineraries',
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        'image_moderation_logs',
        sa.Column('reviewed_at', sa.DateTime(timezone=True), nullable=True),
    )

    # --- content_reports resolution CHECK: add 'content_hidden' -------------
    op.drop_constraint('ck_report_resolution', 'content_reports', type_='check')
    op.create_check_constraint(
        'ck_report_resolution',
        'content_reports',
        "resolution IN ('pending','dismissed','content_removed','content_hidden','user_warned','user_banned')",
    )

    # --- moderation_log -----------------------------------------------------
    op.create_table(
        'moderation_log',
        sa.Column('id', sa.UUID(), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('admin_user_id', sa.UUID(), nullable=True),
        sa.Column('target_type', sa.String(length=16), nullable=False),
        sa.Column('target_id', sa.UUID(), nullable=True),
        sa.Column('action', sa.String(length=32), nullable=False),
        sa.Column('reason', sa.Text(), nullable=False),
        sa.Column('content_snapshot', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.CheckConstraint(
            "target_type IN ('itinerary','user')",
            name='ck_moderation_log_target_type',
        ),
        sa.CheckConstraint(
            "action IN ('dismiss','hide','unhide','delete','warn','ban','unban',"
            "'appeal_restore','appeal_uphold','appeal_reduce')",
            name='ck_moderation_log_action',
        ),
        sa.ForeignKeyConstraint(['admin_user_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        op.f('ix_moderation_log_admin_user_id'),
        'moderation_log', ['admin_user_id'], unique=False,
    )
    op.create_index(
        op.f('ix_moderation_log_target_id'),
        'moderation_log', ['target_id'], unique=False,
    )
    op.create_index(
        op.f('ix_moderation_log_created_at'),
        'moderation_log', ['created_at'], unique=False,
    )

    # --- appeals ------------------------------------------------------------
    op.create_table(
        'appeals',
        sa.Column('id', sa.UUID(), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('user_id', sa.UUID(), nullable=False),
        sa.Column('moderation_log_id', sa.UUID(), nullable=True),
        sa.Column('target_type', sa.String(length=16), nullable=False),
        sa.Column('target_id', sa.UUID(), nullable=False),
        sa.Column('status', sa.String(length=16), server_default=sa.text("'pending'"), nullable=False),
        sa.Column('user_reason', sa.Text(), nullable=False),
        sa.Column('admin_response', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.CheckConstraint(
            "status IN ('pending','upheld','restored','reduced')",
            name='ck_appeal_status',
        ),
        sa.CheckConstraint(
            "target_type IN ('itinerary','user')",
            name='ck_appeal_target_type',
        ),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['moderation_log_id'], ['moderation_log.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        op.f('ix_appeals_user_id'),
        'appeals', ['user_id'], unique=False,
    )
    op.create_index(
        op.f('ix_appeals_target_id'),
        'appeals', ['target_id'], unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f('ix_appeals_target_id'), table_name='appeals')
    op.drop_index(op.f('ix_appeals_user_id'), table_name='appeals')
    op.drop_table('appeals')

    op.drop_index(op.f('ix_moderation_log_created_at'), table_name='moderation_log')
    op.drop_index(op.f('ix_moderation_log_target_id'), table_name='moderation_log')
    op.drop_index(op.f('ix_moderation_log_admin_user_id'), table_name='moderation_log')
    op.drop_table('moderation_log')

    op.drop_constraint('ck_report_resolution', 'content_reports', type_='check')
    op.create_check_constraint(
        'ck_report_resolution',
        'content_reports',
        "resolution IN ('pending','dismissed','content_removed','user_warned','user_banned')",
    )

    op.drop_column('image_moderation_logs', 'reviewed_at')
    op.drop_column('itineraries', 'deleted_at')
    op.drop_column('itineraries', 'hidden_at')
    op.drop_column('users', 'is_admin')
