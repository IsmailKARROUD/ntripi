"""
routers/internal.py — machine-triggered maintenance.

POST /internal/moderation-sweep runs the moderation sweep (SLA enforcement,
post-outage re-checks, cache purge). Any external scheduler can call it — Railway
cron, a GitHub Action, a plain curl — which keeps the deployment portable: no
worker dyno, no Celery, no platform-specific job runner.

This is a publicly reachable URL, so it is hardened the same way /admin is:

  - include_in_schema=False: never appears in the OpenAPI document.
  - SWEEP_TOKEN unset ⇒ every route 404s. The endpoint is invisible when the
    feature is not configured, not merely locked.
  - The token is compared with secrets.compare_digest, and the comparison runs
    even when the header is missing or the wrong length, so a timing signal
    cannot narrow the search.
  - Rate limited, so a brute-force attempt or a misconfigured scheduler in a
    retry loop cannot hammer it.

The sweep holds a PostgreSQL advisory lock, so a duplicate trigger is a cheap
no-op rather than a concurrent run.
"""

from __future__ import annotations

import logging
import secrets

from fastapi import APIRouter, Depends, Header, Request, status
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.database import get_db
from app.errors import ApiError
from app.limiter import limiter
from app.services import sweep_service

logger = logging.getLogger(__name__)

# include_in_schema=False keeps this out of /openapi.json even when DEBUG serves docs.
router = APIRouter(prefix="/internal", tags=["Internal"], include_in_schema=False)


def _require_sweep_token(
    settings: Settings, authorization: str | None
) -> None:
    """Bearer-token gate. 404 when unconfigured; 401 with no detail otherwise."""
    expected = settings.SWEEP_TOKEN
    if not expected:
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="not_found", detail="Not Found.",
        )

    prefix = "Bearer "
    presented = (
        authorization[len(prefix):] if authorization and authorization.startswith(prefix)
        else ""
    )
    # Compared unconditionally, including for a missing or short header, so the
    # response time reveals nothing about the token.
    if not secrets.compare_digest(presented, expected):
        logger.warning("rejected /internal/moderation-sweep call with a bad token")
        raise ApiError(
            status_code=status.HTTP_401_UNAUTHORIZED,
            code="unauthorized", detail="Unauthorized.",
        )


@router.post("/moderation-sweep", summary="Run the moderation sweep")
# Blunts token brute-forcing and a scheduler stuck in a retry loop. The sweep's
# advisory lock already makes overlapping runs harmless.
@limiter.limit("10/minute")
def moderation_sweep(
    request: Request,  # required first positional for slowapi rate limiting
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> dict:
    _require_sweep_token(settings, authorization)
    return sweep_service.run_moderation_sweep(db, settings)
