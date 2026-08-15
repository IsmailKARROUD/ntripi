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
from dataclasses import asdict
from decimal import Decimal
from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile, status
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse, Response
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.config import Settings, get_settings
from app.database import get_db
from app.dependencies import (
    get_current_user, require_edit_access, require_verified_email,
)
from app.limiter import limiter
from app.models.annotation import Annotation
from app.models.itinerary import Itinerary
from app.models.itinerary_annotation import ItineraryAnnotation
from app.models.itinerary_allowed_user import ItineraryAllowedUser
from app.models.itinerary_editor import ItineraryEditor
from app.models.saved_itinerary import SavedItinerary
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
    EditorAdd,
    EditorResponse,
    ItineraryAnnotationCreate,
    ItineraryAnnotationResponse,
    ItineraryAnnotationUpdate,
    ItineraryCreate,
    ItineraryDetail,
    ItineraryFeedItem,
    ItineraryImageResponse,
    ItinerarySummary,
    ItineraryUpdate,
    LockClaimRequest,
    LockClaimResponse,
    LockHolder,
    LockStateResponse,
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
from app.services import edit_lock_service, notification_service
from app.services.block_service import blocked_user_ids, require_not_blocked_or_404
from app.services.image_service import ImageProcessingError, process_and_store, process_cover_image
from app.services.moderation_service import ModerationContext, ModerationRejectedError
from app.services.moderation_actions import escalate_if_flagged
from app.services.itinerary_access import (
    HIDDEN_STATUSES, can_edit_itinerary, can_view_itinerary,
    public_listing_criteria, recalculate_rating, visible_rating_criteria,
)
from app.services.ordering import MAX_RANK_LENGTH, key_between, n_keys_between
from app.services.text_moderation_service import (
    apply_moderation_status, attach_target, moderate_or_422,
)
from app.services.user_service import get_active_user_or_404, public_profile_text
from app.storage.factory import storage
from app.errors import ApiError

router = APIRouter(tags=["Itineraries"])
user_itineraries_router = APIRouter(tags=["Itineraries"])


# ---------------------------------------------------------------------------
# ETag helpers
# ---------------------------------------------------------------------------

def _etag_value(itinerary: Itinerary) -> str:
    # Quoted ISO datetime of updated_at. Canonical version lives in
    # app.dependencies; re-exported here so router code stays self-contained.
    from app.dependencies import _etag_value as _canonical_etag
    return _canonical_etag(itinerary)


def _touch_itinerary(itinerary: Itinerary) -> None:
    # SQLAlchemy only emits an UPDATE when at least one column actually
    # changed, so `onupdate=now()` doesn't fire for mutations that only
    # touch child rows (annotations) or set the same total back (e.g. a
    # zero-duration stop). Without an updated_at bump the GET ETag stays
    # the same and the Dio cache interceptor 304s with stale local data.
    itinerary.updated_at = datetime.now(timezone.utc)


def _etag_json_response(schema_cls, obj, itinerary: Itinerary,
                        status_code: int = status.HTTP_200_OK,
                        extra: dict | None = None) -> JSONResponse:
    # Endpoint-set ETag reuses the If-Match concurrency token (updated_at),
    # so the ETagMiddleware leaves it alone and 304s against this ISO value.
    data = jsonable_encoder(schema_cls.model_validate(obj))
    # Viewer-scoped fields the ORM object cannot carry (can_edit). The schema
    # already declares them, so overwriting here keeps JSON key order intact.
    if extra:
        data.update(extra)
    resp = JSONResponse(content=data, status_code=status_code)
    resp.headers["ETag"] = _etag_value(itinerary)
    return resp


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _get_itinerary_or_404(itinerary_id: uuid.UUID, db: Session) -> Itinerary:
    itinerary = db.get(Itinerary, itinerary_id)
    # Soft-deleted itineraries are gone for everyone (owner included) — 404 here
    # covers the detail read AND every mutation that flows through this helper.
    if not itinerary or itinerary.deleted_at is not None:
        raise ApiError(status_code=status.HTTP_404_NOT_FOUND,
                            code="itinerary_not_found", detail="Itinerary not found.")
    return itinerary


def _require_owner(itinerary: Itinerary, current_user: User) -> None:
    if itinerary.user_id != current_user.id:
        raise ApiError(status_code=status.HTTP_403_FORBIDDEN,
                            code="itinerary_not_owner", detail="You do not have permission to modify this itinerary.")


def _require_viewable(itinerary: Itinerary, viewer_id: uuid.UUID, db: Session,
                      detail: str = "You do not have access to this itinerary.") -> None:
    # Visibility single source of truth — see app/services/itinerary_access.py.
    if not can_view_itinerary(itinerary, viewer_id, db):
        raise ApiError(status_code=status.HTTP_403_FORBIDDEN,
                            code="itinerary_access_denied", detail=detail)


def _moderate_itinerary_text(
    fields: dict[str, str | None],
    itinerary: Itinerary | None,
    db: Session,
    current_user: User,
):
    """Scan text belonging to an itinerary and stamp the outcome on it.

    Stop, annotation and transport-leg text has no status column of its own —
    it rolls up here, because hiding is itinerary-level and a per-fragment
    status would have no read path to enforce it.

    Call from the endpoint BODY, after the ownership/If-Match checks: a 412
    must never spend a moderation call. `itinerary` is None on create (the row
    does not exist yet); the caller stamps the returned status itself.
    """
    ctx = moderate_or_422(
        db, get_settings(),
        target_type="itinerary",
        author=current_user,
        fields=fields,
        target_id=itinerary.id if itinerary is not None else None,
    )
    if itinerary is not None:
        apply_moderation_status(itinerary, ctx.status)
        # A minors hit is taken down on the spot rather than queued. This is the
        # owner's own request, so a plain assignment is right — set_preserving_etag
        # exists for moderation writes that happen outside the owner's request.
        if ctx.escalate and itinerary.hidden_at is None:
            itinerary.hidden_at = datetime.now(timezone.utc)
        # Hiding alone would leave the signal out of /admin/legal — the sweep's
        # re-check path has always escalated, and a write must agree with it.
        escalate_if_flagged(
            db, "itinerary", itinerary,
            escalate_flag=ctx.escalate, decision_id=ctx.decision_id,
        )
    return ctx


def _leg_text_fields(legs) -> dict[str, str | None]:
    """Flatten every leg's free text into one field map, so a segment's legs are
    scanned in a single provider call rather than one per leg. Keys only need to
    be unique — they are never stored."""
    return {
        f"leg{index}_{name}": getattr(leg, name, None)
        for index, leg in enumerate(legs)
        for name in ("line", "direction", "notes")
    }


def _two_phase_renumber(rows, db: Session) -> None:
    # Two-phase to dodge unique-collisions while rewriting a full rank set:
    # first park every row on '!'+id (ASCII 33 sorts below every key_between
    # char under COLLATE "C", so temp ranks can't clash), flush, then assign
    # the final evenly-spaced keys.
    for row in rows:
        row.rank = f"!{row.id}"
    db.flush()
    for row, new_rank in zip(rows, n_keys_between(None, None, len(rows))):
        row.rank = new_rank
    db.flush()


