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

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlalchemy import select, or_, update
from sqlalchemy.orm import Session, selectinload
from starlette.requests import Request

from app.config import get_settings
from app.database import get_db
from app.dependencies import get_current_user
from app.limiter import limiter
from app.models.follow import Follow, FollowStatus
from app.models.itinerary import Itinerary
from app.models.itinerary_rating import ItineraryRating
from app.models.track import Track
from app.models.user import User
from app.schemas.user import (
    DeleteAccountRequest,
    UserImageResponse,
    UserPrivateProfile,
    UserPublicProfile,
    UserSearchResult,
    UserUpdateRequest,
    VisitedLocationItem,
    VisitedLocationsResponse,
)
from app.services.auth import verify_google_id_token, verify_password
from app.services.user_service import (
    bump_follow_counters,
    get_active_user_by_username_or_404,
    get_active_user_or_404,
    get_follow,
    public_profile_text,
)
from app.services.image_service import (
    ImageProcessingError,
    process_and_store,
    process_avatar_image,
    process_cover_image,
)
from app.services.moderation_service import ModerationContext, ModerationRejectedError
from app.services import block_service, notification_service
from app.services.itinerary_access import can_view_itinerary
from app.services.text_moderation_service import moderate_or_422
from app.services.moderation_actions import escalate_if_flagged
from app.storage.factory import storage
from app.errors import ApiError

router = APIRouter(prefix="/users", tags=["Users"])


def _require_not_blocked(db: Session, viewer: User, target: User) -> None:
    """404 when either party has blocked the other.

    Indistinguishable from a deleted account on purpose: the blocked user must
    not be able to tell they were blocked, and the blocker must not have to see
    the profile of someone they blocked.
    """
    if block_service.is_blocked_either_way(db, viewer.id, target.id):
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="user_not_found", detail="User not found.",
        )


