# Re-export all models so Alembic can discover them via `from app.models import *`.
# Alembic's env.py imports Base from database.py and needs all model classes
# to be registered on Base.metadata before it can detect schema changes.
from app.models.user import User
from app.models.follow import Follow, FollowStatus

__all__ = ["User", "Follow", "FollowStatus"]
