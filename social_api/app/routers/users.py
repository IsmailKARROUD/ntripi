"""
routers/users.py — User profile endpoints.

Route prefix: /users
All routes require Bearer token authentication (Depends(get_current_user)).

Endpoints:
  GET  /users/me              → own full profile (includes email)
  PATCH /users/me             → partial update own profile
  GET  /users/search?q=...    → search users by username or display_name
  GET  /users/{user_id}       → public profile of any user (with follow status)
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select, or_, func
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models.follow import Follow, FollowStatus
from app.models.user import User
from app.schemas.user import (
    UserPrivateProfile,
    UserPublicProfile,
    UserSearchResult,
    UserUpdateRequest,
)

router = APIRouter(prefix="/users", tags=["Users"])


@router.get(
    "/me",
    response_model=UserPrivateProfile,
    summary="Get the current user's full profile",
)
def get_my_profile(
    current_user: User = Depends(get_current_user),
) -> UserPrivateProfile:
    """
    Return the authenticated user's own profile, including email.
    This is the only endpoint that exposes the email address.
    """
    return current_user  # type: ignore[return-value]
    # Pydantic's from_attributes mode converts the ORM object automatically.


@router.patch(
    "/me",
    response_model=UserPrivateProfile,
    summary="Update the current user's profile",
)
def update_my_profile(
    payload: UserUpdateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> UserPrivateProfile:
    """
    Partial update of the authenticated user's profile.

    Only fields present in the request body are updated.
    If is_private switches from True → False, all pending follow requests
    are automatically accepted (with counter updates).
    """
    # Determine if we're switching from private to public.
    # This must be detected BEFORE we update the user record.
    switching_to_public = (
        payload.is_private is not None
        and not payload.is_private   # new value is False (public)
        and current_user.is_private  # current value is True (private)
    )

    # Apply only the provided fields (partial update pattern).
    update_data = payload.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(current_user, field, value)

    # Handle the private → public transition.
    # Auto-accept all pending follow requests targeting this user.
    if switching_to_public:
        pending_follows = db.execute(
            select(Follow).where(
                Follow.following_id == current_user.id,
                Follow.status == FollowStatus.pending,
            )
        ).scalars().all()

        for follow in pending_follows:
            follow.status = FollowStatus.accepted
            # Update counters for each newly accepted follower.
            # The follower's following_count goes up, our followers_count goes up.
            follower = db.get(User, follow.follower_id)
            if follower:
                follower.following_count = func.greatest(0, follower.following_count + 1)
            current_user.followers_count = func.greatest(0, current_user.followers_count + 1)

    db.commit()
    db.refresh(current_user)
    return current_user  # type: ignore[return-value]


@router.get(
    "/search",
    response_model=list[UserSearchResult],
    summary="Search users by username or display name",
)
def search_users(
    q: str = Query(..., min_length=1, description="Search query"),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[UserSearchResult]:
    """
    Case-insensitive search on username OR display_name.

    Results are:
      - Ordered by followers_count DESC (most popular first)
      - The current user is excluded from results
      - Paginated via limit/offset

    ILIKE: PostgreSQL's case-insensitive LIKE. % wildcard matches any sequence.
    Using %query% means the query can appear anywhere in the field.
    """
    search_term = f"%{q}%"

    results = db.execute(
        select(User)
        .where(
            User.id != current_user.id,  # Exclude self
            User.is_active == True,
            or_(
                User.username.ilike(search_term),
                User.display_name.ilike(search_term),
            ),
        )
        .order_by(User.followers_count.desc())
        .limit(limit)
        .offset(offset)
    ).scalars().all()

    return results  # type: ignore[return-value]


@router.get(
    "/{user_id}",
    response_model=UserPublicProfile,
    summary="Get a user's public profile",
)
def get_user_profile(
    user_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> UserPublicProfile:
    """
    Return a user's public profile with follow-status context.

    The response includes two computed fields:
      is_following: True if the current user has an ACCEPTED follow to this user.
      follow_is_pending: True if the current user has a PENDING follow request.

    These are computed by querying the follows table for the relationship
    between current_user and the target user.
    """
    target_user = db.get(User, user_id)
    if not target_user or not target_user.is_active:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found.",
        )

    # Look up the follow relationship from current_user → target_user.
    follow_record = db.execute(
        select(Follow).where(
            Follow.follower_id == current_user.id,
            Follow.following_id == target_user.id,
        )
    ).scalar_one_or_none()

    is_following = (
        follow_record is not None and follow_record.status == FollowStatus.accepted
    )
    follow_is_pending = (
        follow_record is not None and follow_record.status == FollowStatus.pending
    )

    # Build the response manually because is_following and follow_is_pending
    # are not columns on the User ORM model — they're computed here.
    return UserPublicProfile(
        id=target_user.id,
        username=target_user.username,
        display_name=target_user.display_name,
        bio=target_user.bio,
        avatar_url=target_user.avatar_url,
        is_private=target_user.is_private,
        followers_count=target_user.followers_count,
        following_count=target_user.following_count,
        created_at=target_user.created_at,
        is_following=is_following,
        follow_is_pending=follow_is_pending,
    )
