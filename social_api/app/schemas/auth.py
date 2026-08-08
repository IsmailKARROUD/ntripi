from datetime import date, datetime

from pydantic import BaseModel, EmailStr, Field, field_validator

from app.services.age_service import is_plausible
from app.validators.password import validate_password_strength
from app.validators.username import validate_username, validate_display_name


def _email_must_be_ascii(v: str) -> str:
    # Internationalized addresses pass EmailStr, but reset/verification mail
    # delivery to them (SMTPUTF8) is unreliable — reject at the door.
    if not v.isascii():
        raise ValueError("Email must contain only Latin (ASCII) characters.")
    return v


def _dob_must_be_plausible(v: date | None) -> date | None:
    # Shape only — a future or impossible date is a malformed request (422).
    # Being under 16 is a real date about a real person and answers 400
    # `underage` from the router, so the client can tell the two apart.
    if v is not None and not is_plausible(v):
        raise ValueError("Date of birth is not a valid date.")
    return v


class RegisterRequest(BaseModel):
    username: str = Field(..., min_length=4, max_length=30)
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)
    display_name: str | None = Field(None, max_length=50)
    tos_accepted: bool
    date_of_birth: date

    @field_validator("date_of_birth")
    @classmethod
    def _check_dob(cls, v: date) -> date:
        return _dob_must_be_plausible(v)

    @field_validator("username")
    @classmethod
    def _check_username(cls, v: str) -> str:
        return validate_username(v)

    @field_validator("display_name")
    @classmethod
    def _check_display_name(cls, v: str | None) -> str | None:
        return validate_display_name(v)

    @field_validator("email")
    @classmethod
    def _check_email_ascii(cls, v: str) -> str:
        return _email_must_be_ascii(v)

    @field_validator("password")
    @classmethod
    def _check_password(cls, v: str) -> str:
        return validate_password_strength(v)


class LoginRequest(BaseModel):
    identifier: str  # email or username — no strict validation, service handles lookup
    password: str


class TokenPair(BaseModel):
    """Response shape for /auth/login, /auth/register, /auth/refresh.

    `refresh_expires_at` lets the client skip a doomed refresh attempt at
    boot when the long-lived token is already past its expiry.
    """
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user_id: str
    username: str
    refresh_expires_at: datetime


class RefreshRequest(BaseModel):
    refresh_token: str


class GoogleAuthRequest(BaseModel):
    """Body for POST /auth/google. `id_token` is the Google ID token obtained
    by the client SDK.

    `tos_accepted` defaults False, so acceptance has to be explicit on this
    path too. Signing in to an existing account never reads it; only the
    create-a-new-account branch does, and it 400s `tos_required` there. The
    client's move is to retry the same ID token with True once the user has
    accepted, which keeps returning users from being re-prompted at every
    sign-in.

    `date_of_birth` and `google_access_token` follow the same rule and default
    None: only the create-a-new-account branch reads either, so a deployed
    client that sends neither still signs in and still links accounts. The
    access token is for the People API birthday lookup — when it yields a
    usable date that is what gets stored, and `date_of_birth` is the fallback
    the consent sheet collects when Google has no birthday, hides the year, or
    the user declined the scope.
    """
    id_token: str
    tos_accepted: bool = False
    date_of_birth: date | None = None
    google_access_token: str | None = None

    @field_validator("date_of_birth")
    @classmethod
    def _check_dob(cls, v: date | None) -> date | None:
        return _dob_must_be_plausible(v)


class AcceptTosRequest(BaseModel):
    """Body for POST /auth/accept-tos.

    Carries a date of birth and nothing else — never a ToS version, which the
    server stamps from its own TOS_VERSION so a client cannot claim acceptance
    of a document it never rendered. Optional because accounts created after
    the age gate already have one; it is required precisely when the account
    does not, which is how pre-gate accounts get backfilled.
    """
    date_of_birth: date | None = None

    @field_validator("date_of_birth")
    @classmethod
    def _check_dob(cls, v: date | None) -> date | None:
        return _dob_must_be_plausible(v)


class ForgotPasswordRequest(BaseModel):
    """Body for POST /auth/forgot-password."""
    email: EmailStr

    @field_validator("email")
    @classmethod
    def _check_email_ascii(cls, v: str) -> str:
        return _email_must_be_ascii(v)


class ResetPasswordRequest(BaseModel):
    """Body for the web reset form / API reset. Same password policy as register."""
    token: str
    new_password: str = Field(..., min_length=8, max_length=128)

    @field_validator("new_password")
    @classmethod
    def _check_password(cls, v: str) -> str:
        return validate_password_strength(v)


class ChangePasswordRequest(BaseModel):
    """Body for POST /auth/change-password (authenticated). Same password policy
    as register/reset. Confirm-match is a client concern — not sent here."""
    current_password: str
    new_password: str = Field(..., min_length=8, max_length=128)

    @field_validator("new_password")
    @classmethod
    def _check_password(cls, v: str) -> str:
        return validate_password_strength(v)
