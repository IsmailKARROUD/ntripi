"""
schemas/itinerary.py — Pydantic schemas for itinerary-related requests and responses.

Hierarchy:
  AnnotationCreate / AnnotationResponse
  StopCreate / StopUpdate / StopResponse
  ItineraryCreate / ItineraryUpdate / ItinerarySummary / ItineraryDetail
  ReorderRequest
"""

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


# ---------------------------------------------------------------------------
# Annotation schemas
# ---------------------------------------------------------------------------

class AnnotationCreate(BaseModel):
    """Input for POST .../annotations."""
    type: str = Field(..., pattern="^(advice|caution|avoid|info)$")
    content: str = Field(..., min_length=1, max_length=2000)


class AnnotationResponse(BaseModel):
    """Annotation as returned by the API."""
    id: uuid.UUID
    stop_id: uuid.UUID
    type: str
    content: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ---------------------------------------------------------------------------
# Stop schemas
# ---------------------------------------------------------------------------

class StopCreate(BaseModel):
    """Input for POST .../stops."""
    position: int = Field(..., ge=1)
    type: str = Field(..., pattern="^(origin|waypoint|transit|destination)$")

    # Location — user-authored text + OSM coordinates (legal to store)
    place_name: Optional[str] = Field(None, max_length=200)
    place_address: Optional[str] = None
    lat: Optional[float] = Field(None, ge=-90, le=90)
    lng: Optional[float] = Field(None, ge=-180, le=180)

    # User-selected place category (not from any external provider)
    place_type: Optional[str] = Field(
        None,
        pattern="^(restaurant|cafe|museum|hotel|park|station|airport|beach|landmark|other)$",
    )

    # Transit fields — only relevant when type='transit'
    transport_mode: Optional[str] = Field(
        None,
        pattern="^(walk|bus|tram|metro|train|taxi|uber|bike|ferry|car)$",
    )
    transport_line: Optional[str] = Field(None, max_length=30)
    transport_direction: Optional[str] = None

    # Time and money
    duration_min: Optional[int] = Field(None, ge=0)
    cost: Decimal = Field(default=Decimal("0.00"), ge=0)
    is_free: bool = False
    notes: Optional[str] = None


class StopUpdate(BaseModel):
    """Input for PATCH .../stops/{stop_id}. All fields optional."""
    position: Optional[int] = Field(None, ge=1)
    type: Optional[str] = Field(None, pattern="^(origin|waypoint|transit|destination)$")
    place_name: Optional[str] = Field(None, max_length=200)
    place_address: Optional[str] = None
    lat: Optional[float] = Field(None, ge=-90, le=90)
    lng: Optional[float] = Field(None, ge=-180, le=180)
    place_type: Optional[str] = Field(
        None,
        pattern="^(restaurant|cafe|museum|hotel|park|station|airport|beach|landmark|other)$",
    )
    transport_mode: Optional[str] = Field(
        None,
        pattern="^(walk|bus|tram|metro|train|taxi|uber|bike|ferry|car)$",
    )
    transport_line: Optional[str] = Field(None, max_length=30)
    transport_direction: Optional[str] = None
    duration_min: Optional[int] = Field(None, ge=0)
    cost: Optional[Decimal] = Field(None, ge=0)
    is_free: Optional[bool] = None
    notes: Optional[str] = None


class StopResponse(BaseModel):
    """Stop as returned by the API, with its annotations included."""
    id: uuid.UUID
    itinerary_id: uuid.UUID
    position: int
    type: str
    place_name: Optional[str]
    place_address: Optional[str]
    lat: Optional[float]
    lng: Optional[float]
    place_type: Optional[str]
    transport_mode: Optional[str]
    transport_line: Optional[str]
    transport_direction: Optional[str]
    duration_min: Optional[int]
    cost: float          # Decimal → float for JSON serialization
    is_free: bool
    notes: Optional[str]
    created_at: datetime
    annotations: list[AnnotationResponse] = []

    model_config = ConfigDict(from_attributes=True)


# ---------------------------------------------------------------------------
# Itinerary schemas
# ---------------------------------------------------------------------------

class ItineraryCreate(BaseModel):
    """Input for POST /itineraries."""
    title: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    currency: str = Field(default="EUR", max_length=3, min_length=3)
    safety_rating: Optional[int] = Field(None, ge=1, le=5)
    is_public: bool = False


class ItineraryUpdate(BaseModel):
    """Input for PATCH /itineraries/{id}. All fields optional."""
    title: Optional[str] = Field(None, min_length=1, max_length=200)
    description: Optional[str] = None
    currency: Optional[str] = Field(None, max_length=3, min_length=3)
    safety_rating: Optional[int] = Field(None, ge=1, le=5)
    is_public: Optional[bool] = None


class ItinerarySummary(BaseModel):
    """
    Compact itinerary view used in list responses.
    Does not include the description or the full stop list.
    """
    id: uuid.UUID
    user_id: uuid.UUID
    title: str
    cover_image_url: Optional[str]
    total_duration_min: int
    total_cost: float    # Decimal → float for JSON serialization
    currency: str
    safety_rating: Optional[int]
    is_public: bool
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ItineraryDetail(ItinerarySummary):
    """
    Full itinerary view used in detail responses.
    Extends ItinerarySummary with description and the ordered stop list.
    """
    description: Optional[str]
    stops: list[StopResponse] = []


# ---------------------------------------------------------------------------
# Reorder schema
# ---------------------------------------------------------------------------

class ReorderRequest(BaseModel):
    """
    Body for PATCH /itineraries/{id}/stops/reorder.
    The client sends the complete ordered list of stop UUIDs.
    The backend reassigns position=1,2,3... in that exact order.
    """
    stop_ids: list[uuid.UUID] = Field(..., min_length=1)
