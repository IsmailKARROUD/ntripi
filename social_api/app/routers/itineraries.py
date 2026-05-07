"""
routers/itineraries.py — Itinerary, track, stop, annotation, allowlist,
segment, and leg endpoints.

All routes require Bearer token authentication (get_current_user dependency).
The router prefix '/itineraries' is added in main.py.

Ownership / visibility rules:
  Every mutating endpoint verifies that the authenticated user owns the
  itinerary. GET delegates to can_view_itinerary() — the single source of truth.

Optimistic concurrency (ETag / If-Match):
  Every mutation on stops, tracks, or annotations requires an If-Match header
  matching the itinerary's current updated_at ETag. Missing header → 428;
  mismatch → 412. On success the response carries the new ETag.

Total recalculation:
  After every stop/segment/leg mutation, _recalculate_totals() recomputes
  itinerary.total_duration_min and itinerary.total_cost from both stops
  and transit segments.

Track lifecycle:
  A track only exists when it has at least one stop. Creating a stop with
  track_id=null creates a new track + stop atomically. Deleting the last stop
  in a track also deletes the track (explicit app-level cascade).
"""

import uuid
from decimal import Decimal
from datetime import timezone

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile, status
from fastapi.responses import Response
from sqlalchemy import select, func as sqlfunc
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.dependencies import get_current_user, require_etag
from app.models.annotation import Annotation
from app.models.itinerary import Itinerary
from app.models.itinerary_annotation import ItineraryAnnotation
from app.models.itinerary_allowed_user import ItineraryAllowedUser
from app.models.stop import Stop
from app.models.track import Track
from app.models.transit_segment import TransitSegment
from app.models.transport_leg import TransportLeg
from app.models.user import User
from app.models.itinerary_rating import ItineraryRating
from app.schemas.itinerary import (
    AllowedUserAdd,
    AllowedUserResponse,
    AnnotationCreate,
    AnnotationResponse,
    AnnotationUpdate,
    ItineraryAnnotationCreate,
    ItineraryAnnotationResponse,
    ItineraryAnnotationUpdate,
    ItineraryCreate,
    ItineraryDetail,
    ItineraryImageResponse,
    ItinerarySummary,
    ItineraryUpdate,
    RaterInfo,
    RatingDistribution,
    RatingResponse,
    RatingSubmit,
    RatingWithUser,
    RatingsPageResponse,
    StopCreate,
    StopResponse,
    StopUpdate,
    TrackResponse,
    TransitSegmentCreate,
    TransitSegmentResponse,
    TransportLegCreate,
    TransportLegResponse,
    TransportLegUpdate,
)
from app.services.image_service import ImageProcessingError, process_cover_image
from app.services.itinerary_access import can_view_itinerary, recalculate_rating
from app.services.ordering import key_between
from app.storage.factory import storage

router = APIRouter(tags=["Itineraries"])
user_itineraries_router = APIRouter(tags=["Itineraries"])


# ---------------------------------------------------------------------------
# ETag helpers
# ---------------------------------------------------------------------------

def _etag_value(itinerary: Itinerary) -> str:
    ts = itinerary.updated_at
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    return f'"{ts.isoformat()}"'


def _bump_and_etag(itinerary: Itinerary, db: Session) -> str:
    """Touch updated_at and return the new ETag string."""
    db.execute(
        select(Itinerary)
        .where(Itinerary.id == itinerary.id)
        .with_for_update()
    )
    db.execute(
        # Use raw SQL so SQLAlchemy's onupdate triggers correctly.
        select(sqlfunc.now())
    )
    itinerary.updated_at = sqlfunc.now()  # type: ignore[assignment]
    db.flush()
    db.refresh(itinerary)
    return _etag_value(itinerary)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _get_itinerary_or_404(itinerary_id: uuid.UUID, db: Session) -> Itinerary:
    itinerary = db.get(Itinerary, itinerary_id)
    if not itinerary:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Itinerary not found.")
    return itinerary


def _require_owner(itinerary: Itinerary, current_user: User) -> None:
    if itinerary.user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="You do not have permission to modify this itinerary.")


