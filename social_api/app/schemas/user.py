"""
schemas/user.py — Pydantic schemas for user-related API responses.

Schema hierarchy:
  UserBase → shared fields between create and response
  UserPublicProfile → what other users see (no email)
  UserPrivateProfile → what the owner sees (includes email)
  UserUpdateRequest → PATCH /users/me input (all fields optional)
  UserSearchResult → compact view for search results
"""

import uuid
from datetime import datetime
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator
import re


class UserBase(BaseModel):
    """Common fields shared between response schemas."""
    id: uuid.UUID
    username: str
    display_name: str | None
    bio: str | None
    avatar_url: str | None
    cover_image_url: str | None
    is_private: bool
    followers_count: int
    following_count: int
    created_at: datetime
    passport_countries: list[str] | None = None
    resident_country: str | None = None
    languages: list[str] | None = None

    # model_config replaces class Config in Pydantic v2.
    # from_attributes=True (was orm_mode=True in v1) allows creating
    # a Pydantic model directly from a SQLAlchemy ORM object.
    model_config = ConfigDict(from_attributes=True)


class UserPublicProfile(UserBase):
    """
    What any authenticated user sees when viewing someone else's profile.
    Email is intentionally excluded — it's private information.

    Two computed fields are added by the router after a follows-table lookup:
      is_following: bool — does the current user follow this person?
      follow_is_pending: bool — is there a pending request?
    These are defaulted to False here; the router populates them.
    """
    is_following: bool = False
    follow_is_pending: bool = False


class UserPrivateProfile(UserBase):
    """
    What the account owner sees at GET /users/me.
    Includes email since you can only see your own profile here.
    """
    email: str
    # Gates high-value actions client-side; the server is the source of truth.
    # Verified by signing in with Google (see require_verified_email).
    email_verified: bool
    # True when the account can log in with a password (not Google-only). The
    # client uses this to show/hide "Change password". Reads User.has_password.
    has_password: bool
    # True when a Google login is linked. With has_password, lets the delete
    # screen offer Google as an alternative re-auth for dual-method accounts.
    has_google: bool
    is_active: bool
    updated_at: datetime
    # Moderation state of display_name + bio, so the owner can be told their
    # profile text is hidden. Deliberately absent from UserPublicProfile — this
    # is the account owner's own read.
    moderation_status: str = "approved"
    # Optional notification switches. On UserPrivateProfile only — what someone
    # chose to be notified about is nobody else's business. Appended, never
    # inserted: field order is JSON key order and part of the API contract.
    notify_ratings: bool = True
    notify_saves: bool = True
    notify_follow_accepted: bool = True
    # False once the ToS are revised, until the user accepts again. Reads
    # User.tos_current. The client blocks the app on it; the server is still
    # the source of truth for whether registration was gated at all.
    tos_current: bool = False


class UserUpdateRequest(BaseModel):
    """
    Input schema for PATCH /users/me.

    All fields are optional — this is a true partial update.
    Only the fields provided in the request body are updated.
    Username editing is intentionally excluded (deferred — needs rate limiting).
    """
    display_name: str | None = Field(None, max_length=50)
    bio: str | None = Field(None, max_length=500)
    avatar_url: str | None = None
    cover_image_url: str | None = None
    is_private: bool | None = None
    passport_countries: list[str] | None = None
    resident_country: str | None = None
    languages: list[str] | None = None
    # Optional in-app notification types. None = leave as-is (partial update),
    # so the notification settings screen PATCHes only the switch that moved.
    notify_ratings: bool | None = None
    notify_saves: bool | None = None
    notify_follow_accepted: bool | None = None

    @field_validator("display_name")
    @classmethod
    def _check_display_name(cls, v: str | None) -> str | None:
        from app.validators.username import validate_display_name
        return validate_display_name(v)

    @field_validator("avatar_url", "cover_image_url")
    @classmethod
    def _check_image_url(cls, v: str | None) -> str | None:
        # Reject external URLs — images must be uploaded (and thus scanned),
        # not pasted. Only our own storage URLs (or null) are accepted here.
        from app.validators.image_url import validate_own_storage_image_url
        return validate_own_storage_image_url(v)

    @field_validator("passport_countries", mode="before")
    @classmethod
    def _check_passports(cls, v: list | None) -> list[str] | None:
        if v is None:
            return None
        if not isinstance(v, list):
            raise ValueError("must be a list of country codes")
        if len(v) > 5:
            raise ValueError("at most 5 passport countries")
        result = []
        for code in v:
            if not isinstance(code, str) or len(code) != 2 or not code.isalpha():
                raise ValueError(f"'{code}' is not a valid 2-letter country code")
            result.append(code.upper())
        return result

    @field_validator("resident_country", mode="before")
    @classmethod
    def _check_resident_country(cls, v: str | None) -> str | None:
        if v is None:
            return None
        if not isinstance(v, str) or len(v) != 2 or not v.isalpha():
            raise ValueError("must be a 2-letter ISO country code")
        return v.upper()

    @field_validator("languages", mode="before")
    @classmethod
    def _check_languages(cls, v: list | None) -> list[str] | None:
        if v is None:
            return None
        if not isinstance(v, list):
            raise ValueError("must be a list of language codes")
        if len(v) > 60:
            raise ValueError("at most 60 languages")
        result = []
        for code in v:
            if not isinstance(code, str) or len(code) < 2 or len(code) > 3 or not code.isalpha():
                raise ValueError(f"'{code}' is not a valid language code")
            result.append(code.upper())
        return result


class DeleteAccountRequest(BaseModel):
    """Input for DELETE /users/me — re-confirmation credential.

    Password accounts send `password`; passwordless (SSO) accounts send their
    provider credential (`google_id_token` today; add `apple_*`/`facebook_*`
    when those providers ship). The endpoint picks the branch by account type.
    """
    password: str | None = None
    google_id_token: str | None = None


class UserSearchResult(BaseModel):
    """
    Compact user representation for search results.
    Only the fields needed to render a search result row.
    """
    id: uuid.UUID
    username: str
    display_name: str | None
    avatar_url: str | None
    is_private: bool
    followers_count: int

    model_config = ConfigDict(from_attributes=True)


class UserImageResponse(BaseModel):
    """Response for avatar/cover upload + delete endpoints.

    Only the field that was mutated will be populated; the other stays None.
    """
    avatar_url: str | None = None
    cover_image_url: str | None = None


class VisitedLocationItem(BaseModel):
    """A single stop coordinate from one of the user's itineraries."""
    lat: float
    lng: float
    place_name: str | None
    place_type: str | None
    itinerary_id: uuid.UUID
    stop_id: uuid.UUID


class VisitedLocationsResponse(BaseModel):
    """All coordinate stops the viewer is allowed to see for a user."""
    locations: list[VisitedLocationItem]
