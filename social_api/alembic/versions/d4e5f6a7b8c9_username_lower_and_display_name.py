"""username_lower_and_display_name

Add username_lower (canonical lowercase lookup). username_lower carries the
unique constraint so usernames are case-insensitively unique. The old
case-sensitive unique constraint on username is dropped if it exists.

Revision ID: d4e5f6a7b8c9
Revises: a1b2c3d4e5f6
Create Date: 2026-04-27 00:00:00.000000+00:00
"""

from alembic import op
import sqlalchemy as sa

revision = 'd4e5f6a7b8c9'
down_revision = 'b7c8d9e0f1a2'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Step 1 — Add username_lower as nullable for backfill.
    op.add_column(
        'users',
        sa.Column('username_lower', sa.String(30), nullable=True),
    )

    # Step 2 — Backfill from existing data.
    op.execute("UPDATE users SET username_lower = LOWER(username)")

    bind = op.get_bind()

    # Step 3 — Fail loudly if case-insensitive duplicates exist.
    duplicates = bind.execute(sa.text("""
        SELECT username_lower, COUNT(*) AS cnt
        FROM users
        GROUP BY username_lower
        HAVING COUNT(*) > 1
    """)).fetchall()
    if duplicates:
        names = [row[0] for row in duplicates]
        raise RuntimeError(
            f"Cannot apply migration: case-insensitive duplicate usernames "
            f"found: {names}. Resolve manually before retrying."
        )

    # Step 4 — Fail loudly if any username is shorter than 4 chars.
    short = bind.execute(sa.text("""
        SELECT username FROM users WHERE LENGTH(username) < 4
    """)).fetchall()
    if short:
        names = [row[0] for row in short]
        raise RuntimeError(
            f"Cannot apply migration: usernames shorter than 4 chars exist "
            f"under old policy: {names}. Extend them manually before retrying."
        )

    # Step 5 — Fail loudly if any hyphenated usernames exist.
    hyphenated = bind.execute(sa.text("""
        SELECT username FROM users WHERE username LIKE '%-%'
    """)).fetchall()
    if hyphenated:
        names = [row[0] for row in hyphenated]
        raise RuntimeError(
            f"Cannot apply migration: hyphenated usernames exist: {names}. "
            f"Rename them (replace - with _) before retrying."
        )

    # Step 6 — Make username_lower non-null and add unique index.
    op.alter_column('users', 'username_lower', nullable=False)
    op.create_unique_constraint(
        'uq_users_username_lower', 'users', ['username_lower']
    )

    # Step 7 — Drop old case-sensitive unique constraint on username if it
    # exists. We query information_schema first so we never attempt a DROP
    # inside an already-failing transaction (try/except doesn't save you in
    # PostgreSQL — the txn is aborted at the DB level even if Python catches).
    exists = bind.execute(sa.text("""
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name = 'users'
          AND constraint_name = 'uq_users_username'
          AND constraint_type = 'UNIQUE'
    """)).fetchone()
    if exists:
        op.drop_constraint('uq_users_username', 'users', type_='unique')
    # display_name column type is intentionally NOT resized here.
    # The application layer (Pydantic) already enforces the 50-char limit.
    # Shrinking VARCHAR(100) → VARCHAR(50) in DDL is unnecessary and risky.


def downgrade() -> None:
    op.create_unique_constraint('uq_users_username', 'users', ['username'])
    op.drop_constraint('uq_users_username_lower', 'users', type_='unique')
    op.drop_column('users', 'username_lower')
