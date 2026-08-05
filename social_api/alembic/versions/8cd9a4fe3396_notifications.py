"""notifications

Creates the in-app notification feed plus the three preference columns that
gate its optional types.

Design notes worth keeping with the schema:

  * entity_id carries NO foreign key. The reference is polymorphic across
    itineraries, ratings, users and follows — the same reasoning as
    content_reports.target_id. A row whose entity is gone renders with a null
    title rather than blocking the delete or needing a cleanup job.

  * actor_id is SET NULL while user_id is CASCADE. Deleting the actor must not
    erase the recipient's history; deleting the recipient makes the row
    unreadable by anyone, so it goes.

  * Types are constrained strings with a check constraint, matching
    ck_bug_report_status / ck_report_reason rather than a native enum — adding
    a type is an ALTER of one constraint, not a Postgres enum migration.

  * The notify_* columns default TRUE for existing rows: the events they gate
    were previously invisible, so opting everyone in matches what users would
    expect the first time they open the screen.

Revision ID: 8cd9a4fe3396
Revises: 2b2bbad6e3c0
Create Date: 2026-08-05 19:34:02.077861+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '8cd9a4fe3396'
down_revision: Union[str, None] = '2b2bbad6e3c0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'notifications',
        sa.Column(
            'id', sa.UUID(), primary_key=True,
            server_default=sa.text('gen_random_uuid()'),
        ),
        sa.Column(
            'user_id', sa.UUID(), nullable=False,
        ),
        sa.Column('type', sa.String(length=32), nullable=False),
        sa.Column('subtype', sa.String(length=40), nullable=True),
        sa.Column('actor_id', sa.UUID(), nullable=True),
        sa.Column('entity_type', sa.String(length=20), nullable=True),
        sa.Column('entity_id', sa.UUID(), nullable=True),
        sa.Column('read_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            'created_at', sa.DateTime(timezone=True), nullable=False,
            server_default=sa.text('now()'),
        ),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['actor_id'], ['users.id'], ondelete='SET NULL'),
        sa.CheckConstraint(
            "type IN ('follow_request','new_follower','follow_accepted',"
            "'itinerary_rated','itinerary_saved','moderation_action')",
            name='ck_notification_type',
        ),
        sa.CheckConstraint(
            "entity_type IS NULL OR entity_type IN "
            "('itinerary','user','follow','rating')",
            name='ck_notification_entity_type',
        ),
    )
    op.create_index('ix_notifications_user_id', 'notifications', ['user_id'])
    op.create_index('ix_notifications_actor_id', 'notifications', ['actor_id'])
    op.create_index('ix_notifications_read_at', 'notifications', ['read_at'])
    # The one query the feed runs: one user's rows, newest first.
    op.create_index(
        'ix_notifications_user_created', 'notifications', ['user_id', 'created_at'],
    )

    for column in ('notify_ratings', 'notify_saves', 'notify_follow_accepted'):
        op.add_column(
            'users',
            sa.Column(
                column, sa.Boolean(), nullable=False,
                server_default=sa.text('true'),
            ),
        )


def downgrade() -> None:
    for column in ('notify_follow_accepted', 'notify_saves', 'notify_ratings'):
        op.drop_column('users', column)

    op.drop_index('ix_notifications_user_created', table_name='notifications')
    op.drop_index('ix_notifications_read_at', table_name='notifications')
    op.drop_index('ix_notifications_actor_id', table_name='notifications')
    op.drop_index('ix_notifications_user_id', table_name='notifications')
    op.drop_table('notifications')
