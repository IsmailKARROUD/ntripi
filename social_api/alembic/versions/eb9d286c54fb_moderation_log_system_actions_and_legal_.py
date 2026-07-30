"""moderation log system actions and legal escalations

Two changes:

1. moderation_log gains the automated actions (auto_reject, auto_hide_reports,
   auto_hide_sla, recheck, appeal_filed, legal_escalate) and 'rating' as a
   target type. Automated rows carry admin_user_id NULL and content_snapshot
   NULL — they record structured facts in `reason` and no raw content.

2. legal_escalations: CSAM signals that cannot be closed as a routine
   moderation item. Belgian law imposes obligations beyond hiding, so these get
   their own dashboard lane and a close action that demands a written note. No
   automated reporting to authorities is implemented — that is deliberate.

Revision ID: eb9d286c54fb
Revises: a673844f962a
Create Date: 2026-07-29 23:30:44.895532+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'eb9d286c54fb'
down_revision: Union[str, None] = 'a673844f962a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_OLD_ACTIONS = (
    "dismiss", "hide", "unhide", "delete", "warn", "ban", "unban",
    "appeal_restore", "appeal_uphold", "appeal_reduce",
)
_NEW_ACTIONS = _OLD_ACTIONS + (
    "auto_reject", "auto_hide_reports", "auto_hide_sla", "recheck",
    "appeal_filed", "legal_escalate",
)


def _in_list(values) -> str:
    return ",".join(f"'{value}'" for value in values)


def upgrade() -> None:
    op.drop_constraint('ck_moderation_log_action', 'moderation_log', type_='check')
    op.create_check_constraint(
        'ck_moderation_log_action', 'moderation_log',
        f"action IN ({_in_list(_NEW_ACTIONS)})",
    )
    op.drop_constraint('ck_moderation_log_target_type', 'moderation_log', type_='check')
    op.create_check_constraint(
        'ck_moderation_log_target_type', 'moderation_log',
        "target_type IN ('itinerary','user','rating')",
    )

    op.create_table(
        'legal_escalations',
        sa.Column('id', sa.UUID(), server_default=sa.text('gen_random_uuid()'),
                  nullable=False),
        sa.Column('target_type', sa.String(length=16), nullable=False),
        # No FK: evidence must survive a hard delete of the content.
        sa.Column('target_id', sa.UUID(), nullable=True),
        sa.Column('source', sa.String(length=16), nullable=False),
        sa.Column('report_id', sa.UUID(), nullable=True),
        sa.Column('decision_id', sa.UUID(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('now()'), nullable=False),
        sa.Column('closed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('closed_by', sa.UUID(), nullable=True),
        sa.Column('closure_note', sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(['report_id'], ['content_reports.id'],
                                ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['decision_id'], ['text_moderation_decisions.id'],
                                ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['closed_by'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.CheckConstraint(
            "target_type IN ('itinerary','rating','user')",
            name='ck_escalation_target_type',
        ),
        sa.CheckConstraint(
            "source IN ('report','score')", name='ck_escalation_source',
        ),
    )
    op.create_index(
        op.f('ix_legal_escalations_target_id'), 'legal_escalations', ['target_id'],
        unique=False,
    )
    op.create_index(
        op.f('ix_legal_escalations_created_at'), 'legal_escalations', ['created_at'],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f('ix_legal_escalations_created_at'), table_name='legal_escalations')
    op.drop_index(op.f('ix_legal_escalations_target_id'), table_name='legal_escalations')
    op.drop_table('legal_escalations')

    # Automated rows and rating targets cannot be expressed under the old
    # constraints, so they are removed before the constraints are narrowed.
    op.execute(
        "DELETE FROM moderation_log WHERE action NOT IN "
        f"({_in_list(_OLD_ACTIONS)}) OR target_type = 'rating'"
    )
    op.drop_constraint('ck_moderation_log_target_type', 'moderation_log', type_='check')
    op.create_check_constraint(
        'ck_moderation_log_target_type', 'moderation_log',
        "target_type IN ('itinerary','user')",
    )
    op.drop_constraint('ck_moderation_log_action', 'moderation_log', type_='check')
    op.create_check_constraint(
        'ck_moderation_log_action', 'moderation_log',
        f"action IN ({_in_list(_OLD_ACTIONS)})",
    )
