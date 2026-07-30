"""allow rating targets on appeals

Review notes can now be hidden on their own (a stranger's abusive review must
not take down the itinerary owner's trip), so their authors need to be able to
appeal that — the appeals table has to accept 'rating' as a target type.

Revision ID: cc74b2080cbf
Revises: eb9d286c54fb
Create Date: 2026-07-30 07:19:08.336794+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'cc74b2080cbf'
down_revision: Union[str, None] = 'eb9d286c54fb'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_constraint('ck_appeal_target_type', 'appeals', type_='check')
    op.create_check_constraint(
        'ck_appeal_target_type', 'appeals',
        "target_type IN ('itinerary','user','rating')",
    )


def downgrade() -> None:
    # Rating appeals cannot be expressed under the old constraint.
    op.execute("DELETE FROM appeals WHERE target_type = 'rating'")
    op.drop_constraint('ck_appeal_target_type', 'appeals', type_='check')
    op.create_check_constraint(
        'ck_appeal_target_type', 'appeals',
        "target_type IN ('itinerary','user')",
    )
