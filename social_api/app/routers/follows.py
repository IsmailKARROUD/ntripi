"""
routers/follows.py — Follow/unfollow, follow requests, and follower/following lists.

All routes require Bearer token authentication.

This file implements the hybrid follow model:
  - Following a public account → immediately accepted.
  - Following a private account → pending until approved.
  - Rejecting a request → delete the record (allows retry).
  - Switching to public → auto-accept all pending requests.

Counter invariant:
  followers_count and following_count are ONLY incremented when a follow
  transitions to 'accepted' status, and ONLY decremented when an 'accepted'
  follow is deleted. Pending requests have no effect on counters.

Security note on follow request routes:
  When accepting/rejecting a follow request, we verify that the
  follow_id's following_id == current_user.id. This prevents a user
  from accepting/rejecting someone else's requests.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user, require_verified_email
from app.models.follow import Follow, FollowStatus
from app.models.user import User
from app.schemas.follow import FollowRequestItem, FollowResponse, FollowerListItem
from app.services import block_service, notification_service
from app.services.user_service import (
    bump_follow_counters,
    get_active_user_or_404,
    get_follow,
    is_accepted_follower,
    public_profile_text,
)
from app.errors import ApiError

router = APIRouter(tags=["Follows"])


def _require_follow_list_access(target_user: User, current_user: User,
                                db: Session) -> None:
    # Private accounts only expose their follower/following lists to the owner
    # and to accepted followers; everyone else is denied.
    if target_user.is_private and target_user.id != current_user.id:
        if not is_accepted_follower(db, current_user.id, target_user.id):
            raise ApiError(
                status_code=status.HTTP_403_FORBIDDEN,
                code="account_private", detail="This account is private.",
            )


def _users_as_list_items(user_ids: list[uuid.UUID], db: Session,
                         viewer_id: uuid.UUID | None = None) -> list[FollowerListItem]:
    results = []
    for uid in user_ids:
        user = db.get(User, uid)
        if user:
            results.append(
                FollowerListItem(
                    id=user.id,
                    username=user.username,
                    display_name=public_profile_text(user, viewer_id)[0],
                    avatar_url=user.avatar_url,
                    is_private=user.is_private,
                )
            )
    return results


# ---------------------------------------------------------------------------
# POST /users/{user_id}/follow — Follow a user
# ---------------------------------------------------------------------------

@router.post(
    "/users/{user_id}/follow",
    response_model=FollowResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Follow a user",
)
def follow_user(
    user_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_verified_email),  # high-value: verified email required
) -> FollowResponse:
    """
    Hybrid follow logic:
      - Target is public → create Follow with status='accepted', update counters.
      - Target is private → create Follow with status='pending', NO counter update.

    Returns 409 if a follow relationship (pending or accepted) already exists.
    Returns 400 if the user tries to follow themselves.
    """
    if user_id == current_user.id:
        raise ApiError(
            status_code=status.HTTP_400_BAD_REQUEST,
            code="cannot_follow_self", detail="You cannot follow yourself.",
        )

    target_user = get_active_user_or_404(db, user_id)

    # A block hides the target as if the account were gone, so following must
    # 404 identically — anything else would confirm the block exists.
    if block_service.is_blocked_either_way(db, current_user.id, user_id):
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="user_not_found", detail="User not found.",
        )

    # Check if a follow record already exists (either pending or accepted).
    existing = get_follow(db, current_user.id, user_id)

    if existing:
        # Give a descriptive message based on the current status.
        if existing.status == FollowStatus.accepted:
            detail = "You are already following this user."
        else:
            detail = "You already have a pending follow request to this user."
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=detail)

    # Determine the initial status based on the target's privacy setting.
    if target_user.is_private:
        initial_status = FollowStatus.pending
    else:
        initial_status = FollowStatus.accepted

    new_follow = Follow(
        follower_id=current_user.id,
        following_id=user_id,
        status=initial_status,
    )
    db.add(new_follow)
    db.flush()  # need new_follow.id for the notification's entity reference

    # Only update counters if the follow is immediately accepted.
    if initial_status == FollowStatus.accepted:
        bump_follow_counters(current_user, target_user, 1)

    # Same transaction as the Follow row: a request the recipient is never told
    # about is a request they can never answer.
    notification_service.notify(
        db,
        user_id=target_user.id,
        type=(
            "follow_request"
            if initial_status == FollowStatus.pending
            else "new_follower"
        ),
        actor=current_user,
        entity_type="follow",
        entity_id=new_follow.id,
    )

    db.commit()
    db.refresh(new_follow)
    return new_follow  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# DELETE /users/{user_id}/follow — Unfollow or cancel a pending request
# ---------------------------------------------------------------------------

@router.delete(
    "/users/{user_id}/follow",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Unfollow a user or cancel a pending follow request",
)
def unfollow_user(
    user_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    """
    Delete the follow record between current_user and the target.

    Counter logic:
      - If the deleted record was 'accepted' → decrement both counters.
      - If the deleted record was 'pending' → leave counters unchanged
        (they were never incremented for a pending follow).
    """
    follow = get_follow(db, current_user.id, user_id)

    if not follow:
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="not_following", detail="You are not following this user.",
        )

    was_accepted = follow.status == FollowStatus.accepted
    db.delete(follow)

    if was_accepted:
        bump_follow_counters(current_user, db.get(User, user_id), -1)

    db.commit()


# ---------------------------------------------------------------------------
# GET /users/me/follow-requests — List pending incoming requests
# ---------------------------------------------------------------------------

@router.get(
    "/users/me/follow-requests",
    response_model=list[FollowRequestItem],
    summary="List pending follow requests for the current user",
)
def list_follow_requests(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[FollowRequestItem]:
    """
    Return all pending follow requests where the current user is the target.
    The requester's username, display_name, and avatar_url are included
    so the client can render each request without a second API call.
    """
    pending_follows = db.execute(
        select(Follow).where(
            Follow.following_id == current_user.id,
            Follow.status == FollowStatus.pending,
        )
    ).scalars().all()

    results = []
    for follow in pending_follows:
        follower = db.get(User, follow.follower_id)
        if follower:
            results.append(
                FollowRequestItem(
                    follow_id=follow.id,
                    follower_id=follow.follower_id,
                    username=follower.username,
                    display_name=public_profile_text(follower, current_user.id)[0],
                    avatar_url=follower.avatar_url,
                    requested_at=follow.created_at,
                )
            )
    return results


# ---------------------------------------------------------------------------
# POST /users/me/follow-requests/{follow_id}/accept — Accept a request
# ---------------------------------------------------------------------------

@router.post(
    "/users/me/follow-requests/{follow_id}/accept",
    response_model=FollowResponse,
    summary="Accept a pending follow request",
)
def accept_follow_request(
    follow_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> FollowResponse:
    """
    Accept a specific pending follow request.

    Security: we verify that this follow request is actually targeting
    the current user (following_id == current_user.id). Without this check,
    a malicious user could accept or reject requests on behalf of others.
    """
    follow = db.get(Follow, follow_id)

    if not follow:
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="follow_request_not_found", detail="Follow request not found.",
        )

    # Security check: only the target user can accept.
    # Return 404 (not 403) to avoid leaking the existence of other users' requests.
    if follow.following_id != current_user.id:
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="follow_request_not_found", detail="Follow request not found.",
        )

    if follow.status != FollowStatus.pending:
        raise ApiError(
            status_code=status.HTTP_400_BAD_REQUEST,
            code="follow_request_already_accepted", detail="This follow request has already been accepted.",
        )

    # Accept the request and update counters.
    follow.status = FollowStatus.accepted

    bump_follow_counters(db.get(User, follow.follower_id), current_user, 1)

    notification_service.notify(
        db,
        user_id=follow.follower_id,
        type="follow_accepted",
        actor=current_user,
        entity_type="user",
        entity_id=current_user.id,
    )

    db.commit()
    db.refresh(follow)
    return follow  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# DELETE /users/me/follow-requests/{follow_id} — Reject a request
# ---------------------------------------------------------------------------

@router.delete(
    "/users/me/follow-requests/{follow_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Reject a pending follow request",
)
def reject_follow_request(
    follow_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    """
    Reject (delete) a pending follow request.

    We delete the record entirely rather than setting a 'rejected' status.
    This lets the requester try again in the future without obstruction.
    No counters to update — pending requests don't affect counters.
    """
    follow = db.get(Follow, follow_id)

    if not follow:
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="follow_request_not_found", detail="Follow request not found.",
        )

    # Security check.
    if follow.following_id != current_user.id:
        raise ApiError(
            status_code=status.HTTP_403_FORBIDDEN,
            code="cannot_reject_request", detail="You cannot reject this follow request.",
        )

    db.delete(follow)
    db.commit()


# ---------------------------------------------------------------------------
# GET /users/{user_id}/followers — List accepted followers
# ---------------------------------------------------------------------------

@router.get(
    "/users/{user_id}/followers",
    response_model=list[FollowerListItem],
    summary="List a user's followers",
)
def list_followers(
    user_id: uuid.UUID,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[FollowerListItem]:
    """
    Return a paginated list of accepted followers for the target user.

    Privacy rules:
      If the target user is private, only:
        - the target user themselves
        - accepted followers of the target
      ...can see the followers list.
      Everyone else gets 403.
    """
    target_user = get_active_user_or_404(db, user_id)
    block_service.require_not_blocked_or_404(db, current_user.id, user_id)

    _require_follow_list_access(target_user, current_user, db)

    # Blocked accounts must not surface in a third party's list either. Filtered
    # in the query rather than after, or limit/offset would return short pages.
    hidden = block_service.blocked_user_ids(db, current_user.id)

    # Get accepted followers.
    follows = db.execute(
        select(Follow).where(
            Follow.following_id == user_id,
            Follow.status == FollowStatus.accepted,
            *([Follow.follower_id.notin_(hidden)] if hidden else []),
        )
        .limit(limit)
        .offset(offset)
    ).scalars().all()

    return _users_as_list_items([f.follower_id for f in follows], db, current_user.id)


# ---------------------------------------------------------------------------
# GET /users/{user_id}/following — List who the user follows
# ---------------------------------------------------------------------------

@router.get(
    "/users/{user_id}/following",
    response_model=list[FollowerListItem],
    summary="List who a user follows",
)
def list_following(
    user_id: uuid.UUID,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[FollowerListItem]:
    """
    Return a paginated list of users that the target user follows.
    Same privacy rules as the followers list.
    """
    target_user = get_active_user_or_404(db, user_id)
    block_service.require_not_blocked_or_404(db, current_user.id, user_id)

    # Privacy check: same logic as list_followers.
    _require_follow_list_access(target_user, current_user, db)

    hidden = block_service.blocked_user_ids(db, current_user.id)

    follows = db.execute(
        select(Follow).where(
            Follow.follower_id == user_id,
            Follow.status == FollowStatus.accepted,
            *([Follow.following_id.notin_(hidden)] if hidden else []),
        )
        .limit(limit)
        .offset(offset)
    ).scalars().all()

    return _users_as_list_items([f.following_id for f in follows], db, current_user.id)
