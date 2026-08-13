"""
dependencies.py — Reusable FastAPI dependencies.

Provides:
  get_current_user     — validate JWT, return authenticated User
  require_etag         — the single guard every itinerary-content mutation goes
  require_edit_access    through: edit permission + edit lock + If-Match. The two
                         names are the same object; see make_etag_checker.

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

from app.config import get_settings
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


def _load_itinerary_for_update(itinerary_id: uuid.UUID, db: Session):
    """The itinerary row, locked for the length of the transaction.

    Why SELECT FOR UPDATE?
      On PostgreSQL it acquires a row-level lock that prevents two concurrent
      requests from passing the ETag check simultaneously and both writing.
      On SQLite (used in tests) it is silently ignored.

    A soft-deleted itinerary 404s here as it does everywhere else — the row
    survives as evidence, but it is gone for every caller including its owner.
    """
    from app.models.itinerary import Itinerary  # late import avoids circular

    stmt = select(Itinerary).where(Itinerary.id == itinerary_id)
    try:
        stmt = stmt.with_for_update()
    except Exception:
        pass  # SQLite doesn't support FOR UPDATE — safe to skip in tests
    itinerary = db.execute(stmt).scalar_one_or_none()

    if not itinerary or itinerary.deleted_at is not None:
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="itinerary_not_found", detail="Itinerary not found.",
        )
    return itinerary


def _check_if_match(request: Request, itinerary) -> None:
    """428 when the client sent no If-Match, 412 when it sent a stale one."""
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


def make_etag_checker(itinerary_id_param: str = "itinerary_id"):
    """
    Factory returning the FastAPI dependency every itinerary mutation depends on.

    Order is load-bearing:
      1. Load FOR UPDATE; 404 if missing or soft-deleted.
      2. 403 unless the caller may edit — owner or granted editor, re-derived
         from can_edit_itinerary() so edit rights can never outlive view rights.
      3. 428 if no X-Edit-Lock header; 409 if the claim it names is not theirs.
      4. 428 / 412 on If-Match.
      5. Refresh the claim's heartbeat — saving is activity.

    Step 3 sits ABOVE step 4 deliberately. After a takeover the ETag has usually
    moved as well, and answering 412 would send the user off to reload into a
    screen they still cannot save from; "you lost the claim" is both the more
    specific truth and the only one they can act on.
    """
    def _check(
        request: Request,
        itinerary_id: uuid.UUID,
        db: Session = Depends(get_db),
        current_user: User = Depends(get_current_user),
    ):
        from app.services import edit_lock_service
        from app.services.itinerary_access import can_edit_itinerary

        itinerary = _load_itinerary_for_update(itinerary_id, db)

        if not can_edit_itinerary(itinerary, current_user.id, db):
            # Same code and wording a non-owner has always received: whether the
            # caller could edit and never was granted, or was granted and lost
            # view access, is not something to spell out to them.
            raise ApiError(
                status_code=status.HTTP_403_FORBIDDEN,
                code="itinerary_not_owner", detail="You do not have permission to modify this itinerary.",
            )

        lock = edit_lock_service.assert_holder(
            db, itinerary, current_user,
            request.headers.get(edit_lock_service.LOCK_HEADER),
            get_settings(),
        )

        _check_if_match(request, itinerary)

        edit_lock_service.touch(lock)
        return itinerary

    return _check


# Pre-built dependency instance used by every itinerary-content mutation.
# Usage in a router: itinerary: Itinerary = Depends(require_etag)
require_etag = make_etag_checker()

# The same object under the name that says what it now does. `require_etag` is
# kept because ten endpoints and their tests already spell it that way, and the
# ETag check is still half of the job.
require_edit_access = require_etag
