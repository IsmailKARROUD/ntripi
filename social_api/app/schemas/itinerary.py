"""
schemas/itinerary.py — Pydantic schemas for itinerary-related requests and responses.

Hierarchy:
  AnnotationCreate / AnnotationResponse
  StopCreate / StopUpdate / StopResponse
  TransportLegCreate / TransportLegUpdate / TransportLegResponse
  TransitSegmentCreate / TransitSegmentResponse
  ItineraryCreate / ItineraryUpdate / ItinerarySummary / ItineraryDetail
  AllowedUserAdd / AllowedUserResponse
  ReorderRequest
"""

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field, model_validator


# ---------------------------------------------------------------------------
# Annotation schemas
# ---------------------------------------------------------------------------

class AnnotationCreate(BaseModel):
    type: str = Field(..., pattern="^(advice|caution|avoid|info)$")
    content: str = Field(..., min_length=1, max_length=2000)


class AnnotationResponse(BaseModel):
    id: uuid.UUID
    stop_id: uuid.UUID
    type: str
    content: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ---------------------------------------------------------------------------
# Stop schemas  — 'transit' type removed
# ---------------------------------------------------------------------------

class StopCreate(BaseModel):
    position: int = Field(..., ge=1)
    type: Literal['origin', 'waypoint', 'destination']

    place_name: Optional[str] = Field(None, max_length=200)
    place_address: Optional[str] = None
    lat: Optional[float] = Field(None, ge=-90, le=90)
    lng: Optional[float] = Field(None, ge=-180, le=180)

    place_type: Optional[str] = Field(
        None,
        pattern="^(restaurant|cafe|museum|hotel|park|station|airport|beach|landmark|other)$",
    )

    duration_min: Optional[int] = Field(None, ge=0)
    cost: Decimal = Field(default=Decimal("0.00"), ge=0)
    is_free: bool = False
    notes: Optional[str] = None


class StopUpdate(BaseModel):
    position: Optional[int] = Field(None, ge=1)
    type: Optional[Literal['origin', 'waypoint', 'destination']] = None
    place_name: Optional[str] = Field(None, max_length=200)
    place_address: Optional[str] = None
    lat: Optional[float] = Field(None, ge=-90, le=90)
    lng: Optional[float] = Field(None, ge=-180, le=180)
    place_type: Optional[str] = Field(
        None,
        pattern="^(restaurant|cafe|museum|hotel|park|station|airport|beach|landmark|other)$",
    )
    duration_min: Optional[int] = Field(None, ge=0)
    cost: Optional[Decimal] = Field(None, ge=0)
    is_free: Optional[bool] = None
    notes: Optional[str] = None


class StopResponse(BaseModel):
    id: uuid.UUID
    itinerary_id: uuid.UUID
    position: int
    type: str
    place_name: Optional[str]
    place_address: Optional[str]
    lat: Optional[float]
    lng: Optional[float]
    place_type: Optional[str]
    duration_min: Optional[int]
    cost: float
    is_free: bool
    notes: Optional[str]
    created_at: datetime
    annotations: list[AnnotationResponse] = []

    model_config = ConfigDict(from_attributes=True)


# ---------------------------------------------------------------------------
# TransportLeg schemas
# ---------------------------------------------------------------------------

_LEG_MODES = Literal[
    'walk', 'bus', 'tram', 'metro', 'train',
    'taxi', 'uber', 'bike', 'ferry', 'car', 'airplane',
]


class TransportLegCreate(BaseModel):
    position: int = Field(..., ge=1)
    mode: _LEG_MODES
    line: Optional[str] = Field(None, max_length=30)
    direction: Optional[str] = None
    duration_min: Optional[int] = Field(None, ge=0)
    cost: Decimal = Field(default=Decimal("0.00"), ge=0)
    is_free: bool = False
    notes: Optional[str] = None


class TransportLegUpdate(BaseModel):
    # position is intentionally omitted — leg positions are reassigned as a
    # unit when the parent segment is updated (full replace via PATCH /segments/{id}).
    mode: Optional[_LEG_MODES] = None
    line: Optional[str] = Field(None, max_length=30)
    direction: Optional[str] = None
    duration_min: Optional[int] = Field(None, ge=0)
    cost: Optional[Decimal] = Field(None, ge=0)
    is_free: Optional[bool] = None
    notes: Optional[str] = None


class TransportLegResponse(BaseModel):
    id: uuid.UUID
    segment_id: uuid.UUID
    position: int
    mode: str
    line: Optional[str]
    direction: Optional[str]
    duration_min: Optional[int]
    cost: float
    is_free: bool
    notes: Optional[str]
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ---------------------------------------------------------------------------
# TransitSegment schemas
# ---------------------------------------------------------------------------