def _require_stops_in_itinerary(itinerary_id: uuid.UUID, from_stop_id: uuid.UUID,
                                to_stop_id: uuid.UUID, db: Session) -> None:
    for stop_id, label in ((from_stop_id, "from_stop_id"), (to_stop_id, "to_stop_id")):
        stop = db.execute(
            select(Stop).where(Stop.id == stop_id, Stop.itinerary_id == itinerary_id)
        ).scalar_one_or_none()
        if not stop:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail=f"{label} does not belong to this itinerary.")


def _annotation_not_found() -> ApiError:
    return ApiError(status_code=status.HTTP_404_NOT_FOUND,
                        code="annotation_not_found", detail="Annotation not found.")


def _get_itinerary_annotation_or_404(annotation_id: uuid.UUID, itinerary_id: uuid.UUID,
                                     db: Session) -> ItineraryAnnotation:
    annotation = db.execute(
        select(ItineraryAnnotation).where(
            ItineraryAnnotation.id == annotation_id,
            ItineraryAnnotation.itinerary_id == itinerary_id,
        )
    ).scalar_one_or_none()
    if not annotation:
        raise _annotation_not_found()
    return annotation


def _get_stop_annotation_or_404(annotation_id: uuid.UUID, stop_id: uuid.UUID,
                                itinerary_id: uuid.UUID, db: Session) -> Annotation:
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
        raise _annotation_not_found()
    return annotation


def _apply_annotation_fields(annotation, body) -> None:
    if body.type is not None:
        annotation.type = body.type
    if body.content is not None:
        annotation.content = body.content


def _save_annotation(annotation, itinerary: Itinerary, db: Session):
    db.add(annotation)  # no-op for an already-persistent annotation on update
    _touch_itinerary(itinerary)
    db.commit()
    db.refresh(annotation)
    return annotation


def _delete_annotation(annotation, itinerary: Itinerary, db: Session) -> None:
    db.delete(annotation)
    _touch_itinerary(itinerary)
    db.commit()


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
    _touch_itinerary(itinerary)


def _load_itinerary_detail(itinerary_id: uuid.UUID, db: Session) -> Itinerary:
    """
    Load itinerary with all related data for the detail response.

    Uses selectinload chains to avoid N+1 queries:
      itinerary → tracks → stops → annotations   (3 levels deep)
      itinerary → segments → legs
      itinerary → segments → from_stop  (needed to order segments later)
      itinerary → itinerary_annotations

    WHY SORT AFTER LOADING?
      selectinload ignores the relationship's order_by when loading eagerly.
      We re-sort in Python after loading. The DB index on (itinerary_id, rank)
      and (track_id, rank) means the data arrives roughly sorted anyway, so
      Python sort is O(n log n) on nearly-sorted data — very fast.
    """
    itinerary = db.execute(
        select(Itinerary)
        .options(
            selectinload(Itinerary.tracks).selectinload(Track.stops).selectinload(Stop.annotations),
            selectinload(Itinerary.segments).selectinload(TransitSegment.legs),
            selectinload(Itinerary.segments).selectinload(TransitSegment.from_stop),
            selectinload(Itinerary.annotations),
        )
        .where(Itinerary.id == itinerary_id, Itinerary.deleted_at.is_(None))
    ).scalar_one_or_none()

    if not itinerary:
        raise ApiError(status_code=status.HTTP_404_NOT_FOUND,
                            code="itinerary_not_found", detail="Itinerary not found.")

    # Sort tracks and stops by rank. Because rank is COLLATE "C" in the DB
    # and Python uses the same byte ordering by default, the Python sort and
    # the DB ORDER BY produce identical results.
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
        raise ApiError(status_code=status.HTTP_404_NOT_FOUND,
                            code="stop_not_found", detail="Stop not found.")
    return stop


def _get_track_or_404(track_id: uuid.UUID, itinerary_id: uuid.UUID, db: Session) -> Track:
    track = db.execute(
        select(Track).where(Track.id == track_id, Track.itinerary_id == itinerary_id)
    ).scalar_one_or_none()
    if not track:
        raise ApiError(status_code=status.HTTP_404_NOT_FOUND,
                            code="track_not_found", detail="Track not found or does not belong to this itinerary.")
    return track


def _delete_track_if_empty(track_id: uuid.UUID, db: Session) -> None:
    """
    Delete the track if it has no remaining stops.

    Called after every stop deletion and after every cross-track move.
    The DB model allows ON DELETE CASCADE from tracks to stops, but we don't
    use it here because we want this logic to be explicit and auditable —
    a database trigger would be invisible to the application code.

    LIMIT 1 is intentional: we only need to know if any stop exists, not count them all.
    """
    remaining = db.execute(
        select(Stop).where(Stop.track_id == track_id).limit(1)
    ).scalar_one_or_none()
    if remaining is None:
        track = db.get(Track, track_id)
        if track:
            db.delete(track)


def _rebalance_track(track: Track, db: Session) -> None:
    """
    Renumber every stop in `track` with evenly spaced fractional-index ranks.

    Called when `_resolve_stop_rank` would otherwise produce a key longer than
    MAX_RANK_LENGTH — typically because a user repeatedly inserts at the same
    edge of a track, which adds one character per insert past the halving range.
    After this pass every rank is ≤ 2 chars regardless of prior history.

    TWO-PHASE WRITE:
      UNIQUE(track_id, rank) is enforced immediately, so we cannot rewrite ranks
      in place — a stop's new rank could collide with another stop's still-old
      rank. Phase 1 parks every stop on a temp rank starting with '!' (ASCII 33,
      which sorts below every digit/letter that key_between can produce, so the
      relative ordering during phase 1 is irrelevant). Phase 2 assigns the final
      keys in the same order they previously had.
    """
    stops = db.execute(
        select(Stop).where(Stop.track_id == track.id).order_by(Stop.rank)
    ).scalars().all()
    if len(stops) <= 1:
        return

    _two_phase_renumber(stops, db)


