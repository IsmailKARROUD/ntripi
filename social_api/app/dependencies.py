"""
dependencies.py — Reusable FastAPI dependencies.

Why a separate dependencies.py?
  - Dependencies are shared across multiple routers. Centralising them
    here avoids circular imports and makes them easy to find.
  - FastAPI's dependency injection system is one of its best features.
    Any function can be a dependency; FastAPI handles calling it and
    injecting the result automatically.

The key dependency here is get_current_user, which:
  1. Extracts the Bearer token from the Authorization header.
  2. Decodes and validates the JWT.
  3. Looks up the user in the database.
  4. Verifies the user is active.
  5. Returns the User ORM object.

Any route that needs an authenticated user just declares:
    current_user: User = Depends(get_current_user)
"""

import uuid
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.services.auth import decode_access_token

# HTTPBearer extracts the token from the "Authorization: Bearer <token>" header.
# auto_error=True means FastAPI automatically returns 403 if the header is missing.
bearer_scheme = HTTPBearer(auto_error=True)


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    """
    Validate the JWT and return the authenticated User object.

    This dependency is the authentication gate for all protected routes.
    It is designed to fail fast with appropriate HTTP errors:
      - 401 if the token is invalid or expired.
      - 401 if the user no longer exists.
      - 403 if the user's account is deactivated.

    Why check is_active?
      A suspended user's token may still be technically valid (not expired),
      so we must explicitly check the flag on every request.
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials.",
        headers={"WWW-Authenticate": "Bearer"},
    )

    try:
        payload = decode_access_token(credentials.credentials)
        user_id_str: str | None = payload.get("sub")
        if user_id_str is None:
            raise credentials_exception
        user_id = uuid.UUID(user_id_str)
    except (JWTError, ValueError):
        # JWTError: invalid/expired token.
        # ValueError: 'sub' is not a valid UUID string.
        raise credentials_exception

    user = db.get(User, user_id)
    if user is None:
        raise credentials_exception

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your account has been deactivated.",
        )

    return user
