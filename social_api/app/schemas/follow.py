"""
schemas/follow.py — Pydantic schemas for follow-related responses.
"""

import uuid
from datetime import datetime
from pydantic import BaseModel, ConfigDict


class FollowResponse(BaseModel):
    """Response returned after a follow/unfollow action."""
    id: uuid.UUID
    follower_id: uuid.UUID
    following_id: uuid.UUID
    status: str  # 'pending' or 'accepted'
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class FollowRequestItem(BaseModel):
    """
    A single pending follow request as seen in GET /users/me/follow-requests.

    The follow_id is included so the client can reference the specific record
    when accepting or rejecting (POST/DELETE /users/me/follow-requests/{follow_id}).
    """
    follow_id: uuid.UUID       # The Follow record's own ID
    follower_id: uuid.UUID     # Who sent the request
    username: str              # follower's username
    display_name: str | None   # follower's display name (nullable)
    avatar_url: str | None     # follower's avatar (nullable)
    requested_at: datetime     # when the request was sent (follow.created_at)

    model_config = ConfigDict(from_attributes=True)


class FollowerListItem(BaseModel):
    """
    A single item in the followers or following list.
    Compact profile view for list rendering.
    """
    id: uuid.UUID
    username: str
    display_name: str | None
    avatar_url: str | None
    is_private: bool

    model_config = ConfigDict(from_attributes=True)
