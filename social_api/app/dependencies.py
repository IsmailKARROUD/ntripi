"""
dependencies.py — Reusable FastAPI dependencies.

Provides:
  get_current_user   — validate JWT, return authenticated User
  check_etag         — validate If-Match header for optimistic concurrency
"""

import uuid
from datetime import timezone
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.services.auth import decode_access_token

bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    """
    Validate the JWT and return the authenticated User object.

    Fails fast:
      - 403 if Authorization header is missing.
      - 401 if token is invalid or expired.
      - 401 if the user no longer exists.
      - 403 if the user's account is deactivated.
    """
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authenticated.",
        )

    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials.",
        headers={"WWW-Authenticate": "Bearer"},
    )

    user_id_str = decode_access_token(credentials.credentials)
    if user_id_str is None:
        raise credentials_exception
    try:
        user_id = uuid.UUID(user_id_str)
    except ValueError:
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


def _etag_value(itinerary) -> str:
    """Format the ETag header value from itinerary.updated_at (RFC 7232)."""
    ts = itinerary.updated_at
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    return f'"{ts.isoformat()}"'


def _normalize_etag(raw: str) -> str:
    """Strip quotes and normalize timezone suffix for comparison.

    Pydantic v2 serializes naive datetimes without '+00:00'; clients may
    send that back. The server always stores UTC so we treat missing tz as UTC.
    """
    s = raw.strip('"').strip()
    if "T" in s and "+" not in s and not s.endswith("Z"):
        s += "+00:00"
    return s


def make_etag_checker(itinerary_id_param: str = "itinerary_id"):
    """
    Factory returning a FastAPI dependency that:
      1. Loads the itinerary row (SELECT FOR UPDATE).
      2. Validates the If-Match header (RFC 7232).
      3. Returns the locked itinerary on success.

    Usage in a router:
        itinerary = Depends(make_etag_checker())
    """
    def _check(
        request: Request,
        itinerary_id: uuid.UUID,
        db: Session = Depends(get_db),
        current_user: User = Depends(get_current_user),
    ):
        from app.models.itinerary import Itinerary  # late import avoids circular

        stmt = select(Itinerary).where(Itinerary.id == itinerary_id)
        # SELECT FOR UPDATE on PostgreSQL; SQLite ignores it gracefully.
        try:
            stmt = stmt.with_for_update()
        except Exception:
            pass
        itinerary = db.execute(stmt).scalar_one_or_none()

        if not itinerary:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Itinerary not found.",
            )

        if itinerary.user_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You do not have permission to modify this itinerary.",
            )

        if_match = request.headers.get("If-Match")
        if not if_match:
            raise HTTPException(
                status_code=status.HTTP_428_PRECONDITION_REQUIRED,
                detail="If-Match header is required for mutations.",
            )

        client_etag = _normalize_etag(if_match)
        server_etag = _normalize_etag(_etag_value(itinerary))

        if client_etag != server_etag:
            raise HTTPException(
                status_code=status.HTTP_412_PRECONDITION_FAILED,
                detail="itinerary modified, please reload",
            )

        return itinerary

    return _check


# Singleton dependency instances for the standard itinerary_id path parameter.
require_etag = make_etag_checker()
