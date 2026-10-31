"""
services/stop_location.py — what a stop may store about where it is.

The only Google content a stop may hold is a place ID: Google's terms let a
place ID be kept indefinitely and nothing else, and coordinates read out of a
Google Maps link are Google's too. This module is the one place a stop write
becomes a location those rules allow, whatever client sent it — installed
builds included, which still unfurl a pasted link and send its coordinates.

  link         map_url, plus a ChIJ place ID found in the link's own text;
               no coordinates, no address, no search text
  google       google_place_id + google_place_query; nothing else locates it
  osm / typed  coordinates (and an address); no Google fields, no link

A body without `place_source` (an installed build, or an edit that left the
location alone) is read from what it sends: a link makes a link stop, a stored
Google place stays one while no coordinates arrive, and coordinates make an
ordinary stop. The refresh stamps move only when the stored place ID changes,
so a re-sent ID keeps its NOT_FOUND mark and its refresh date.
"""

from __future__ import annotations

import re
from datetime import datetime
from typing import Any

# Mirrors extractPlaceId in the app. Only the ChIJ namespace (and an explicit
# place_id param) is a place ID — the hex !1s0x…:0x… feature ID most long URLs
# carry is a different identifier Google's embeds do not accept.
_PLACE_ID_PATTERNS = (
    re.compile(r"place_id[:=]([A-Za-z0-9_-]{15,})"),
    re.compile(r"!1s(ChIJ[A-Za-z0-9_-]+)"),
)

_COORD_SOURCES = ("osm", "typed")


def extract_place_id(url: str | None) -> str | None:
    """A Google place ID written in a Maps URL's own text, or None. Reads the
    string only — a link is never fetched to find one."""
    if not url:
        return None
    for pattern in _PLACE_ID_PATTERNS:
        match = pattern.search(url)
        if match:
            return match.group(1)
    return None


def normalize(fields: dict[str, Any], existing: Any | None, now: datetime) -> dict[str, Any]:
    """`fields` rewritten so the stop they produce obeys the location rules.

    `fields` are the columns a create or update is about to set (an update's
    partial set); `existing` is the stored stop, None on create. Returns a new
    dict — the caller sets every key in it.
    """
    out = dict(fields)

    def resulting(key: str) -> Any:
        if key in out:
            return out[key]
        return getattr(existing, key) if existing is not None else None

    source = out.get("place_source")
    if source is None:
        source = _source_of_unlabelled_write(out, existing, resulting)

    if source == "link":
        out.update(lat=None, lng=None, place_address=None, google_place_query=None,
                   google_place_id=extract_place_id(resulting("map_url")))
    elif source == "google":
        out.update(lat=None, lng=None, place_address=None, map_url=None)
    elif resulting("lat") is not None or resulting("lng") is not None or source in _COORD_SOURCES:
        out.update(google_place_id=None, google_place_query=None, map_url=None)
    out["place_source"] = source

    new_id = resulting("google_place_id")
    old_id = existing.google_place_id if existing is not None else None
    if new_id != old_id:
        # A new pick (or a link carrying another ID) is confirmed now; a dead
        # mark belonged to the ID that is gone.
        out["google_place_checked_at"] = now if new_id else None
        out["google_place_missing_at"] = None
    return out


def _source_of_unlabelled_write(out: dict[str, Any], existing: Any | None, resulting) -> str | None:
    """The kind of location a body without `place_source` produces."""
    if resulting("map_url"):
        return "link"
    has_coords = resulting("lat") is not None or resulting("lng") is not None
    if resulting("google_place_id") and not has_coords:
        # An installed build saving a Google stop sends null coordinates and no
        # link: the place stays.
        return "google"
    stored = existing.place_source if existing is not None else None
    if has_coords and stored in _COORD_SOURCES:
        return stored
    # Coordinates from a build that cannot say where they came from, or no
    # location at all.
    return None
