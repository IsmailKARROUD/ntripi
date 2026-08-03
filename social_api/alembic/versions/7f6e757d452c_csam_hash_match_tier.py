"""csam hash match takedown

Widens two CHECK constraints so a Cloudflare CSAM notice can be actioned and
preserved:

1. image_moderation_logs.action gains 'rejected_csam' — the evidence row for a
   hash match. It is exempt from the 90-day purge (moderation_service.
   PRESERVED_ACTION), because once the object is deleted this row and its
   SHA-256 are the only surviving record of a reportable event.
2. legal_escalations.source gains 'hash_match', alongside the human report and
   the classifier score.

The suspension itself reuses the existing operator 'ban' action: a takedown has
a human actor (the operator working the Cloudflare digest), so it carries a
content snapshot and shows up in the /admin/log unban flow like any other ban.

Columns-only change: no new tables, no data backfill.

Revision ID: 7f6e757d452c
Revises: 9dcbd2b7d34c
Create Date: 2026-07-30 20:48:10.527797+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7f6e757d452c'
down_revision: Union[str, None] = '9dcbd2b7d34c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_OLD_IMAGE_ACTIONS = ("approved", "flagged", "rejected", "error_allowed")
_NEW_IMAGE_ACTIONS = _OLD_IMAGE_ACTIONS + ("rejected_csam",)

_OLD_SOURCES = ("report", "score")
_NEW_SOURCES = _OLD_SOURCES + ("hash_match",)


def _in_list(values) -> str:
    return ",".join(f"'{value}'" for value in values)


def upgrade() -> None:
    op.drop_constraint('ck_moderation_action', 'image_moderation_logs', type_='check')
    op.create_check_constraint(
        'ck_moderation_action', 'image_moderation_logs',
        f"action IN ({_in_list(_NEW_IMAGE_ACTIONS)})",
    )

    op.drop_constraint('ck_escalation_source', 'legal_escalations', type_='check')
    op.create_check_constraint(
        'ck_escalation_source', 'legal_escalations',
        f"source IN ({_in_list(_NEW_SOURCES)})",
    )


def downgrade() -> None:
    # CSAM rows cannot be expressed under the old constraints. They are mapped
    # onto their nearest legacy value rather than deleted — every one of them is
    # evidence of a reportable event, and the sibling migrations' delete-then-
    # narrow pattern would destroy it. Running this in production still loses
    # the distinction that made those rows purge-exempt; get counsel sign-off
    # first. See docs/csam_response_runbook.md.
    op.execute(
        "UPDATE image_moderation_logs SET action = 'rejected' "
        "WHERE action = 'rejected_csam'"
    )
    op.drop_constraint('ck_moderation_action', 'image_moderation_logs', type_='check')
    op.create_check_constraint(
        'ck_moderation_action', 'image_moderation_logs',
        f"action IN ({_in_list(_OLD_IMAGE_ACTIONS)})",
    )

    op.execute(
        "UPDATE legal_escalations SET source = 'score' WHERE source = 'hash_match'"
    )
    op.drop_constraint('ck_escalation_source', 'legal_escalations', type_='check')
    op.create_check_constraint(
        'ck_escalation_source', 'legal_escalations',
        f"source IN ({_in_list(_OLD_SOURCES)})",
    )
