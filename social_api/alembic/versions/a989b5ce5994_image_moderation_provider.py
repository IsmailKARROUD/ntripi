"""image moderation provider

Records which provider scanned an image: image_moderation_logs.provider, NULL
or one of the MODERATION_PROVIDER values (ck_moderation_provider). Google Cloud
Vision joins AWS Rekognition as a scanner, chosen by that variable.

Rekognition was the only scanner before this revision, so every existing scan
row is backfilled 'rekognition'. A 'rejected_csam' row is a takedown's evidence,
not a scan, and stays NULL — as every future one will. A scan the previous build
writes between this migration and the new code starting stays NULL too.

The table holds 90 days of scans plus its unreviewed queue, so the backfill and
the CHECK's validating scan are small; nothing here needs CONCURRENTLY or NOT
VALID, and the new column carries no index.

Revision ID: a989b5ce5994
Revises: 1afc3c26511a
Create Date: 2026-10-25 17:50:32.847259+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a989b5ce5994'
down_revision: Union[str, None] = '1afc3c26511a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'image_moderation_logs',
        sa.Column('provider', sa.String(length=32), nullable=True),
    )
    op.execute(
        "UPDATE image_moderation_logs SET provider = 'rekognition' "
        "WHERE action <> 'rejected_csam'"
    )
    op.create_check_constraint(
        'ck_moderation_provider', 'image_moderation_logs',
        "provider IN ('rekognition','google_vision')",
    )


def downgrade() -> None:
    # Drops which provider scanned each row. The labels stay: a Cloud Vision row
    # keeps its {name, likelihood} labels, which the old admin pages print as 0%.
    op.drop_constraint('ck_moderation_provider', 'image_moderation_logs', type_='check')
    op.drop_column('image_moderation_logs', 'provider')
