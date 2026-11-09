"""
test_text_limits.py — the app's text caps are the API's.

The app keeps every cap the server puts on a user's text in one file,
social_flutter/lib/core/text/text_limits.dart: a field shows its count from 90%
of its cap and holds Save back past it, so the server's 422 is never what tells
the user. A cap changed on one side only would bring that 422 back — or have
the app refuse text the server takes. The two codebases share no code, so this
reads the Dart file and checks each number against the request schemas the app
writes through, taken from the API's own OpenAPI document.

Coverage:
  TestEveryCapIsTheApis — each TextLimits constant equals the max_length of
                          every request field it stands for
  TestNothingUnchecked  — every constant is mapped here, and every free-text
                          field the app writes is
"""

import re
from pathlib import Path

import pytest

from app.main import app

API = Path(__file__).resolve().parents[1]
TEXT_LIMITS = (
    API.parent / "social_flutter" / "lib" / "core" / "text" / "text_limits.dart"
)

_CONST = re.compile(r"static const (\w+) = (\d+);")

# Each app constant → the request fields it caps: (method, path, property).
# A path's body is its JSON schema, or a multipart form's for the bug report.
FIELDS: dict[str, list[tuple[str, str, str]]] = {
    "itineraryTitle": [
        ("post", "/itineraries/", "title"),
        ("patch", "/itineraries/{itinerary_id}", "title"),
    ],
    "itineraryDescription": [
        ("post", "/itineraries/", "description"),
        ("patch", "/itineraries/{itinerary_id}", "description"),
    ],
    "periodNote": [
        ("post", "/itineraries/", "recommended_period_note"),
        ("patch", "/itineraries/{itinerary_id}", "recommended_period_note"),
    ],
    "stopName": [
        ("post", "/itineraries/{itinerary_id}/stops", "place_name"),
        ("patch", "/itineraries/{itinerary_id}/stops/{stop_id}", "place_name"),
    ],
    "stopAddress": [
        ("post", "/itineraries/{itinerary_id}/stops", "place_address"),
        ("patch", "/itineraries/{itinerary_id}/stops/{stop_id}", "place_address"),
    ],
    "stopNotes": [
        ("post", "/itineraries/{itinerary_id}/stops", "notes"),
        ("patch", "/itineraries/{itinerary_id}/stops/{stop_id}", "notes"),
    ],
    "mapLink": [
        ("post", "/itineraries/{itinerary_id}/stops", "map_url"),
        ("patch", "/itineraries/{itinerary_id}/stops/{stop_id}", "map_url"),
    ],
    "placeSearch": [
        ("post", "/places/google/autocomplete", "input"),
        ("post", "/itineraries/{itinerary_id}/stops", "google_place_query"),
        ("patch", "/itineraries/{itinerary_id}/stops/{stop_id}", "google_place_query"),
    ],
    "annotation": [
        ("post", "/itineraries/{itinerary_id}/annotations", "content"),
        ("patch", "/itineraries/{itinerary_id}/annotations/{annotation_id}", "content"),
        ("post", "/itineraries/{itinerary_id}/stops/{stop_id}/annotations", "content"),
        ("patch",
         "/itineraries/{itinerary_id}/stops/{stop_id}/annotations/{annotation_id}",
         "content"),
    ],
    "legLine": [
        ("post", "/itineraries/{itinerary_id}/segments/{segment_id}/legs", "line"),
        ("patch",
         "/itineraries/{itinerary_id}/segments/{segment_id}/legs/{leg_id}", "line"),
    ],
    "legDirection": [
        ("post", "/itineraries/{itinerary_id}/segments/{segment_id}/legs", "direction"),
        ("patch",
         "/itineraries/{itinerary_id}/segments/{segment_id}/legs/{leg_id}",
         "direction"),
    ],
    "legNotes": [
        ("post", "/itineraries/{itinerary_id}/segments/{segment_id}/legs", "notes"),
        ("patch",
         "/itineraries/{itinerary_id}/segments/{segment_id}/legs/{leg_id}", "notes"),
    ],
    "ratingNote": [("post", "/itineraries/{itinerary_id}/ratings", "note")],
    "displayName": [
        ("patch", "/users/me", "display_name"),
        ("post", "/auth/register", "display_name"),
    ],
    "bio": [("patch", "/users/me", "bio")],
    "username": [("post", "/auth/register", "username")],
    "reportNotes": [("post", "/reports", "notes")],
    "appealReason": [("post", "/appeals", "reason")],
    "bugMessage": [("post", "/bug-reports", "message")],
}

