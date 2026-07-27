"""add image moderation

Adds the automated image-moderation infrastructure (AWS Rekognition scan at
upload time):
  - itineraries.moderation_status — cover-image moderation state
    ('pending' | 'approved' | 'flagged' | 'rejected'), default 'approved'.
  - image_moderation_logs — one row per scan decision (90-day retention,
    deleted opportunistically by moderation_service). Only label names and
    confidences are stored, never the raw AWS response.

Revision ID: b858424a1092
Revises: acd2209b7778
Create Date: 2026-07-27 18:39:24.405676+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = 'b858424a1092'
down_revision: Union[str, None] = 'acd2209b7778'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'itineraries',
        sa.Column(
            'moderation_status',
            sa.String(length=20),
            server_default=sa.text("'approved'"),
            nullable=False,
        ),
    )
    op.create_check_constraint(
        'ck_itinerary_moderation_status',
        'itineraries',
        "moderation_status IN ('pending','approved','flagged','rejected')",
    )

    op.create_table(
        'image_moderation_logs',
        sa.Column('id', sa.UUID(), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('image_hash', sa.String(length=64), nullable=False),
        sa.Column('target_kind', sa.String(length=32), nullable=False),
        sa.Column('target_itinerary_id', sa.UUID(), nullable=True),
        sa.Column('uploader_user_id', sa.UUID(), nullable=True),
        sa.Column('action', sa.String(length=32), nullable=False),
        sa.Column('labels', sa.JSON(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.CheckConstraint(
            "target_kind IN ('itinerary_cover','avatar','user_cover')",
            name='ck_moderation_target_kind',
        ),
        sa.CheckConstraint(
            "action IN ('approved','flagged','rejected','error_allowed')",
            name='ck_moderation_action',
        ),
        sa.ForeignKeyConstraint(['target_itinerary_id'], ['itineraries.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['uploader_user_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        op.f('ix_image_moderation_logs_target_itinerary_id'),
        'image_moderation_logs', ['target_itinerary_id'], unique=False,
    )
    op.create_index(
        op.f('ix_image_moderation_logs_uploader_user_id'),
        'image_moderation_logs', ['uploader_user_id'], unique=False,
    )
    op.create_index(
        op.f('ix_image_moderation_logs_created_at'),
        'image_moderation_logs', ['created_at'], unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f('ix_image_moderation_logs_created_at'), table_name='image_moderation_logs')
    op.drop_index(op.f('ix_image_moderation_logs_uploader_user_id'), table_name='image_moderation_logs')
    op.drop_index(op.f('ix_image_moderation_logs_target_itinerary_id'), table_name='image_moderation_logs')
    op.drop_table('image_moderation_logs')
    op.drop_constraint('ck_itinerary_moderation_status', 'itineraries', type_='check')
    op.drop_column('itineraries', 'moderation_status')
