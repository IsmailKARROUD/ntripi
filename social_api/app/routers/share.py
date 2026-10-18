"""
routers/share.py — Public share landing page for itineraries.

GET /share/i/{itinerary_id} returns an HTML page with rich Open Graph
meta tags so links look good when pasted into WhatsApp, Twitter, iMessage.

No authentication is required — this is a public web page.
Visibility enforcement happens at the template level:
  public     → full rich page with stops, stats, map placeholder
  followers /
  restricted → "this trip is private" page: no title, owner or cover
  only_me    → 404 page (protects privacy, doesn't leak existence)

On a phone with the app, these links open the app instead (see
services/app_links.py); every page here offers the app first and the web app
second to a visitor who landed in the browser.
"""

from __future__ import annotations

import uuid
from fastapi import APIRouter, Depends, Request
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session, selectinload
from sqlalchemy import select

from app.config import Settings, get_settings
from app.database import get_db
from app.models.itinerary import Itinerary
from app.models.stop import Stop
from app.models.track import Track
from app.models.transit_segment import TransitSegment
from app.models.user import User
from app.errors import ApiError
from app.services import user_service
from app.services.app_links import cta_context, store_links
from app.services.share_service import (
    absolutize_stored_url,
    build_profile_share_url,
    build_share_url,
    default_preview_image_url,
    prepare_profile_share_context,
    prepare_share_context,
    resolve_profile_image_url,
)
from app.templating import templates

router = APIRouter(prefix="/share", tags=["share"])

# A prolific account must not render a thousand rows into one page.
_MAX_PROFILE_ITINERARIES = 12


def _not_found(
    request: Request, settings: Settings, *, kind: str = "itinerary"
) -> HTMLResponse:
    """The one page for every link that leads nowhere — identical whatever the
    reason, so a link never reveals whether its target exists."""
    return templates.TemplateResponse(
        request,
        "share_not_found.html",
        {"kind": kind, "app_cta": store_links(settings)},
        status_code=404,
    )


@router.get("/i/{itinerary_id}", response_class=HTMLResponse)
def share_itinerary(
    itinerary_id: str,
    request: Request,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> HTMLResponse:
    """
    Render a share landing page for an itinerary.

    Visibility rules:
      public      → full rich page
      followers / restricted → "private" page carrying no title, owner or cover
      only_me     → 404 (same as not found — privacy protection)
    """
    # Parsed here rather than typed as uuid.UUID: a link cut short in a chat
    # would otherwise answer FastAPI's raw JSON 422 to a browser.
    try:
        parsed_id = uuid.UUID(itinerary_id)
    except ValueError:
        return _not_found(request, settings)

    itinerary = db.execute(
        select(Itinerary)
        .options(
            selectinload(Itinerary.tracks)
            .selectinload(Track.stops)
            .selectinload(Stop.outgoing_segment)
            .selectinload(TransitSegment.legs)
        )
        .where(Itinerary.id == parsed_id)
    ).scalar_one_or_none()

    if itinerary:
        itinerary.tracks.sort(key=lambda t: t.rank)
        for track in itinerary.tracks:
            track.stops.sort(key=lambda s: s.rank)

    # Not found, only_me, or moderator soft-deleted/hidden → identical 404 to
    # avoid leaking existence (a hidden/deleted itinerary must never render here).
    if (
        itinerary is None
        or itinerary.visibility == "only_me"
        or itinerary.deleted_at is not None
        or itinerary.hidden_at is not None
    ):
        return _not_found(request, settings)

    owner = db.execute(
        select(User).where(User.id == itinerary.user_id)
    ).scalar_one_or_none()

    # Owner deleted (edge case) or banned → treat as not found.
    if owner is None or not owner.is_active:
        return _not_found(request, settings)

    share_url = build_share_url(itinerary, settings)

    if itinerary.visibility in ("followers", "restricted"):
        # Nothing about the trip is passed, so the template cannot leak it: this
        # page and its preview card reach everyone the link reaches — mostly
        # people who cannot open the trip. Those who can open it in the app.
        return templates.TemplateResponse(
            request,
            "share_private.html",
            {
                "share_url": share_url,
                "preview_image_url": default_preview_image_url(settings),
                "app_cta": cta_context(share_url, settings),
            },
        )

    # Public — build the full rich context.
    # Stops are ordered by track rank then stop rank (tracks already sorted by loader).
    stops = [s for track in itinerary.tracks for s in sorted(track.stops, key=lambda s: s.rank)]
    segments = [
        stop.outgoing_segment
        for stop in stops
        if stop.outgoing_segment is not None
    ]

    context = prepare_share_context(
        itinerary=itinerary,
        owner=owner,
        stops=stops,
        segments=segments,
        settings=settings,
    )

    return templates.TemplateResponse(request, "share_public.html", context)


@router.get("/u/{username}", response_class=HTMLResponse)
def share_profile(
    username: str,
    request: Request,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> HTMLResponse:
    """
    Render a share landing page for a profile.

    Visibility rules:
      public   → full page with bio, counts and public itineraries
      private  → minimal page (name, handle, "open in app")
      unknown / banned / deleted → 404 (identical, so existence never leaks)

    A moderation-hidden profile still renders: users.moderation_status covers
    only display_name + bio, which public_profile_text blanks. The account
    itself is unaffected — bans are is_active, and those 404 here.
    """
    try:
        user = user_service.get_active_user_by_username_or_404(db, username)
    except ApiError:
        # The helper raises a JSON 404; this is an HTML page, so re-render.
        return _not_found(request, settings, kind="profile")

    share_url = build_profile_share_url(user, settings)

    if user.is_private:
        display_name, _bio = user_service.public_profile_text(user, viewer_id=None)
        return templates.TemplateResponse(
            request,
            "share_profile_private.html",
            {
                "user": user,
                "display_name": display_name or f"@{user.username}",
                "avatar_url": user.avatar_url
                and absolutize_stored_url(user.avatar_url, settings),
                "share_url": share_url,
                "preview_image_url": resolve_profile_image_url(user, settings),
                "app_cta": cta_context(share_url, settings),
            },
        )

    # Public — same exclusions as share_itinerary, so nothing reachable here is
    # unreachable through its own share link.
    itineraries = list(
        db.execute(
            select(Itinerary)
            .options(selectinload(Itinerary.tracks).selectinload(Track.stops))
            .where(
                Itinerary.user_id == user.id,
                Itinerary.visibility == "public",
                Itinerary.deleted_at.is_(None),
                Itinerary.hidden_at.is_(None),
            )
            .order_by(Itinerary.created_at.desc())
            .limit(_MAX_PROFILE_ITINERARIES)
        ).scalars()
    )

    context = prepare_profile_share_context(user, itineraries, settings)
    return templates.TemplateResponse(request, "share_profile_public.html", context)
