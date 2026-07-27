"""
schemas/report.py — Request/response schemas for content reporting.

The reason field stays a `pattern=` constrained string (not a Literal) so the
422 validation-error body keeps the project's standard shape. The regex mirrors
REPORT_REASONS in app/models/content_report.py.
"""

from __future__ import annotations

import uuid

from pydantic import BaseModel, Field

# Kept as pattern= (not Literal) — project rule: switching changes the 422 body shape.
_REPORT_REASON_PATTERN = r"^(spam|nsfw|violence|hate_speech|harassment|copyright|other)$"


class ReportCreate(BaseModel):
    itinerary_id: uuid.UUID
    reason: str = Field(pattern=_REPORT_REASON_PATTERN)
    notes: str | None = Field(default=None, max_length=2000)


class ReportAck(BaseModel):
    ok: bool = True
