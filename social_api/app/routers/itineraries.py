"""
routers/itineraries.py — Itinerary, stop, and annotation endpoints.

All routes require Bearer token authentication (get_current_user dependency).
The router prefix '/itineraries' is added in main.py.

Ownership rule:
  Every mutating endpoint (PATCH, DELETE) verifies that the authenticated
  user owns the itinerary. Unauthorized access returns 403.

Visibility rule:
  GET /itineraries/{id} returns 403 for non-owners if is_public=False.

Total recalculation:
  After every stop add/update/delete, _recalculate_totals() recomputes
  itinerary.total_duration_min and itinerary.total_cost so summary views
  always reflect the current state.
"""

import uuid
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.dependencies import get_current_user
from app.models.annotation import Annotation
from app.models.itinerary import Itinerary
from app.models.stop import Stop
from app.models.user import User
from app.schemas.itinerary import (
    AnnotationCreate,
    AnnotationResponse,
    ItineraryCreate,
    ItineraryDetail,
    ItinerarySummary,
    ItineraryUpdate,
    ReorderRequest,
    StopCreate,
    StopResponse,
    StopUpdate,
)

router = APIRouter(tags=["Itineraries"])


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


def _recalculate_totals(itinerary: Itinerary, db: Session) -> None:
    """
    Recompute total_duration_min and total_cost from the current set of stops.

    Called after every stop add/update/delete so the itinerary summary always
    reflects accurate aggregates without a separate aggregation query on read.

    Cost rule: only include stops where is_free=False.
    Duration rule: treat NULL duration_min as 0.
    """
    stops = db.execute(
        select(Stop).where(Stop.itinerary_id == itinerary.id)
    ).scalars().all()

    itinerary.total_duration_min = sum(s.duration_min or 0 for s in stops)
    itinerary.total_cost = sum(
        (s.cost if s.cost is not None else Decimal("0.00"))
        for s in stops
        if not s.is_free
    )


def _load_itinerary_detail(itinerary_id: uuid.UUID, db: Session) -> Itinerary:
    """
    Fetch an itinerary with all stops and annotations eagerly loaded.
    Uses selectinload to avoid N+1 queries:
      1 query for the itinerary
      1 query for all its stops
      1 query for all annotations across those stops
    """
    itinerary = db.execute(
        select(Itinerary)
        .options(
            selectinload(Itinerary.stops).selectinload(Stop.annotations)
        )
        .where(Itinerary.id == itinerary_id)
    ).scalar_one_or_none()

    if not itinerary:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Itinerary not found.",
        )
    return itinerary


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
    are added.
    """
    itinerary = Itinerary(
        user_id=current_user.id,
        title=body.title,
        description=body.description,
        currency=body.currency,
        safety_rating=body.safety_rating,
        is_public=body.is_public,
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

    Visibility rule:
      - If is_public=False, only the owner can view. Others receive 403.
      - If is_public=True, any authenticated user can view.
    """
    itinerary = _load_itinerary_detail(itinerary_id, db)

    if not itinerary.is_public and itinerary.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This itinerary is private.",
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
    """Partial update — only the fields present in the body are changed."""
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
    Permanently delete the itinerary. All stops and annotations are removed
    via ON DELETE CASCADE at the database level.
    """
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    db.delete(itinerary)
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

    # Build a lookup map and reassign positions.
    stop_map = {s.id: s for s in existing_stops}
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

    The position must be provided by the client. If you want to append to
    the end, use len(existing_stops) + 1.
    """
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    stop = Stop(
        itinerary_id=itinerary_id,
        **body.model_dump(),
    )
    db.add(stop)
    db.flush()  # Flush to get the stop's ID before recalculating

    # Update denormalized totals on the itinerary row.
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
