"""
alembic/env.py — Alembic environment configuration.

This file is run by Alembic every time a migration command is executed.
It configures:
  1. How to connect to the database (DATABASE_URL from settings).
  2. Which models to inspect for schema changes (all models via Base.metadata).

Why load DATABASE_URL from settings?
  The database URL is a sensitive value (contains credentials).
  It should be defined in EXACTLY one place: the .env file.
  By importing settings here, Alembic uses the same URL as the application,
  eliminating the risk of them getting out of sync.
"""

from logging.config import fileConfig
from sqlalchemy import engine_from_config, pool
from alembic import context

# Import the app's settings singleton.
from app.config import get_settings

# Import Base and all models so Alembic can detect schema changes.
# The models must be imported before Alembic inspects Base.metadata,
# otherwise it won't know about the tables defined in those models.
from app.database import Base
import app.models  # noqa: F401 — side-effect import to register all models

# Alembic Config object (parsed from alembic.ini).
config = context.config

# Set up Python logging from the alembic.ini [loggers] config.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Tell Alembic which metadata to compare against the database.
# This is how `alembic revision --autogenerate` detects schema changes.
target_metadata = Base.metadata

# Override the sqlalchemy.url from alembic.ini with the value from settings.
# This is the key integration point: DATABASE_URL comes from .env, not alembic.ini.
settings = get_settings()
config.set_main_option("sqlalchemy.url", settings.DATABASE_URL)


def run_migrations_offline() -> None:
    """
    Run migrations in 'offline' mode.

    In offline mode, Alembic generates SQL scripts without actually connecting
    to the database. Useful for generating migration scripts to review or
    apply manually (e.g., in environments where direct DB access isn't possible).
    """
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """
    Run migrations in 'online' mode (the normal mode).

    In online mode, Alembic connects to the database and applies migrations
    directly. This is what runs when you do `alembic upgrade head`.
    """
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,  # NullPool: no connection pooling during migrations
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
        )

        with context.begin_transaction():
            context.run_migrations()


# Determine which mode to run based on whether we have a DB connection.
if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
