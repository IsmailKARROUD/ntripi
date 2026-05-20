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
from sqlalchemy import select, or_, update
from sqlalchemy.orm import Session
from starlette.requests import Request

from app.database import get_db
from app.dependencies import get_current_user
from app.limiter import limiter
from app.models.follow import Follow, FollowStatus
from app.models.itinerary_rating import ItineraryRating
from app.models.user import User
from app.schemas.user import (
    DeleteAccountRequest,
    UserPrivateProfile,
    UserPublicProfile,
    UserSearchResult,
    UserUpdateRequest,
)
from app.services.auth import verify_password

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
            follower = db.get(User, follow.follower_id)
            if follower:
                follower.following_count = max(0, follower.following_count + 1)
            current_user.followers_count = max(0, current_user.followers_count + 1)

    db.commit()
    db.refresh(current_user)
    return current_user  # type: ignore[return-value]


@router.delete(
    "/me",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Permanently delete the current user's account",
)
def delete_my_account(
    payload: DeleteAccountRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    """
    Permanently delete the authenticated user's account.

    Steps (order is critical):

    1. Re-verify password — prevents accidental or unauthorized deletion.

    2. Decrement denormalized follow counters on other users BEFORE the
       cascade delete removes the follow rows and we lose the information.
         - Users that current_user follows: their followers_count -= 1
         - Users that follow current_user: their following_count -= 1

    3. Anonymize ratings: SET user_id = NULL on all rating rows belonging
       to this user. This makes them GDPR-compliant anonymous community data.
       We do this explicitly (not relying solely on ON DELETE SET NULL) so
       the intent is clear to future developers.

    4. Delete the user row. Cascade handles: itineraries, stops, annotations,
       allowlist entries, follow rows, and any remaining non-anonymized data.

    Token invalidation: get_current_user fetches the user from the DB on
    every request. With the user row gone, it returns None and raises 401.
    No token blacklist is needed.
    """
    # Step 1 — re-verify password.
    if not verify_password(payload.password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect password.",
        )

    # Step 2 — fix denormalized follow counters on other users.
    # Users that current_user follows (accepted): they lose a follower.
    following_ids = db.execute(
        select(Follow.following_id).where(
            Follow.follower_id == current_user.id,
            Follow.status == FollowStatus.accepted,
        )
    ).scalars().all()

    if following_ids:
        db.execute(
            update(User)
            .where(User.id.in_(following_ids))
            .values(followers_count=User.followers_count - 1)
        )

    # Users that follow current_user (accepted): they lose someone they follow.
    follower_ids = db.execute(
        select(Follow.follower_id).where(
            Follow.following_id == current_user.id,
            Follow.status == FollowStatus.accepted,
        )
    ).scalars().all()

    if follower_ids:
        db.execute(
            update(User)
            .where(User.id.in_(follower_ids))
            .values(following_count=User.following_count - 1)
        )

    # Step 3 — anonymize ratings before deleting the user row.
    # ON DELETE SET NULL would handle this automatically, but doing it
    # explicitly makes the GDPR anonymization intent clear in the code.
    db.execute(
        update(ItineraryRating)
        .where(ItineraryRating.user_id == current_user.id)
        .values(user_id=None)
    )

    # Step 4 — delete the user. Cascade handles all remaining owned data.
    db.delete(current_user)
    db.commit()


@router.get(
    "/by-username/{username}",
    response_model=UserPublicProfile,
    summary="Get a user's public profile by username (case-insensitive)",
)
def get_user_by_username(
    username: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> UserPublicProfile:
    target_user = db.execute(
        select(User).where(User.username_lower == username.lower())
    ).scalar_one_or_none()

    if not target_user or not target_user.is_active:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found.",
        )

    follow_record = db.execute(
        select(Follow).where(
            Follow.follower_id == current_user.id,
            Follow.following_id == target_user.id,
        )
    ).scalar_one_or_none()

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
        passport_countries=target_user.passport_countries,
        resident_country=target_user.resident_country,
        languages=target_user.languages,
        is_following=(
            follow_record is not None
            and follow_record.status == FollowStatus.accepted
        ),
        follow_is_pending=(
            follow_record is not None
            and follow_record.status == FollowStatus.pending
        ),
    )


@router.get(
    "/search",
    response_model=list[UserSearchResult],
    summary="Search users by username or display name",
)
@limiter.limit("30/minute")
def search_users(
    request: Request,
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
    q_lower = q.lower()
    prefix_term = f"{q_lower}%"

    results = db.execute(
        select(User)
        .where(
            User.id != current_user.id,
            User.is_active == True,
            or_(
                User.username_lower.ilike(search_term.lower()),
                User.display_name.ilike(search_term),
            ),
        )
        .order_by(
            (User.username_lower == q_lower).desc(),
            User.username_lower.ilike(prefix_term).desc(),
            User.followers_count.desc(),
        )
        .limit(limit)
        .offset(offset)
    ).scalars().all()

    return results  # type: ignore[return-value]


@router.get(
    "/{identifier}",
    response_model=UserPublicProfile,
    summary="Get a user's public profile (by UUID or username)",
)
def get_user_profile(
    identifier: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> UserPublicProfile:
    """
    Return a user's public profile with follow-status context.

    Accepts either a UUID or a username (case-insensitive) as the path parameter,
    so existing UUID-based clients keep working while new code can use usernames.

    The response includes two computed fields:
      is_following: True if the current user has an ACCEPTED follow to this user.
      follow_is_pending: True if the current user has a PENDING follow request.
    """
    target_user = None
    try:
        user_uuid = uuid.UUID(identifier)
        target_user = db.get(User, user_uuid)
    except ValueError:
        target_user = db.execute(
            select(User).where(User.username_lower == identifier.lower())
        ).scalar_one_or_none()

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
        passport_countries=target_user.passport_countries,
        resident_country=target_user.resident_country,
        languages=target_user.languages,
        is_following=is_following,
        follow_is_pending=follow_is_pending,
    )
