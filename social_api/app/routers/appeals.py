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
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.errors import ApiError
from app.limiter import limiter
from app.models.user import User
from app.schemas.appeal import (
    AppealCreate, AppealResponse, ViolationsResponse,
)
from app.services import appeal_service

router = APIRouter(prefix="/appeals", tags=["Appeals"])


@router.get(
    "/violations",
    response_model=ViolationsResponse,
    summary="Moderation actions against the current user (Account status screen)",
)
def list_violations(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ViolationsResponse:
    return ViolationsResponse(
        violations=appeal_service.violations_feed(db, current_user)  # type: ignore[arg-type]
    )


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
) -> AppealResponse:
    try:
        appeal = appeal_service.create_appeal(
            db, current_user, body.target_type, body.target_id, body.reason,
        )
    except appeal_service.AppealError as exc:
        raise ApiError(
            status_code=exc.http_status, code=exc.code, detail=exc.message,
        )
    return appeal  # type: ignore[return-value]
