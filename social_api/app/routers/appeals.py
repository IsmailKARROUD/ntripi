"""
routers/appeals.py — Authenticated half of the appeals workflow.

GET /appeals/violations backs the in-app "Account status" screen: every
moderation action against the user or their content, with whether each can be
appealed right now. POST /appeals opens an appeal.

Banned users cannot reach either endpoint (is_active=False → 403 on every
authenticated request); they appeal through the public token form in web.py.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request, status
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse, Response
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user, return_requested
from app.errors import ApiError
from app.limiter import limiter
from app.models.user import User
from app.schemas.appeal import (
    AppealCreate, AppealResponse, ViolationsResponse,
)
from app.services import appeal_service

router = APIRouter(prefix="/appeals", tags=["Appeals"])

# POST /appeals: the Account status list as it stands with the new appeal on it.
wants_violations = return_requested("violations")


def _violations(db: Session, user: User) -> ViolationsResponse:
    """The Account status list — the GET's body, and an appeal's when asked."""
    return ViolationsResponse(
        violations=appeal_service.violations_feed(db, user)  # type: ignore[arg-type]
    )


@router.get(
    "/violations",
    response_model=ViolationsResponse,
    summary="Moderation actions against the current user (Account status screen)",
)
def list_violations(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ViolationsResponse:
    return _violations(db, current_user)


@router.post(
    "",
    response_model=AppealResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Appeal a moderation action",
)
@limiter.limit("10/hour")  # appeals are rare and human-written; cap abuse cheaply
def create_appeal(
    request: Request,  # required first positional for slowapi rate limiting
    body: AppealCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    wants: str | None = Depends(wants_violations),
) -> Response:
    try:
        appeal = appeal_service.create_appeal(
            db, current_user, body.target_type, body.target_id, body.reason,
        )
    except appeal_service.AppealError as exc:
        raise ApiError(
            status_code=exc.http_status, code=exc.code, detail=exc.message,
        )
    if wants:
        # Filed from Account status: the list it shows now, the appeal's row
        # marked pending, so the app adopts it instead of downloading it again.
        return JSONResponse(status_code=status.HTTP_201_CREATED,
                            content=jsonable_encoder(_violations(db, current_user)))
    return appeal  # type: ignore[return-value]
