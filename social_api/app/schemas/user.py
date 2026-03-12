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
from pydantic import BaseModel, EmailStr, Field, field_validator, model_config
import re


class UserBase(BaseModel):
    """Common fields shared between response schemas."""
    id: uuid.UUID
    username: str
    display_name: str | None
    bio: str | None
    avatar_url: str | None
    is_private: bool
    followers_count: int
    following_count: int
    created_at: datetime

    # model_config replaces class Config in Pydantic v2.
    # from_attributes=True (was orm_mode=True in v1) allows creating
    # a Pydantic model directly from a SQLAlchemy ORM object.
    model_config = model_config(from_attributes=True)


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
    is_active: bool
    updated_at: datetime


class UserUpdateRequest(BaseModel):
    """
    Input schema for PATCH /users/me.

    All fields are optional — this is a true partial update.
    Only the fields provided in the request body are updated.
    """
    display_name: str | None = Field(None, max_length=100)
    bio: str | None = Field(None, max_length=500)
    avatar_url: str | None = None
    is_private: bool | None = None


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

    model_config = model_config(from_attributes=True)
