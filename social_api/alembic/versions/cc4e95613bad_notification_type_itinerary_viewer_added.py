"""notification type itinerary_viewer_added

Widens ck_notification_type for 'itinerary_viewer_added' — the notice an owner's
allowlist grant sends. PostgreSQL cannot alter a CHECK constraint in place, so
it is dropped and recreated (same shape as 192d73531acf, which added
'itinerary_editor_added').

Revision ID: cc4e95613bad
Revises: 393a6b3179ce
Create Date: 2026-08-15 17:41:22.108156+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'cc4e95613bad'
down_revision: Union[str, None] = '393a6b3179ce'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


_NOTIFICATION_TYPES_BEFORE = (
    "'follow_request','new_follower','follow_accepted',"
    "'itinerary_rated','itinerary_saved','moderation_action',"
    "'itinerary_editor_added'"
)
_NOTIFICATION_TYPES_AFTER = _NOTIFICATION_TYPES_BEFORE + ",'itinerary_viewer_added'"


def upgrade() -> None:
    op.drop_constraint('ck_notification_type', 'notifications', type_='check')
    op.create_check_constraint(
        'ck_notification_type', 'notifications',
        f"type IN ({_NOTIFICATION_TYPES_AFTER})",
    )


def downgrade() -> None:
    # Rows of the retired type would violate the narrower constraint, so drop
    # them before restoring it.
    op.execute("DELETE FROM notifications WHERE type = 'itinerary_viewer_added'")
    op.drop_constraint('ck_notification_type', 'notifications', type_='check')
    op.create_check_constraint(
        'ck_notification_type', 'notifications',
        f"type IN ({_NOTIFICATION_TYPES_BEFORE})",
    )
