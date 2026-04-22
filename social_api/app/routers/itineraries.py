"""
routers/itineraries.py — Itinerary, stop, annotation, allowlist, segment, and leg endpoints.

All routes require Bearer token authentication (get_current_user dependency).
The router prefix '/itineraries' is added in main.py.

Ownership rule:
  Every mutating endpoint (PATCH, DELETE) verifies that the authenticated
  user owns the itinerary. Unauthorized access returns 403.

Visibility rule:
  GET /itineraries/{id} delegates to can_view_itinerary() in
  services/itinerary_access.py — the single source of truth for visibility
  logic. Logic is never duplicated inline here.

Total recalculation:
  After every stop/segment/leg mutation, _recalculate_totals() recomputes
  itinerary.total_duration_min and itinerary.total_cost from both stops
  and transit segments so summary views always reflect current state.
"""

import uuid
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.dependencies import get_current_user
from app.models.annotation import Annotation
from app.models.itinerary import Itinerary
from app.models.itinerary_allowed_user import ItineraryAllowedUser
from app.models.stop import Stop
from app.models.transit_segment import TransitSegment
from app.models.transport_leg import TransportLeg
from app.models.user import User
from app.models.itinerary_rating import ItineraryRating
from app.schemas.itinerary import (
    AllowedUserAdd,
    AllowedUserResponse,
    AnnotationCreate,
    AnnotationResponse,
    ItineraryCreate,
    ItineraryDetail,
    ItinerarySummary,
    ItineraryUpdate,
    RaterInfo,
    RatingDistribution,
    RatingResponse,
    RatingSubmit,
    RatingWithUser,
    RatingsPageResponse,
    ReorderRequest,
    StopCreate,
    StopResponse,
    StopUpdate,
    TransitSegmentCreate,
    TransitSegmentResponse,
    TransportLegCreate,
    TransportLegResponse,
    TransportLegUpdate,
)
from app.services.itinerary_access import can_view_itinerary, recalculate_rating

router = APIRouter(tags=["Itineraries"])

# Second router mounted under /users in main.py.
# Kept separate to avoid prefix conflicts with the /itineraries router.
user_itineraries_router = APIRouter(tags=["Itineraries"])


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _get_itinerary_or_404(itinerary_id: uuid.UUID, db: Session) -> Itinerary:
    """Fetch an itinerary by ID or raise 404."""
    itinerary = db.get(Itinerary, itinerary_id)
    if not itinerary:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Itinerary not found.",
        )
    return itinerary


def _require_owner(itinerary: Itinerary, current_user: User) -> None:
    """Raise 403 if the current user does not own the itinerary."""
    if itinerary.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have permission to modify this itinerary.",
        )


def _recalculate_segment_totals(segment: TransitSegment, db: Session) -> None:
    """Recompute segment.total_duration_min and total_cost from its legs."""
    legs = db.execute(
        select(TransportLeg).where(TransportLeg.segment_id == segment.id)
    ).scalars().all()

    segment.total_duration_min = sum(lg.duration_min or 0 for lg in legs)
    segment.total_cost = sum(
        (lg.cost if lg.cost is not None else Decimal("0.00"))
        for lg in legs
        if not lg.is_free
    )


def _recalculate_totals(itinerary: Itinerary, db: Session) -> None:
    """
    Recompute total_duration_min and total_cost from stops AND transit segments.

    Cost rule: only include stops/legs where is_free=False.
    Duration rule: treat NULL duration_min as 0.
    """
    stops = db.execute(
        select(Stop).where(Stop.itinerary_id == itinerary.id)
    ).scalars().all()

    segments = db.execute(
        select(TransitSegment).where(TransitSegment.itinerary_id == itinerary.id)
    ).scalars().all()

    stop_duration = sum(s.duration_min or 0 for s in stops)
    stop_cost = sum(
        (s.cost if s.cost is not None else Decimal("0.00"))
        for s in stops
        if not s.is_free
    )
    seg_duration = sum(seg.total_duration_min for seg in segments)
    seg_cost = sum(seg.total_cost for seg in segments)

    itinerary.total_duration_min = stop_duration + seg_duration
    itinerary.total_cost = stop_cost + seg_cost


