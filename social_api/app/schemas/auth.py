"""
schemas/auth.py — Pydantic schemas for authentication endpoints.

Why separate schemas from ORM models?
  - ORM models define the DB structure; schemas define the API contract.
  - They often differ: the DB stores password_hash, but the API accepts
    plain password and never returns it.
  - Schemas also enforce input validation (regex, length, format) that
    would be inappropriate to put on ORM models.

Why Pydantic v2?
  - Significantly faster than v1 (Rust-based validation core).
  - model_config replaces the inner class Config in v1.
  - Field validators use @field_validator instead of @validator.
"""

import uuid
from datetime import datetime

from pydantic import BaseModel, EmailStr, Field, field_validator


class RegisterRequest(BaseModel):
    """
    Input schema for POST /auth/register.

    Validation rules are enforced BEFORE any database operation,
    which keeps the service layer clean and focused on business logic.
    """

    username: str = Field(
        ...,
        min_length=3,
        max_length=30,
        description="Lowercase letters, digits, underscores only.",
    )
    email: EmailStr  # EmailStr validates format and normalizes the email
    password: str = Field(..., min_length=8, max_length=128)
    display_name: str | None = Field(None, max_length=100)

    @field_validator("username")
    @classmethod
    def username_must_be_valid(cls, v: str) -> str:
        """
        Enforce the username character set at the API layer.
        The regex [a-z0-9_]+ ensures only lowercase letters, digits,
        and underscores — no spaces, no hyphens, no uppercase.
        """
        import re
        if not re.match(r"^[a-z0-9_]+$", v):
            raise ValueError(
                "Username may only contain lowercase letters, digits, and underscores."
            )
        return v

    @field_validator("password")
    @classmethod
    def password_must_contain_digit(cls, v: str) -> str:
        """
        Require at least one digit in the password.
        This is a lightweight complexity requirement without a full
        password strength library.
        """
        if not any(c.isdigit() for c in v):
            raise ValueError("Password must contain at least one digit.")
        return v


class LoginRequest(BaseModel):
    """Input schema for POST /auth/login."""
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    """
    Response schema returned on successful login or registration.

    token_type is always "bearer" (lowercase) per the OAuth2 spec.
    The client should send: Authorization: Bearer <access_token>
    """
    access_token: str
    token_type: str = "bearer"
    # Include basic user info so the client doesn't need a second request
    # to identify the logged-in user right after auth.
    user_id: str
    username: str
