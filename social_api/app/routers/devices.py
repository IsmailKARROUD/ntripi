"""
routers/devices.py — register and unregister FCM device tokens.

A token here is a delivery address, not a session: it is created when the user
grants notification permission and destroyed when they sign out. Both endpoints
answer 204 and neither ever 404s.

WHY REGISTER IS AN UPSERT ON `token`, NOT ON (user, token): FCM reassigns a
token to whichever account is signed in on that install. Two people sharing a
phone would otherwise end up with two rows carrying the same address, and the
first person would keep receiving the second person's notifications. Moving the
row is the correct answer, and the UNIQUE constraint on `token` is what forces
us to make that choice explicitly.

DELETE takes the token in the path rather than deleting by user, because
signing out on one device must not silence the others.
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.constants import push_i18n
from app.database import get_db
from app.dependencies import get_current_user
from app.models.device_token import DeviceToken
from app.models.user import User
from app.schemas.device import DeviceRegisterRequest

router = APIRouter(prefix="/devices", tags=["Devices"])


@router.post("", status_code=status.HTTP_204_NO_CONTENT)
def register_device(
    payload: DeviceRegisterRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Response:
    """Register this device for push, or refresh an existing registration.

    Idempotent: the client calls it on every launch and on every token refresh,
    because a token it never re-sent is a token we would keep pushing to after
    it stopped working.
    """
    # Stored normalised so the send path never has to think about "fr-CA": an
    # unrecognised tag becomes "en" here rather than at every render.
    locale = push_i18n.normalize(payload.locale)
    now = datetime.now(timezone.utc)

    existing = db.execute(
        select(DeviceToken).where(DeviceToken.token == payload.token)
    ).scalar_one_or_none()

    if existing is not None:
        # Reassignment, not a duplicate — see the module docstring.
        existing.user_id = current_user.id
        existing.platform = payload.platform
        existing.locale = locale
        existing.last_seen_at = now
    else:
        db.add(
            DeviceToken(
                user_id=current_user.id,
                token=payload.token,
                platform=payload.platform,
                locale=locale,
                created_at=now,
                last_seen_at=now,
            )
        )

    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/{token}", status_code=status.HTTP_204_NO_CONTENT)
def unregister_device(
    token: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> Response:
    """Stop pushing to this device. Called on sign-out.

    Never 404s, for the same reason the notification DELETEs never do: the
    client fires this while tearing its session down and cannot act on an
    error. `user_id` in the WHERE is the IDOR guard, which also makes another
    user's token indistinguishable from one that was already gone.
    """
    row = db.execute(
        select(DeviceToken).where(
            DeviceToken.token == token,
            DeviceToken.user_id == current_user.id,
        )
    ).scalar_one_or_none()

    if row is not None:
        db.delete(row)
        db.commit()

    return Response(status_code=status.HTTP_204_NO_CONTENT)
