"""
routers/auth.py — Authentication endpoints (register and login).

Route prefix: /auth
No authentication required — these endpoints are the entry point for new users.

Endpoints:
  POST /auth/register → create a new account, returns a JWT token.
  POST /auth/login    → log in with email + password, returns a JWT token.

Security notes:
  - Passwords are hashed with bcrypt before storage (see services/auth.py).
  - Login uses a dummy hash to prevent timing-based user enumeration attacks.
    If we only ran bcrypt.verify on existing users, an attacker could time
    the response to determine whether an email exists in the database.
  - The router returns a JWT token immediately after registration, so the
    client doesn't need a separate login step.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.constants.tos import TOS_DATE, TOS_SUMMARY, TOS_VERSION
from app.database import get_db
from app.schemas.auth import LoginRequest, RegisterRequest, TokenResponse
from app.services import auth_service

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post(
    "/register",
    response_model=TokenResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new account",
)
def register(payload: RegisterRequest, db: Session = Depends(get_db)) -> TokenResponse:
    """
    Create a new user account and return a JWT token.
    Input validation (format, length) is handled by RegisterRequest.
    Business logic (uniqueness, hashing) is handled by auth_service.
    """
    try:
        user, token = auth_service.create_user(
            username=payload.username,
            email=payload.email,
            password=payload.password,
            display_name=payload.display_name,
            tos_accepted=payload.tos_accepted,
            db=db,
        )
    except auth_service.AuthError as e:
        raise HTTPException(status_code=e.http_status, detail=e.message)
    return TokenResponse(
        access_token=token,
        user_id=str(user.id),
        username=user.username,
    )


@router.post(
    "/login",
    response_model=TokenResponse,
    summary="Log in with email and password",
)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    try:
        user, token = auth_service.authenticate_user(payload.email, payload.password, db)
    except auth_service.AuthError as e:
        raise HTTPException(status_code=e.http_status, detail=e.message)
    return TokenResponse(
        access_token=token,
        user_id=str(user.id),
        username=user.username,
    )


@router.get(
    "/tos",
    summary="Get the current Terms of Service",
)
def get_tos() -> dict:
    """
    Return the current ToS version, date, and summary text.
    No authentication required — this is fetched during registration.
    Serving it from the backend means updating the ToS requires only a
    backend deploy, not an app store submission.
    """
    return {
        "version": TOS_VERSION,
        "date": TOS_DATE,
        "summary": TOS_SUMMARY,
    }