class TransitSegmentCreate(BaseModel):
    from_stop_id: uuid.UUID
    to_stop_id: uuid.UUID
    # At least one leg required — a segment with zero legs is meaningless.
    legs: list[TransportLegCreate] = Field(..., min_length=1)

    @model_validator(mode='after')
    def _validate_legs(self) -> 'TransitSegmentCreate':
        # Enforce contiguous 1-based positions so the router can insert legs
        # in order without gaps or duplicate position violations.
        positions = sorted(leg.position for leg in self.legs)
        if positions != list(range(1, len(positions) + 1)):
            raise ValueError("Leg positions must be contiguous starting from 1.")
        return self


class TransitSegmentResponse(BaseModel):
    id: uuid.UUID
    itinerary_id: uuid.UUID
    from_stop_id: uuid.UUID
    to_stop_id: uuid.UUID
    total_duration_min: int
    total_cost: float
    legs: list[TransportLegResponse] = []
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ---------------------------------------------------------------------------
# Itinerary schemas
# ---------------------------------------------------------------------------

class ItineraryCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    currency: str = Field(default="EUR", max_length=3, min_length=3)
    safety_rating: Optional[int] = Field(None, ge=1, le=5)
    visibility: Literal['public', 'followers', 'restricted', 'only_me'] = 'only_me'


class ItineraryUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=200)
    description: Optional[str] = None
    currency: Optional[str] = Field(None, max_length=3, min_length=3)
    safety_rating: Optional[int] = Field(None, ge=1, le=5)
    visibility: Optional[Literal['public', 'followers', 'restricted', 'only_me']] = None


# ---------------------------------------------------------------------------
# Rating schemas
# ---------------------------------------------------------------------------

class RatingSubmit(BaseModel):
    stars: int = Field(..., ge=1, le=5)
    safety_stars: Optional[int] = Field(None, ge=1, le=5)
    experience_stars: Optional[int] = Field(None, ge=1, le=5)
    accessibility_stars: Optional[int] = Field(None, ge=1, le=5)
    family_friendly_stars: Optional[int] = Field(None, ge=1, le=5)


class RatingResponse(BaseModel):
    stars: int
    safety_stars: Optional[int]
    experience_stars: Optional[int]
    accessibility_stars: Optional[int]
    family_friendly_stars: Optional[int]
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class RaterInfo(BaseModel):
    # All fields are Optional because the rater may have deleted their account.
    # ItineraryRating.user_id is SET NULL on user delete (GDPR anonymization),
    # so these fields can all be None for historical ratings.
    user_id: Optional[uuid.UUID]
    username: Optional[str]
    display_name: Optional[str]
    avatar_url: Optional[str]


class RatingWithUser(BaseModel):
    score: int
    safety_score: Optional[int]
    experience_score: Optional[int]
    accessibility_score: Optional[int]
    family_friendly_score: Optional[int]
    updated_at: datetime
    user: RaterInfo


class RatingDistribution(BaseModel):
    five: int
    four: int
    three: int
    two: int
    one: int


class RatingsPageResponse(BaseModel):
    rating_avg: Optional[float]
    rating_count: int
    distribution: RatingDistribution
    ratings: list[RatingWithUser]


class ItinerarySummary(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    title: str
    cover_image_url: Optional[str]
    total_duration_min: int
    total_cost: float
    currency: str
    safety_rating: Optional[int]
    visibility: Literal['public', 'followers', 'restricted', 'only_me']
    created_at: datetime
    rating_avg: Optional[float]
    rating_count: int = 0

    model_config = ConfigDict(from_attributes=True)


# ItineraryDetail extends ItinerarySummary with the full stop + segment lists.
# Used by GET /itineraries/{id} and the reorder endpoint.
class ItineraryDetail(ItinerarySummary):
    description: Optional[str]
    stops: list[StopResponse] = []
    segments: list[TransitSegmentResponse] = []


# ---------------------------------------------------------------------------
# Allowlist schemas
# ---------------------------------------------------------------------------

class AllowedUserAdd(BaseModel):
    user_id: uuid.UUID


class AllowedUserResponse(BaseModel):
    user_id: uuid.UUID
    username: str
    display_name: Optional[str]
    created_at: datetime


# ---------------------------------------------------------------------------
# Reorder schema
# ---------------------------------------------------------------------------

class ReorderRequest(BaseModel):
    stop_ids: list[uuid.UUID] = Field(..., min_length=1)
