"""
services/itinerary_access.py — Single source of truth for itinerary visibility logic.

Every read endpoint that needs to check whether a viewer can see an itinerary
calls can_view_itinerary(). Logic is never duplicated inline in routers.

Visibility rules:
  public      — any authenticated user can view
  followers   — owner + users who follow the owner (status=accepted)
  restricted  — owner + users explicitly listed in itinerary_allowed_users
  only_me     — owner only
"""

import uuid

from sqlalchemy.orm import Session
from sqlalchemy import func, select

from app.models.itinerary import Itinerary
from app.models.itinerary_allowed_user import ItineraryAllowedUser
from app.models.itinerary_rating import ItineraryRating
from app.services.user_service import is_accepted_follower


def can_view_itinerary(
    itinerary: Itinerary,
    viewer_id: uuid.UUID,
    db: Session,
) -> bool:
    """
    Returns True if viewer_id is allowed to see this itinerary.

    The owner check runs first, before the visibility check, so owners always
    have access regardless of visibility setting.
    """
    # Owner always has access.
    if itinerary.user_id == viewer_id:
        return True

    visibility = itinerary.visibility

    if visibility == 'public':
        return True

    if visibility == 'followers':
        return is_accepted_follower(db, viewer_id, itinerary.user_id)

    if visibility == 'restricted':
        allowed = db.execute(
            select(ItineraryAllowedUser).where(
                ItineraryAllowedUser.itinerary_id == itinerary.id,
                ItineraryAllowedUser.user_id == viewer_id,
            )
        ).scalar_one_or_none()
        return allowed is not None

    # only_me — owner already passed above, so deny everyone else.
    return False


def recalculate_rating(itinerary: Itinerary, db: Session) -> None:
    """
    Recomputes rating_avg and rating_count from the itinerary_ratings table
    and writes them back to the itinerary row.

    Call this after every ItineraryRating insert, update, or delete.
    The caller is responsible for committing the session.
    """
    row = db.execute(
        select(
            func.count(ItineraryRating.id).label("cnt"),
            func.avg(ItineraryRating.stars).label("avg"),
        ).where(ItineraryRating.itinerary_id == itinerary.id)
    ).one()

    itinerary.rating_count = row.cnt or 0
    itinerary.rating_avg = float(row.avg) if row.avg is not None else None
