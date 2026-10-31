"""
routers/places.py — Google place search for the stop form.

GET  /places/config               — which Google features are on
POST /places/google/autocomplete  — Google's suggestions for the user's text

The form searches OpenStreetMap first, in the app; this is the fallback when
OSM has nothing or the user asks for Google. The key stays here, so it never
ships in an app build, and each user has an hourly budget because Google bills
every request (GOOGLE_PLACES_USER_HOURLY_LIMIT). With GOOGLE_PLACES_API_KEY
unset the POST 404s and the config says so — the app draws no Google row.

The answer is Google's display text: passed through, never stored, never
logged, and a POST with `Cache-Control: no-store` so no cache keeps it either.
Sync `def` on purpose — a blocking call in the threadpool, as translations.
"""

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.database import get_db
from app.dependencies import get_current_user, require_verified_email
from app.errors import ApiError
from app.limiter import limiter
from app.models.user import User
from app.schemas.places import (
    GoogleAutocompleteRequest,
    GoogleAutocompleteResponse,
    GoogleSuggestionOut,
    PlacesConfigResponse,
)
from app.services import google_places

router = APIRouter(prefix="/places", tags=["Places"])


@router.get("/config", response_model=PlacesConfigResponse,
            summary="Which Google place features are available")
def places_config(
    _user: User = Depends(get_current_user),
    settings: Settings = Depends(get_settings),
) -> PlacesConfigResponse:
    return PlacesConfigResponse(
        google_search=settings.google_place_search_enabled,
        google_maps=settings.google_map_embeds_enabled,
    )


@router.post("/google/autocomplete", response_model=GoogleAutocompleteResponse,
             summary="Google place suggestions for the stop form's search text")
# Per IP, in front of the per-user budget: a burst guard, not the budget.
@limiter.limit(lambda: get_settings().PLACE_SEARCH_RATE_LIMIT)
def google_autocomplete(
    request: Request,  # required first positional for slowapi rate limiting
    body: GoogleAutocompleteRequest,
    db: Session = Depends(get_db),
    # A paid call: the same bar as adding a stop.
    current_user: User = Depends(require_verified_email),
    settings: Settings = Depends(get_settings),
) -> JSONResponse:
    if not settings.google_place_search_enabled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not Found")

    now = datetime.now(timezone.utc)
    counted = google_places.reserve_request(
        db, current_user.id, settings.GOOGLE_PLACES_USER_HOURLY_LIMIT, now,
    )
    # Spend is spend even if Google fails, and no transaction may stay open
    # across the call to Google.
    db.commit()
    if not counted:
        next_hour = now.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)
        raise ApiError(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            code="place_search_rate_limited",
            detail="Too many Google place searches — try again later.",
            headers={"Retry-After": str(max(1, int((next_hour - now).total_seconds())))},
        )

    bias = (body.bias.lat, body.bias.lng) if body.bias is not None else None
    suggestions = google_places.autocomplete(settings, body.input, body.language, bias)
    if suggestions is None:
        raise ApiError(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            code="place_search_unavailable",
            detail="Google place search is unavailable right now.",
        )
    answer = GoogleAutocompleteResponse(suggestions=[
        GoogleSuggestionOut(place_id=s.place_id, main_text=s.main_text,
                            secondary_text=s.secondary_text)
        for s in suggestions
    ])
    return JSONResponse(answer.model_dump(mode="json"), headers={"Cache-Control": "no-store"})