def _resolve_stop_rank(
    track: Track,
    after_stop_id: uuid.UUID | None,
    before_stop_id: uuid.UUID | None,
    db: Session,
) -> str:
    """
    Compute a fractional-index rank for a new stop within a track.

    The client sends anchor stop IDs:
      after_stop_id  → the new stop goes after this one  (lower bound)
      before_stop_id → the new stop goes before this one (upper bound)

    key_between(after.rank, before.rank) produces a rank string strictly
    between the two. If no anchors are provided, the stop is placed at the
    tail (after the current last stop in the track).

    WHY VALIDATE THAT ANCHORS BELONG TO THIS TRACK?
      A stale client could send an anchor from a different track, or one that
      was deleted. Either case is a client bug — we return 422 rather than
      silently placing the stop at the wrong position.

    WHY 412 WHEN after.rank >= before.rank?
      The client's view of stop order is stale (someone else reordered between
      the client's last fetch and this insert). 412 signals "reload first".

    REBALANCE FALLBACK:
      If the freshly computed key exceeds MAX_RANK_LENGTH the track is
      pathologically long; we rebalance it in-place and recompute against the
      now-fresh anchor ranks. The rebalance shares this transaction so the move
      and the renumber commit atomically (and bump the same ETag).
    """
    def _resolve(allow_rebalance: bool) -> str:
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
            raise ApiError(
                status_code=status.HTTP_412_PRECONDITION_FAILED,
                code="itinerary_stale", detail="itinerary modified, please reload",
            )

        # No anchors → tail insert: place after the last existing stop in this track.
        if after_rank is None and before_rank is None:
            last = db.execute(
                select(Stop).where(Stop.track_id == track.id).order_by(Stop.rank.desc()).limit(1)
            ).scalar_one_or_none()
            if last is not None:
                after_rank = last.rank

        new_rank = key_between(after_rank, before_rank)
        if len(new_rank) > MAX_RANK_LENGTH and allow_rebalance:
            _rebalance_track(track, db)
            return _resolve(allow_rebalance=False)
        return new_rank

    return _resolve(allow_rebalance=True)


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
        raise ApiError(
            status_code=status.HTTP_412_PRECONDITION_FAILED,
            code="itinerary_stale", detail="itinerary modified, please reload",
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
        raise ApiError(status_code=status.HTTP_404_NOT_FOUND,
                            code="segment_not_found", detail="Transit segment not found.")
    return segment


def _get_leg_or_404(leg_id, segment_id, db):
    leg = db.execute(
        select(TransportLeg).where(TransportLeg.id == leg_id,
                                   TransportLeg.segment_id == segment_id)
    ).scalar_one_or_none()
    if not leg:
        raise ApiError(status_code=status.HTTP_404_NOT_FOUND,
                            code="leg_not_found", detail="Transport leg not found.")
    return leg


# ---------------------------------------------------------------------------
# POST /itineraries — Create an itinerary
# ---------------------------------------------------------------------------

@router.post("/", response_model=ItinerarySummary, status_code=status.HTTP_201_CREATED,
             summary="Create a new itinerary")
def create_itinerary(
    body: ItineraryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_verified_email),  # high-value: verified email required
) -> ItinerarySummary:
    ctx = _moderate_itinerary_text(
        {
            "title": body.title,
            "description": body.description,
            "recommended_period_note": body.recommended_period_note,
        },
        None, db, current_user,
    )
    itinerary = Itinerary(
        user_id=current_user.id,
        title=body.title,
        description=body.description,
        currency=body.currency,
        visibility=body.visibility,
        # Dumped to plain dicts — a JSON column cannot store Pydantic instances.
        recommended_periods=(
            [w.model_dump() for w in body.recommended_periods]
            if body.recommended_periods else None
        ),
        recommended_weekdays=body.recommended_weekdays,
        recommended_period_note=body.recommended_period_note,
        total_duration_min=0,
        total_cost=Decimal("0.00"),
        moderation_status=ctx.status,
        # A minors hit publishes hidden rather than queued — see moderation_policy.
        hidden_at=datetime.now(timezone.utc) if ctx.escalate else None,
    )
    db.add(itinerary)
    db.flush()
    # The scan ran before this row existed, so its decision has no target yet.
    attach_target(ctx, itinerary.id)
    # Same reason attach_target waits for the flush: escalate needs a real id.
    escalate_if_flagged(
        db, "itinerary", itinerary,
        escalate_flag=ctx.escalate, decision_id=ctx.decision_id,
    )
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
        # Owner sees their own hidden itineraries (with a banner) but never their
        # soft-deleted ones.
        .where(Itinerary.user_id == current_user.id, Itinerary.deleted_at.is_(None))
        .order_by(Itinerary.created_at.desc())
    ).scalars().all()
    return itineraries  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# GET /itineraries/feed — Public discovery feed (Top / Recent)
# Declared before /{itinerary_id} so FastAPI matches the literal "feed" path
# instead of treating it as a {itinerary_id} UUID.
# ---------------------------------------------------------------------------

def _to_feed_item(itinerary: Itinerary, owner: User,
                  viewer_id: uuid.UUID | None = None) -> ItineraryFeedItem:
    # Reuse ItinerarySummary's field mapping for the base, then graft on the
    # owner (same RaterInfo shape the ratings endpoint builds).
    return ItineraryFeedItem(
        **ItinerarySummary.model_validate(itinerary).model_dump(),
        owner=RaterInfo(
            user_id=owner.id,
            username=owner.username,
            # The feed is the widest-reach surface — a moderated display name
            # must not ride along with an otherwise clean itinerary.
            display_name=public_profile_text(owner, viewer_id)[0],
            avatar_url=owner.avatar_url,
        ),
    )


@router.get("/feed", response_model=list[ItineraryFeedItem],
            summary="Public discovery feed of itineraries")
@limiter.limit("30/minute")
def list_feed(
    request: Request,  # required first positional for slowapi rate limiting
    sort: Literal["top", "recent"] = Query("recent"),
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    settings: Settings = Depends(get_settings),
) -> list[ItineraryFeedItem]:
    # Only 'public' is visible to an arbitrary viewer — this SQL filter is the
    # cheap equivalent of can_view_itinerary() (which short-circuits True for
    # public) without an O(n) per-row Python evaluation.
    query = (
        select(Itinerary, User)
        .join(User, Itinerary.user_id == User.id)
        # Eager-load tracks→stops so the stops_count property is cheap (no N+1);
        # same selectinload pattern as _load_itinerary_detail.
        .options(selectinload(Itinerary.tracks).selectinload(Track.stops))
        .where(Itinerary.visibility == "public")
        # Exclude moderator-hidden/soft-deleted itineraries and banned owners'
        # content — single source of truth in itinerary_access.
        .where(*public_listing_criteria(db, current_user.id))
    )

    if sort == "top":
        # Min rating count keeps a single 5-star trip from dominating; threshold
        # is env-configurable so it can flex as the catalogue grows.
        query = query.where(Itinerary.rating_count >= settings.FEED_TOP_MIN_RATINGS).order_by(
            Itinerary.rating_avg.desc(),
            Itinerary.rating_count.desc(),
            Itinerary.created_at.desc(),
            Itinerary.id.desc(),  # final tie-breaker for stable pagination
        )
    else:
        query = query.order_by(
            Itinerary.created_at.desc(),
            Itinerary.id.desc(),  # final tie-breaker for stable pagination
        )

    rows = db.execute(query.limit(limit).offset(offset)).all()
    return [
        _to_feed_item(itinerary, owner, current_user.id) for itinerary, owner in rows
    ]


# ---------------------------------------------------------------------------
# GET /itineraries/saved — The current user's saved (bookmarked) itineraries
# Declared before /{itinerary_id} so FastAPI matches the literal "saved" path
# instead of treating it as a {itinerary_id} UUID.
# ---------------------------------------------------------------------------

@router.get("/saved", response_model=list[ItinerarySummary],
            summary="List the current user's saved itineraries")
