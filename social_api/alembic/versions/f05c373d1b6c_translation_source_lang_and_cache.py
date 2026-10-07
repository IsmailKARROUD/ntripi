"""translation source lang and cache

Groundwork for translating user content into the viewer's language.

  * `source_lang` on the six tables that hold translatable prose: the language
    detected when the text is saved, NULL when it could not be told. Nullable
    with no default, so each ADD COLUMN is a catalog change — no table rewrite.
    Existing rows are filled by scripts/backfill_source_lang.py.
  * `content_translations`, the translation cache. `content_id` is polymorphic
    and carries no FK; `itinerary_id` does, with ON DELETE CASCADE, so deleting
    a trip or an account takes its translations with it. The table is new and
    empty, so its indexes need no CONCURRENTLY.

Revision ID: f05c373d1b6c
Revises: a681984a1a04
Create Date: 2026-10-07 15:47:06.763716+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f05c373d1b6c'
down_revision: Union[str, None] = 'a681984a1a04'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SOURCE_LANG_TABLES = (
    'itineraries', 'itinerary_annotations', 'stops', 'annotations',
    'itinerary_ratings', 'transport_legs',
)


def upgrade() -> None:
    for table in _SOURCE_LANG_TABLES:
        op.add_column(table, sa.Column('source_lang', sa.Text(), nullable=True))

    op.create_table(
        'content_translations',
        sa.Column(
            'id', sa.UUID(), primary_key=True,
            server_default=sa.text('gen_random_uuid()'),
        ),
        sa.Column('itinerary_id', sa.UUID(), nullable=False),
        sa.Column('content_type', sa.Text(), nullable=False),
        sa.Column('content_id', sa.UUID(), nullable=False),
        sa.Column('field', sa.Text(), nullable=False),
        sa.Column('target_lang', sa.Text(), nullable=False),
        sa.Column('source_hash', sa.Text(), nullable=False),
        sa.Column('source_lang', sa.Text(), nullable=True),
        sa.Column('translated_text', sa.Text(), nullable=False),
        sa.Column('provider', sa.Text(), nullable=False),
        sa.Column('model', sa.Text(), nullable=True),
        sa.Column(
            'created_at', sa.DateTime(timezone=True), nullable=False,
            server_default=sa.text('now()'),
        ),
        sa.ForeignKeyConstraint(
            ['itinerary_id'], ['itineraries.id'], ondelete='CASCADE',
        ),
        sa.CheckConstraint(
            "content_type IN ('itinerary', 'itinerary_annotation', 'stop', "
            "'stop_annotation', 'rating', 'transport_leg')",
            name='ck_content_translation_type',
        ),
        sa.CheckConstraint(
            "field IN ('title', 'description', 'recommended_period_note', "
            "'content', 'notes', 'note')",
            name='ck_content_translation_field',
        ),
        # Leading (content_type, content_id) also serves per-content lookups.
        sa.UniqueConstraint(
            'content_type', 'content_id', 'field', 'target_lang', 'source_hash',
            name='uq_content_translation',
        ),
    )
    # The FK's own index: the cascade from itineraries and the per-trip
    # orphan purge both filter on it.
    op.create_index(
        'ix_content_translations_itinerary_id', 'content_translations',
        ['itinerary_id'],
    )


def downgrade() -> None:
    op.drop_index(
        'ix_content_translations_itinerary_id', table_name='content_translations',
    )
    op.drop_table('content_translations')
    for table in _SOURCE_LANG_TABLES:
        op.drop_column(table, 'source_lang')
