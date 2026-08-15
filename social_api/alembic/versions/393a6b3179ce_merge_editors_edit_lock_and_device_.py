"""merge editors/edit-lock and device-tokens branches

Two feature branches both revised 2ddec1197cc9, forking the chain:

  192d73531acf  itinerary editors + edit lock   (ntripiworktree)
  dfb62a1759d8  device tokens for push          (Dev)

Production had already migrated to 192d73531acf, so deploying the other branch
failed at boot with "Can't locate revision identified by '192d73531acf'" — the
stamped revision did not exist in that image's versions/ directory.

NO DDL HERE, DELIBERATELY. A merge revision only rejoins the graph; both
parents keep their own upgrade(). Adding anything to upgrade() below would run
only for deployments that pass through this node and not for a fresh database
built by walking either parent, so it would silently skew the two.

Revision ID: 393a6b3179ce
Revises: 192d73531acf, dfb62a1759d8
Create Date: 2026-08-14 13:21:07.619403+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '393a6b3179ce'
down_revision: Union[str, None] = ('192d73531acf', 'dfb62a1759d8')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
