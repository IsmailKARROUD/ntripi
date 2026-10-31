"""
services/google_places.py — Google Places (New): place search and ID refresh.

Two calls, both on GOOGLE_PLACES_API_KEY:

  autocomplete   the stop form's Google fallback. Billed per request (no Place
                 Details ever follows: a suggestion already carries its place
                 ID, and a session ended by Place Details would still bill every
                 request and add the Details call on top).
  refresh        the yearly check of a stored place ID — Place Details with the
                 field mask `id` only, the free "IDs Only" SKU.

What crosses to Google is the search text, the app language and a bias point
rounded to 0.1° — never a user id, an email, a stop or a trip. What comes back
is passed through to the app and never stored, cached or logged: the place ID
(stored by the stop write, the only Google content our terms allow) is the one
exception, and it is the client that sends it back.

FAILS QUIET, never raises: every unusable answer is None (or a transient
outcome) and the caller answers 503 or skips. Logs carry the status code or the
exception class, never a body — copy this, not jira_service, whose logs quote
`resp.text`. Sync `requests` on purpose: the callers are sync endpoints in the
threadpool and the sweep, and requests.Session.send is the seam the slow-request
log times outbound calls through.
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any

import requests
from sqlalchemy import delete
from sqlalchemy.orm import Session

from app.database import reserve_within_limit
from app.models.place_search_usage import PlaceSearchUsage

logger = logging.getLogger(__name__)

_AUTOCOMPLETE_URL = "https://places.googleapis.com/v1/places:autocomplete"
_DETAILS_URL = "https://places.googleapis.com/v1/places/{place_id}"
# Only what the app shows: the ID and the two display lines.
_AUTOCOMPLETE_FIELDS = (
    "suggestions.placePrediction.placeId,"
    "suggestions.placePrediction.structuredFormat"
)
# The bias circle: wide enough for a city and its surroundings. Google's max.
_BIAS_RADIUS_METERS = 50_000.0
# Old enough that no hourly budget can still read them.
_USAGE_ROWS_KEPT = timedelta(days=2)


@dataclass(frozen=True)
class Suggestion:
    place_id: str
    main_text: str
    secondary_text: str | None


@dataclass(frozen=True)
class RefreshOutcome:
    """`kind`: 'kept' (same ID), 'changed' (Google answered another ID),
    'missing' (NOT_FOUND / INVALID_REQUEST), or 'transient' (try again later)."""
    kind: str
    place_id: str | None = None


def round_bias(value: float) -> float:
    """0.1° (about 11 km): enough to steer a search, too coarse to place a person."""
    return round(value, 1)


def autocomplete(settings, text: str, language: str,
                 bias: tuple[float, float] | None) -> list[Suggestion] | None:
    """Google's suggestions for `text`, or None when Google could not answer."""
    body: dict[str, Any] = {"input": text, "languageCode": language}
    if bias is not None:
        body["locationBias"] = {"circle": {
            "center": {"latitude": round_bias(bias[0]), "longitude": round_bias(bias[1])},
            "radius": _BIAS_RADIUS_METERS,
        }}
    try:
        response = requests.post(
            _AUTOCOMPLETE_URL,
            json=body,
            headers={
                "X-Goog-Api-Key": settings.GOOGLE_PLACES_API_KEY,
                "X-Goog-FieldMask": _AUTOCOMPLETE_FIELDS,
            },
            timeout=settings.GOOGLE_PLACES_TIMEOUT_SECONDS,
        )
    except requests.RequestException as exc:
        logger.warning("Places autocomplete failed: %s", exc.__class__.__name__)
        return None
    if response.status_code != 200:
        logger.warning("Places autocomplete returned %s", response.status_code)
        return None
    try:
        payload = response.json()
    except ValueError:
        logger.warning("Places autocomplete returned a non-JSON body")
        return None
    return _suggestions(payload)


def _suggestions(payload: Any) -> list[Suggestion] | None:
    if not isinstance(payload, dict):
        return None
    out: list[Suggestion] = []
    for item in payload.get("suggestions") or []:
        prediction = item.get("placePrediction") if isinstance(item, dict) else None
        if not isinstance(prediction, dict):
            continue  # a query prediction, or a shape this build does not know
        place_id = prediction.get("placeId")
        fmt = prediction.get("structuredFormat") or {}
        main = (fmt.get("mainText") or {}).get("text")
        if not isinstance(place_id, str) or not place_id or not isinstance(main, str):
            continue
        secondary = (fmt.get("secondaryText") or {}).get("text")
        out.append(Suggestion(
            place_id=place_id,
            main_text=main,
            secondary_text=secondary if isinstance(secondary, str) else None,
        ))
    return out


def refresh(settings, place_id: str) -> RefreshOutcome:
    """Ask Google whether a stored place ID still stands (free, IDs only)."""
    try:
        response = requests.get(
            _DETAILS_URL.format(place_id=place_id),
            headers={
                "X-Goog-Api-Key": settings.GOOGLE_PLACES_API_KEY,
                "X-Goog-FieldMask": "id",
            },
            timeout=settings.GOOGLE_PLACES_TIMEOUT_SECONDS,
        )
    except requests.RequestException as exc:
        logger.warning("Place ID refresh failed: %s", exc.__class__.__name__)
        return RefreshOutcome("transient")
    if response.status_code == 200:
        try:
            current = response.json().get("id")
        except (ValueError, AttributeError):
            return RefreshOutcome("transient")
        if not isinstance(current, str) or not current:
            return RefreshOutcome("transient")
        return RefreshOutcome("kept" if current == place_id else "changed", current)
    if response.status_code == 404 or _is_invalid_place_id(response):
        # Obsolete (closed, moved, merged) or not a usable ID any more.
        return RefreshOutcome("missing")
    logger.warning("Place ID refresh returned %s", response.status_code)
    return RefreshOutcome("transient")


def _is_invalid_place_id(response) -> bool:
    """A 400 naming the place ID as invalid — not a 400 about our own request."""
    if response.status_code != 400:
        return False
    try:
        message = str((response.json().get("error") or {}).get("message", "")).lower()
    except (ValueError, AttributeError):
        return False
    return "place id" in message or "place_id" in message


def reserve_request(db: Session, user_id: uuid.UUID, limit: int, now: datetime) -> bool:
    """Count one search against the user's hour if it fits under `limit`."""
    return reserve_within_limit(
        db, PlaceSearchUsage,
        {"user_id": user_id, "hour_start": now.replace(minute=0, second=0, microsecond=0)},
        PlaceSearchUsage.requests, 1, limit,
    )


def purge_usage(db: Session, now: datetime) -> int:
    """Delete hourly counters no budget can still read."""
    result = db.execute(
        delete(PlaceSearchUsage).where(PlaceSearchUsage.hour_start < now - _USAGE_ROWS_KEPT)
    )
    return result.rowcount or 0