def list_saved_itineraries(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[ItinerarySummary]:
    itineraries = db.execute(
        select(Itinerary)
        .join(SavedItinerary, SavedItinerary.itinerary_id == Itinerary.id)
        .where(SavedItinerary.user_id == current_user.id)
        # Eager-load tracks→stops so the stops_count property is cheap (no N+1);
        # same selectinload pattern as the feed.
        .options(selectinload(Itinerary.tracks).selectinload(Track.stops))
        # saved_at can collide (server now()), so id is the stable tie-breaker.
        .order_by(SavedItinerary.saved_at.desc(), Itinerary.id.desc())
    ).scalars().all()

    # Filter through the single source of truth — a saved itinerary whose
    # visibility later dropped (e.g. to only_me) must not leak here.
    return [
        i for i in itineraries
        if can_view_itinerary(i, current_user.id, db)
    ]  # type: ignore[return-value]


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

    # Preserve the pre-refactor wording (contraction, no period) — the other
    # access-denied sites use the _require_viewable default; this one differs.
    _require_viewable(itinerary, current_user.id, db,
                      detail="You don't have access to this itinerary")

    return _etag_json_response(
        ItineraryDetail, itinerary, itinerary,
        extra={"can_edit": can_edit_itinerary(itinerary, current_user.id, db)},
    )


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
    itinerary: Itinerary = Depends(require_edit_access),
) -> ItinerarySummary:
    update_data = body.model_dump(exclude_unset=True)

    # Mixed authority: the guard admits editors, but who may SEE the itinerary
    # is the owner's decision alone and is not part of editing its content.
    if "visibility" in update_data and itinerary.user_id != current_user.id:
        raise ApiError(status_code=status.HTTP_403_FORBIDDEN,
                       code="itinerary_not_owner",
                       detail="Only the owner can change who can see this itinerary.")

    # Only the text actually being submitted is scanned — re-scanning untouched
    # fields would bill for text already cleared on a previous write.
    _moderate_itinerary_text(
        {
            key: update_data[key]
            for key in ("title", "description", "recommended_period_note")
            if key in update_data
        },
        itinerary, db, current_user,
    )
    # model_dump already flattened the nested period windows to plain dicts, so
    # every ItineraryUpdate field whose name matches a column lands as-is here.
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
async def delete_itinerary(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    had_cover = itinerary.cover_image_url is not None
    db.delete(itinerary)
    db.commit()

    # Purge the cover from storage after the row is gone — orphans a file at
    # worst if storage fails, rather than leaving a live itinerary imageless.
    if had_cover:
        await storage().delete(f"itineraries/{itinerary_id}.jpg")


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
        raise ApiError(status_code=status.HTTP_400_BAD_REQUEST,
                            code="allowlist_restricted_only", detail="Allowlist only applies to restricted itineraries")

    target_user = db.get(User, body.user_id)
    if not target_user:
        raise ApiError(status_code=status.HTTP_404_NOT_FOUND, code="user_not_found", detail="User not found.")

    existing = db.execute(
        select(ItineraryAllowedUser).where(
            ItineraryAllowedUser.itinerary_id == itinerary_id,
            ItineraryAllowedUser.user_id == body.user_id,
        )
    ).scalar_one_or_none()
    if existing:
        raise ApiError(status_code=status.HTTP_409_CONFLICT,
                            code="allowlist_user_exists", detail="User already has access")

    entry = ItineraryAllowedUser(itinerary_id=itinerary_id, user_id=body.user_id)
    db.add(entry)
    # Access nobody is told about is access nobody uses — a restricted itinerary
    # is invisible in every feed, so this row is the only way they learn of it.
    # No _touch_itinerary: the allowlist changes nothing in ItineraryDetail, and
    # bumping updated_at would 412 the owner's open editor.
    notification_service.notify(
        db, user_id=target_user.id, type="itinerary_viewer_added",
        actor=current_user, entity_type="itinerary", entity_id=itinerary.id,
    )
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
        raise ApiError(status_code=status.HTTP_404_NOT_FOUND,
                            code="allowlist_user_not_found", detail="User not found in allowlist")

    db.delete(entry)
    db.commit()


# ---------------------------------------------------------------------------
# Editor endpoints — /itineraries/{id}/editors
# (Same literal-path-before-/stops placement rule as the allowlist above.)
#
# Only the owner grants or revokes. A grant is inert unless the target can also
# VIEW the itinerary, and that is re-checked on every write by
# can_edit_itinerary — so this table can never widen visibility, only ride on it.
# ---------------------------------------------------------------------------

def _editor_row(db: Session, itinerary_id: uuid.UUID,
                user_id: uuid.UUID) -> ItineraryEditor | None:
    return db.execute(
        select(ItineraryEditor).where(
            ItineraryEditor.itinerary_id == itinerary_id,
            ItineraryEditor.user_id == user_id,
        )
    ).scalar_one_or_none()


def _to_editor_response(entry: ItineraryEditor, user: User,
                        viewer_id: uuid.UUID) -> EditorResponse:
    # public_profile_text, not user.display_name — a moderated name must not
    # leak through a list the allowlist endpoints happen to read raw.
    display_name, _ = public_profile_text(user, viewer_id)
    return EditorResponse(
        user_id=entry.user_id,
        username=user.username,
        display_name=display_name,
        avatar_url=user.avatar_url,
        created_at=entry.created_at,
    )


@router.post("/{itinerary_id}/editors", response_model=EditorResponse,
             status_code=status.HTTP_201_CREATED,
             summary="Grant a user permission to edit this itinerary")
def add_editor(
    itinerary_id: uuid.UUID,
    body: EditorAdd,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> EditorResponse:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    # get_active_user_or_404, not a bare db.get — the allowlist endpoint's bare
    # lookup lets a banned account onto the list, which is not worth copying.
    target = get_active_user_or_404(db, body.user_id)

    if target.id == itinerary.user_id:
        raise ApiError(status_code=status.HTTP_400_BAD_REQUEST,
                       code="editor_is_owner",
                       detail="The owner already has full edit rights.")

    if _editor_row(db, itinerary_id, target.id) is not None:
        raise ApiError(status_code=status.HTTP_409_CONFLICT,
                       code="editor_exists", detail="User can already edit this itinerary.")

    if not can_view_itinerary(itinerary, target.id, db):
        # grant_view only ever adds an allowlist row, and only for 'restricted'.
        # It must never change `visibility`: followers → restricted would cut off
        # every follower silently, and only_me → anything is a privacy decision
        # the owner has to make deliberately on the visibility screen.
        if body.grant_view and itinerary.visibility == 'restricted':
            db.add(ItineraryAllowedUser(itinerary_id=itinerary_id, user_id=target.id))
            db.flush()
        if not body.grant_view or itinerary.visibility != 'restricted':
            raise ApiError(
                status_code=status.HTTP_409_CONFLICT,
                code="editor_cannot_view",
                detail="This user cannot see this itinerary, so they cannot edit it.",
                extra={
                    "visibility": itinerary.visibility,
                    # Whether the client can fix this itself, or has to send the
                    # owner to the visibility screen.
                    "can_fix_with_allowlist": itinerary.visibility == 'restricted',
                },
            )

    entry = ItineraryEditor(
        itinerary_id=itinerary_id, user_id=target.id, granted_by=current_user.id,
    )
    db.add(entry)
    # can_edit rides in ItineraryDetail, whose ETag is updated_at — without this
    # a revoked editor's cached detail would keep offering them a pencil.
    _touch_itinerary(itinerary)
    notification_service.notify(
        db, user_id=target.id, type="itinerary_editor_added", actor=current_user,
        entity_type="itinerary", entity_id=itinerary.id,
    )
    db.commit()
    db.refresh(entry)

    return _to_editor_response(entry, target, current_user.id)


@router.get("/{itinerary_id}/editors", response_model=list[EditorResponse],
            summary="List users who can edit this itinerary")
def get_editors(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[EditorResponse]:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    # Editors read this too, not just the owner — someone sharing a document
    # should be able to see who else is holding a pen.
    if not can_edit_itinerary(itinerary, current_user.id, db):
        raise ApiError(status_code=status.HTTP_403_FORBIDDEN,
                       code="itinerary_not_owner",
                       detail="You do not have permission to modify this itinerary.")

    results = db.execute(
        select(ItineraryEditor, User)
        .join(User, ItineraryEditor.user_id == User.id)
        .where(ItineraryEditor.itinerary_id == itinerary_id)
        .order_by(ItineraryEditor.created_at.asc())
    ).all()

    return [
        _to_editor_response(entry, user, current_user.id)
        for entry, user in results
    ]


@router.delete("/{itinerary_id}/editors/{user_id}",
               status_code=status.HTTP_204_NO_CONTENT,
               summary="Revoke a user's permission to edit this itinerary")
def remove_editor(
    itinerary_id: uuid.UUID,
    user_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    entry = _editor_row(db, itinerary_id, user_id)
    if not entry:
        raise ApiError(status_code=status.HTTP_404_NOT_FOUND,
                       code="editor_not_found", detail="User is not an editor of this itinerary.")

    db.delete(entry)
    # Leaving a revoked editor's claim standing would block everyone else until
    # the TTL ran out, for a person who can no longer use it.
    edit_lock_service.release_for_user(db, itinerary_id, user_id)
    _touch_itinerary(itinerary)
    db.commit()


# ---------------------------------------------------------------------------
# Edit-lock endpoints — /itineraries/{id}/lock
#
# The claim is identified by a server-minted token, not by user id: a takeover
# rotates it, which is the whole reason the displaced device cannot save. These
# endpoints are the only place the raw token is ever produced.
# ---------------------------------------------------------------------------

def _lock_holder(db: Session, lock, viewer_id: uuid.UUID) -> LockHolder:
    return LockHolder(**asdict(
        edit_lock_service.to_view(db, lock, viewer_id, get_settings())
    ))


def _require_editable(itinerary: Itinerary, current_user: User,
                      db: Session) -> None:
    """403 unless this caller may edit. Same code and wording as the non-owner
    rejection everywhere else — whether they were never granted or lost view
    access is not something to spell out to them."""
    if not can_edit_itinerary(itinerary, current_user.id, db):
        raise ApiError(status_code=status.HTTP_403_FORBIDDEN,
                       code="itinerary_not_owner",
                       detail="You do not have permission to modify this itinerary.")


@router.post("/{itinerary_id}/lock", response_model=LockClaimResponse,
             summary="Start an editing session (claim the edit lock)")
def acquire_lock(
    itinerary_id: uuid.UUID,
    body: LockClaimRequest | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> LockClaimResponse:
    settings = get_settings()
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_editable(itinerary, current_user, db)

    lock, raw = edit_lock_service.claim(
        db, itinerary, current_user, settings,
        takeover=body.takeover if body is not None else False,
    )
    holder = _lock_holder(db, lock, current_user.id)
    db.commit()

    return LockClaimResponse(
        token=raw,
        lock=holder,
        heartbeat_interval_seconds=settings.EDIT_LOCK_HEARTBEAT_SECONDS,
        ttl_seconds=settings.EDIT_LOCK_TTL_SECONDS,
    )


@router.post("/{itinerary_id}/lock/heartbeat", response_model=LockHolder,
             summary="Keep an editing session alive")
def heartbeat_lock(
    request: Request,
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> LockHolder:
    settings = get_settings()
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_editable(itinerary, current_user, db)

    # Same gate a save goes through — a ping that could not save must not
    # reassure the client that it still holds the claim.
    lock = edit_lock_service.heartbeat(
        db, itinerary, current_user,
        request.headers.get(edit_lock_service.LOCK_HEADER), settings,
    )
    holder = _lock_holder(db, lock, current_user.id)
    db.commit()
    return holder


@router.delete("/{itinerary_id}/lock", status_code=status.HTTP_204_NO_CONTENT,
               summary="End an editing session (release the edit lock)")
def release_lock(
    request: Request,
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_editable(itinerary, current_user, db)

    # Idempotent and never 404: the client fires this from teardown, so a retry,
    # or a claim the TTL already handed to someone else, must not raise for
    # something the user has finished with. The owner may release without a
    # token — that is the "unlock it from my other device" path.
    edit_lock_service.release(
        db, itinerary, current_user,
        request.headers.get(edit_lock_service.LOCK_HEADER), get_settings(),
    )
    db.commit()


@router.get("/{itinerary_id}/lock", response_model=LockStateResponse,
            summary="Who, if anyone, is editing this itinerary")
def get_lock_state(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> LockStateResponse:
    settings = get_settings()
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    # View access is enough to read this — the detail screen shows the banner
    # before it knows whether the reader will ever try to edit.
    _require_viewable(itinerary, current_user.id, db)

    lock = edit_lock_service.get_lock(db, itinerary_id)
    return LockStateResponse(
        can_edit=can_edit_itinerary(itinerary, current_user.id, db),
        lock=_lock_holder(db, lock, current_user.id) if lock is not None else None,
        heartbeat_interval_seconds=settings.EDIT_LOCK_HEARTBEAT_SECONDS,
        ttl_seconds=settings.EDIT_LOCK_TTL_SECONDS,
    )


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
    _verified: User = Depends(require_verified_email),  # high-value: verified email required
    itinerary: Itinerary = Depends(require_edit_access),
) -> Response:
    """
    Add a new stop. Requires an edit claim + If-Match (both validated by
    require_edit_access).

    Two modes:
      track_id provided  → add the stop inside that existing track, using
                           after_stop_id / before_stop_id as rank anchors.
      track_id = null    → create a brand-new track, using after_track_id /
                           before_track_id to place it within the itinerary,
                           then add the stop at the start of the new track.

    WHY A RETRY LOOP?
      Two concurrent requests might compute the same rank for the same anchor
      pair. The UNIQUE(track_id, rank) constraint catches this as an
      IntegrityError. We retry up to 3 times (re-fetching ranks each time)
      before giving up with 409. In practice collisions are extremely rare.
    """
    # Before the retry loop: a rank collision must not re-bill the moderation call.
    _moderate_itinerary_text(
        {"place_name": body.place_name, "place_address": body.place_address,
         "notes": body.notes},
        itinerary, db, _verified,
    )

    for attempt in range(3):
        try:
            if body.track_id is not None:
                # Add to an existing track.
                track = _get_track_or_404(body.track_id, itinerary_id, db)
                stop_rank = _resolve_stop_rank(
                    track, body.after_stop_id, body.before_stop_id, db
                )
            else:
                # Create a brand-new track at the computed position, then add
                # the first (and only) stop with rank "a0" — the initial key.
                track_rank = _resolve_track_rank(
                    itinerary_id, body.after_track_id, body.before_track_id, db
                )
                track = Track(itinerary_id=itinerary_id, rank=track_rank)
                db.add(track)
                db.flush()  # flush to get track.id before creating the stop
                stop_rank = key_between(None, None)  # "a0" — first key in empty range

            # Exclude the positioning fields — they're not columns on the stops table.
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
            break  # success — exit the retry loop

        except IntegrityError:
            db.rollback()
            if attempt == 2:
                raise ApiError(status_code=status.HTTP_409_CONFLICT,
                                    code="rank_collision", detail="Rank collision — please retry.")
            # The rank we computed collided with a concurrent insert at the same
            # anchor. Roll back, let the loop re-run _resolve_*_rank with fresh DB
            # state, which will now see the concurrent row and bisect around it.

    _recalculate_totals(itinerary, db)
    db.commit()
    db.refresh(stop)
    db.refresh(itinerary)  # refresh to get the new updated_at for the ETag

    # Return the new ETag so the client can immediately use it for the next mutation.
    return _etag_json_response(StopResponse, stop, itinerary,
                               status_code=status.HTTP_201_CREATED)


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
    # Same cached instance require_edit_access already resolved — no extra query.
    current_user: User = Depends(get_current_user),
    itinerary: Itinerary = Depends(require_edit_access),
) -> Response:
    stop = _get_stop_or_404(stop_id, itinerary_id, db)
    old_track_id = stop.track_id

    # Apply scalar field updates.
    scalar_fields = body.model_dump(exclude_unset=True, exclude={
        'track_id', 'after_stop_id', 'before_stop_id',
        'after_track_id', 'before_track_id',
    })
    _moderate_itinerary_text(
        {key: scalar_fields[key]
         for key in ("place_name", "place_address", "notes") if key in scalar_fields},
        itinerary, db, current_user,
    )
    for field, value in scalar_fields.items():
        setattr(stop, field, value)

    # Handle move / reorder.
    target_track_id = body.track_id
    new_track_created = False
    if (target_track_id is None
            and (body.after_track_id is not None or body.before_track_id is not None)):
        # New-track move: create a track at the requested position, place the
        # stop as its first (and only) member. _resolve_track_rank validates
        # the anchors belong to this itinerary (422 otherwise).
        new_track_rank = _resolve_track_rank(
            itinerary_id, body.after_track_id, body.before_track_id, db,
        )
        new_track = Track(itinerary_id=itinerary_id, rank=new_track_rank)
        db.add(new_track)
        db.flush()
        stop.track_id = new_track.id
        stop.rank = key_between(None, None)
        new_track_created = True
    elif (target_track_id is not None
            or body.after_stop_id is not None
            or body.before_stop_id is not None):
        effective_track_id = target_track_id or old_track_id
        track = _get_track_or_404(effective_track_id, itinerary_id, db)
        new_rank = _resolve_stop_rank(track, body.after_stop_id, body.before_stop_id, db)
        stop.track_id = track.id
        stop.rank = new_rank

    _recalculate_totals(itinerary, db)
    db.commit()

    # If source track is now empty, delete it. Applies to both the existing
    # cross-track move path and the new-track path.
    if (new_track_created and old_track_id != stop.track_id) or (
        target_track_id is not None and target_track_id != old_track_id
    ):
        _delete_track_if_empty(old_track_id, db)
        db.commit()

    db.refresh(stop)
    db.refresh(itinerary)

    return _etag_json_response(StopResponse, stop, itinerary)


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
    itinerary: Itinerary = Depends(require_edit_access),
) -> Response:
    stop = db.execute(
        select(Stop).where(Stop.id == stop_id, Stop.itinerary_id == itinerary_id)
    ).scalar_one_or_none()

    if not stop:
        raise ApiError(status_code=status.HTTP_404_NOT_FOUND,
                            code="stop_not_found", detail="Stop not found.")

    track_id = stop.track_id
    db.delete(stop)
    db.flush()

    _delete_track_if_empty(track_id, db)
    _recalculate_totals(itinerary, db)
    db.commit()
    db.refresh(itinerary)

    resp = Response(status_code=status.HTTP_204_NO_CONTENT)
    resp.headers["ETag"] = _etag_value(itinerary)
    return resp


# ---------------------------------------------------------------------------
# POST /itineraries/{itinerary_id}/reorder — Batch reorder (stops, tracks, segments)
# ---------------------------------------------------------------------------

@router.post("/{itinerary_id}/reorder", response_model=ItineraryDetail,
             summary="Batch reorder tracks and/or stops, plus optional segment deletions")
def reorder_itinerary(
    itinerary_id: uuid.UUID,
    body: ReorderRequest,
    request: Request,
    db: Session = Depends(get_db),
    itinerary: Itinerary = Depends(require_edit_access),
) -> Response:
    """
    Apply a batch reorder of stops within tracks, a new track order, and/or
    delete one or more segments, all in a single transaction.

    Client sends the new ORDER (list of ids); server computes the
    fractional-index ranks via n_keys_between. Keeps all ordering logic on
    the backend — no Dart port of key_between needed.

    Atomicity: everything is validated up front. Any validation failure
    raises before any writes; any IntegrityError during write rolls back the
    whole transaction.

    Two-phase write per rank rewrite avoids the UNIQUE constraint:
    phase 1 parks every row on a temp rank starting with '!' (ASCII 33,
    below every digit/letter key_between can produce), phase 2 assigns the
    final keys.
    """
    # ── Validate stop_orders ────────────────────────────────────────────────
    for track_id, stop_ids in body.stop_orders.items():
        track = db.execute(
            select(Track)
            .options(selectinload(Track.stops))
            .where(Track.id == track_id,
                   Track.itinerary_id == itinerary_id)
        ).scalar_one_or_none()
        if not track:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"track_id {track_id} does not belong to this itinerary.",
            )

        provided_set = set(stop_ids)
        if len(provided_set) != len(stop_ids):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"stop_orders[{track_id}] contains duplicate stop_ids.",
            )

        current_set = {s.id for s in track.stops}
        if provided_set != current_set:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=(
                    f"stop_orders[{track_id}] must contain exactly the "
                    "current stops of that track."
                ),
            )

    # ── Validate track_order ───────────────────────────────────────────────
    if body.track_order is not None:
        if len(set(body.track_order)) != len(body.track_order):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="track_order contains duplicate ids.",
            )
        current_track_ids = {
            t_id for (t_id,) in db.execute(
                select(Track.id).where(Track.itinerary_id == itinerary_id)
            ).all()
        }
        if set(body.track_order) != current_track_ids:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=(
                    "track_order must contain exactly the current tracks "
                    "of this itinerary."
                ),
            )

    # ── Validate segments_to_delete ────────────────────────────────────────
    for seg_id in body.segments_to_delete:
        seg = db.execute(
            select(TransitSegment).where(
                TransitSegment.id == seg_id,
                TransitSegment.itinerary_id == itinerary_id,
            )
        ).scalar_one_or_none()
        if not seg:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"segment {seg_id} does not belong to this itinerary.",
            )

    # ── Apply track_order via two-phase rank rewrite ───────────────────────
    if body.track_order is not None:
        _two_phase_renumber([db.get(Track, tid) for tid in body.track_order], db)

    # ── Apply stop_orders per-track two-phase rank rewrite ─────────────────
    for track_id, stop_ids in body.stop_orders.items():
        _two_phase_renumber([db.get(Stop, sid) for sid in stop_ids], db)

    # ── Delete segments (cascade-removes legs) ─────────────────────────────
    for seg_id in body.segments_to_delete:
        seg = db.get(TransitSegment, seg_id)
        if seg is not None:
            db.delete(seg)
    db.flush()

    _recalculate_totals(itinerary, db)
    db.commit()
    db.refresh(itinerary)

    detail = _load_itinerary_detail(itinerary_id, db)

    # ETag comes from the freshly reloaded detail, not the pre-commit itinerary.
    # can_edit is True by construction — the guard just let this caller write.
    return _etag_json_response(ItineraryDetail, detail, detail,
                               extra={"can_edit": True})