def _recalculate_segment_totals(segment: TransitSegment, db: Session) -> None:
    legs = db.execute(
        select(TransportLeg).where(TransportLeg.segment_id == segment.id)
    ).scalars().all()
    segment.total_duration_min = sum(lg.duration_min or 0 for lg in legs)
    segment.total_cost = sum(
        (lg.cost if lg.cost is not None else Decimal("0.00"))
        for lg in legs if not lg.is_free
    )


def _recalculate_totals(itinerary: Itinerary, db: Session) -> None:
    stops = db.execute(
        select(Stop).where(Stop.itinerary_id == itinerary.id)
    ).scalars().all()
    segments = db.execute(
        select(TransitSegment).where(TransitSegment.itinerary_id == itinerary.id)
    ).scalars().all()

    stop_duration = sum(s.duration_min or 0 for s in stops)
    stop_cost = sum(
        (s.cost if s.cost is not None else Decimal("0.00"))
        for s in stops if not s.is_free
    )
    seg_duration = sum(seg.total_duration_min for seg in segments)
    seg_cost = sum(seg.total_cost for seg in segments)

    itinerary.total_duration_min = stop_duration + seg_duration
    itinerary.total_cost = stop_cost + seg_cost


def _load_itinerary_detail(itinerary_id: uuid.UUID, db: Session) -> Itinerary:
    """Load itinerary with tracks → stops → annotations, plus segments+legs."""
    itinerary = db.execute(
        select(Itinerary)
        .options(
            selectinload(Itinerary.tracks).selectinload(Track.stops).selectinload(Stop.annotations),
            selectinload(Itinerary.segments).selectinload(TransitSegment.legs),
            selectinload(Itinerary.segments).selectinload(TransitSegment.from_stop),
            selectinload(Itinerary.annotations),
        )
        .where(Itinerary.id == itinerary_id)
    ).scalar_one_or_none()

    if not itinerary:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Itinerary not found.")

    # Sort tracks by rank, stops within each track by rank.
    itinerary.tracks.sort(key=lambda t: t.rank)
    for track in itinerary.tracks:
        track.stops.sort(key=lambda s: s.rank)

    return itinerary


def _get_stop_or_404(stop_id: uuid.UUID, itinerary_id: uuid.UUID, db: Session) -> Stop:
    stop = db.execute(
        select(Stop)
        .options(selectinload(Stop.annotations))
        .where(Stop.id == stop_id, Stop.itinerary_id == itinerary_id)
    ).scalar_one_or_none()
    if not stop:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Stop not found.")
    return stop


def _get_track_or_404(track_id: uuid.UUID, itinerary_id: uuid.UUID, db: Session) -> Track:
    track = db.execute(
        select(Track).where(Track.id == track_id, Track.itinerary_id == itinerary_id)
    ).scalar_one_or_none()
    if not track:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Track not found or does not belong to this itinerary.")
    return track


def _delete_track_if_empty(track_id: uuid.UUID, db: Session) -> None:
    """Delete track if it has no remaining stops."""
    remaining = db.execute(
        select(Stop).where(Stop.track_id == track_id).limit(1)
    ).scalar_one_or_none()
    if remaining is None:
        track = db.get(Track, track_id)
        if track:
            db.delete(track)


def _resolve_stop_rank(
    track: Track,
    after_stop_id: uuid.UUID | None,
    before_stop_id: uuid.UUID | None,
    db: Session,
) -> str:
    """Compute a rank for a new stop within track using the provided anchors.

    When both anchors are None, places the stop after all existing stops
    in the track (tail insert).
    """
    after_rank: str | None = None
    before_rank: str | None = None

    if after_stop_id:
        after_stop = db.execute(
            select(Stop).where(Stop.id == after_stop_id, Stop.track_id == track.id)
        ).scalar_one_or_none()
        if not after_stop:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="after_stop_id does not belong to the target track.",
            )
        after_rank = after_stop.rank

    if before_stop_id:
        before_stop = db.execute(
            select(Stop).where(Stop.id == before_stop_id, Stop.track_id == track.id)
        ).scalar_one_or_none()
        if not before_stop:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="before_stop_id does not belong to the target track.",
            )
        before_rank = before_stop.rank

    if after_rank and before_rank and after_rank >= before_rank:
        raise HTTPException(
            status_code=status.HTTP_412_PRECONDITION_FAILED,
            detail="itinerary modified, please reload",
        )

    # No anchors → tail insert: place after the last existing stop in this track.
    if after_rank is None and before_rank is None:
        last = db.execute(
            select(Stop).where(Stop.track_id == track.id).order_by(Stop.rank.desc()).limit(1)
        ).scalar_one_or_none()
        if last is not None:
            after_rank = last.rank

    return key_between(after_rank, before_rank)