def _load_itinerary_detail(itinerary_id: uuid.UUID, db: Session) -> Itinerary:
    """
    Fetch an itinerary with stops, annotations, and transit segments+legs loaded.
    Uses selectinload to avoid N+1 queries.
    """
    itinerary = db.execute(
        select(Itinerary)
        .options(
            selectinload(Itinerary.stops).selectinload(Stop.annotations),
            selectinload(Itinerary.segments).selectinload(TransitSegment.legs),
            selectinload(Itinerary.segments).selectinload(TransitSegment.from_stop),
        )
        .where(Itinerary.id == itinerary_id)
    ).scalar_one_or_none()

    if not itinerary:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Itinerary not found.",
        )
    itinerary.segments.sort(
        key=lambda seg: seg.from_stop.position if seg.from_stop else 0
    )
    return itinerary


def _get_segment_or_404(
    segment_id: uuid.UUID,
    itinerary_id: uuid.UUID,
    db: Session,
) -> TransitSegment:
    """Fetch a segment and verify it belongs to the given itinerary."""
    segment = db.execute(
        select(TransitSegment)
        .options(selectinload(TransitSegment.legs))
        .where(
            TransitSegment.id == segment_id,
            TransitSegment.itinerary_id == itinerary_id,
        )
    ).scalar_one_or_none()

    if not segment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transit segment not found.",
        )
    return segment


def _get_leg_or_404(
    leg_id: uuid.UUID,
    segment_id: uuid.UUID,
    db: Session,
) -> TransportLeg:
    """Fetch a leg and verify it belongs to the given segment."""
    leg = db.execute(
        select(TransportLeg).where(
            TransportLeg.id == leg_id,
            TransportLeg.segment_id == segment_id,
        )
    ).scalar_one_or_none()

    if not leg:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transport leg not found.",
        )
    return leg


def _get_stop_or_404(
    stop_id: uuid.UUID,
    itinerary_id: uuid.UUID,
    db: Session,
) -> Stop:
    """Fetch a stop and verify it belongs to the given itinerary."""
    stop = db.execute(
        select(Stop)
        .options(selectinload(Stop.annotations))
        .where(Stop.id == stop_id, Stop.itinerary_id == itinerary_id)
    ).scalar_one_or_none()

    if not stop:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Stop not found.",
        )
    return stop


# ---------------------------------------------------------------------------
# POST /itineraries — Create an itinerary
# ---------------------------------------------------------------------------

