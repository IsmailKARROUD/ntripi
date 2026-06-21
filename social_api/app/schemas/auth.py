from datetime import datetime

from pydantic import BaseModel, EmailStr, Field, field_validator

from app.validators.username import validate_username, validate_display_name


class RegisterRequest(BaseModel):
    username: str = Field(..., min_length=4, max_length=30)
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)
    display_name: str | None = Field(None, max_length=50)
    tos_accepted: bool

    @field_validator("username")
    @classmethod
    def _check_username(cls, v: str) -> str:
        return validate_username(v)

    @field_validator("display_name")
    @classmethod
    def _check_display_name(cls, v: str | None) -> str | None:
        return validate_display_name(v)

    @field_validator("password")
    @classmethod
    def password_must_contain_digit(cls, v: str) -> str:
        if not any(c.isdigit() for c in v):
            raise ValueError("Password must contain at least one digit.")
        return v


class LoginRequest(BaseModel):
    identifier: str  # email or username — no strict validation, service handles lookup
    password: str


class TokenResponse(BaseModel):
    """Legacy access-token-only response. Kept for reference; not used by
    the public auth endpoints anymore (they return TokenPair)."""
    access_token: str
    token_type: str = "bearer"
    user_id: str
    username: str


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
    by the client SDK. `tos_accepted` defaults True — tapping the Google button
    implies acceptance (the ToS/Privacy links are shown next to it)."""
    id_token: str
    tos_accepted: bool = True


class ForgotPasswordRequest(BaseModel):
    """Body for POST /auth/forgot-password."""
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    """Body for the web reset form / API reset. Same password policy as register."""
    token: str
    new_password: str = Field(..., min_length=8, max_length=128)

    @field_validator("new_password")
    @classmethod
    def password_must_contain_digit(cls, v: str) -> str:
        if not any(c.isdigit() for c in v):
            raise ValueError("Password must contain at least one digit.")
        return v
