"""add moderation_status to ratings and users

Text moderation needs a content state per moderated record. Itineraries already
have `moderation_status` (added for image moderation; text now shares it, and
stop / annotation / transport-leg text rolls up to the parent itinerary because
hiding is itinerary-level). Two records need their own:

  itinerary_ratings — a stranger's abusive review must never take down the
  itinerary owner's trip, so review notes carry their own state.

  users — covers display_name and bio. Distinct from is_active, which is the
  ban switch.

Existing rows are backfilled to 'approved' by the server default: content that
predates moderation is treated as clean, not as an unreviewed backlog.

Revision ID: d3db17c28b44
Revises: 4bdacee286ac
Create Date: 2026-07-29 19:02:31.840761+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd3db17c28b44'
down_revision: Union[str, None] = '4bdacee286ac'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_STATUSES = "('approved','pending','flagged','hidden','rejected')"


def upgrade() -> None:
    op.add_column(
        'itinerary_ratings',
        sa.Column('moderation_status', sa.String(length=20),
                  server_default=sa.text("'approved'"), nullable=False),
    )
    op.create_check_constraint(
        'ck_rating_moderation_status', 'itinerary_ratings',
        f"moderation_status IN {_STATUSES}",
    )

    op.add_column(
        'users',
        sa.Column('moderation_status', sa.String(length=20),
                  server_default=sa.text("'approved'"), nullable=False),
    )
    op.create_check_constraint(
        'ck_user_moderation_status', 'users',
        f"moderation_status IN {_STATUSES}",
    )


def downgrade() -> None:
    op.drop_constraint('ck_user_moderation_status', 'users', type_='check')
    op.drop_column('users', 'moderation_status')

    op.drop_constraint('ck_rating_moderation_status', 'itinerary_ratings', type_='check')
    op.drop_column('itinerary_ratings', 'moderation_status')
