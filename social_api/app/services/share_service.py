"""
services/share_service.py — Context builder for share landing page templates.

Keeps all formatting logic out of the router so the router stays thin and
templates receive clean, pre-formatted strings.
"""

from __future__ import annotations

from decimal import Decimal
from typing import TYPE_CHECKING

from app.storage.factory import storage

if TYPE_CHECKING:
    from app.config import Settings
    from app.models.itinerary import Itinerary
    from app.models.stop import Stop
    from app.models.transit_segment import TransitSegment
    from app.models.user import User


def absolute_storage_url(key: str, settings: "Settings") -> str:
    """Absolute public URL for a stored object.

    The only way to turn a storage key into a URL safe to hand to something
    outside our own pages (emails, Jira tickets, OG crawlers): filesystem
    storage returns a relative /uploads/... path, which is dead text anywhere
    but a browser already on the site, so prefix SHARE_BASE_URL. R2 already
    returns an absolute URL and is passed through untouched.
    """
    url = storage().public_url(key)
    if url.startswith("/"):
        return f"{settings.share_base_url}{url}"
    return url


def prepare_share_context(
    itinerary: "Itinerary",
    owner: "User",
    stops: list["Stop"],
    segments: list["TransitSegment"],
    settings: "Settings",
) -> dict:
    """
    Build the Jinja2 template context for a public share landing page.

    All IDs are converted to strings so Jinja2 dict lookups are consistent.
    Segments are indexed by their from_stop_id (string) for O(1) lookup in
    the template stop loop.
    """
    segments_by_from_stop = {
        str(seg.from_stop_id): {
            "total_duration_min": seg.total_duration_min,
            "legs": [
                {
                    "mode": leg.mode,
                    "mode_emoji": _mode_emoji(leg.mode),
                }
                for leg in seg.legs
            ],
        }
        for seg in segments
    }

    stop_dicts = [
        {
            "id": str(stop.id),
            "place_name": stop.place_name or "Unnamed stop",
            "place_address": stop.place_address,
            "duration_min": stop.duration_min,
            "cost": float(stop.cost),
            "is_free": stop.is_free,
        }
        for stop in stops
    ]

    share_url = build_share_url(itinerary, settings)

    return {
        "itinerary": itinerary,
        "owner": owner,
        "stops": stop_dicts,
        "segments_by_from_stop": segments_by_from_stop,
        "formatted_duration": _format_duration(itinerary.total_duration_min),
        "formatted_cost": _format_cost(itinerary.total_cost, itinerary.currency),
        "stop_count": len(stops),
        "rating_avg": (
            f"{itinerary.rating_avg:.1f}" if itinerary.rating_avg else None
        ),
        "rating_count": itinerary.rating_count,
        "share_url": share_url,
        "preview_image_url": _resolve_preview_image_url(itinerary, settings),
    }


def prepare_profile_share_context(
    user: "User",
    itineraries: list["Itinerary"],
    settings: "Settings",
) -> dict:
    """Build the Jinja2 context for a public profile landing page.

    Display name and bio come from user_service.public_profile_text with no
    viewer, so moderated text is blanked for the anonymous web visitor exactly
    as it is for every non-author in the API.
    """
    from app.services.user_service import public_profile_text

    display_name, bio = public_profile_text(user, viewer_id=None)

    return {
        "user": user,
        # A blanked display name degrades to the handle, never to an empty header.
        "display_name": display_name or f"@{user.username}",
        "bio": bio,
        "avatar_url": user.avatar_url and absolutize_stored_url(user.avatar_url, settings),
        "itineraries": [
            {
                "id": str(it.id),
                "title": it.title,
                "cover_image_url": it.cover_image_url
                and absolutize_stored_url(it.cover_image_url, settings),
                "stop_count": it.stops_count,
                "rating_avg": f"{it.rating_avg:.1f}" if it.rating_avg else None,
                "rating_count": it.rating_count,
                "url": build_share_url(it, settings),
            }
            for it in itineraries
        ],
        "share_url": build_profile_share_url(user, settings),
        "preview_image_url": resolve_profile_image_url(user, settings),
    }


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

def build_share_url(itinerary: "Itinerary", settings: "Settings") -> str:
    """Absolute public share URL for an itinerary."""
    return f"{settings.share_base_url}/share/i/{itinerary.id}"


def build_profile_share_url(user: "User", settings: "Settings") -> str:
    """Absolute public share URL for a profile.

    Keyed by username rather than id: PATCH /users/me deliberately excludes
    username editing, so handles are immutable and the link cannot rot.
    """
    return f"{settings.share_base_url}/share/u/{user.username}"


def absolutize_stored_url(url: str, settings: "Settings") -> str:
    """Make a stored image URL fit for an OG crawler.

    Filesystem storage yields a relative /uploads/... path, which is dead text
    to anything not already on the site; R2 is absolute and passes through.
    Distinct from absolute_storage_url(), which takes a storage *key*.
    """
    if url.startswith("/"):
        return f"{settings.share_base_url}{url}"
    return url


def _resolve_preview_image_url(itinerary: "Itinerary", settings: "Settings") -> str:
    """Return the absolute URL for the itinerary's OG preview image.

    Priority:
      1. User-uploaded cover image (Phase 1 — this release).
      2. Auto-generated map image (Phase 2 — future).
      3. Default Ntripi OG image (permanent fallback).
    """
    if itinerary.cover_image_url:
        return absolutize_stored_url(itinerary.cover_image_url, settings)

    # Phase 2 map-image fallback goes here.

    return f"{settings.share_base_url}/static/ntripi-og-default.png"


def resolve_profile_image_url(user: "User", settings: "Settings") -> str:
    """Absolute OG preview image for a profile: avatar, else the default."""
    if user.avatar_url:
        return absolutize_stored_url(user.avatar_url, settings)
    return f"{settings.share_base_url}/static/ntripi-og-default.png"


def _mode_emoji(mode: str) -> str:
    return {
        "walk": "🚶",
        "bus": "🚌",
        "tram": "🚋",
        "metro": "🚇",
        "train": "🚆",
        "taxi": "🚕",
        "uber": "🚗",
        "bike": "🚴",
        "ferry": "⛴️",
        "car": "🚗",
        "airplane": "✈️",
    }.get(mode, "🚗")


def _format_duration(minutes: int) -> str:
    if minutes <= 0:
        return "—"
    hours = minutes // 60
    mins = minutes % 60
    if hours == 0:
        return f"{mins}min"
    if mins == 0:
        return f"{hours}h"
    return f"{hours}h {mins}min"


def _format_cost(cost: Decimal | float, currency: str) -> str:
    amount = float(cost)
    if amount <= 0:
        return "Free"
    return f"{amount:.2f} {currency}"