def _resolve_track_rank(
    itinerary_id: uuid.UUID,
    after_track_id: uuid.UUID | None,
    before_track_id: uuid.UUID | None,
    db: Session,
) -> str:
    """Compute a rank for a new track using the provided anchor tracks."""
    after_rank: str | None = None
    before_rank: str | None = None

    if after_track_id:
        after_track = db.execute(
            select(Track).where(Track.id == after_track_id,
                                Track.itinerary_id == itinerary_id)
        ).scalar_one_or_none()
        if not after_track:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="after_track_id does not belong to this itinerary.",
            )
        after_rank = after_track.rank

    if before_track_id:
        before_track = db.execute(
            select(Track).where(Track.id == before_track_id,
                                Track.itinerary_id == itinerary_id)
        ).scalar_one_or_none()
        if not before_track:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="before_track_id does not belong to this itinerary.",
            )
        before_rank = before_track.rank

    if after_rank and before_rank and after_rank >= before_rank:
        raise HTTPException(
            status_code=status.HTTP_412_PRECONDITION_FAILED,
            detail="itinerary modified, please reload",
        )

    return key_between(after_rank, before_rank)


def _get_segment_or_404(segment_id, itinerary_id, db):
    segment = db.execute(
        select(TransitSegment)
        .options(selectinload(TransitSegment.legs))
        .where(TransitSegment.id == segment_id,
               TransitSegment.itinerary_id == itinerary_id)
    ).scalar_one_or_none()
    if not segment:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Transit segment not found.")
    return segment


def _get_leg_or_404(leg_id, segment_id, db):
    leg = db.execute(
        select(TransportLeg).where(TransportLeg.id == leg_id,
                                   TransportLeg.segment_id == segment_id)
    ).scalar_one_or_none()
    if not leg:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Transport leg not found.")
    return leg


# ---------------------------------------------------------------------------
# POST /itineraries — Create an itinerary
# ---------------------------------------------------------------------------

@router.post("/", response_model=ItinerarySummary, status_code=status.HTTP_201_CREATED,
             summary="Create a new itinerary")