# Free text the app writes that is capped some other way, with the reason.
NOT_TEXT_LIMITS = {
    # A three-letter code chosen from a list, never typed.
    ("post", "/itineraries/", "currency"),
    ("patch", "/itineraries/{itinerary_id}", "currency"),
    # Google's own identifier, sent as Google gave it — never typed.
    ("post", "/itineraries/{itinerary_id}/stops", "google_place_id"),
    ("patch", "/itineraries/{itinerary_id}/stops/{stop_id}", "google_place_id"),
    # A password: the app holds it to bcrypt's 72 bytes, well under the cap.
    ("post", "/auth/register", "password"),
}


def _dart_limits() -> dict[str, int]:
    return {
        name: int(value)
        for name, value in _CONST.findall(TEXT_LIMITS.read_text(encoding="utf-8"))
    }


@pytest.fixture(scope="module")
def spec() -> dict:
    return app.openapi()


def _resolve(spec: dict, schema: dict) -> dict:
    ref = schema.get("$ref")
    if ref is None:
        return schema
    return spec["components"]["schemas"][ref.rsplit("/", 1)[-1]]


def _body(spec: dict, method: str, path: str) -> dict:
    content = spec["paths"][path][method]["requestBody"]["content"]
    media = content.get("application/json") or content["multipart/form-data"]
    return _resolve(spec, media["schema"])


def _max_length(spec: dict, prop: dict) -> int | None:
    """A property's maxLength — on itself, or on the string arm of an Optional."""
    if "maxLength" in prop:
        return prop["maxLength"]
    for arm in prop.get("anyOf", ()):
        arm = _resolve(spec, arm)
        if "maxLength" in arm:
            return arm["maxLength"]
    return None


class TestEveryCapIsTheApis:

    @pytest.mark.parametrize("name", sorted(FIELDS))
    def test_the_app_cap_is_the_api_cap(self, spec, name):
        limits = _dart_limits()
        assert name in limits, f"TextLimits.{name} is missing from text_limits.dart"
        for method, path, prop in FIELDS[name]:
            schema = _body(spec, method, path)
            assert prop in schema["properties"], f"{method} {path} has no {prop}"
            api_cap = _max_length(spec, schema["properties"][prop])
            assert api_cap == limits[name], (
                f"TextLimits.{name} is {limits[name]}, but {method.upper()} "
                f"{path} caps {prop} at {api_cap} — change both together"
            )


class TestNothingUnchecked:

    def test_every_app_constant_is_mapped(self):
        unmapped = set(_dart_limits()) - set(FIELDS)
        assert not unmapped, (
            f"TextLimits {sorted(unmapped)} stand for no request field here — "
            "map each to the API fields it caps"
        )

    def test_every_capped_string_the_app_writes_is_mapped(self, spec):
        # The routes the app's text fields write through; any capped string
        # property on them is a field the app must hold to its cap.
        paths = {(method, path) for fields in FIELDS.values()
                 for method, path, _ in fields}
        mapped = {field for fields in FIELDS.values() for field in fields}
        missing = []
        for method, path in sorted(paths):
            for prop, schema in _body(spec, method, path)["properties"].items():
                field = (method, path, prop)
                if (_max_length(spec, schema) is not None
                        and field not in mapped and field not in NOT_TEXT_LIMITS):
                    missing.append(field)
        assert not missing, (
            f"capped text fields with no TextLimits constant: {missing} — add "
            "one to text_limits.dart and map it here, or list the field in "
            "NOT_TEXT_LIMITS with the reason"
        )
