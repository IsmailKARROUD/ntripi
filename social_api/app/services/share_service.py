"""
services/share_service.py — Context builder for share landing page templates.

Keeps all formatting logic out of the router so the router stays thin and
templates receive clean, pre-formatted strings.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from app.services.app_links import cta_context
from app.storage.factory import storage

if TYPE_CHECKING:
    from app.config import Settings
    from app.models.itinerary import Itinerary
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


def prepare_share_context(itinerary: "Itinerary", settings: "Settings") -> dict:
    """The Jinja2 context for a public trip's share page: the teaser and nothing
    else — title, cover, rating, description.

    Only these fields reach the template, never the row: whoever reads the page
    without an account (a person, a chat crawler, a search engine) gets exactly
    what is passed here, and the rest of the trip is behind sign-in.
    """
    share_url = build_share_url(itinerary, settings)
    rated = bool(itinerary.rating_count) and itinerary.rating_avg is not None
    return {
        "itinerary_id": str(itinerary.id),
        "title": itinerary.title,
        "description": (itinerary.description or "").strip() or None,
        "cover_image_url": itinerary.cover_image_url
        and absolutize_stored_url(itinerary.cover_image_url, settings),
        "rating_avg": f"{itinerary.rating_avg:.1f}" if rated else None,
        "rating_count": itinerary.rating_count if rated else 0,
        # The chat card says what the page says (the template adds the
        # fallback line when there is neither).
        "card_excerpt": _excerpt(itinerary.description),
        "share_url": share_url,
        "preview_image_url": _resolve_preview_image_url(itinerary, settings),
        "app_cta": cta_context(share_url, settings),
    }


def prepare_profile_share_context(user: "User", settings: "Settings") -> dict:
    """The Jinja2 context for a profile's share page: display name, @username
    and avatar — the same three for a public and a private account.

    The display name comes from user_service.public_profile_text with no viewer,
    so moderated text is blanked for the anonymous visitor exactly as it is for
    every non-author in the API. Only these fields reach the template.
    """
    from app.services.user_service import public_profile_text

    display_name, _bio = public_profile_text(user, viewer_id=None)
    share_url = build_profile_share_url(user, settings)
    return {
        "username": user.username,
        # A blanked display name degrades to the handle, never to an empty header.
        "display_name": display_name or f"@{user.username}",
        "initial": (display_name or user.username)[:1].upper(),
        "avatar_url": user.avatar_url and absolutize_stored_url(user.avatar_url, settings),
        "is_private": user.is_private,
        "share_url": share_url,
        "preview_image_url": resolve_profile_image_url(user, settings),
        "app_cta": cta_context(share_url, settings),
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

    return default_preview_image_url(settings)


def default_preview_image_url(settings: "Settings") -> str:
    """The Ntripi card every page falls back to — and the only image a private
    trip's preview may carry, since its cover would show it to the whole chat."""
    return f"{settings.share_base_url}/static/ntripi-og-default.png"


def resolve_profile_image_url(user: "User", settings: "Settings") -> str:
    """Absolute OG preview image for a profile: avatar, else the default."""
    if user.avatar_url:
        return absolutize_stored_url(user.avatar_url, settings)
    return default_preview_image_url(settings)


def _excerpt(text: str | None, limit: int = 150) -> str | None:
    """The start of a description for a preview card: whitespace collapsed,
    cut at a word boundary."""
    flat = " ".join((text or "").split())
    if len(flat) <= limit:
        return flat or None
    cut = flat[:limit].rsplit(" ", 1)[0] or flat[:limit]
    return cut.rstrip(" ,.;:") + "…"
