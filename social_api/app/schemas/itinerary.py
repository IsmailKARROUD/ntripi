"""
schemas/itinerary.py — Pydantic schemas for itinerary-related requests and responses.

Hierarchy:
  AnnotationCreate / AnnotationResponse
  StopCreate / StopUpdate / StopResponse
  TrackResponse
  TransportLegCreate / TransportLegUpdate / TransportLegResponse
  TransitSegmentCreate / TransitSegmentResponse
  ItineraryCreate / ItineraryUpdate / ItinerarySummary / ItineraryDetail
  AllowedUserAdd / AllowedUserResponse
"""

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Literal, Optional
from urllib.parse import urlparse

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


# Shared field constraints. Kept as regex strings (not Literal types) so the
# 422 validation-error shape stays byte-identical to the pre-refactor schemas.
_NOTE_TYPE_PATTERN = "^(advice|caution|avoid|info)$"
_PLACE_TYPE_PATTERN = (
    "^(eatDrink|sleep|pray|learnSee|buy|playWatch|nature|transport|healBathe|entertainment|sight)$"
)
_VISIBILITY = Literal['public', 'followers', 'restricted', 'only_me']


# A stop's map_url may only point at Google Maps — OSM's gazetteer is thinner,
# so users paste a Google Maps link for places it can't resolve. This is the
# security boundary (do not trust the client): any host not on the allowlist is
# rejected, so an arbitrary link (YouTube, other providers) can never be stored.
def validate_google_maps_url(url: Optional[str]) -> Optional[str]:
    if url is None:
        return url
    parsed = urlparse(url.strip())
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise ValueError("map_url must be an http(s) Google Maps link")
    host = parsed.hostname.lower()
    path = parsed.path or ""
    # Short-link / maps subdomains carry the destination in the path itself.
    if host in ("maps.google.com", "maps.app.goo.gl"):
        return url.strip()
    # Bare-domain hosts must scope to /maps so a generic google.com/goo.gl
    # (search, mail, arbitrary short link) can't slip through.
    if host in ("google.com", "www.google.com", "goo.gl") and path.startswith("/maps"):
        return url.strip()
    raise ValueError("map_url must be a Google Maps link")


# ---------------------------------------------------------------------------
# Annotation schemas
#
# Itinerary-level and stop-level annotations share identical request bodies;
# only the response FK differs (itinerary_id vs stop_id). The two Response
# classes stay separate on purpose — a shared base would serialize the FK
# field last (base-class fields come first), changing the JSON key order.
# ---------------------------------------------------------------------------

class _AnnotationCreateBase(BaseModel):
    type: str = Field(..., pattern=_NOTE_TYPE_PATTERN)
    content: str = Field(..., min_length=1, max_length=2000)


class _AnnotationUpdateBase(BaseModel):
    type: str | None = Field(None, pattern=_NOTE_TYPE_PATTERN)
    content: str | None = Field(None, min_length=1, max_length=2000)

    @model_validator(mode='after')
    def at_least_one_field(self) -> '_AnnotationUpdateBase':
        if self.type is None and self.content is None:
            raise ValueError(
                "At least one field (type or content) must be provided."
            )
        return self


class ItineraryAnnotationCreate(_AnnotationCreateBase):
    pass


class ItineraryAnnotationUpdate(_AnnotationUpdateBase):
    pass


class ItineraryAnnotationResponse(BaseModel):
    id: uuid.UUID
    itinerary_id: uuid.UUID
    type: str
    content: str
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class AnnotationCreate(_AnnotationCreateBase):
    pass


class AnnotationUpdate(_AnnotationUpdateBase):
    pass


class AnnotationResponse(BaseModel):
    id: uuid.UUID
    stop_id: uuid.UUID
    type: str
    content: str
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ---------------------------------------------------------------------------
# Stop schemas
# ---------------------------------------------------------------------------

