"""allow hidden itinerary moderation status

itineraries.moderation_status has been able to hold 'hidden' in code since the
admin/appeals tier landed, but its CHECK constraint was never widened to match.
b858424a1092 created it with the four image-moderation states, and d3db17c28b44
added 'hidden' to the ratings and users constraints only — the itineraries one
was left behind. Every auto-hide of an itinerary has therefore been raising
CheckViolation → 500: report thresholds (violence_threat/csam/sexual_content hide
on a single report), the SLA sweep, the post-outage re-check, operator hides,
appeal-reduce, and any create/update whose text scan returns hide_escalate.

The gap survived because the test suite builds its schema from ORM metadata and
the Itinerary model declared no constraint at all; the model now declares one, so
SQLite enforces the same five values.

Widening only: no backfill, because the constraint has been rejecting 'hidden'
all along and no row can be holding it.

Revision ID: 12b6e3451c36
Revises: 7f6e757d452c
Create Date: 2026-08-03 20:43:20.895904+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '12b6e3451c36'
down_revision: Union[str, None] = '7f6e757d452c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_OLD_STATUSES = ("pending", "approved", "flagged", "rejected")
# Same five values, same order, as ck_rating_moderation_status / ck_user_moderation_status.
_NEW_STATUSES = ("approved", "pending", "flagged", "hidden", "rejected")


def _in_list(values) -> str:
    return ",".join(f"'{value}'" for value in values)


def upgrade() -> None:
    op.drop_constraint(
        'ck_itinerary_moderation_status', 'itineraries', type_='check'
    )
    op.create_check_constraint(
        'ck_itinerary_moderation_status', 'itineraries',
        f"moderation_status IN ({_in_list(_NEW_STATUSES)})",
    )


def downgrade() -> None:
    # Demote rather than delete: an itinerary's takedown is carried by hidden_at,
    # not by this column — can_view_itinerary and the is_hidden idempotency guard
    # both key off hidden_at — so mapping to 'flagged' keeps the content down and
    # keeps it in the moderator queue.
    op.execute(
        "UPDATE itineraries SET moderation_status = 'flagged' "
        "WHERE moderation_status = 'hidden'"
    )
    op.drop_constraint(
        'ck_itinerary_moderation_status', 'itineraries', type_='check'
    )
    op.create_check_constraint(
        'ck_itinerary_moderation_status', 'itineraries',
        f"moderation_status IN ({_in_list(_OLD_STATUSES)})",
    )
