"""
services/itinerary_access.py — Single source of truth for itinerary visibility logic.

Every read endpoint that needs to check whether a viewer can see an itinerary
calls can_view_itinerary(). Logic is never duplicated inline in routers.

Visibility rules:
  public      — any authenticated user can view
  followers   — owner + users who follow the owner (status=accepted)
  restricted  — owner + users explicitly listed in itinerary_allowed_users
  only_me     — owner only

can_edit_itinerary() answers the write-side question and is built on top of
can_view_itinerary(), so edit rights can never outlive view rights.
"""

import uuid

from sqlalchemy.orm import Session
from sqlalchemy import func, or_, select

from app.models.itinerary import Itinerary
from app.models.itinerary_allowed_user import ItineraryAllowedUser
from app.models.itinerary_editor import ItineraryEditor
from app.models.itinerary_rating import ItineraryRating
from app.models.user import User
from app.services.user_service import is_accepted_follower


def public_listing_criteria(db: Session | None = None,
                            viewer_id: uuid.UUID | None = None) -> list:
    """SQLAlchemy WHERE clauses that hide moderator-affected itineraries from
    public/other-user list queries. Caller MUST join `User` (the owner) so the
    banned-owner clause resolves. Keep in lock-step with can_view_itinerary so a
    row-level check and a query-level filter can never disagree.

    Pass `db` and `viewer_id` to also exclude blocked users — omitted only for
    call sites with no viewer (there are none today; the defaults exist so an
    older caller cannot silently lose the moderation clauses)."""
    criteria = [
        Itinerary.deleted_at.is_(None),   # soft-deleted → gone for everyone
        Itinerary.hidden_at.is_(None),    # moderator-hidden → owner-only
        User.is_active.is_(True),         # banned owner → all their content hidden
    ]
    if db is not None and viewer_id is not None:
        from app.services.block_service import blocked_user_ids

        hidden_authors = blocked_user_ids(db, viewer_id)
        if hidden_authors:
            criteria.append(Itinerary.user_id.notin_(hidden_authors))
    return criteria


# Content states that hide a record from everyone but its author. 'pending' and
# 'flagged' stay visible on purpose: they are internal states, and announcing a
# review that may come to nothing helps nobody.
HIDDEN_STATUSES = ("hidden", "rejected")


def visible_rating_criteria(viewer_id: uuid.UUID | None) -> list:
    """WHERE clauses hiding moderated review notes from everyone but their
    author. Ratings carry their own status rather than rolling up to the
    itinerary — a stranger's abusive review must not take down the owner's trip.

    Keep in lock-step with recalculate_rating, which applies the same filter to
    the averages: a hidden rating is excluded from every read path, aggregates
    included."""
    visible = ItineraryRating.moderation_status.notin_(HIDDEN_STATUSES)
    if viewer_id is None:
        return [visible]
    return [or_(visible, ItineraryRating.user_id == viewer_id)]


def can_view_itinerary(
    itinerary: Itinerary,
    viewer_id: uuid.UUID,
    db: Session,
) -> bool:
    """
    Returns True if viewer_id is allowed to see this itinerary.

    Moderation state is checked first: a soft-deleted itinerary is invisible to
    everyone (including the owner); a hidden one or a banned owner's content is
    invisible to everyone except the owner. Only then does the owner short-circuit
    and the visibility ladder apply.
    """
    # Soft-deleted → invisible to everyone, owner included (evidence preserved).
    if itinerary.deleted_at is not None:
        return False

    # Owner always has access to their own live/hidden content (they're active —
    # a banned user can't authenticate to become a viewer in the first place).
    if itinerary.user_id == viewer_id:
        return True

    # Moderator-hidden → owner-only (handled above); everyone else is denied.
    if itinerary.hidden_at is not None:
        return False

    # Either party blocking the other hides the content both ways — a one-sided
    # block would let the blocked user keep reading someone who asked to be left
    # alone. Imported lazily: block_service imports user_service, which this
    # module also imports.
    from app.services.block_service import is_blocked_either_way

    if is_blocked_either_way(db, viewer_id, itinerary.user_id):
        return False

    # Banned owner → hide all their content from other viewers until unbanned.
    owner = db.get(User, itinerary.user_id)
    if owner is not None and not owner.is_active:
        return False

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


def can_edit_itinerary(
    itinerary: Itinerary,
    editor_id: uuid.UUID,
    db: Session,
) -> bool:
    """
    Returns True if editor_id may modify this itinerary and its subcontent.

    Editing is a layer on top of visibility, never a parallel ladder: the view
    check runs first and unmodified, so a block, a visibility change, a
    moderator hide, a banned owner or a soft delete revokes editing the moment
    it revokes viewing — with no rows to clean up. That is why this delegates
    rather than re-deriving anything; there is one access ladder, not two.

    Holding the edit lock is a separate question answered on the write path —
    this only answers whether the person is allowed to hold it at all.
    """
    if not can_view_itinerary(itinerary, editor_id, db):
        return False

    if itinerary.user_id == editor_id:
        return True

    granted = db.execute(
        select(ItineraryEditor).where(
            ItineraryEditor.itinerary_id == itinerary.id,
            ItineraryEditor.user_id == editor_id,
        )
    ).scalar_one_or_none()
    return granted is not None


def recalculate_rating(itinerary: Itinerary, db: Session) -> None:
    """
    Recomputes rating_avg and rating_count from the itinerary_ratings table
    and writes them back to the itinerary row.

    Call this after every ItineraryRating insert, update, or delete — and after
    any change to a rating's moderation_status, since hidden ratings are
    excluded here too. The aggregate is a read path, so "hidden content is
    excluded from all read paths" applies to it.

    The caller is responsible for committing the session.
    """
    row = db.execute(
        select(
            func.count(ItineraryRating.id).label("cnt"),
            func.avg(ItineraryRating.stars).label("avg"),
        ).where(
            ItineraryRating.itinerary_id == itinerary.id,
            # No viewer here: an aggregate is public, so even the author's own
            # hidden rating must not move the number others see.
            *visible_rating_criteria(None),
        )
    ).one()

    itinerary.rating_count = row.cnt or 0
    itinerary.rating_avg = float(row.avg) if row.avg is not None else None