# ---------------------------------------------------------------------------
# Itinerary-level annotation endpoints
# ---------------------------------------------------------------------------

@router.post("/{itinerary_id}/annotations", response_model=ItineraryAnnotationResponse,
             status_code=status.HTTP_201_CREATED, summary="Add an annotation to an itinerary")
def add_itinerary_annotation(
    itinerary_id: uuid.UUID,
    body: ItineraryAnnotationCreate,
    request: Request,
    current_user: User = Depends(require_verified_email),  # high-value: verified email required
    db: Session = Depends(get_db),
    itinerary: Itinerary = Depends(require_edit_access),
) -> ItineraryAnnotationResponse:
    _moderate_itinerary_text({"content": body.content}, itinerary, db, current_user)
    annotation = ItineraryAnnotation(
        itinerary_id=itinerary_id,
        type=body.type,
        content=body.content,
    )
    return _save_annotation(annotation, itinerary, db)  # type: ignore[return-value]


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
    itinerary: Itinerary = Depends(require_edit_access),
) -> ItineraryAnnotationResponse:
    annotation = _get_itinerary_annotation_or_404(annotation_id, itinerary_id, db)
    _moderate_itinerary_text({"content": body.content}, itinerary, db, current_user)
    _apply_annotation_fields(annotation, body)
    return _save_annotation(annotation, itinerary, db)  # type: ignore[return-value]


