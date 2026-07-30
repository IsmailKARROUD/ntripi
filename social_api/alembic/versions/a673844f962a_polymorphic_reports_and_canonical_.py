"""polymorphic reports and canonical reasons

Three changes to content_reports:

1. Polymorphic target. `reported_itinerary_id` becomes `target_type` +
   `target_id`, so ratings and profiles can be reported too. target_id carries
   NO foreign key — same evidence rule as moderation_log: a hard delete of the
   reported content must not cascade away the record that it was reported.
   Existing rows backfill as ('itinerary', reported_itinerary_id).

2. Canonical reason vocabulary. The old list was invented ad hoc; the new one
   maps 1:1 onto the distinct-reporter hide thresholds. Existing rows are
   translated (nsfw→sexual_content, violence→violence_threat, copyright→other).
   Deployed clients still SEND the old values — the Pydantic schema accepts them
   and report_service.normalize_reason translates before storage, so this column
   only ever holds canonical values from here on.

3. `auto_hidden` resolution, for content taken down by the SLA sweep or the
   report threshold. Distinct from `content_hidden` (a human hid it) so the
   audit trail never claims a moderator acted when none did.

The downgrade is faithful: itinerary targets go back into a rebuilt
reported_itinerary_id and reasons are mapped back. Rating/profile reports have
no representation in the old shape and are dropped — noted here because it is
the one lossy step, and it is unavoidable.

Revision ID: a673844f962a
Revises: d3db17c28b44
Create Date: 2026-07-29 23:29:51.652010+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a673844f962a'
down_revision: Union[str, None] = 'd3db17c28b44'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_NEW_REASONS = (
    "csam", "sexual_content", "violence_threat",
    "hate_speech", "harassment", "other", "spam",
)
_OLD_REASONS = (
    "spam", "nsfw", "violence", "hate_speech", "harassment", "copyright", "other",
)
_NEW_RESOLUTIONS = (
    "pending", "dismissed", "content_removed", "content_hidden",
    "user_warned", "user_banned", "auto_hidden",
)
_OLD_RESOLUTIONS = (
    "pending", "dismissed", "content_removed", "content_hidden",
    "user_warned", "user_banned",
)

# nsfw/violence/copyright were the pre-canonical names.
_REASON_UP = {"nsfw": "sexual_content", "violence": "violence_threat", "copyright": "other"}
_REASON_DOWN = {"sexual_content": "nsfw", "violence_threat": "violence", "csam": "nsfw"}


def _in_list(values) -> str:
    return ",".join(f"'{value}'" for value in values)


def upgrade() -> None:
    # --- 1. polymorphic target -------------------------------------------------
    op.add_column(
        'content_reports',
        sa.Column('target_type', sa.String(length=16), nullable=True),
    )
    op.add_column(
        'content_reports',
        sa.Column('target_id', sa.UUID(), nullable=True),
    )
    op.execute(
        "UPDATE content_reports "
        "SET target_type = 'itinerary', target_id = reported_itinerary_id"
    )
    # Rows whose itinerary FK was already SET-NULLed keep target_type so the
    # check constraint holds; target_id stays NULL (the target is gone).
    op.execute(
        "UPDATE content_reports SET target_type = 'itinerary' WHERE target_type IS NULL"
    )
    op.alter_column('content_reports', 'target_type', nullable=False)
    op.create_index(
        op.f('ix_content_reports_target_id'), 'content_reports', ['target_id'],
        unique=False,
    )
    op.create_check_constraint(
        'ck_report_target_type', 'content_reports',
        "target_type IN ('itinerary','rating','user')",
    )
    op.drop_index(
        op.f('ix_content_reports_reported_itinerary_id'), table_name='content_reports'
    )
    op.drop_column('content_reports', 'reported_itinerary_id')

    # --- 2. canonical reasons --------------------------------------------------
    # Constraint first: the old one would reject the translated values.
    op.drop_constraint('ck_report_reason', 'content_reports', type_='check')
    for old, new in _REASON_UP.items():
        op.execute(
            f"UPDATE content_reports SET reason = '{new}' WHERE reason = '{old}'"
        )
    op.create_check_constraint(
        'ck_report_reason', 'content_reports', f"reason IN ({_in_list(_NEW_REASONS)})",
    )

    # --- 3. auto_hidden resolution --------------------------------------------
    op.drop_constraint('ck_report_resolution', 'content_reports', type_='check')
    op.create_check_constraint(
        'ck_report_resolution', 'content_reports',
        f"resolution IN ({_in_list(_NEW_RESOLUTIONS)})",
    )

    # The SLA sweep scans for pending reports older than the deadline.
    op.create_index(
        op.f('ix_content_reports_created_at'), 'content_reports', ['created_at'],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f('ix_content_reports_created_at'), table_name='content_reports')

    # auto_hidden has no old equivalent — the closest truthful mapping is
    # content_hidden (the content IS hidden; only the actor differs).
    op.execute(
        "UPDATE content_reports SET resolution = 'content_hidden' "
        "WHERE resolution = 'auto_hidden'"
    )
    op.drop_constraint('ck_report_resolution', 'content_reports', type_='check')
    op.create_check_constraint(
        'ck_report_resolution', 'content_reports',
        f"resolution IN ({_in_list(_OLD_RESOLUTIONS)})",
    )

    op.drop_constraint('ck_report_reason', 'content_reports', type_='check')
    for new, old in _REASON_DOWN.items():
        op.execute(
            f"UPDATE content_reports SET reason = '{old}' WHERE reason = '{new}'"
        )
    op.create_check_constraint(
        'ck_report_reason', 'content_reports', f"reason IN ({_in_list(_OLD_REASONS)})",
    )

    op.add_column(
        'content_reports',
        sa.Column('reported_itinerary_id', sa.UUID(), nullable=True),
    )
    op.create_foreign_key(
        'content_reports_reported_itinerary_id_fkey', 'content_reports',
        'itineraries', ['reported_itinerary_id'], ['id'], ondelete='SET NULL',
    )
    op.execute(
        "UPDATE content_reports SET reported_itinerary_id = target_id "
        "WHERE target_type = 'itinerary'"
    )
    # Lossy by necessity: rating and profile reports cannot be expressed in the
    # itinerary-only shape.
    op.execute("DELETE FROM content_reports WHERE target_type <> 'itinerary'")
    op.create_index(
        op.f('ix_content_reports_reported_itinerary_id'), 'content_reports',
        ['reported_itinerary_id'], unique=False,
    )

    op.drop_constraint('ck_report_target_type', 'content_reports', type_='check')
    op.drop_index(op.f('ix_content_reports_target_id'), table_name='content_reports')
    op.drop_column('content_reports', 'target_id')
    op.drop_column('content_reports', 'target_type')
