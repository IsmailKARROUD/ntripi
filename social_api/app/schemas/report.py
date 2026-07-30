"""
schemas/report.py — Request/response schemas for content reporting.

The reason field stays a `pattern=` constrained string (not a Literal) so the
422 validation-error body keeps the project's standard shape. The regex accepts
the canonical REPORT_REASONS from app/models/content_report.py PLUS the legacy
aliases — deployed app versions still send the old vocabulary, and rejecting it
would break every installed client. report_service.normalize_reason maps them
before storage, so the DB only ever holds canonical values.

Targets are polymorphic. `itinerary_id` is kept as a deprecated alias so the
already-shipped clients (and the public share page) keep working unchanged.
"""

from __future__ import annotations

import uuid

from pydantic import BaseModel, Field, model_validator

# Kept as pattern= (not Literal) — project rule: switching changes the 422 body shape.
_REPORT_REASON_PATTERN = (
    r"^(csam|sexual_content|violence_threat|hate_speech|harassment|other|spam"
    r"|nsfw|violence|copyright)$"  # trailing three are legacy aliases
)
_REPORT_TARGET_PATTERN = r"^(itinerary|rating|user)$"


class ReportCreate(BaseModel):
    # New polymorphic form.
    target_type: str | None = Field(default=None, pattern=_REPORT_TARGET_PATTERN)
    target_id: uuid.UUID | None = None

    # Legacy form from already-shipped clients: an itinerary-only report.
    itinerary_id: uuid.UUID | None = None

    reason: str = Field(pattern=_REPORT_REASON_PATTERN)
    notes: str | None = Field(default=None, max_length=2000)

    @model_validator(mode="after")
    def _resolve_target(self) -> "ReportCreate":
        """Collapse the legacy shape onto the polymorphic one so the router only
        ever reads target_type/target_id."""
        if self.target_id is None and self.itinerary_id is not None:
            self.target_type = "itinerary"
            self.target_id = self.itinerary_id
        if self.target_id is None:
            raise ValueError("target_id (or itinerary_id) is required")
        if self.target_type is None:
            self.target_type = "itinerary"
        return self


class ReportAck(BaseModel):
    ok: bool = True
