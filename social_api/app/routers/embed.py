"""
routers/embed.py — the one page every Google map in the app is drawn through.

GET /embed/place?id=          a Google place, by its place ID
GET /embed/point?lat=&lng=    a point (OSM or typed coordinates)
GET /embed/search?q=          a text query — only the stop page's fetched link
                              preview uses it, for a link it could name but not
                              place
GET /embed/directions?points= the trip's route: 2–22 points, `|`-separated,
                              each `place_id:<id>` or `lat,lng`
                              (origin + up to 20 waypoints + destination)

Each takes `language` (never `lang`: LanguageCookieMiddleware would write the
web cookie from it). The app's WebView loads these pages and the web app frames
them; the page frames Google's free Maps Embed API with GOOGLE_MAPS_EMBED_API_KEY.
That keeps the key on the server — rotated with an env var, not an app release —
and gives Google a real referrer (this site) on phones too, where a WebView
built from an HTML string sent none.

Strict on input: only the parameters above, each validated, anything else a 400
that echoes nothing back. No database, no session: classified MAP_EMBED in
test_public_surface.py. `/embed/*` is the one path family other pages of ours
may frame (SecurityHeadersMiddleware, EMBED_FRAME_ANCESTORS). Unset key → 404,
and the app (told by /places/config) draws no map.
"""

import math
import re
from urllib.parse import urlencode

from fastapi import APIRouter, Depends, Request
from fastapi.responses import HTMLResponse, Response

from app.config import Settings, get_settings
from app.i18n import SUPPORTED
from app.limiter import limiter
from app.templating import templates

router = APIRouter(prefix="/embed", include_in_schema=False)

_GOOGLE_EMBED = "https://www.google.com/maps/embed/v1/"
_PLACE_ID = re.compile(r"^[A-Za-z0-9_-]{1,1024}$")
_MAX_QUERY = 200
_MIN_POINTS, _MAX_POINTS = 2, 22
# The zoom the map preview has always used: a city with its surroundings.
_ZOOM = "12"
_CACHE = "public, max-age=86400"


class _Refused(Exception):
    pass


def _params(request: Request, allowed: set[str]) -> dict[str, str]:
    items = request.query_params.multi_items()
    keys = [key for key, _ in items]
    if any(key not in allowed for key in keys) or len(keys) != len(set(keys)):
        raise _Refused
    return dict(items)


def _language(params: dict[str, str]) -> str:
    language = params.get("language", "en")
    if language not in SUPPORTED:
        raise _Refused
    return language


def _coordinate(raw: str | None, bound: float) -> str:
    try:
        value = float(raw or "")
    except ValueError:
        raise _Refused
    if not math.isfinite(value) or abs(value) > bound:
        raise _Refused
    return f"{value:.6f}".rstrip("0").rstrip(".")


def _point_token(token: str) -> str:
    if token.startswith("place_id:"):
        place_id = token[len("place_id:"):]
        if not _PLACE_ID.match(place_id):
            raise _Refused
        return token
    lat, sep, lng = token.partition(",")
    if not sep:
        raise _Refused
    return f"{_coordinate(lat, 90)},{_coordinate(lng, 180)}"


def _page(request: Request, settings: Settings, mode: str, query: dict[str, str],
          language: str) -> Response:
    src = _GOOGLE_EMBED + mode + "?" + urlencode(
        {"key": settings.GOOGLE_MAPS_EMBED_API_KEY, **query, "language": language},
        safe=":,|",
    )
    return templates.TemplateResponse(
        request, "embed.html", {"src": src, "language": language},
        headers={"Cache-Control": _CACHE},
    )


def _refused(status_code: int) -> Response:
    return HTMLResponse("", status_code=status_code, headers={"Cache-Control": "no-store"})


def _serve(request: Request, settings: Settings, build) -> Response:
    if not settings.google_map_embeds_enabled:
        return _refused(404)
    try:
        return build()
    except _Refused:
        return _refused(400)


@router.get("/place", response_class=HTMLResponse)
@limiter.limit(lambda: get_settings().EMBED_RATE_LIMIT)
def embed_place(request: Request, settings: Settings = Depends(get_settings)) -> Response:
    def build():
        params = _params(request, {"id", "language"})
        place_id = params.get("id", "")
        if not _PLACE_ID.match(place_id):
            raise _Refused
        return _page(request, settings, "place",
                     {"q": f"place_id:{place_id}", "zoom": _ZOOM}, _language(params))
    return _serve(request, settings, build)


@router.get("/point", response_class=HTMLResponse)
@limiter.limit(lambda: get_settings().EMBED_RATE_LIMIT)
def embed_point(request: Request, settings: Settings = Depends(get_settings)) -> Response:
    def build():
        params = _params(request, {"lat", "lng", "language"})
        point = f"{_coordinate(params.get('lat'), 90)},{_coordinate(params.get('lng'), 180)}"
        return _page(request, settings, "place", {"q": point, "zoom": _ZOOM},
                     _language(params))
    return _serve(request, settings, build)


@router.get("/search", response_class=HTMLResponse)
@limiter.limit(lambda: get_settings().EMBED_RATE_LIMIT)
def embed_search(request: Request, settings: Settings = Depends(get_settings)) -> Response:
    def build():
        params = _params(request, {"q", "language"})
        query = params.get("q", "").strip()
        if not query or len(query) > _MAX_QUERY:
            raise _Refused
        return _page(request, settings, "place", {"q": query, "zoom": _ZOOM},
                     _language(params))
    return _serve(request, settings, build)


@router.get("/directions", response_class=HTMLResponse)
@limiter.limit(lambda: get_settings().EMBED_RATE_LIMIT)
def embed_directions(request: Request, settings: Settings = Depends(get_settings)) -> Response:
    def build():
        params = _params(request, {"points", "language"})
        tokens = [token.strip() for token in params.get("points", "").split("|")]
        if not _MIN_POINTS <= len(tokens) <= _MAX_POINTS:
            raise _Refused
        points = [_point_token(token) for token in tokens]
        query = {"origin": points[0], "destination": points[-1]}
        if len(points) > 2:
            query["waypoints"] = "|".join(points[1:-1])
        # No `mode`: Google shows the most relevant ones for the route.
        return _page(request, settings, "directions", query, _language(params))
    return _serve(request, settings, build)


def rate_limited_page(request: Request, exc) -> Response:
    """The /embed 429: a blank frame rather than slowapi's JSON in a map box."""
    return HTMLResponse("", status_code=429, headers={"Cache-Control": "no-store"})
