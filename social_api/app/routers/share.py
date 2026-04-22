"""
routers/share.py — Public share landing page for itineraries.

GET /share/i/{itinerary_id} returns an HTML page with rich Open Graph
meta tags so links look good when pasted into WhatsApp, Twitter, iMessage.

No authentication is required — this is a public web page.
Visibility enforcement happens at the template level:
  public     → full rich page with stops, stats, map placeholder
  followers /
  restricted → minimal page ("private itinerary, open in app")
  only_me    → 404 page (protects privacy, doesn't leak existence)
"""

from __future__ import annotations

import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session, selectinload
from sqlalchemy import select

from app.config import Settings, get_settings
from app.database import get_db
from app.models.itinerary import Itinerary
from app.models.stop import Stop
from app.models.transit_segment import TransitSegment
from app.models.user import User
from app.services.share_service import prepare_share_context

router = APIRouter(prefix="/share", tags=["share"])

_TEMPLATES_DIR = Path(__file__).parent.parent / "templates"
templates = Jinja2Templates(directory=str(_TEMPLATES_DIR))


@router.get("/i/{itinerary_id}", response_class=HTMLResponse)
def share_itinerary(
    itinerary_id: uuid.UUID,
    request: Request,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> HTMLResponse:
    """
    Render a share landing page for an itinerary.

    Visibility rules:
      public      → full rich page
      followers / restricted → minimal "private" page
      only_me     → 404 (same as not found — privacy protection)
    """
    itinerary = db.execute(
        select(Itinerary)
        .options(
            selectinload(Itinerary.stops).selectinload(Stop.outgoing_segment).selectinload(
                TransitSegment.legs
            )
        )
        .where(Itinerary.id == itinerary_id)
    ).scalar_one_or_none()

    # Not found or only_me → identical 404 response to avoid leaking existence.
    if itinerary is None or itinerary.visibility == "only_me":
        return templates.TemplateResponse(
            request,
            "share_not_found.html",
            status_code=404,
        )

    owner = db.execute(
        select(User).where(User.id == itinerary.user_id)
    ).scalar_one_or_none()

    # Owner deleted (edge case) → treat as not found.
    if owner is None:
        return templates.TemplateResponse(
            request,
            "share_not_found.html",
            status_code=404,
        )

    share_url = f"{settings.share_base_url}/share/i/{itinerary.id}"
    preview_image_url = f"{settings.share_base_url}/static/ntripi-og-default.jpg"

    if itinerary.visibility in ("followers", "restricted"):
        return templates.TemplateResponse(
            request,
            "share_private.html",
            {
                "itinerary": itinerary,
                "owner": owner,
                "share_url": share_url,
                "preview_image_url": preview_image_url,
            },
        )

    # Public — build the full rich context.
    stops = sorted(itinerary.stops, key=lambda s: s.position)
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
