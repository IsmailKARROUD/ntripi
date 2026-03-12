"""
routers/auth.py — Authentication endpoints (register and login).

Route prefix: /auth
No authentication required for any route in this file (they produce tokens).

Design notes:
  - Registration immediately returns a JWT so the client can proceed without
    a separate login step. This is common in mobile apps.
  - Login uses constant-time password comparison to prevent timing attacks
    (see services/auth.py for the explanation).
  - We return separate 409 errors for duplicate username vs duplicate email,
    so the client can show a precise error message to the user.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.schemas.auth import LoginRequest, RegisterRequest, TokenResponse
from app.services.auth import (
    create_access_token,
    hash_password,
    verify_password,
    verify_password_against_dummy,
)

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post(
    "/register",
    response_model=TokenResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new account",
)
def register(payload: RegisterRequest, db: Session = Depends(get_db)) -> TokenResponse:
    """
    Register a new user and return an access token immediately.

    Steps:
      1. Check for duplicate username (409 if taken).
      2. Check for duplicate email (409 if taken).
      3. Hash the password.
      4. Create the user record.
      5. Issue and return a JWT token.
    """
    # Step 1: Check duplicate username.
    # We use select() (SQLAlchemy 2.0 style) instead of db.query() (legacy style).
    existing_user = db.execute(
        select(User).where(User.username == payload.username)
    ).scalar_one_or_none()

    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This username is already taken.",
        )

    # Step 2: Check duplicate email.
    existing_email = db.execute(
        select(User).where(User.email == payload.email)
    ).scalar_one_or_none()

    if existing_email:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists.",
        )

    # Step 3 & 4: Hash the password and create the user.
    # We never touch the plain password after this point.
    new_user = User(
        username=payload.username,
        email=payload.email,
        password_hash=hash_password(payload.password),
        display_name=payload.display_name,
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)  # Reload the record to get DB-generated values (id, created_at, etc.)

    # Step 5: Issue a JWT token.
    token = create_access_token(subject=str(new_user.id))

    return TokenResponse(
        access_token=token,
        user_id=str(new_user.id),
        username=new_user.username,
    )


@router.post(
    "/login",
    response_model=TokenResponse,
    summary="Log in with email and password",
)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    """
    Authenticate a user and return an access token.

    Security: constant-time comparison.
      If the user is not found, we still call bcrypt.verify (against a dummy hash)
      to ensure the response time is the same whether the email exists or not.
      This prevents an attacker from enumerating valid email addresses by measuring
      response times (timing side-channel attack).
    """
    user = db.execute(
        select(User).where(User.email == payload.email)
    ).scalar_one_or_none()

    if user is None:
        # Call dummy verify to keep response time constant.
        verify_password_against_dummy(payload.password)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password.",
        )

    # Verify against the real hash.
    if not verify_password(payload.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password.",
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your account has been deactivated.",
        )

    token = create_access_token(subject=str(user.id))

    return TokenResponse(
        access_token=token,
        user_id=str(user.id),
        username=user.username,
    )