@router.delete("/{itinerary_id}/annotations/{annotation_id}",
               status_code=status.HTTP_204_NO_CONTENT,
               summary="Delete an itinerary annotation")
def delete_itinerary_annotation(
    itinerary_id: uuid.UUID,
    annotation_id: uuid.UUID,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    itinerary: Itinerary = Depends(require_edit_access),
) -> None:
    annotation = _get_itinerary_annotation_or_404(annotation_id, itinerary_id, db)
    _delete_annotation(annotation, itinerary, db)


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
    current_user: User = Depends(require_verified_email),  # high-value: verified email required
    itinerary: Itinerary = Depends(require_edit_access),
) -> AnnotationResponse:
    stop = db.execute(
        select(Stop).where(Stop.id == stop_id, Stop.itinerary_id == itinerary_id)
    ).scalar_one_or_none()

    if not stop:
        raise ApiError(status_code=status.HTTP_404_NOT_FOUND,
                            code="stop_not_found", detail="Stop not found.")

    _moderate_itinerary_text({"content": body.content}, itinerary, db, current_user)
    annotation = Annotation(stop_id=stop_id, type=body.type, content=body.content)
    return _save_annotation(annotation, itinerary, db)  # type: ignore[return-value]


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
    itinerary: Itinerary = Depends(require_edit_access),
) -> None:
    annotation = _get_stop_annotation_or_404(annotation_id, stop_id, itinerary_id, db)
    _delete_annotation(annotation, itinerary, db)


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
    itinerary: Itinerary = Depends(require_edit_access),
) -> AnnotationResponse:
    annotation = _get_stop_annotation_or_404(annotation_id, stop_id, itinerary_id, db)
    _moderate_itinerary_text({"content": body.content}, itinerary, db, current_user)
    _apply_annotation_fields(annotation, body)
    return _save_annotation(annotation, itinerary, db)  # type: ignore[return-value]


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
    current_user: User = Depends(require_verified_email),  # high-value: verified email required
) -> RatingResponse:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_viewable(itinerary, current_user.id, db)

    existing = db.execute(
        select(ItineraryRating).where(
            ItineraryRating.itinerary_id == itinerary_id,
            ItineraryRating.user_id == current_user.id,
        )
    ).scalar_one_or_none()

    note = body.note.strip() if body.note else None
    if note == "":
        note = None

    # Ratings carry their own status: a stranger's abusive review must never
    # take down the itinerary owner's trip.
    ctx = moderate_or_422(
        db, get_settings(),
        target_type="rating",
        author=current_user,
        fields={"note": note},
        target_id=existing.id if existing else None,
    )

    # Only a first rating is news. This endpoint is an upsert, so without this
    # flag every star correction would re-notify the owner.
    is_first_rating = existing is None

    if existing:
        existing.stars = body.stars
        existing.safety_stars = body.safety_stars
        existing.experience_stars = body.experience_stars
        existing.accessibility_stars = body.accessibility_stars
        existing.family_friendly_stars = body.family_friendly_stars
        existing.crowdedness_stars = body.crowdedness_stars
        existing.note = note
        # Assigned, not escalated: an edited note is new content, so a rewritten
        # note that now passes clears the previous flag.
        existing.moderation_status = ctx.status
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
            crowdedness_stars=body.crowdedness_stars,
            note=note,
            moderation_status=ctx.status,
        )
        db.add(rating)

    db.flush()
    # A first-time rating is scanned before its row exists — point the decision
    # at it now so the moderator queue knows what it refers to.
    attach_target(ctx, rating.id)
    # A rating has no hidden_at column — HIDDEN_STATUSES already filters it out
    # of reads, so the status plus this escalation is the whole takedown.
    escalate_if_flagged(
        db, "rating", rating,
        escalate_flag=ctx.escalate, decision_id=ctx.decision_id,
    )
    recalculate_rating(itinerary, db)

    if is_first_rating:
        notification_service.notify(
            db,
            user_id=itinerary.user_id,
            type="itinerary_rated",
            actor=current_user,
            entity_type="itinerary",
            entity_id=itinerary.id,
        )

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
        raise ApiError(status_code=status.HTTP_404_NOT_FOUND,
                            code="rating_not_found", detail="You have not rated this itinerary.")

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
        raise ApiError(status_code=status.HTTP_404_NOT_FOUND,
                            code="rating_not_found", detail="You have not rated this itinerary.")

    return rating  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# POST/DELETE /itineraries/{itinerary_id}/save — Save / unsave (bookmark)
