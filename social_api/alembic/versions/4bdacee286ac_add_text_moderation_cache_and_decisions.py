"""add text moderation cache and decisions

Two tables backing automated text moderation:

  text_moderation_cache — verdicts keyed by sha256(text + model + policy
  version), so identical text is never re-submitted to a paid API and a
  container restart doesn't lose the cache. Holds no raw text and no user
  reference; a model or policy change moves the key, which is how invalidation
  happens.

  text_moderation_decisions — one append-only row per scan: the audit record
  backing the DSA statement-of-reasons obligation, and (where reviewed_at is
  NULL) the moderator's text-flag queue. target_id has no FK on purpose, so a
  hard delete of the content cannot cascade away the evidence; author_user_id
  is SET NULL so the row outlives the account while retaining nothing personal.

Revision ID: 4bdacee286ac
Revises: e190f1dcbf2c
Create Date: 2026-07-29 18:25:23.951442+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '4bdacee286ac'
down_revision: Union[str, None] = 'e190f1dcbf2c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'text_moderation_cache',
        sa.Column('cache_key', sa.String(length=64), nullable=False),
        sa.Column('outcome', sa.String(length=16), nullable=False),
        sa.Column('scores', sa.JSON(), nullable=False),
        sa.Column('provider', sa.String(length=32), nullable=False),
        sa.Column('model', sa.String(length=64), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('now()'), nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint('cache_key'),
        sa.CheckConstraint(
            "outcome IN ('approve','review','reject','hide_escalate')",
            name='ck_text_moderation_cache_outcome',
        ),
    )
    op.create_index(
        op.f('ix_text_moderation_cache_expires_at'),
        'text_moderation_cache', ['expires_at'], unique=False,
    )

    op.create_table(
        'text_moderation_decisions',
        sa.Column('id', sa.UUID(), server_default=sa.text('gen_random_uuid()'),
                  nullable=False),
        sa.Column('content_hash', sa.String(length=64), nullable=False),
        sa.Column('target_type', sa.String(length=24), nullable=False),
        # No FK: evidence must survive a hard delete of the target.
        sa.Column('target_id', sa.UUID(), nullable=True),
        sa.Column('author_user_id', sa.UUID(), nullable=True),
        sa.Column('outcome', sa.String(length=16), nullable=False),
        sa.Column('scores', sa.JSON(), nullable=False),
        sa.Column('provider', sa.String(length=32), nullable=True),
        sa.Column('model', sa.String(length=64), nullable=True),
        sa.Column('policy_version', sa.String(length=8), nullable=False),
        sa.Column('source', sa.String(length=16), nullable=False),
        sa.Column('queue_label', sa.String(length=16), nullable=True),
        sa.Column('reviewed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['author_user_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.CheckConstraint(
            "target_type IN ('itinerary','rating','user')",
            name='ck_text_decision_target_type',
        ),
        sa.CheckConstraint(
            "outcome IN ('approve','review','reject','hide_escalate','pending')",
            name='ck_text_decision_outcome',
        ),
        sa.CheckConstraint(
            "source IN ('write','recheck')",
            name='ck_text_decision_source',
        ),
    )
    op.create_index(
        op.f('ix_text_moderation_decisions_content_hash'),
        'text_moderation_decisions', ['content_hash'], unique=False,
    )
    op.create_index(
        op.f('ix_text_moderation_decisions_target_id'),
        'text_moderation_decisions', ['target_id'], unique=False,
    )
    op.create_index(
        op.f('ix_text_moderation_decisions_author_user_id'),
        'text_moderation_decisions', ['author_user_id'], unique=False,
    )
    op.create_index(
        op.f('ix_text_moderation_decisions_created_at'),
        'text_moderation_decisions', ['created_at'], unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f('ix_text_moderation_decisions_created_at'),
                  table_name='text_moderation_decisions')
    op.drop_index(op.f('ix_text_moderation_decisions_author_user_id'),
                  table_name='text_moderation_decisions')
    op.drop_index(op.f('ix_text_moderation_decisions_target_id'),
                  table_name='text_moderation_decisions')
    op.drop_index(op.f('ix_text_moderation_decisions_content_hash'),
                  table_name='text_moderation_decisions')
    op.drop_table('text_moderation_decisions')

    op.drop_index(op.f('ix_text_moderation_cache_expires_at'),
                  table_name='text_moderation_cache')
    op.drop_table('text_moderation_cache')