class StopCreate(BaseModel):
    # Track placement: provide an existing track_id to add within that track,
    # or omit (null) to create a new track.
    track_id: Optional[uuid.UUID] = None

    # Anchor stops for rank computation. Both optional; the server bisects.
    after_stop_id: Optional[uuid.UUID] = None
    before_stop_id: Optional[uuid.UUID] = None

    # Anchor tracks for rank computation when creating a new track (track_id=null).
    after_track_id: Optional[uuid.UUID] = None
    before_track_id: Optional[uuid.UUID] = None

    place_name: Optional[str] = Field(None, max_length=200)
    place_address: Optional[str] = None
    lat: Optional[float] = Field(None, ge=-90, le=90)
    lng: Optional[float] = Field(None, ge=-180, le=180)
    map_url: Optional[str] = Field(None, max_length=500)

    place_type: Optional[str] = Field(None, pattern=_PLACE_TYPE_PATTERN)

    duration_min: Optional[int] = Field(None, ge=0)
    cost: Decimal = Field(default=Decimal("0.00"), ge=0)
    is_free: bool = False
    notes: Optional[str] = None

    _validate_map_url = field_validator("map_url")(validate_google_maps_url)


class StopUpdate(BaseModel):
    place_name: Optional[str] = Field(None, max_length=200)
    place_address: Optional[str] = None
    lat: Optional[float] = Field(None, ge=-90, le=90)
    lng: Optional[float] = Field(None, ge=-180, le=180)
    map_url: Optional[str] = Field(None, max_length=500)
    place_type: Optional[str] = Field(None, pattern=_PLACE_TYPE_PATTERN)
    duration_min: Optional[int] = Field(None, ge=0)

    _validate_map_url = field_validator("map_url")(validate_google_maps_url)
    cost: Optional[Decimal] = Field(None, ge=0)
    is_free: Optional[bool] = None
    notes: Optional[str] = None

    # Optional move: if track_id provided and differs from current, stop is moved.
    track_id: Optional[uuid.UUID] = None
    after_stop_id: Optional[uuid.UUID] = None
    before_stop_id: Optional[uuid.UUID] = None

    # New-track move: when track_id is null and either anchor is provided,
    # the server creates a brand-new track at that position and moves this
    # stop into it. Mirrors the StopCreate API for "create new track" inserts.
    after_track_id: Optional[uuid.UUID] = None
    before_track_id: Optional[uuid.UUID] = None

    @model_validator(mode='after')
    def _validate_move_target(self) -> 'StopUpdate':
        # New-track anchors are only valid when track_id is null. Otherwise
        # the intent is ambiguous (move to existing track vs create new one).
        if self.track_id is not None and (
            self.after_track_id is not None or self.before_track_id is not None
        ):
            raise ValueError(
                "after_track_id / before_track_id are only valid when "
                "track_id is null (new-track move)."
            )
        return self


class ReorderRequest(BaseModel):
    """
    Batch reorder of tracks and/or stops, plus optional segment deletions.

    At least one of the three fields must be provided.

    stop_orders   — map of track_id → list of stop_ids in the desired display
                    order. For each entry, the provided stop_id set must
                    exactly match the track's current stop_id set (no missing,
                    no extra, no duplicates). Every track must belong to the
                    itinerary referenced in the URL.
    track_order   — full track order for the itinerary. If provided, must
                    contain exactly the current track-id set (no missing, no
                    extra, no duplicates).
    segments_to_delete
                  — segment IDs to delete in the same transaction (typically
                    those orphaned by a track reorder).

    Server computes new fractional-index ranks (via n_keys_between) — the
    client never sends rank strings, only order.
    """

    stop_orders: dict[uuid.UUID, list[uuid.UUID]] = Field(default_factory=dict)
    track_order: Optional[list[uuid.UUID]] = None
    segments_to_delete: list[uuid.UUID] = Field(default_factory=list)

    @model_validator(mode='after')
    def _validate(self) -> 'ReorderRequest':
        if (not self.stop_orders
                and self.track_order is None
                and not self.segments_to_delete):
            raise ValueError(
                "at least one of stop_orders, track_order, or "
                "segments_to_delete must be provided"
            )
        for track_id, stop_ids in self.stop_orders.items():
            if not stop_ids:
                raise ValueError(
                    f"stop_orders[{track_id}] must contain at least one stop"
                )
        return self


