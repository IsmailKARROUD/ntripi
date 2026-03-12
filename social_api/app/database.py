"""
database.py — SQLAlchemy engine and session configuration.

Why SQLAlchemy 2.0?
  - The 2.0 API uses a cleaner, more explicit style (Session.execute with select()).
  - Typed query results, better async support, and active development.
  - The 1.x "legacy" API still works but is discouraged for new projects.

Why a session factory with dependency injection?
  - Each HTTP request gets its own database session (one per request pattern).
  - The session is automatically committed on success or rolled back on error.
  - Injecting the session via FastAPI's Depends() makes it easy to mock in tests.

Why not async SQLAlchemy?
  - For a V0.1 app, synchronous SQLAlchemy with a connection pool is sufficient.
  - Async SQLAlchemy adds complexity (different drivers, different session types).
  - When traffic demands it, migrating to async is straightforward.
"""

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase
from app.config import get_settings

settings = get_settings()

# Create the SQLAlchemy engine.
# pool_pre_ping=True: sends a lightweight "SELECT 1" before each connection
# is handed out from the pool, automatically recovering from stale connections
# (e.g., after the DB server restarts or a firewall kills an idle connection).
engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,
)

# SessionLocal is a factory class. Calling SessionLocal() creates a new session.
# autocommit=False: we must call session.commit() explicitly — this is correct
#   because it gives us transactional control.
# autoflush=False: SQLAlchemy won't flush (send SQL) until we explicitly commit
#   or query. This avoids partial writes during a request.
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    """
    All ORM models inherit from this class.
    DeclarativeBase is the SQLAlchemy 2.0 way to define the declarative base.
    It provides the metadata registry that Alembic uses to detect schema changes.
    """
    pass


def get_db():
    """
    FastAPI dependency that provides a database session for the duration of a request.

    Usage in a route:
        @router.get("/example")
        def example(db: Session = Depends(get_db)):
            ...

    The try/finally pattern guarantees the session is always closed, even if
    an unhandled exception occurs. This returns the connection to the pool.
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