def create_itinerary(
    body: ItineraryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ItinerarySummary:
    itinerary = Itinerary(
        user_id=current_user.id,
        title=body.title,
        description=body.description,
        currency=body.currency,
        visibility=body.visibility,
        total_duration_min=0,
        total_cost=Decimal("0.00"),
    )
    db.add(itinerary)
    db.commit()
    db.refresh(itinerary)
    return itinerary  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# GET /itineraries/me
# ---------------------------------------------------------------------------

@router.get("/me", response_model=list[ItinerarySummary], summary="List my itineraries")
def list_my_itineraries(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[ItinerarySummary]:
    itineraries = db.execute(
        select(Itinerary)
        .where(Itinerary.user_id == current_user.id)
        .order_by(Itinerary.created_at.desc())
    ).scalars().all()
    return itineraries  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# GET /itineraries/{itinerary_id} — Get itinerary detail
# ---------------------------------------------------------------------------

@router.get("/{itinerary_id}", response_model=ItineraryDetail,
            summary="Get itinerary detail with tracks and stops")
def get_itinerary(
    itinerary_id: uuid.UUID,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Response:
    itinerary = _load_itinerary_detail(itinerary_id, db)

    if not can_view_itinerary(itinerary, current_user.id, db):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="You don't have access to this itinerary")

    from fastapi.responses import JSONResponse
    import json
    from fastapi.encoders import jsonable_encoder

    data = jsonable_encoder(ItineraryDetail.model_validate(itinerary))
    response = JSONResponse(content=data)
    response.headers["ETag"] = _etag_value(itinerary)
    return response


# ---------------------------------------------------------------------------
# PATCH /itineraries/{itinerary_id}
# ---------------------------------------------------------------------------

@router.patch("/{itinerary_id}", response_model=ItinerarySummary,
              summary="Update itinerary title, description, or settings")
def update_itinerary(
    itinerary_id: uuid.UUID,
    body: ItineraryUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ItinerarySummary:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    update_data = body.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(itinerary, field, value)

    db.commit()
    db.refresh(itinerary)
    return itinerary  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# DELETE /itineraries/{itinerary_id}
# ---------------------------------------------------------------------------

@router.delete("/{itinerary_id}", status_code=status.HTTP_204_NO_CONTENT,
               summary="Delete an itinerary and all its tracks/stops")
def delete_itinerary(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)
    db.delete(itinerary)
    db.commit()


# ---------------------------------------------------------------------------
# Allowlist endpoints — /itineraries/{id}/allowed-users
# (Defined before stop endpoints so FastAPI matches literal path first.)
# ---------------------------------------------------------------------------

@router.post("/{itinerary_id}/allowed-users", response_model=AllowedUserResponse,
             status_code=status.HTTP_201_CREATED, summary="Add a user to the restricted allowlist")
def add_allowed_user(
    itinerary_id: uuid.UUID,
    body: AllowedUserAdd,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> AllowedUserResponse:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    if itinerary.visibility != 'restricted':
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="Allowlist only applies to restricted itineraries")

    target_user = db.get(User, body.user_id)
    if not target_user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")

    existing = db.execute(
        select(ItineraryAllowedUser).where(
            ItineraryAllowedUser.itinerary_id == itinerary_id,
            ItineraryAllowedUser.user_id == body.user_id,
        )
    ).scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                            detail="User already has access")

    entry = ItineraryAllowedUser(itinerary_id=itinerary_id, user_id=body.user_id)
    db.add(entry)
    db.commit()
    db.refresh(entry)

    return AllowedUserResponse(
        user_id=entry.user_id,
        username=target_user.username,
        display_name=target_user.display_name,
        created_at=entry.created_at,
    )


@router.get("/{itinerary_id}/allowed-users", response_model=list[AllowedUserResponse],
            summary="List users in the restricted allowlist")
def get_allowed_users(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[AllowedUserResponse]:
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


@router.delete("/{itinerary_id}/allowed-users/{user_id}",
               status_code=status.HTTP_204_NO_CONTENT,
               summary="Remove a user from the restricted allowlist")
def remove_allowed_user(
    itinerary_id: uuid.UUID,
    user_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    entry = db.execute(
        select(ItineraryAllowedUser).where(
            ItineraryAllowedUser.itinerary_id == itinerary_id,
            ItineraryAllowedUser.user_id == user_id,
        )
    ).scalar_one_or_none()

    if not entry:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="User not found in allowlist")

    db.delete(entry)
    db.commit()


# ---------------------------------------------------------------------------
# POST /itineraries/{itinerary_id}/stops — Add a stop
# ---------------------------------------------------------------------------

@router.post("/{itinerary_id}/stops", response_model=StopResponse,
             status_code=status.HTTP_201_CREATED, summary="Add a stop to an itinerary")
def add_stop(
    itinerary_id: uuid.UUID,
    body: StopCreate,
    request: Request,
    db: Session = Depends(get_db),
    itinerary: Itinerary = Depends(require_etag),
) -> Response:
    """
    Add a new stop. If track_id is provided, add within that track; otherwise
    create a new track using after_track_id / before_track_id anchors.
    Requires If-Match header.
    """
    for attempt in range(3):
        try:
            if body.track_id is not None:
                # Add to existing track.
                track = _get_track_or_404(body.track_id, itinerary_id, db)
                stop_rank = _resolve_stop_rank(
                    track, body.after_stop_id, body.before_stop_id, db
                )
            else:
                # Create a new track, then add the stop.
                track_rank = _resolve_track_rank(
                    itinerary_id, body.after_track_id, body.before_track_id, db
                )
                track = Track(itinerary_id=itinerary_id, rank=track_rank)
                db.add(track)
                db.flush()
                stop_rank = key_between(None, None)

            stop_fields = body.model_dump(exclude={
                'track_id', 'after_stop_id', 'before_stop_id',
                'after_track_id', 'before_track_id',
            })
            stop = Stop(
                itinerary_id=itinerary_id,
                track_id=track.id,
                rank=stop_rank,
                **stop_fields,
            )
            db.add(stop)
            db.flush()
            break

        except IntegrityError:
            db.rollback()
            if attempt == 2:
                raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                                    detail="Rank collision — please retry.")
            # Re-fetch anchors and retry.

    _recalculate_totals(itinerary, db)
    db.commit()
    db.refresh(stop)
    db.refresh(itinerary)

    from fastapi.encoders import jsonable_encoder
    from fastapi.responses import JSONResponse
    data = jsonable_encoder(StopResponse.model_validate(stop))
    resp = JSONResponse(content=data, status_code=status.HTTP_201_CREATED)
    resp.headers["ETag"] = _etag_value(itinerary)
    return resp


# ---------------------------------------------------------------------------
# PATCH /itineraries/{itinerary_id}/stops/{stop_id} — Update / move a stop
# ---------------------------------------------------------------------------

@router.patch("/{itinerary_id}/stops/{stop_id}", response_model=StopResponse,
              summary="Update a stop (partial update, optional move across tracks)")
def update_stop(
    itinerary_id: uuid.UUID,
    stop_id: uuid.UUID,
    body: StopUpdate,
    request: Request,
    db: Session = Depends(get_db),
    itinerary: Itinerary = Depends(require_etag),
) -> Response:
    stop = _get_stop_or_404(stop_id, itinerary_id, db)
    old_track_id = stop.track_id

    # Apply scalar field updates.
    scalar_fields = body.model_dump(exclude_unset=True, exclude={
        'track_id', 'after_stop_id', 'before_stop_id'
    })
    for field, value in scalar_fields.items():
        setattr(stop, field, value)

    # Handle move / reorder.
    target_track_id = body.track_id
    if target_track_id is not None or body.after_stop_id is not None or body.before_stop_id is not None:
        effective_track_id = target_track_id or old_track_id
        track = _get_track_or_404(effective_track_id, itinerary_id, db)
        new_rank = _resolve_stop_rank(track, body.after_stop_id, body.before_stop_id, db)
        stop.track_id = track.id
        stop.rank = new_rank

    _recalculate_totals(itinerary, db)
    db.commit()

    # If source track is now empty, delete it.
    if target_track_id is not None and target_track_id != old_track_id:
        _delete_track_if_empty(old_track_id, db)
        db.commit()

    db.refresh(stop)
    db.refresh(itinerary)

    from fastapi.encoders import jsonable_encoder
    from fastapi.responses import JSONResponse
    data = jsonable_encoder(StopResponse.model_validate(stop))
    resp = JSONResponse(content=data)
    resp.headers["ETag"] = _etag_value(itinerary)
    return resp


# ---------------------------------------------------------------------------
# DELETE /itineraries/{itinerary_id}/stops/{stop_id} — Delete a stop
# ---------------------------------------------------------------------------

@router.delete("/{itinerary_id}/stops/{stop_id}", status_code=status.HTTP_204_NO_CONTENT,
               summary="Delete a stop from an itinerary")
def delete_stop(
    itinerary_id: uuid.UUID,
    stop_id: uuid.UUID,
    request: Request,
    db: Session = Depends(get_db),
    itinerary: Itinerary = Depends(require_etag),
) -> Response:
    stop = db.execute(
        select(Stop).where(Stop.id == stop_id, Stop.itinerary_id == itinerary_id)
    ).scalar_one_or_none()

    if not stop:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Stop not found.")

    track_id = stop.track_id
    db.delete(stop)
    db.flush()

    _delete_track_if_empty(track_id, db)
    _recalculate_totals(itinerary, db)
    db.commit()
    db.refresh(itinerary)

    from fastapi.responses import Response as FastAPIResponse
    resp = FastAPIResponse(status_code=status.HTTP_204_NO_CONTENT)
    resp.headers["ETag"] = _etag_value(itinerary)
    return resp


# ---------------------------------------------------------------------------
# Itinerary-level annotation endpoints
# ---------------------------------------------------------------------------

@router.post("/{itinerary_id}/annotations", response_model=ItineraryAnnotationResponse,
             status_code=status.HTTP_201_CREATED, summary="Add an annotation to an itinerary")
def add_itinerary_annotation(
    itinerary_id: uuid.UUID,
    body: ItineraryAnnotationCreate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    itinerary: Itinerary = Depends(require_etag),
) -> ItineraryAnnotationResponse:
    annotation = ItineraryAnnotation(
        itinerary_id=itinerary_id,
        type=body.type,
        content=body.content,
    )
    db.add(annotation)
    db.commit()
    db.refresh(annotation)
    return annotation  # type: ignore[return-value]


@router.patch("/{itinerary_id}/annotations/{annotation_id}",
              response_model=ItineraryAnnotationResponse,
              summary="Update an itinerary annotation")
def update_itinerary_annotation(
    itinerary_id: uuid.UUID,
    annotation_id: uuid.UUID,
    body: ItineraryAnnotationUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    itinerary: Itinerary = Depends(require_etag),
) -> ItineraryAnnotationResponse:
    annotation = db.execute(
        select(ItineraryAnnotation).where(
            ItineraryAnnotation.id == annotation_id,
            ItineraryAnnotation.itinerary_id == itinerary_id,
        )
    ).scalar_one_or_none()

    if not annotation:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Annotation not found.")

    if body.type is not None:
        annotation.type = body.type
    if body.content is not None:
        annotation.content = body.content

    db.commit()
    db.refresh(annotation)
    return annotation  # type: ignore[return-value]


@router.delete("/{itinerary_id}/annotations/{annotation_id}",
               status_code=status.HTTP_204_NO_CONTENT,
               summary="Delete an itinerary annotation")
def delete_itinerary_annotation(
    itinerary_id: uuid.UUID,
    annotation_id: uuid.UUID,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    itinerary: Itinerary = Depends(require_etag),
) -> None:
    annotation = db.execute(
        select(ItineraryAnnotation).where(
            ItineraryAnnotation.id == annotation_id,
            ItineraryAnnotation.itinerary_id == itinerary_id,
        )
    ).scalar_one_or_none()

    if not annotation:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Annotation not found.")

    db.delete(annotation)
    db.commit()


# ---------------------------------------------------------------------------
# Stop-level annotation endpoints
# ---------------------------------------------------------------------------

@router.post("/{itinerary_id}/stops/{stop_id}/annotations",
             response_model=AnnotationResponse, status_code=status.HTTP_201_CREATED,
             summary="Add an annotation to a stop")
def add_annotation(
    itinerary_id: uuid.UUID,
    stop_id: uuid.UUID,
    body: AnnotationCreate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    itinerary: Itinerary = Depends(require_etag),
) -> AnnotationResponse:
    stop = db.execute(
        select(Stop).where(Stop.id == stop_id, Stop.itinerary_id == itinerary_id)
    ).scalar_one_or_none()

    if not stop:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Stop not found.")

    annotation = Annotation(stop_id=stop_id, type=body.type, content=body.content)
    db.add(annotation)
    db.commit()
    db.refresh(annotation)
    return annotation  # type: ignore[return-value]


@router.delete("/{itinerary_id}/stops/{stop_id}/annotations/{annotation_id}",
               status_code=status.HTTP_204_NO_CONTENT,
               summary="Delete an annotation from a stop")
def delete_annotation(
    itinerary_id: uuid.UUID,
    stop_id: uuid.UUID,
    annotation_id: uuid.UUID,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    itinerary: Itinerary = Depends(require_etag),
) -> None:
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
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Annotation not found.")

    db.delete(annotation)
    db.commit()


@router.patch("/{itinerary_id}/stops/{stop_id}/annotations/{annotation_id}",
              response_model=AnnotationResponse, summary="Edit an annotation on a stop")
def update_annotation(
    itinerary_id: uuid.UUID,
    stop_id: uuid.UUID,
    annotation_id: uuid.UUID,
    body: AnnotationUpdate,
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    itinerary: Itinerary = Depends(require_etag),
) -> AnnotationResponse:
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
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Annotation not found.")

    if body.content is not None:
        annotation.content = body.content
    if body.type is not None:
        annotation.type = body.type

    db.commit()
    db.refresh(annotation)
    return annotation  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# Rating endpoints
# ---------------------------------------------------------------------------

@router.post("/{itinerary_id}/ratings", response_model=RatingResponse,
             status_code=status.HTTP_201_CREATED,
             summary="Submit or update the current user's rating for an itinerary")
def upsert_rating(
    itinerary_id: uuid.UUID,
    body: RatingSubmit,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> RatingResponse:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    if not can_view_itinerary(itinerary, current_user.id, db):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="You do not have access to this itinerary.")

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


@router.delete("/{itinerary_id}/ratings/me", status_code=status.HTTP_204_NO_CONTENT,
               summary="Remove the current user's rating from an itinerary")
def delete_my_rating(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    itinerary = _get_itinerary_or_404(itinerary_id, db)

    rating = db.execute(
        select(ItineraryRating).where(
            ItineraryRating.itinerary_id == itinerary_id,
            ItineraryRating.user_id == current_user.id,
        )
    ).scalar_one_or_none()

    if not rating:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="You have not rated this itinerary.")

    db.delete(rating)
    db.flush()
    recalculate_rating(itinerary, db)
    db.commit()


@router.get("/{itinerary_id}/ratings/me", response_model=RatingResponse,
            summary="Get the current user's rating for an itinerary")
def get_my_rating(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> RatingResponse:
    _get_itinerary_or_404(itinerary_id, db)

    rating = db.execute(
        select(ItineraryRating).where(
            ItineraryRating.itinerary_id == itinerary_id,
            ItineraryRating.user_id == current_user.id,
        )
    ).scalar_one_or_none()

    if not rating:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="You have not rated this itinerary.")

    return rating  # type: ignore[return-value]


@router.get("/{itinerary_id}/ratings", response_model=RatingsPageResponse,
            summary="Get the full ratings page for an itinerary")
def get_ratings_page(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> RatingsPageResponse:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    if not can_view_itinerary(itinerary, current_user.id, db):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="You do not have access to this itinerary.")

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

    dist: dict[int, int] = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
    for row in rows:
        dist[row.stars] += 1

    distribution = RatingDistribution(
        five=dist[5], four=dist[4], three=dist[3], two=dist[2], one=dist[1]
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
# Transit segment endpoints
# ---------------------------------------------------------------------------

@router.post("/{itinerary_id}/segments", response_model=TransitSegmentResponse,
             status_code=status.HTTP_201_CREATED,
             summary="Create a transit segment between two stops")
def create_segment(
    itinerary_id: uuid.UUID,
    body: TransitSegmentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> TransitSegmentResponse:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    for stop_id, label in ((body.from_stop_id, "from_stop_id"), (body.to_stop_id, "to_stop_id")):
        stop = db.execute(
            select(Stop).where(Stop.id == stop_id, Stop.itinerary_id == itinerary_id)
        ).scalar_one_or_none()
        if not stop:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail=f"{label} does not belong to this itinerary.")

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
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                            detail="A segment between these two stops already exists.")

    for leg_data in body.legs:
        leg = TransportLeg(segment_id=segment.id, **leg_data.model_dump())
        db.add(leg)

    db.flush()
    _recalculate_segment_totals(segment, db)
    _recalculate_totals(itinerary, db)
    db.commit()
    db.refresh(segment)
    return segment  # type: ignore[return-value]


@router.get("/{itinerary_id}/segments", response_model=list[TransitSegmentResponse],
            summary="List all transit segments for an itinerary")
def list_segments(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[TransitSegmentResponse]:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    if not can_view_itinerary(itinerary, current_user.id, db):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="You do not have access to this itinerary.")

    segments = db.execute(
        select(TransitSegment)
        .options(
            selectinload(TransitSegment.legs),
            selectinload(TransitSegment.from_stop),
        )
        .where(TransitSegment.itinerary_id == itinerary_id)
    ).scalars().all()

    # Order by the from_stop's track rank then stop rank.
    segments.sort(key=lambda seg: (
        seg.from_stop.track.rank if seg.from_stop and seg.from_stop.track else "",
        seg.from_stop.rank if seg.from_stop else "",
    ))
    return segments  # type: ignore[return-value]


@router.patch("/{itinerary_id}/segments/{segment_id}",
              response_model=TransitSegmentResponse,
              summary="Update a transit segment's stop references")
def update_segment(
    itinerary_id: uuid.UUID,
    segment_id: uuid.UUID,
    body: TransitSegmentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> TransitSegmentResponse:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    segment = _get_segment_or_404(segment_id, itinerary_id, db)

    for stop_id, label in ((body.from_stop_id, "from_stop_id"), (body.to_stop_id, "to_stop_id")):
        stop = db.execute(
            select(Stop).where(Stop.id == stop_id, Stop.itinerary_id == itinerary_id)
        ).scalar_one_or_none()
        if not stop:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail=f"{label} does not belong to this itinerary.")

    segment.from_stop_id = body.from_stop_id
    segment.to_stop_id = body.to_stop_id

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
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                            detail="A segment between these two stops already exists.")

    _recalculate_segment_totals(segment, db)
    _recalculate_totals(itinerary, db)
    db.commit()
    db.refresh(segment)
    return segment  # type: ignore[return-value]


@router.delete("/{itinerary_id}/segments/{segment_id}",
               status_code=status.HTTP_204_NO_CONTENT,
               summary="Delete a transit segment and all its legs")
def delete_segment(
    itinerary_id: uuid.UUID,
    segment_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    segment = _get_segment_or_404(segment_id, itinerary_id, db)

    db.delete(segment)
    db.flush()
    _recalculate_totals(itinerary, db)
    db.commit()


# ---------------------------------------------------------------------------
# Transport leg endpoints
# ---------------------------------------------------------------------------

@router.post("/{itinerary_id}/segments/{segment_id}/legs",
             response_model=TransportLegResponse, status_code=status.HTTP_201_CREATED,
             summary="Add a transport leg to a segment")
def add_leg(
    itinerary_id: uuid.UUID,
    segment_id: uuid.UUID,
    body: TransportLegCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> TransportLegResponse:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    segment = _get_segment_or_404(segment_id, itinerary_id, db)

    leg = TransportLeg(segment_id=segment.id, **body.model_dump())
    db.add(leg)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                            detail=f"A leg at position {body.position} already exists in this segment.")

    _recalculate_segment_totals(segment, db)
    _recalculate_totals(itinerary, db)
    db.commit()
    db.refresh(leg)
    return leg  # type: ignore[return-value]


@router.patch("/{itinerary_id}/segments/{segment_id}/legs/{leg_id}",
              response_model=TransportLegResponse,
              summary="Update a transport leg (partial update)")
def update_leg(
    itinerary_id: uuid.UUID,
    segment_id: uuid.UUID,
    leg_id: uuid.UUID,
    body: TransportLegUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> TransportLegResponse:
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


@router.delete("/{itinerary_id}/segments/{segment_id}/legs/{leg_id}",
               status_code=status.HTTP_204_NO_CONTENT,
               summary="Delete a transport leg from a segment")
def delete_leg(
    itinerary_id: uuid.UUID,
    segment_id: uuid.UUID,
    leg_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
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
# Cover image endpoints
# ---------------------------------------------------------------------------

@router.post("/{itinerary_id}/image", response_model=ItineraryImageResponse,
             summary="Upload or replace the cover image for an itinerary")
async def upload_itinerary_image(
    itinerary_id: uuid.UUID,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ItineraryImageResponse:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    raw_bytes = await file.read()

    try:
        processed = process_cover_image(raw_bytes)
    except ImageProcessingError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))

    key = f"itineraries/{itinerary_id}.jpg"
    public_url = await storage().save(key, processed, "image/jpeg")

    itinerary.cover_image_url = public_url
    db.commit()

    return ItineraryImageResponse(cover_image_url=public_url)


@router.delete("/{itinerary_id}/image", status_code=status.HTTP_204_NO_CONTENT,
               summary="Remove the cover image from an itinerary")
async def delete_itinerary_image(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    key = f"itineraries/{itinerary_id}.jpg"
    await storage().delete(key)

    itinerary.cover_image_url = None
    db.commit()


# ---------------------------------------------------------------------------
# GET /users/{user_id}/itineraries  (mounted on user_itineraries_router)
# ---------------------------------------------------------------------------

@user_itineraries_router.get("/{user_id}/itineraries",
                              response_model=list[ItinerarySummary],
                              summary="List a user's itineraries visible to the current user")
def get_user_itineraries(
    user_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[ItinerarySummary]:
    target_user = db.get(User, user_id)
    if not target_user or not target_user.is_active:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="User not found.")

    itineraries = db.execute(
        select(Itinerary)
        .where(Itinerary.user_id == user_id)
        .order_by(Itinerary.created_at.desc())
    ).scalars().all()

    return [
        i for i in itineraries
        if can_view_itinerary(i, current_user.id, db)
    ]  # type: ignore[return-value]
