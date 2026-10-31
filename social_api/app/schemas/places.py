"""
schemas/places.py — the stop form's Google place search and its config.

The suggestion fields are Google's display text, passed through for the user to
choose from and never stored: only the chosen place ID comes back, on the stop
write, with the user's own search text.
"""

from typing import Optional

from pydantic import BaseModel, Field, field_validator

from app.i18n import SUPPORTED

_LANGUAGE_PATTERN = "^(" + "|".join(SUPPORTED) + ")$"


class PlacesConfigResponse(BaseModel):
    # Each is on only while its key is set (GOOGLE_PLACES_API_KEY,
    # GOOGLE_MAPS_EMBED_API_KEY).
    google_search: bool
    google_maps: bool


class BiasPoint(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


class GoogleAutocompleteRequest(BaseModel):
    input: str = Field(min_length=3, max_length=200)
    language: str = Field(pattern=_LANGUAGE_PATTERN)
    # The trip's own anchor stop, or the device on a trip's first search;
    # rounded to 0.1° before it leaves the server either way.
    bias: Optional[BiasPoint] = None

    @field_validator("input")
    @classmethod
    def _strip(cls, value: str) -> str:
        value = value.strip()
        if len(value) < 3:
            raise ValueError("input needs at least 3 characters")
        return value


class GoogleSuggestionOut(BaseModel):
    place_id: str
    main_text: str
    secondary_text: Optional[str] = None


class GoogleAutocompleteResponse(BaseModel):
    suggestions: list[GoogleSuggestionOut]
