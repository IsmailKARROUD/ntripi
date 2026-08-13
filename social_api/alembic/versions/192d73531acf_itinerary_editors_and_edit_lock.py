"""itinerary editors and edit lock

Adds collaborative editing:

  itinerary_editors     — who, besides the owner, may modify an itinerary.
                          A grant is inert unless can_view_itinerary() also
                          passes, so this table never widens visibility.

  itinerary_edit_locks  — the live editing claim. itinerary_id is the PK, so
                          "at most one holder" is a database invariant. The
                          claim is identified by a rotating token hash, not by
                          user_id: a takeover rotates it, which is what leaves
                          the previous device unable to save.

Also widens ck_notification_type for 'itinerary_editor_added'. PostgreSQL
cannot alter a CHECK constraint in place, so it is dropped and recreated.

Revision ID: 192d73531acf
Revises: 2ddec1197cc9
Create Date: 2026-08-12 13:58:39.388538+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '192d73531acf'
down_revision: Union[str, None] = '2ddec1197cc9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


_NOTIFICATION_TYPES_BEFORE = (
    "'follow_request','new_follower','follow_accepted',"
    "'itinerary_rated','itinerary_saved','moderation_action'"
)
_NOTIFICATION_TYPES_AFTER = _NOTIFICATION_TYPES_BEFORE + ",'itinerary_editor_added'"


def upgrade() -> None:
    op.create_table(
        'itinerary_editors',
        sa.Column('itinerary_id', sa.UUID(), nullable=False),
        sa.Column('user_id', sa.UUID(), nullable=False),
        sa.Column('granted_by', sa.UUID(), nullable=True),
        sa.Column(
            'created_at', sa.DateTime(timezone=True), nullable=False,
            server_default=sa.text('now()'),
        ),
        sa.ForeignKeyConstraint(
            ['itinerary_id'], ['itineraries.id'], ondelete='CASCADE',
        ),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        # Audit only — losing the granting account must not revoke the grant.
        sa.ForeignKeyConstraint(['granted_by'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('itinerary_id', 'user_id'),
    )
    # "Itineraries I can edit" queries the trailing PK column, which the
    # composite index cannot serve.
    op.create_index('ix_itinerary_editors_user', 'itinerary_editors', ['user_id'])

    op.create_table(
        'itinerary_edit_locks',
        # PK, not just FK: one holder per itinerary is enforced by the database.
        sa.Column('itinerary_id', sa.UUID(), nullable=False),
        sa.Column('user_id', sa.UUID(), nullable=False),
        sa.Column('token_hash', sa.String(length=64), nullable=False),
        sa.Column('acquired_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('last_heartbeat_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ['itinerary_id'], ['itineraries.id'], ondelete='CASCADE',
        ),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('itinerary_id'),
    )
    op.create_index(
        'ix_itinerary_edit_locks_heartbeat',
        'itinerary_edit_locks', ['last_heartbeat_at'],
    )

    op.drop_constraint('ck_notification_type', 'notifications', type_='check')
    op.create_check_constraint(
        'ck_notification_type', 'notifications',
        f"type IN ({_NOTIFICATION_TYPES_AFTER})",
    )


def downgrade() -> None:
    # Rows of the retired type would violate the narrower constraint, so drop
    # them before restoring it.
    op.execute("DELETE FROM notifications WHERE type = 'itinerary_editor_added'")
    op.drop_constraint('ck_notification_type', 'notifications', type_='check')
    op.create_check_constraint(
        'ck_notification_type', 'notifications',
        f"type IN ({_NOTIFICATION_TYPES_BEFORE})",
    )

    op.drop_index('ix_itinerary_edit_locks_heartbeat', 'itinerary_edit_locks')
    op.drop_table('itinerary_edit_locks')
    op.drop_index('ix_itinerary_editors_user', 'itinerary_editors')
    op.drop_table('itinerary_editors')