def _build_public_profile(target_user: User, current_user: User,
                          db: Session) -> UserPublicProfile:
    _require_not_blocked(db, current_user, target_user)
    # is_following / follow_is_pending aren't columns — derived from the
    # current_user → target_user follow row and built by hand.
    follow_record = get_follow(db, current_user.id, target_user.id)
    display_name, bio = public_profile_text(target_user, current_user.id)
    return UserPublicProfile(
        id=target_user.id,
        username=target_user.username,
        display_name=display_name,
        bio=bio,
        avatar_url=target_user.avatar_url,
        cover_image_url=target_user.cover_image_url,
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

    ctx = moderate_or_422(
        db, get_settings(),
        target_type="user",
        author=current_user,
        fields={key: update_data[key]
                for key in ("display_name", "bio") if key in update_data},
        target_id=current_user.id,
    )
    if "display_name" in update_data or "bio" in update_data:
        # Assigned, not escalated: rewritten profile text is new content, so a
        # cleaned-up bio clears the previous flag.
        current_user.moderation_status = ctx.status
        escalate_if_flagged(
            db, "user", current_user,
            escalate_flag=ctx.escalate, decision_id=ctx.decision_id,
        )

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
            bump_follow_counters(db.get(User, follow.follower_id), current_user, 1)
            # One per requester — going public accepts them all at once, and
            # each of them is owed the same notice as an individual accept.
            notification_service.notify(
                db,
                user_id=follow.follower_id,
                type="follow_accepted",
                actor=current_user,
                entity_type="user",
                entity_id=current_user.id,
            )

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

    1. Re-authenticate — prevents accidental or unauthorized deletion.
       Password accounts re-verify their password; passwordless (SSO) accounts
       re-verify with their provider (Google today) — a fresh ID token whose
       `sub` must match the account.

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
    # Step 1 — re-authenticate before an irreversible delete. Dual-method
    # accounts (password + linked Google) may present EITHER credential; the
    # branch is picked by which one the client sent, not by account precedence.
    # Truthy checks mean an empty-string password counts as "not given," so a
    # dual-method user sending only a Google token still reaches the Google path.
    if payload.password and current_user.has_password:
        # has_password guarantees password_hash is not None — keeps
        # verify_password None-safe (it can't hash a None).
        if not verify_password(payload.password, current_user.password_hash):
            raise ApiError(
                status_code=status.HTTP_401_UNAUTHORIZED,
                code="incorrect_password", detail="Incorrect password.",
            )
    elif payload.google_id_token and current_user.google_sub:
        # Verify a fresh Google ID token whose `sub` matches this account
        # (mirrors the /auth/google re-auth path).
        try:
            claims = verify_google_id_token(payload.google_id_token)
        except Exception:
            # Any verification failure is an auth failure — never leak details.
            raise ApiError(
                status_code=status.HTTP_401_UNAUTHORIZED,
                code="google_token_invalid", detail="Invalid Google token.",
            )
        if claims.get("sub") != current_user.google_sub:
            raise ApiError(
                status_code=status.HTTP_401_UNAUTHORIZED,
                code="google_account_mismatch",
                detail="Google account does not match.",
            )
    # No usable credential was supplied — report by what the account expects.
    # Future providers (Apple/Facebook) add an `elif current_user.apple_sub:` /
    # `elif current_user.facebook_id:` branch above, verifying that provider's
    # credential from a new optional field on DeleteAccountRequest.
    elif current_user.has_password:
        raise ApiError(
            status_code=status.HTTP_401_UNAUTHORIZED,
            code="incorrect_password", detail="Incorrect password.",
        )
    elif current_user.google_sub:
        raise ApiError(
            status_code=status.HTTP_401_UNAUTHORIZED,
            code="google_reauth_required",
            detail="Google re-authentication required.",
        )
    else:
        # No password and no known provider — should be unreachable; fail closed.
        raise ApiError(
            status_code=status.HTTP_401_UNAUTHORIZED,
            code="reauth_required", detail="Re-authentication required.",
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
    target_user = get_active_user_by_username_or_404(db, username)
    return _build_public_profile(target_user, current_user, db)


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

    # Built by hand rather than from_attributes: a moderated display name must
    # not leak through search, which is exactly where an abusive handle would
    # get the most reach. (The user is excluded from their own results, so the
    # author-sees-own case can't arise here.)
    return [
        UserSearchResult(
            id=user.id,
            username=user.username,
            display_name=public_profile_text(user, current_user.id)[0],
            avatar_url=user.avatar_url,
            is_private=user.is_private,
            followers_count=user.followers_count,
        )
        for user in results
    ]


# ---------------------------------------------------------------------------
# Avatar & cover image — multipart upload + delete
#
# Both endpoints reuse the existing 1200×630 process_cover_image pipeline.
# The avatar gets center-cropped into a circle on the client (ClipOval +
# BoxFit.cover), so a single image pipeline is enough.
# ---------------------------------------------------------------------------

@router.post(
    "/me/avatar",
    response_model=UserImageResponse,
    summary="Upload or replace the current user's avatar",
)
@limiter.limit("10/minute")
async def upload_my_avatar(
    request: Request,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> UserImageResponse:
    raw_bytes = await file.read()
    key = f"avatars/{current_user.id}.jpg"
    moderation = ModerationContext(
        db=db, settings=get_settings(), target_kind="avatar",
        uploader=current_user, storage_key=key,
    )
    try:
        # Square 800×800 pipeline so the client's 1:1 crop is preserved.
        versioned_url = await process_and_store(
            raw_bytes, key, process_avatar_image, cache_bust=True,
            moderation=moderation)
    except ImageProcessingError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    except ModerationRejectedError:
        raise ApiError(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            code="image_moderation_rejected",
            detail="This image appears to contain prohibited content and was not uploaded.",
        )

    current_user.avatar_url = versioned_url
    db.commit()

    return UserImageResponse(avatar_url=versioned_url)


@router.delete(
    "/me/avatar",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Remove the current user's avatar",
)
async def delete_my_avatar(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    key = f"avatars/{current_user.id}.jpg"
    await storage().delete(key)
    current_user.avatar_url = None
    db.commit()


@router.post(
    "/me/cover-image",
    response_model=UserImageResponse,
    summary="Upload or replace the current user's cover image",
)
@limiter.limit("10/minute")
async def upload_my_cover_image(
    request: Request,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> UserImageResponse:
    raw_bytes = await file.read()
    key = f"covers/{current_user.id}.jpg"
    moderation = ModerationContext(
        db=db, settings=get_settings(), target_kind="user_cover",
        uploader=current_user, storage_key=key,
    )
    try:
        # See note on upload_my_avatar — same cache-busting rationale.
        versioned_url = await process_and_store(
            raw_bytes, key, process_cover_image, cache_bust=True,
            moderation=moderation)
    except ImageProcessingError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    except ModerationRejectedError:
        raise ApiError(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            code="image_moderation_rejected",
            detail="This image appears to contain prohibited content and was not uploaded.",
        )

    current_user.cover_image_url = versioned_url
    db.commit()

    return UserImageResponse(cover_image_url=versioned_url)


@router.delete(
    "/me/cover-image",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Remove the current user's cover image",
)
async def delete_my_cover_image(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    key = f"covers/{current_user.id}.jpg"
    await storage().delete(key)
    current_user.cover_image_url = None
    db.commit()


# ---------------------------------------------------------------------------
# GET /users/{user_id}/locations — aggregate stop coords for the profile hero
#
# Declared BEFORE the catch-all /{identifier} so the typed UUID path parameter
# takes precedence and bad-UUID requests return 422 instead of falling through
# to the username lookup.
# ---------------------------------------------------------------------------

@router.get(
    "/{user_id}/locations",
    response_model=VisitedLocationsResponse,
    summary="All stop coordinates visible to the viewer for this user",
)
def get_user_locations(
    user_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> VisitedLocationsResponse:
    get_active_user_or_404(db, user_id)  # 404 if the target doesn't exist

    itineraries = db.execute(
        select(Itinerary)
        .where(Itinerary.user_id == user_id)
        .options(selectinload(Itinerary.tracks).selectinload(Track.stops))
    ).scalars().all()

    locations: list[VisitedLocationItem] = []
    for itin in itineraries:
        if not can_view_itinerary(itin, current_user.id, db):
            continue
        for track in itin.tracks:
            for stop in track.stops:
                if stop.lat is None or stop.lng is None:
                    continue
                locations.append(
                    VisitedLocationItem(
                        lat=float(stop.lat),
                        lng=float(stop.lng),
                        place_name=stop.place_name,
                        place_type=stop.place_type,
                        itinerary_id=itin.id,
                        stop_id=stop.id,
                    )
                )

    return VisitedLocationsResponse(locations=locations)


# ---------------------------------------------------------------------------
# Blocking
#
# Declared before /{identifier} so "me" and the block paths are matched
# literally rather than being swallowed as a username.
# ---------------------------------------------------------------------------

@router.get(
    "/me/blocks",
    response_model=list[UserSearchResult],
    summary="List the accounts the current user has blocked",
)
def list_my_blocks(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[UserSearchResult]:
    """The blocked-users list. Reviewers look for this specifically: a block
    that cannot be found and lifted is not a real block."""
    return [
        UserSearchResult(
            id=user.id,
            username=user.username,
            # Blocked-user text is shown to the person who blocked them, so the
            # moderation filter still applies.
            display_name=public_profile_text(user, current_user.id)[0],
            avatar_url=user.avatar_url,
            is_private=user.is_private,
            followers_count=user.followers_count,
        )
        for user in block_service.list_blocks(db, current_user)
    ]


@router.post(
    "/{user_id}/block",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Block a user",
)
def block_user(
    user_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    if user_id == current_user.id:
        raise ApiError(
            status_code=status.HTTP_400_BAD_REQUEST,
            code="cannot_block_self", detail="You cannot block yourself.",
        )
    # Deliberately not get_active_user_or_404's blocked-aware variant: blocking
    # someone must work even if they already blocked you.
    target = db.get(User, user_id)
    if target is None or not target.is_active:
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="user_not_found", detail="User not found.",
        )
    block_service.create_block(db, current_user, target)


@router.delete(
    "/{user_id}/block",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Unblock a user",
)
def unblock_user(
    user_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> None:
    # Idempotent: unblocking someone who isn't blocked is a no-op, so an
    # optimistic UI never has to error.
    block_service.delete_block(db, current_user, user_id)


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
        raise ApiError(
            status_code=status.HTTP_404_NOT_FOUND,
            code="user_not_found", detail="User not found.",
        )

    return _build_public_profile(target_user, current_user, db)
