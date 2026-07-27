"""
dependencies.py — Reusable FastAPI dependencies.

Provides:
  get_current_user  — validate JWT, return authenticated User
  require_etag      — ETag / If-Match optimistic concurrency check

WHY ETAG / IF-MATCH?
  Without concurrency control, two users (or two browser tabs) can silently
  overwrite each other's changes. The ETag pattern works like this:

    1. Client fetches the itinerary → server returns ETag: "<16 hex>"
    2. Client stores that value alongside the data.
    3. Client sends a mutation → includes If-Match: "<16 hex>"
    4. Server compares the header to the current ETag derived from updated_at:
         - Match  → proceed, return new ETag.
         - Stale  → 412 Precondition Failed ("please reload").
         - Missing→ 428 Precondition Required.

  The concurrency ETag is the itinerary's `updated_at` as an ISO datetime
  string, wrapped in quotes. _normalize_etag normalizes both sides so
  `Z` ↔ `+00:00` and `W/`-prefix differences (added by intermediaries like
  Cloudflare) are tolerated. The cache ETag emitted by `ETagMiddleware` is
  a separate, body-hash-based opaque token — they don't share a format.
"""

import uuid
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.services.auth import decode_access_token
from app.errors import ApiError

bearer_scheme = HTTPBearer(auto_error=False)


def _authenticated_user(credentials: HTTPAuthorizationCredentials, db: Session) -> User:
    """Validate a present Bearer token and return its User (401 invalid/expired/
    unknown, 403 deactivated). Shared by the required and optional dependencies."""
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
        raise ApiError(
            status_code=status.HTTP_403_FORBIDDEN,
            code="account_deactivated", detail="Your account has been deactivated.",
        )

    return user


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
        raise ApiError(
            status_code=status.HTTP_403_FORBIDDEN,
            code="not_authenticated", detail="Not authenticated.",
        )
    return _authenticated_user(credentials, db)


def get_current_user_optional(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User | None:
    """
    Return the authenticated User, or None when no Authorization header is sent.

    A *present but invalid* token still 401s (via _authenticated_user) — a stale
    app token must not silently downgrade a request to anonymous.
    """
    if credentials is None:
        return None
    return _authenticated_user(credentials, db)


def require_verified_email(
    current_user: User = Depends(get_current_user),
) -> User:
    """
    Like get_current_user, but also gates high-value actions behind a verified
    email. Verification currently happens only by signing in with Google (which
    carries Google's email_verified claim) — so unverified users get a 403 that
    the client surfaces as a "verify with Google" prompt.
    """
    if not current_user.email_verified:
        raise ApiError(
            status_code=status.HTTP_403_FORBIDDEN,
            code="email_unverified", detail="Please verify your email by signing in with Google to do this.",
        )
    return current_user


# ---------------------------------------------------------------------------
# ETag helpers
# ---------------------------------------------------------------------------

def _etag_value(itinerary) -> str:
    """Quoted ISO datetime of the itinerary's `updated_at`. Round-tripped by
    clients via If-Match. `_normalize_etag` handles format differences."""
    return f'"{itinerary.updated_at.isoformat()}"'


def _normalize_etag(raw: str) -> str:
    """Normalize an ETag for byte comparison:
      - strip whitespace
      - strip optional `W/` weak-validator prefix (RFC 7232 §2.3, added by
        intermediaries like Cloudflare when they recompress the body)
      - strip surrounding quotes
      - normalize `Z` → `+00:00` so Dart's `toIso8601String()` ("…Z") and
        Python's `datetime.isoformat()` ("…+00:00") compare equal."""
    s = raw.strip()
    if s.startswith("W/"):
        s = s[2:]
    s = s.strip('"')
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    return s


def make_etag_checker(itinerary_id_param: str = "itinerary_id"):
    """
    Factory that returns a FastAPI dependency for ETag / If-Match validation.

    The returned dependency:
      1. Loads the itinerary row with SELECT FOR UPDATE (prevents another
         request from modifying the row between our check and our write).
      2. Verifies the caller owns the itinerary (403 if not).
      3. Checks the If-Match header against the current ETag:
           - Missing header → 428 Precondition Required
           - Stale header   → 412 Precondition Failed
      4. Returns the locked itinerary object to the endpoint function.

    Why SELECT FOR UPDATE?
      On PostgreSQL it acquires a row-level lock that prevents two concurrent
      requests from passing the ETag check simultaneously and both writing.
      On SQLite (used in tests) it is silently ignored.
    """
    def _check(
        request: Request,
        itinerary_id: uuid.UUID,
        db: Session = Depends(get_db),
        current_user: User = Depends(get_current_user),
    ):
        from app.models.itinerary import Itinerary  # late import avoids circular

        stmt = select(Itinerary).where(Itinerary.id == itinerary_id)
        try:
            stmt = stmt.with_for_update()
        except Exception:
            pass  # SQLite doesn't support FOR UPDATE — safe to skip in tests
        itinerary = db.execute(stmt).scalar_one_or_none()

        if not itinerary:
            raise ApiError(
                status_code=status.HTTP_404_NOT_FOUND,
                code="itinerary_not_found", detail="Itinerary not found.",
            )

        if itinerary.user_id != current_user.id:
            raise ApiError(
                status_code=status.HTTP_403_FORBIDDEN,
                code="itinerary_not_owner", detail="You do not have permission to modify this itinerary.",
            )

        if_match = request.headers.get("If-Match")
        if not if_match:
            # Client forgot to send the header — reject immediately.
            raise ApiError(
                status_code=status.HTTP_428_PRECONDITION_REQUIRED,
                code="if_match_required", detail="If-Match header is required for mutations.",
            )

        # Normalize both sides to the same timezone representation before comparing.
        client_etag = _normalize_etag(if_match)
        server_etag = _normalize_etag(_etag_value(itinerary))

        if client_etag != server_etag:
            # The itinerary was modified between the client's last fetch and now.
            # The client must reload before retrying.
            raise ApiError(
                status_code=status.HTTP_412_PRECONDITION_FAILED,
                code="itinerary_stale", detail="itinerary modified, please reload",
            )

        return itinerary

    return _check


# Pre-built dependency instance used by all mutation endpoints.
# Usage in a router: itinerary: Itinerary = Depends(require_etag)
require_etag = make_etag_checker()