# User-scoped state (like ratings) — no If-Match; itinerary body is untouched.
# ---------------------------------------------------------------------------

@router.post("/{itinerary_id}/save", status_code=status.HTTP_204_NO_CONTENT,
             summary="Save (bookmark) an itinerary for the current user")
def save_itinerary(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    itinerary = _get_itinerary_or_404(itinerary_id, db)

    if itinerary.user_id == current_user.id:
        raise ApiError(status_code=status.HTTP_400_BAD_REQUEST,
                            code="cannot_save_own_itinerary", detail="You cannot save your own itinerary.")

    _require_viewable(itinerary, current_user.id, db)

    existing = db.get(SavedItinerary, (itinerary_id, current_user.id))
    if existing:
        return  # idempotent — re-saving is a no-op so an optimistic UI never errors

    db.add(SavedItinerary(itinerary_id=itinerary_id, user_id=current_user.id))
    # Below the idempotent early-return above, so a re-save never re-notifies.
    notification_service.notify(
        db,
        user_id=itinerary.user_id,
        type="itinerary_saved",
        actor=current_user,
        entity_type="itinerary",
        entity_id=itinerary.id,
    )
    db.commit()


@router.delete("/{itinerary_id}/save", status_code=status.HTTP_204_NO_CONTENT,
               summary="Unsave (remove bookmark) an itinerary for the current user")
def unsave_itinerary(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    # No existence/visibility check — users must be able to unsave itineraries
    # that were since deleted or made invisible to them.
    saved = db.get(SavedItinerary, (itinerary_id, current_user.id))
    if saved:
        db.delete(saved)
        db.commit()


@router.get("/{itinerary_id}/ratings", response_model=RatingsPageResponse,
            summary="Get the full ratings page for an itinerary")
def get_ratings_page(
    itinerary_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> RatingsPageResponse:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_viewable(itinerary, current_user.id, db)

    rows = db.execute(
        select(
            ItineraryRating.id,
            ItineraryRating.stars,
            ItineraryRating.safety_stars,
            ItineraryRating.experience_stars,
            ItineraryRating.accessibility_stars,
            ItineraryRating.family_friendly_stars,
            ItineraryRating.crowdedness_stars,
            ItineraryRating.note,
            ItineraryRating.updated_at,
            ItineraryRating.user_id,
            ItineraryRating.moderation_status.label("rating_moderation_status"),
            User.username,
            User.display_name,
            User.avatar_url,
            User.moderation_status.label("rater_moderation_status"),
        )
        .outerjoin(User, ItineraryRating.user_id == User.id)
        .where(
            ItineraryRating.itinerary_id == itinerary_id,
            # Moderated notes are visible to their own author only.
            *visible_rating_criteria(current_user.id),
        )
        .order_by(ItineraryRating.updated_at.desc())
    ).all()

    # Distribution is computed over ALL rows, before the block filter below: the
    # score is a fact about the itinerary, so hiding a blocked author's row must
    # not make the histogram (or rating_avg/rating_count) disagree per viewer.
    dist: dict[int, int] = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
    for row in rows:
        dist[row.stars] += 1

    distribution = RatingDistribution(
        five=dist[5], four=dist[4], three=dist[3], two=dist[2], one=dist[1]
    )

    # A review carries its author's name, avatar and prose — the last surface
    # where a blocked account was still fully visible on a third party's page.
    hidden_raters = set(blocked_user_ids(db, current_user.id))

    ratings = [
        RatingWithUser(
            score=row.stars,
            safety_score=row.safety_stars,
            experience_score=row.experience_stars,
            accessibility_score=row.accessibility_stars,
            family_friendly_score=row.family_friendly_stars,
            crowdedness_score=row.crowdedness_stars,
            note=row.note,
            updated_at=row.updated_at,
            id=row.id,
            # Only the author learns their own review's state; everyone else's
            # row reads 'approved' so no internal status leaks sideways.
            moderation_status=(
                row.rating_moderation_status
                if row.user_id == current_user.id else "approved"
            ),
            user=RaterInfo(
                user_id=row.user_id,
                username=row.username,
                display_name=(
                    row.display_name
                    if row.rater_moderation_status not in HIDDEN_STATUSES
                    or row.user_id == current_user.id
                    else None
                ),
                avatar_url=row.avatar_url,
            ),
        )
        for row in rows
        if row.user_id not in hidden_raters
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
    current_user: User = Depends(require_verified_email),  # high-value: verified email required
    itinerary: Itinerary = Depends(require_edit_access),
) -> TransitSegmentResponse:
    _require_stops_in_itinerary(itinerary_id, body.from_stop_id, body.to_stop_id, db)

    _moderate_itinerary_text(_leg_text_fields(body.legs), itinerary, db, current_user)

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
        raise ApiError(status_code=status.HTTP_409_CONFLICT,
                            code="segment_already_exists", detail="A segment between these two stops already exists.")

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
    _require_viewable(itinerary, current_user.id, db)

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
    itinerary: Itinerary = Depends(require_edit_access),
) -> TransitSegmentResponse:
    segment = _get_segment_or_404(segment_id, itinerary_id, db)

    _require_stops_in_itinerary(itinerary_id, body.from_stop_id, body.to_stop_id, db)

    _moderate_itinerary_text(_leg_text_fields(body.legs), itinerary, db, current_user)

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
        raise ApiError(status_code=status.HTTP_409_CONFLICT,
                            code="segment_already_exists", detail="A segment between these two stops already exists.")

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
    itinerary: Itinerary = Depends(require_edit_access),
) -> None:
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
    current_user: User = Depends(require_verified_email),  # high-value: verified email required
    itinerary: Itinerary = Depends(require_edit_access),
) -> TransportLegResponse:
    segment = _get_segment_or_404(segment_id, itinerary_id, db)

    _moderate_itinerary_text(_leg_text_fields([body]), itinerary, db, current_user)

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
    itinerary: Itinerary = Depends(require_edit_access),
) -> TransportLegResponse:
    segment = _get_segment_or_404(segment_id, itinerary_id, db)
    leg = _get_leg_or_404(leg_id, segment_id, db)

    update_data = body.model_dump(exclude_unset=True)
    _moderate_itinerary_text(
        {key: update_data[key]
         for key in ("line", "direction", "notes") if key in update_data},
        itinerary, db, current_user,
    )
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
    itinerary: Itinerary = Depends(require_edit_access),
) -> None:
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
    current_user: User = Depends(require_verified_email),  # high-value: verified email required
) -> ItineraryImageResponse:
    itinerary = _get_itinerary_or_404(itinerary_id, db)
    _require_owner(itinerary, current_user)

    raw_bytes = await file.read()

    key = f"itineraries/{itinerary_id}.jpg"
    moderation = ModerationContext(
        db=db, settings=get_settings(), target_kind="itinerary_cover",
        uploader=current_user, storage_key=key, itinerary_id=itinerary.id,
    )
    try:
        # No cache-bust here: itinerary covers have never carried a ?v= suffix.
        public_url = await process_and_store(
            raw_bytes, key, process_cover_image, cache_bust=False,
            moderation=moderation)
    except ImageProcessingError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    except ModerationRejectedError:
        # Rejected content was never stored; the audit row was already committed.
        raise ApiError(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            code="image_moderation_rejected",
            detail="This image appears to contain prohibited content and was not uploaded.",
        )

    itinerary.cover_image_url = public_url
    # 'error_allowed' (AWS was down) → needs later review; else mirror the scan.
    itinerary.moderation_status = (
        "pending" if moderation.action == "error_allowed" else moderation.action
    )
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
    itinerary.moderation_status = "approved"  # no cover → nothing to moderate
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
    get_active_user_or_404(db, user_id)  # 404 if the target doesn't exist
    # can_view_itinerary would already return an empty list across a block;
    # 404ing matches the profile endpoint so nothing confirms the account exists.
    require_not_blocked_or_404(db, current_user.id, user_id)

    itineraries = db.execute(
        select(Itinerary)
        .where(Itinerary.user_id == user_id)
        .order_by(Itinerary.created_at.desc())
    ).scalars().all()

    return [
        i for i in itineraries
        if can_view_itinerary(i, current_user.id, db)
    ]  # type: ignore[return-value]
