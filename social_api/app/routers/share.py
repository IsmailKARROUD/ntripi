"""
routers/share.py — Public share landing pages for itineraries and profiles.

GET /share/i/{itinerary_id} and GET /share/u/{username} return HTML with Open
Graph tags, so a link pasted into WhatsApp, iMessage, Twitter or Slack previews.

No authentication — and nobody reading without an account gets more than a
teaser, a person, a chat crawler and a search engine alike:
  public trip     → title, cover, rating, description; the rest after sign-in
  followers /
  restricted      → "this trip is private" page: no title, owner or cover
  only_me         → 404 page (protects privacy, doesn't leak existence)
  profile         → display name, @username, avatar (private: also noindex)
The routes pass the templates those fields and nothing else, and
test_public_surface.py holds every page here to it.

On a phone with the app, these links open the app instead (see
services/app_links.py); a visitor who landed in the browser is offered the web
app, which signs them in and opens the same trip or profile.
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Request
from fastapi.responses import HTMLResponse
from slowapi.errors import RateLimitExceeded
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.database import get_db
from app.errors import ApiError
from app.limiter import limiter
from app.models.itinerary import Itinerary
from app.models.user import User
from app.services import user_service
from app.services.app_links import cta_context, store_links
from app.services.share_service import (
    build_share_url,
    default_preview_image_url,
    prepare_profile_share_context,
    prepare_share_context,
)
from app.templating import templates

router = APIRouter(prefix="/share", tags=["share"])


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


def rate_limited_page(request: Request, exc: RateLimitExceeded) -> HTMLResponse:
    """The /share 429 as a page: these are read in browsers, where slowapi's
    JSON body would be a screen of raw text. Registered in main.py."""
    try:
        retry_after = str(exc.limit.limit.get_expiry())
    except AttributeError:  # a slowapi without the window on the exception
        retry_after = "60"
    return templates.TemplateResponse(
        request,
        "share_rate_limited.html",
        {"app_cta": store_links(get_settings())},
        status_code=429,
        headers={"Retry-After": retry_after},
    )


@router.get("/i/{itinerary_id}", response_class=HTMLResponse)
# Per-IP, generous: stops one scraper hammering the origin; a person never
# reaches it (SHARE_RATE_LIMIT, tunable without a redeploy).
@limiter.limit(lambda: get_settings().SHARE_RATE_LIMIT)
def share_itinerary(
    itinerary_id: str,
    request: Request,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> HTMLResponse:
    """
    Render a share landing page for an itinerary.

    Visibility rules:
      public      → the teaser: title, cover, rating, description
      followers / restricted → "private" page carrying no title, owner or cover
      only_me     → 404 (same as not found — privacy protection)
    """
    # Parsed here rather than typed as uuid.UUID: a link cut short in a chat
    # would otherwise answer FastAPI's raw JSON 422 to a browser.
    try:
        parsed_id = uuid.UUID(itinerary_id)
    except ValueError:
        return _not_found(request, settings)

    # The row alone: the teaser shows nothing below the itinerary, so its
    # stops, segments and legs are never loaded for an anonymous reader.
    itinerary = db.get(Itinerary, parsed_id)

    # Not found, only_me, or moderator soft-deleted/hidden → identical 404 to
    # avoid leaking existence (a hidden/deleted itinerary must never render here).
    if (
        itinerary is None
        or itinerary.visibility == "only_me"
        or itinerary.deleted_at is not None
        or itinerary.hidden_at is not None
    ):
        return _not_found(request, settings)

    owner = db.get(User, itinerary.user_id)

    # Owner deleted (edge case) or banned → treat as not found.
    if owner is None or not owner.is_active:
        return _not_found(request, settings)

    share_url = build_share_url(itinerary, settings)

    if itinerary.visibility in ("followers", "restricted"):
        # Nothing about the trip is passed, so the template cannot leak it: this
        # page and its preview card reach everyone the link reaches — mostly
        # people who cannot open the trip. Those who can open it once signed in.
        return templates.TemplateResponse(
            request,
            "share_private.html",
            {
                "share_url": share_url,
                "noindex": True,
                "preview_image_url": default_preview_image_url(settings),
                "app_cta": cta_context(share_url, settings),
            },
        )

    return templates.TemplateResponse(
        request, "share_public.html", prepare_share_context(itinerary, settings)
    )


@router.get("/u/{username}", response_class=HTMLResponse)
@limiter.limit(lambda: get_settings().SHARE_RATE_LIMIT)
def share_profile(
    username: str,
    request: Request,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> HTMLResponse:
    """
    Render a share landing page for a profile.

    Visibility rules:
      public / private → display name, @username, avatar — private also noindex
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

    context = prepare_profile_share_context(user, settings)
    context["noindex"] = user.is_private
    return templates.TemplateResponse(request, "share_profile.html", context)