class StopResponse(BaseModel):
    id: uuid.UUID
    itinerary_id: uuid.UUID
    track_id: uuid.UUID
    rank: str
    place_name: Optional[str]
    place_address: Optional[str]
    lat: Optional[float]
    lng: Optional[float]
    map_url: Optional[str]
    place_type: Optional[str]
    duration_min: Optional[int]
    cost: float
    is_free: bool
    notes: Optional[str]
    created_at: datetime
    annotations: list[AnnotationResponse] = []

    model_config = ConfigDict(from_attributes=True)


# ---------------------------------------------------------------------------
# Track schemas
# ---------------------------------------------------------------------------

class TrackResponse(BaseModel):
    id: uuid.UUID
    itinerary_id: uuid.UUID
    rank: str
    stops: list[StopResponse] = []

    model_config = ConfigDict(from_attributes=True)


# ---------------------------------------------------------------------------
# TransportLeg schemas
# ---------------------------------------------------------------------------

_LEG_MODES = Literal[
    'walk', 'bus', 'tram', 'metro', 'train',
    'taxi', 'uber', 'bike', 'ferry', 'car', 'airplane',
]

_NOTE_TYPES = Literal['advice', 'caution', 'avoid', 'info']


class TransportLegCreate(BaseModel):
    position: int = Field(..., ge=1)
    mode: _LEG_MODES
    line: Optional[str] = Field(None, max_length=30)
    direction: Optional[str] = None
    duration_min: Optional[int] = Field(None, ge=0)
    cost: Decimal = Field(default=Decimal("0.00"), ge=0)
    is_free: bool = False
    notes: Optional[str] = None
    note_type: Optional[_NOTE_TYPES] = None


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
    note_type: Optional[_NOTE_TYPES] = None


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
    note_type: Optional[str]
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
    visibility: _VISIBILITY = 'only_me'


class ItineraryUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=200)
    description: Optional[str] = None
    currency: Optional[str] = Field(None, max_length=3, min_length=3)
    visibility: Optional[_VISIBILITY] = None


# ---------------------------------------------------------------------------
# Rating schemas
# ---------------------------------------------------------------------------

class RatingSubmit(BaseModel):
    stars: int = Field(..., ge=1, le=5)
    safety_stars: Optional[int] = Field(None, ge=1, le=5)
    experience_stars: Optional[int] = Field(None, ge=1, le=5)
    accessibility_stars: Optional[int] = Field(None, ge=1, le=5)
    family_friendly_stars: Optional[int] = Field(None, ge=1, le=5)
    crowdedness_stars: Optional[int] = Field(None, ge=1, le=5)
    note: Optional[str] = None


class RatingResponse(BaseModel):
    stars: int
    safety_stars: Optional[int]
    experience_stars: Optional[int]
    accessibility_stars: Optional[int]
    family_friendly_stars: Optional[int]
    crowdedness_stars: Optional[int]
    note: Optional[str]
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class RaterInfo(BaseModel):
    # All fields are Optional because the rater may have deleted their account.
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
    crowdedness_score: Optional[int]
    note: Optional[str]
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
    visibility: _VISIBILITY
    created_at: datetime
    updated_at: datetime
    rating_avg: Optional[float]
    rating_count: int = 0
    stops_count: int = 0

    model_config = ConfigDict(from_attributes=True)


# ItineraryFeedItem extends ItinerarySummary with owner attribution — the discovery
# feed lists itineraries across users, so each card needs to show who authored it.
# RaterInfo is reused (same user_id/username/display_name/avatar_url shape).
class ItineraryFeedItem(ItinerarySummary):
    owner: RaterInfo


# ItineraryDetail extends ItinerarySummary with tracks (ordered) + segments.
class ItineraryDetail(ItinerarySummary):
    description: Optional[str]
    tracks: list[TrackResponse] = []
    segments: list[TransitSegmentResponse] = []
    annotations: list[ItineraryAnnotationResponse] = []
    # Moderator-hidden flag (from Itinerary.hidden). Appended last so existing
    # JSON key order — part of the API contract — is unchanged. Only ever true
    # for the owner: every other viewer is filtered out or 403s before this.
    hidden: bool = False


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
# Cover image schema
# ---------------------------------------------------------------------------

class ItineraryImageResponse(BaseModel):
    cover_image_url: str
