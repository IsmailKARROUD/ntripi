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
from app.dependencies import get_current_user
from app.models.follow import Follow, FollowStatus
from app.models.user import User
from app.schemas.follow import FollowRequestItem, FollowResponse, FollowerListItem

router = APIRouter(tags=["Follows"])


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
    current_user: User = Depends(get_current_user),
) -> FollowResponse:
    """
    Hybrid follow logic:
      - Target is public → create Follow with status='accepted', update counters.
      - Target is private → create Follow with status='pending', NO counter update.

    Returns 409 if a follow relationship (pending or accepted) already exists.
    Returns 400 if the user tries to follow themselves.
    """
    if user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You cannot follow yourself.",
        )

    target_user = db.get(User, user_id)
    if not target_user or not target_user.is_active:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found.",
        )

    # Check if a follow record already exists (either pending or accepted).
    existing = db.execute(
        select(Follow).where(
            Follow.follower_id == current_user.id,
            Follow.following_id == user_id,
        )
    ).scalar_one_or_none()

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

    # Only update counters if the follow is immediately accepted.
    if initial_status == FollowStatus.accepted:
        current_user.following_count = max(0, current_user.following_count + 1)
        target_user.followers_count = max(0, target_user.followers_count + 1)

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
    follow = db.execute(
        select(Follow).where(
            Follow.follower_id == current_user.id,
            Follow.following_id == user_id,
        )
    ).scalar_one_or_none()

    if not follow:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="You are not following this user.",
        )

    was_accepted = follow.status == FollowStatus.accepted
    db.delete(follow)

    if was_accepted:
        unfollowed_user = db.get(User, user_id)
        current_user.following_count = max(0, current_user.following_count - 1)
        if unfollowed_user:
            unfollowed_user.followers_count = max(0, unfollowed_user.followers_count - 1)

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
                    display_name=follower.display_name,
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
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Follow request not found.",
        )

    # Security check: only the target user can accept.
    # Return 404 (not 403) to avoid leaking the existence of other users' requests.
    if follow.following_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Follow request not found.",
        )

    if follow.status != FollowStatus.pending:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This follow request has already been accepted.",
        )

    # Accept the request and update counters.
    follow.status = FollowStatus.accepted

    requester = db.get(User, follow.follower_id)
    if requester:
        requester.following_count = max(0, requester.following_count + 1)
    current_user.followers_count = max(0, current_user.followers_count + 1)

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
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Follow request not found.",
        )

    # Security check.
    if follow.following_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You cannot reject this follow request.",
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
    target_user = db.get(User, user_id)
    if not target_user or not target_user.is_active:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")

    # Check privacy access.
    if target_user.is_private and target_user.id != current_user.id:
        # Is the current user an accepted follower?
        follow_check = db.execute(
            select(Follow).where(
                Follow.follower_id == current_user.id,
                Follow.following_id == target_user.id,
                Follow.status == FollowStatus.accepted,
            )
        ).scalar_one_or_none()

        if not follow_check:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="This account is private.",
            )

    # Get accepted followers.
    follows = db.execute(
        select(Follow).where(
            Follow.following_id == user_id,
            Follow.status == FollowStatus.accepted,
        )
        .limit(limit)
        .offset(offset)
    ).scalars().all()

    results = []
    for follow in follows:
        follower = db.get(User, follow.follower_id)
        if follower:
            results.append(
                FollowerListItem(
                    id=follower.id,
                    username=follower.username,
                    display_name=follower.display_name,
                    avatar_url=follower.avatar_url,
                    is_private=follower.is_private,
                )
            )
    return results


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
    target_user = db.get(User, user_id)
    if not target_user or not target_user.is_active:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")

    # Privacy check: same logic as list_followers.
    if target_user.is_private and target_user.id != current_user.id:
        follow_check = db.execute(
            select(Follow).where(
                Follow.follower_id == current_user.id,
                Follow.following_id == target_user.id,
                Follow.status == FollowStatus.accepted,
            )
        ).scalar_one_or_none()

        if not follow_check:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="This account is private.",
            )

    follows = db.execute(
        select(Follow).where(
            Follow.follower_id == user_id,
            Follow.status == FollowStatus.accepted,
        )
        .limit(limit)
        .offset(offset)
    ).scalars().all()

    results = []
    for follow in follows:
        followed_user = db.get(User, follow.following_id)
        if followed_user:
            results.append(
                FollowerListItem(
                    id=followed_user.id,
                    username=followed_user.username,
                    display_name=followed_user.display_name,
                    avatar_url=followed_user.avatar_url,
                    is_private=followed_user.is_private,
                )
            )
    return results
