"""allow undelete moderation log action

The /admin dashboard gains a Removed-itineraries lane whose only action is
restoring a soft-deleted itinerary. `unhide` was the closest existing verb, but
reusing it would make the audit trail lie about what was reversed — an unhide
clears hidden_at, an undelete clears deleted_at. So the vocabulary gains
'undelete'.

Widening only: no backfill, since no row can already carry a value the
constraint has been rejecting.

Revision ID: e17d93969953
Revises: 12b6e3451c36
Create Date: 2026-08-03 22:01:30.073476+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e17d93969953'
down_revision: Union[str, None] = '12b6e3451c36'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_OLD_ACTIONS = (
    "dismiss", "hide", "unhide", "delete", "warn", "ban", "unban",
    "appeal_restore", "appeal_uphold", "appeal_reduce",
    "auto_reject", "auto_hide_reports", "auto_hide_sla", "recheck",
    "appeal_filed", "legal_escalate",
)
# Mirrors MODERATION_LOG_ACTIONS in app/models/moderation_log.py, which builds
# the model-side CheckConstraint from the same vocabulary.
_NEW_ACTIONS = (
    "dismiss", "hide", "unhide", "undelete", "delete", "warn", "ban", "unban",
    "appeal_restore", "appeal_uphold", "appeal_reduce",
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


def downgrade() -> None:
    # Demote rather than delete: the row is an audit record of a real operator
    # decision, and 'unhide' is the nearest legacy verb for "this takedown was
    # reversed". The distinction between the two reversals is what is lost.
    op.execute(
        "UPDATE moderation_log SET action = 'unhide' WHERE action = 'undelete'"
    )
    op.drop_constraint('ck_moderation_log_action', 'moderation_log', type_='check')
    op.create_check_constraint(
        'ck_moderation_log_action', 'moderation_log',
        f"action IN ({_in_list(_OLD_ACTIONS)})",
    )