@router.post(
    "/",
    response_model=ItinerarySummary,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new itinerary",
)
def create_itinerary(
    body: ItineraryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ItinerarySummary:
    """
    Create a new empty itinerary owned by the authenticated user.
    total_duration_min and total_cost start at 0 — they are updated as stops
    are added. visibility defaults to 'only_me'.
    """
    itinerary = Itinerary(
        user_id=current_user.id,
        title=body.title,
        description=body.description,
        currency=body.currency,
        safety_rating=body.safety_rating,
        visibility=body.visibility,
        total_duration_min=0,
        total_cost=Decimal("0.00"),
    )
    db.add(itinerary)
    db.commit()
    db.refresh(itinerary)
    return itinerary  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# GET /itineraries/me — List the current user's itineraries
# ---------------------------------------------------------------------------

@router.get(
    "/me",
    response_model=list[ItinerarySummary],
    summary="List my itineraries",
)
def list_my_itineraries(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[ItinerarySummary]:
    """Return all itineraries owned by the authenticated user, newest first."""
    itineraries = db.execute(
        select(Itinerary)
        .where(Itinerary.user_id == current_user.id)
        .order_by(Itinerary.created_at.desc())
    ).scalars().all()
    return itineraries  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# GET /itineraries/{itinerary_id} — Get itinerary detail
# ---------------------------------------------------------------------------

@router.get(
    "/{itinerary_id}",
    response_model=ItineraryDetail,
    summary="Get itinerary detail with stops and annotations",
)
def get_itinerary(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ItineraryDetail:
    """
    Return the full itinerary including all stops (with annotations).

    Visibility is enforced by can_view_itinerary() — the single source of truth.
    Non-owners who fail the visibility check receive 403.
    """
    itinerary = _load_itinerary_detail(itinerary_id, db)

    if not can_view_itinerary(itinerary, current_user.id, db):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have access to this itinerary",
        )

    return itinerary  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# PATCH /itineraries/{itinerary_id} — Update itinerary header
# ---------------------------------------------------------------------------

@router.patch(
    "/{itinerary_id}",
    response_model=ItinerarySummary,
    summary="Update itinerary title, description, or settings",
)
def update_itinerary(
    itinerary_id: uuid.UUID,
    body: ItineraryUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ItinerarySummary:
    """
    Partial update — only the fields present in the body are changed.
    When visibility changes away from 'restricted', the allowlist rows are
    preserved so they can be reused if the owner switches back.
    """
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    update_data = body.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(itinerary, field, value)

    db.commit()
    db.refresh(itinerary)
    return itinerary  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# DELETE /itineraries/{itinerary_id} — Delete an itinerary
# ---------------------------------------------------------------------------

@router.delete(
    "/{itinerary_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete an itinerary and all its stops",
)
def delete_itinerary(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    """
    Permanently delete the itinerary. All stops, annotations, and allowlist
    entries are removed via ON DELETE CASCADE at the database level.
    """
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    db.delete(itinerary)
    db.commit()


# ---------------------------------------------------------------------------
# Allowlist endpoints — /itineraries/{id}/allowed-users
# ---------------------------------------------------------------------------
# These three endpoints are defined BEFORE the stop endpoints to ensure
# FastAPI matches '/allowed-users' as a literal path segment, not a stop_id.

@router.post(
    "/{itinerary_id}/allowed-users",
    response_model=AllowedUserResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Add a user to the restricted allowlist",
)
def add_allowed_user(
    itinerary_id: uuid.UUID,
    body: AllowedUserAdd,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> AllowedUserResponse:
    """
    Grant a specific user access to a restricted itinerary.

    Only the owner can call this endpoint.
    The itinerary must have visibility='restricted'; otherwise 400 is returned.
    """
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    if itinerary.visibility != 'restricted':
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Allowlist only applies to restricted itineraries",
        )

    target_user = db.get(User, body.user_id)
    if not target_user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found.",
        )

    existing = db.execute(
        select(ItineraryAllowedUser).where(
            ItineraryAllowedUser.itinerary_id == itinerary_id,
            ItineraryAllowedUser.user_id == body.user_id,
        )
    ).scalar_one_or_none()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="User already has access",
        )

    entry = ItineraryAllowedUser(
        itinerary_id=itinerary_id,
        user_id=body.user_id,
    )
    db.add(entry)
    db.commit()
    db.refresh(entry)

    return AllowedUserResponse(
        user_id=entry.user_id,
        username=target_user.username,
        display_name=target_user.display_name,
        created_at=entry.created_at,
    )


@router.get(
    "/{itinerary_id}/allowed-users",
    response_model=list[AllowedUserResponse],
    summary="List users in the restricted allowlist",
)
def get_allowed_users(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[AllowedUserResponse]:
    """
    Return all users currently in the allowlist for this itinerary.
    Only the owner can call this endpoint.
    """
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    results = db.execute(
        select(ItineraryAllowedUser, User)
        .join(User, ItineraryAllowedUser.user_id == User.id)
        .where(ItineraryAllowedUser.itinerary_id == itinerary_id)
        .order_by(ItineraryAllowedUser.created_at.asc())
    ).all()

    return [
        AllowedUserResponse(
            user_id=allowed.user_id,
            username=user.username,
            display_name=user.display_name,
            created_at=allowed.created_at,
        )
        for allowed, user in results
    ]


@router.delete(
    "/{itinerary_id}/allowed-users/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Remove a user from the restricted allowlist",
)
def remove_allowed_user(
    itinerary_id: uuid.UUID,
    user_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    """
    Revoke a specific user's access to a restricted itinerary.
    Only the owner can call this endpoint.
    """
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    entry = db.execute(
        select(ItineraryAllowedUser).where(
            ItineraryAllowedUser.itinerary_id == itinerary_id,
            ItineraryAllowedUser.user_id == user_id,
        )
    ).scalar_one_or_none()

    if not entry:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found in allowlist",
        )

    db.delete(entry)
    db.commit()


# ---------------------------------------------------------------------------
# PATCH /itineraries/{itinerary_id}/stops/reorder — Reorder stops
# ---------------------------------------------------------------------------
# Defined BEFORE /{itinerary_id}/stops/{stop_id} so FastAPI matches the
# literal segment 'reorder' first, not the parameterized {stop_id}.

@router.patch(
    "/{itinerary_id}/stops/reorder",
    response_model=ItineraryDetail,
    summary="Reorder stops by providing the full ordered list of stop IDs",
)
def reorder_stops(
    itinerary_id: uuid.UUID,
    body: ReorderRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ItineraryDetail:
    """
    Reassign position=1,2,3,... to the stops in the order the client provides.

    The request body must contain ALL stop IDs for this itinerary.
    Returns 400 if any ID is missing or does not belong to this itinerary.
    """
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    # Load all existing stops to validate the provided IDs.
    existing_stops = db.execute(
        select(Stop).where(Stop.itinerary_id == itinerary_id)
    ).scalars().all()

    existing_ids = {s.id for s in existing_stops}
    provided_ids = set(body.stop_ids)

    if existing_ids != provided_ids:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="stop_ids must contain exactly all stop IDs for this itinerary.",
        )

    # Two-phase reassignment avoids unique-constraint collisions when positions
    # are shuffled. Phase 1: park every stop at a temporary position that can't
    # collide with any real 1-based index. Phase 2: write the real positions.
    stop_map = {s.id: s for s in existing_stops}
    offset = len(body.stop_ids) + 1
    for i, stop_id in enumerate(body.stop_ids):
        stop_map[stop_id].position = offset + i
    db.flush()

    for new_position, stop_id in enumerate(body.stop_ids, start=1):
        stop_map[stop_id].position = new_position

    db.commit()

    # Return the full detail with updated ordering.
    return _load_itinerary_detail(itinerary_id, db)  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# POST /itineraries/{itinerary_id}/stops — Add a stop
# ---------------------------------------------------------------------------

@router.post(
    "/{itinerary_id}/stops",
    response_model=StopResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Add a stop to an itinerary",
)
def add_stop(
    itinerary_id: uuid.UUID,
    body: StopCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> StopResponse:
    """
    Add a new stop and recalculate itinerary totals.

    If the requested position is already occupied, all stops at that position
    and above are shifted up by 1 before inserting (two-phase to avoid
    UNIQUE constraint violations during the shift).
    """
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    # Shift any stops that sit at or above the requested position.
    conflicting = db.execute(
        select(Stop).where(
            Stop.itinerary_id == itinerary_id,
            Stop.position >= body.position,
        )
    ).scalars().all()

    if conflicting:
        offset = max(s.position for s in conflicting) + 1
        for s in conflicting:
            s.position += offset
        db.flush()
        for s in conflicting:
            s.position -= offset - 1  # net effect: original + 1
        db.flush()

    stop = Stop(
        itinerary_id=itinerary_id,
        **body.model_dump(),
    )
    db.add(stop)
    db.flush()

    _recalculate_totals(itinerary, db)
    db.commit()
    db.refresh(stop)
    return stop  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# PATCH /itineraries/{itinerary_id}/stops/{stop_id} — Update a stop
# ---------------------------------------------------------------------------

@router.patch(
    "/{itinerary_id}/stops/{stop_id}",
    response_model=StopResponse,
    summary="Update a stop (partial update)",
)
def update_stop(
    itinerary_id: uuid.UUID,
    stop_id: uuid.UUID,
    body: StopUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> StopResponse:
    """Partial update a stop and recalculate itinerary totals."""
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    stop = _get_stop_or_404(stop_id, itinerary_id, db)

    update_data = body.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(stop, field, value)

    _recalculate_totals(itinerary, db)

    db.commit()
    db.refresh(stop)
    return stop  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# DELETE /itineraries/{itinerary_id}/stops/{stop_id} — Delete a stop
# ---------------------------------------------------------------------------

@router.delete(
    "/{itinerary_id}/stops/{stop_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a stop from an itinerary",
)
def delete_stop(
    itinerary_id: uuid.UUID,
    stop_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    """
    Delete a stop. Its annotations are removed via ON DELETE CASCADE.
    Itinerary totals are recalculated after deletion.

    Note: positions of remaining stops are NOT automatically renumbered.
    Use the reorder endpoint to compact positions after deletion.
    """
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    stop = db.execute(
        select(Stop).where(Stop.id == stop_id, Stop.itinerary_id == itinerary_id)
    ).scalar_one_or_none()

    if not stop:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Stop not found.",
        )

    db.delete(stop)
    db.flush()

    _recalculate_totals(itinerary, db)

    db.commit()


# ---------------------------------------------------------------------------
# POST /itineraries/{itinerary_id}/stops/{stop_id}/annotations — Add annotation
# ---------------------------------------------------------------------------

@router.post(
    "/{itinerary_id}/stops/{stop_id}/annotations",
    response_model=AnnotationResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Add an annotation to a stop",
)
def add_annotation(
    itinerary_id: uuid.UUID,
    stop_id: uuid.UUID,
    body: AnnotationCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> AnnotationResponse:
    """
    Add a new annotation to a stop.

    The itinerary_id path parameter is used to verify ownership — the
    current user must own the itinerary that contains this stop.
    """
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    # Verify the stop belongs to this itinerary.
    stop = db.execute(
        select(Stop).where(Stop.id == stop_id, Stop.itinerary_id == itinerary_id)
    ).scalar_one_or_none()

    if not stop:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Stop not found.",
        )

    annotation = Annotation(
        stop_id=stop_id,
        type=body.type,
        content=body.content,
    )
    db.add(annotation)
    db.commit()
    db.refresh(annotation)
    return annotation  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# DELETE /itineraries/{itinerary_id}/stops/{stop_id}/annotations/{annotation_id}
# ---------------------------------------------------------------------------

@router.delete(
    "/{itinerary_id}/stops/{stop_id}/annotations/{annotation_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete an annotation from a stop",
)
def delete_annotation(
    itinerary_id: uuid.UUID,
    stop_id: uuid.UUID,
    annotation_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    """Delete an annotation. Ownership is verified via the itinerary."""
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    annotation = db.execute(
        select(Annotation)
        .join(Stop, Annotation.stop_id == Stop.id)
        .where(
            Annotation.id == annotation_id,
            Annotation.stop_id == stop_id,
            Stop.itinerary_id == itinerary_id,
        )
    ).scalar_one_or_none()

    if not annotation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Annotation not found.",
        )

    db.delete(annotation)
    db.commit()


# ---------------------------------------------------------------------------
# Rating endpoints — POST/DELETE/GET /itineraries/{id}/ratings
# ---------------------------------------------------------------------------

@router.post(
    "/{itinerary_id}/ratings",
    response_model=RatingResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Submit or update the current user's rating for an itinerary",
)
def upsert_rating(
    itinerary_id: uuid.UUID,
    body: RatingSubmit,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> RatingResponse:
    """
    Upsert a 1–5 star rating for this itinerary.
    Any authenticated user who can view the itinerary may rate it.
    Calling again with a different value updates the existing rating.
    """
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    if not can_view_itinerary(itinerary, current_user.id, db):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this itinerary.",
        )

    existing = db.execute(
        select(ItineraryRating).where(
            ItineraryRating.itinerary_id == itinerary_id,
            ItineraryRating.user_id == current_user.id,
        )
    ).scalar_one_or_none()

    if existing:
        existing.stars = body.stars
        existing.safety_stars = body.safety_stars
        existing.experience_stars = body.experience_stars
        existing.accessibility_stars = body.accessibility_stars
        existing.family_friendly_stars = body.family_friendly_stars
        rating = existing
    else:
        rating = ItineraryRating(
            itinerary_id=itinerary_id,
            user_id=current_user.id,
            stars=body.stars,
            safety_stars=body.safety_stars,
            experience_stars=body.experience_stars,
            accessibility_stars=body.accessibility_stars,
            family_friendly_stars=body.family_friendly_stars,
        )
        db.add(rating)

    db.flush()
    recalculate_rating(itinerary, db)
    db.commit()
    db.refresh(rating)
    return rating  # type: ignore[return-value]


@router.delete(
    "/{itinerary_id}/ratings/me",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Remove the current user's rating from an itinerary",
)
def delete_my_rating(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    """Delete the caller's rating. 404 if no rating exists."""
    itinerary = _get_itinerary_or_404(itinerary_id, db)

    rating = db.execute(
        select(ItineraryRating).where(
            ItineraryRating.itinerary_id == itinerary_id,
            ItineraryRating.user_id == current_user.id,
        )
    ).scalar_one_or_none()

    if not rating:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="You have not rated this itinerary.",
        )

    db.delete(rating)
    db.flush()
    recalculate_rating(itinerary, db)
    db.commit()


@router.get(
    "/{itinerary_id}/ratings/me",
    response_model=RatingResponse,
    summary="Get the current user's rating for an itinerary",
)
def get_my_rating(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> RatingResponse:
    """Return the caller's rating, or 404 if they have not rated yet."""
    _get_itinerary_or_404(itinerary_id, db)

    rating = db.execute(
        select(ItineraryRating).where(
            ItineraryRating.itinerary_id == itinerary_id,
            ItineraryRating.user_id == current_user.id,
        )
    ).scalar_one_or_none()

    if not rating:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="You have not rated this itinerary.",
        )

    return rating  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# GET /itineraries/{itinerary_id}/ratings — Full ratings page
# ---------------------------------------------------------------------------

@router.get(
    "/{itinerary_id}/ratings",
    response_model=RatingsPageResponse,
    summary="Get the full ratings page for an itinerary",
)
def get_ratings_page(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> RatingsPageResponse:
    """
    Return the ratings page: aggregate stats, star distribution, and the
    full list of individual ratings with rater identity.

    Access rule: same as GET /itineraries/{id} — delegates to
    can_view_itinerary(), returns 403 if the caller has no access.

    LEFT JOIN is mandatory here: INNER JOIN would silently drop ratings
    whose user_id is NULL (deleted users). LEFT JOIN preserves them so
    the anonymized community scores remain visible.
    """
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    if not can_view_itinerary(itinerary, current_user.id, db):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this itinerary.",
        )

    # LEFT JOIN so deleted-user rows (user_id = NULL) are preserved.
    rows = db.execute(
        select(
            ItineraryRating.stars,
            ItineraryRating.safety_stars,
            ItineraryRating.experience_stars,
            ItineraryRating.accessibility_stars,
            ItineraryRating.family_friendly_stars,
            ItineraryRating.updated_at,
            ItineraryRating.user_id,
            User.username,
            User.display_name,
            User.avatar_url,
        )
        .outerjoin(User, ItineraryRating.user_id == User.id)
        .where(ItineraryRating.itinerary_id == itinerary_id)
        .order_by(ItineraryRating.updated_at.desc())
    ).all()

    # Compute overall star distribution by iterating the result set.
    dist: dict[int, int] = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
    for row in rows:
        dist[row.stars] += 1

    distribution = RatingDistribution(
        five=dist[5],
        four=dist[4],
        three=dist[3],
        two=dist[2],
        one=dist[1],
    )

    ratings = [
        RatingWithUser(
            score=row.stars,
            safety_score=row.safety_stars,
            experience_score=row.experience_stars,
            accessibility_score=row.accessibility_stars,
            family_friendly_score=row.family_friendly_stars,
            updated_at=row.updated_at,
            user=RaterInfo(
                user_id=row.user_id,
                username=row.username,
                display_name=row.display_name,
                avatar_url=row.avatar_url,
            ),
        )
        for row in rows
    ]

    return RatingsPageResponse(
        rating_avg=itinerary.rating_avg,
        rating_count=itinerary.rating_count,
        distribution=distribution,
        ratings=ratings,
    )


# ---------------------------------------------------------------------------
# Transit segment endpoints — /itineraries/{id}/segments
# ---------------------------------------------------------------------------

@router.post(
    "/{itinerary_id}/segments",
    response_model=TransitSegmentResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a transit segment between two stops",
)
def create_segment(
    itinerary_id: uuid.UUID,
    body: TransitSegmentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> TransitSegmentResponse:
    """
    Create a TransitSegment with one or more TransportLegs between two stops.

    Both from_stop_id and to_stop_id must belong to this itinerary.
    Only one segment per stop pair is allowed (UNIQUE constraint).
    Leg positions must be contiguous starting at 1 (validated by schema).
    """
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    # Verify both stops belong to this itinerary.
    for stop_id, label in ((body.from_stop_id, "from_stop_id"), (body.to_stop_id, "to_stop_id")):
        stop = db.execute(
            select(Stop).where(Stop.id == stop_id, Stop.itinerary_id == itinerary_id)
        ).scalar_one_or_none()
        if not stop:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"{label} does not belong to this itinerary.",
            )

    segment = TransitSegment(
        itinerary_id=itinerary_id,
        from_stop_id=body.from_stop_id,
        to_stop_id=body.to_stop_id,
    )
    db.add(segment)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A segment between these two stops already exists.",
        )

    for leg_data in body.legs:
        leg = TransportLeg(segment_id=segment.id, **leg_data.model_dump())
        db.add(leg)

    db.flush()
    _recalculate_segment_totals(segment, db)
    _recalculate_totals(itinerary, db)
    db.commit()
    db.refresh(segment)
    return segment  # type: ignore[return-value]


@router.get(
    "/{itinerary_id}/segments",
    response_model=list[TransitSegmentResponse],
    summary="List all transit segments for an itinerary",
)
def list_segments(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[TransitSegmentResponse]:
    """Return all transit segments for the itinerary, ordered by from_stop.position."""
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    if not can_view_itinerary(itinerary, current_user.id, db):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this itinerary.",
        )

    segments = db.execute(
        select(TransitSegment)
        .options(
            selectinload(TransitSegment.legs),
            selectinload(TransitSegment.from_stop),
        )
        .where(TransitSegment.itinerary_id == itinerary_id)
    ).scalars().all()

    segments.sort(key=lambda seg: seg.from_stop.position if seg.from_stop else 0)
    return segments  # type: ignore[return-value]


@router.patch(
    "/{itinerary_id}/segments/{segment_id}",
    response_model=TransitSegmentResponse,
    summary="Update a transit segment's stop references",
)
def update_segment(
    itinerary_id: uuid.UUID,
    segment_id: uuid.UUID,
    body: TransitSegmentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> TransitSegmentResponse:
    """
    Replace from_stop_id and to_stop_id (and the full leg list) of a segment.
    Both stop IDs must belong to this itinerary.
    """
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    segment = _get_segment_or_404(segment_id, itinerary_id, db)

    for stop_id, label in ((body.from_stop_id, "from_stop_id"), (body.to_stop_id, "to_stop_id")):
        stop = db.execute(
            select(Stop).where(Stop.id == stop_id, Stop.itinerary_id == itinerary_id)
        ).scalar_one_or_none()
        if not stop:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"{label} does not belong to this itinerary.",
            )

    segment.from_stop_id = body.from_stop_id
    segment.to_stop_id = body.to_stop_id

    # Replace all legs with the new set.
    for leg in list(segment.legs):
        db.delete(leg)
    db.flush()

    for leg_data in body.legs:
        leg = TransportLeg(segment_id=segment.id, **leg_data.model_dump())
        db.add(leg)

    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A segment between these two stops already exists.",
        )

    _recalculate_segment_totals(segment, db)
    _recalculate_totals(itinerary, db)
    db.commit()
    db.refresh(segment)
    return segment  # type: ignore[return-value]


@router.delete(
    "/{itinerary_id}/segments/{segment_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a transit segment and all its legs",
)
def delete_segment(
    itinerary_id: uuid.UUID,
    segment_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    """Delete a segment. Its legs are removed via ON DELETE CASCADE."""
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    segment = _get_segment_or_404(segment_id, itinerary_id, db)

    db.delete(segment)
    db.flush()
    _recalculate_totals(itinerary, db)
    db.commit()


# ---------------------------------------------------------------------------
# Transport leg endpoints — /itineraries/{id}/segments/{segment_id}/legs
#
# NOTE: The Flutter mobile app does NOT call these endpoints individually.
# It uses PATCH /segments/{id} (full leg replacement) for all leg changes,
# which is simpler for a mobile client. These endpoints exist for future
# API consumers (web client, third-party integrations, etc.) that may need
# fine-grained per-leg control without replacing the entire segment.
# ---------------------------------------------------------------------------

@router.post(
    "/{itinerary_id}/segments/{segment_id}/legs",
    response_model=TransportLegResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Add a transport leg to a segment",
)
def add_leg(
    itinerary_id: uuid.UUID,
    segment_id: uuid.UUID,
    body: TransportLegCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> TransportLegResponse:
    """
    Append a new leg to a transit segment.
    Position must not collide with existing legs (409 if it does).
    """
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    segment = _get_segment_or_404(segment_id, itinerary_id, db)

    leg = TransportLeg(segment_id=segment.id, **body.model_dump())
    db.add(leg)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"A leg at position {body.position} already exists in this segment.",
        )

    _recalculate_segment_totals(segment, db)
    _recalculate_totals(itinerary, db)
    db.commit()
    db.refresh(leg)
    return leg  # type: ignore[return-value]


@router.patch(
    "/{itinerary_id}/segments/{segment_id}/legs/{leg_id}",
    response_model=TransportLegResponse,
    summary="Update a transport leg (partial update)",
)
def update_leg(
    itinerary_id: uuid.UUID,
    segment_id: uuid.UUID,
    leg_id: uuid.UUID,
    body: TransportLegUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> TransportLegResponse:
    """Partial update a leg and recalculate segment and itinerary totals."""
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    segment = _get_segment_or_404(segment_id, itinerary_id, db)
    leg = _get_leg_or_404(leg_id, segment_id, db)

    update_data = body.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(leg, field, value)

    _recalculate_segment_totals(segment, db)
    _recalculate_totals(itinerary, db)
    db.commit()
    db.refresh(leg)
    return leg  # type: ignore[return-value]


@router.delete(
    "/{itinerary_id}/segments/{segment_id}/legs/{leg_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a transport leg from a segment",
)
def delete_leg(
    itinerary_id: uuid.UUID,
    segment_id: uuid.UUID,
    leg_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    """Delete a leg and recalculate segment and itinerary totals."""
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    segment = _get_segment_or_404(segment_id, itinerary_id, db)
    leg = _get_leg_or_404(leg_id, segment_id, db)

    db.delete(leg)
    db.flush()
    _recalculate_segment_totals(segment, db)
    _recalculate_totals(itinerary, db)
    db.commit()


# ---------------------------------------------------------------------------
# GET /users/{user_id}/itineraries  (mounted on user_itineraries_router)
# ---------------------------------------------------------------------------

@user_itineraries_router.get(
    "/{user_id}/itineraries",
    response_model=list[ItinerarySummary],
    summary="List a user's itineraries visible to the current user",
)
def get_user_itineraries(
    user_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[ItinerarySummary]:
    """
    Return the itineraries owned by user_id that the current user is allowed
    to see, filtered by can_view_itinerary() — no visibility logic is
    duplicated here.

    When user_id == current_user.id the owner always passes can_view, so
    all of their own itineraries are returned.
    """
    target_user = db.get(User, user_id)
    if not target_user or not target_user.is_active:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found.",
        )

    itineraries = db.execute(
        select(Itinerary)
        .where(Itinerary.user_id == user_id)
        .order_by(Itinerary.created_at.desc())
    ).scalars().all()

    return [
        i for i in itineraries
        if can_view_itinerary(i, current_user.id, db)
    ]  # type: ignore[return-value]
