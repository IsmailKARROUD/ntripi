from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.user import User
from app.schemas.auth import LoginRequest, RegisterRequest, TokenResponse
from app.services.auth import create_access_token, hash_password, verify_password

router = APIRouter(prefix="/auth", tags=["Authentication"])

# A real bcrypt hash computed once at startup, used as a timing-attack stand-in.
# When a login attempt uses an email that doesn't exist, we still call
# verify_password() against this hash so the response time is identical whether
# the email was wrong or the password was wrong.
# We can't hardcode a hash string because bcrypt will raise ValueError on an
# invalid hash format — so we generate it once here at module load time.
_DUMMY_HASH = hash_password("dummy_timing_placeholder_password1")


@router.post(
    "/register",
    response_model=TokenResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new account",
)
def register(payload: RegisterRequest, db: Session = Depends(get_db)) -> TokenResponse:
    existing_user = db.execute(
        select(User).where(User.username == payload.username)
    ).scalar_one_or_none()
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This username is already taken.",
        )

    existing_email = db.execute(
        select(User).where(User.email == payload.email)
    ).scalar_one_or_none()
    if existing_email:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists.",
        )

    new_user = User(
        username=payload.username,
        email=payload.email,
        password_hash=hash_password(payload.password),
        display_name=payload.display_name,
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)

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
    user = db.execute(
        select(User).where(User.email == payload.email)
    ).scalar_one_or_none()

    # Always call verify_password — if user doesn't exist, we verify against
    # the dummy hash so the response time is identical in both failure cases.
    password_matches = verify_password(
        payload.password,
        user.password_hash if user else _DUMMY_HASH,
    )

    if not user or not password_matches:
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