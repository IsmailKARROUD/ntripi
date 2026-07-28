"""
schemas/appeal.py — Request/response schemas for the user appeals workflow.

target_type stays a `pattern=` constrained string (not a Literal) so the 422
validation-error body keeps the project's standard shape. The regex mirrors
MODERATION_LOG_TARGET_TYPES in app/models/moderation_log.py.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

# Kept as pattern= (not Literal) — project rule: switching changes the 422 body shape.
_TARGET_TYPE_PATTERN = r"^(itinerary|user)$"


class AppealCreate(BaseModel):
    target_type: str = Field(pattern=_TARGET_TYPE_PATTERN)
    target_id: uuid.UUID
    reason: str = Field(min_length=1, max_length=2000)


class AppealResponse(BaseModel):
    id: uuid.UUID
    target_type: str
    target_id: uuid.UUID
    status: str
    user_reason: str
    admin_response: str | None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ViolationItem(BaseModel):
    """One moderation action against the user, as shown on Account status."""

    id: uuid.UUID
    action: str
    target_type: str
    target_id: uuid.UUID | None
    item_title: str | None
    created_at: datetime
    # False once the penalty was lifted (unhide / unban / appeal restore).
    active: bool
    appealable: bool
    appeal_status: str | None
    cooldown_until: datetime | None


class ViolationsResponse(BaseModel):
    violations: list[ViolationItem]
