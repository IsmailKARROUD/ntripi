"""
test_public_surface.py — the proof that a reader without an account reaches the
teaser and nothing else.

Two halves, the same shape as test_edit_guard_coverage.py:

  Structural — every route the app serves without sign-in is classified below
  by what it hands out. A new open route fails the suite until somebody
  classifies it, and a classified one that disappears fails it too, so the
  list stays the truth.

  Sentinel — a public trip, a private trip, a hidden trip and two profiles are
  seeded with a unique marker in every field that is NOT teaser content: stop
  names, addresses and notes, both kinds of annotation, transport legs, a
  review, bios, a profile cover, emails. Every open GET is then fetched signed
  out — every /admin page too — and the anonymous report POST made, and a
  marker anywhere in a response, body or headers, fails the test.

What a signed-in reader may see is a different question, answered by
can_view_itinerary; this file is only about the reader with no account.
"""

from datetime import datetime, timezone
import uuid

from fastapi.routing import APIRoute
from starlette.routing import Mount

from app.config import get_settings
from app.main import app
from app.models.itinerary import Itinerary
from app.models.user import User

from conftest import TestingSessionLocal, auth_headers, edit_now, register_user

# Dependencies that make a route require an account (require_edit_access and
# friends all resolve through get_current_user).
AUTH_DEPENDENCIES = {"get_current_user", "require_verified_email"}
# The admin pages have their own sign-in (HTTP Basic + an admin session).
ADMIN_DEPENDENCIES = {"_require_admin_page", "_require_basic"}

TEASER = "teaser"              # /share/*: the teaser, and only it
HELP = "help"                  # help centre: our own prose, no user content
LEGAL = "legal"                # legal documents
SITE = "site"                  # the homepage: our own marketing, no user content
AUTH_FLOW = "auth-flow"        # sign in / up / out; answers about the caller only
TOKEN_FORM = "token-form"      # emailed-token pages; need the token to do anything
MACHINE = "machine-file"       # robots, sitemap, llms, app association files
HEALTH = "health"
ANONYMOUS_WRITE = "anonymous-write"  # takes input, returns an acknowledgement
INTERNAL = "internal"          # bearer-token maintenance; 404 without its token
MAP_EMBED = "map-embed"        # a Google map frame built from its own query only

PUBLIC_ROUTES = {
    ("GET", "/share/i/{itinerary_id}"): TEASER,
    ("GET", "/share/u/{username}"): TEASER,
    ("GET", "/auth/tos"): LEGAL,
    ("GET", "/privacy"): LEGAL,
    ("GET", "/terms"): LEGAL,
    ("GET", "/guidelines"): LEGAL,
    ("GET", "/help"): HELP,
    ("GET", "/help/search"): HELP,
    ("GET", "/help/search-index.json"): HELP,
    ("GET", "/help/{slug}.md"): HELP,
    ("GET", "/help/{slug}"): HELP,
    ("GET", "/"): SITE,
    ("GET", "/login"): AUTH_FLOW,
    ("GET", "/register"): AUTH_FLOW,
    ("POST", "/auth/register"): AUTH_FLOW,
    ("POST", "/auth/login"): AUTH_FLOW,
    ("POST", "/auth/google"): AUTH_FLOW,
    ("POST", "/auth/refresh"): AUTH_FLOW,
    ("POST", "/auth/logout"): AUTH_FLOW,
    ("POST", "/auth/forgot-password"): AUTH_FLOW,
    ("GET", "/reset-password"): TOKEN_FORM,
    ("GET", "/verify-email"): TOKEN_FORM,
    ("GET", "/appeal/{token}"): TOKEN_FORM,
    ("GET", "/appeal"): TOKEN_FORM,
    ("POST", "/web/reset-password"): TOKEN_FORM,
    ("POST", "/web/appeal"): TOKEN_FORM,
    ("POST", "/web/appeal-request"): TOKEN_FORM,
    ("GET", "/robots.txt"): MACHINE,
    ("GET", "/sitemap.xml"): MACHINE,
    ("GET", "/llms.txt"): MACHINE,
    ("GET", "/llms-full.txt"): MACHINE,
    ("GET", "/.well-known/apple-app-site-association"): MACHINE,
    ("GET", "/.well-known/assetlinks.json"): MACHINE,
    ("GET", "/manifest.webmanifest"): MACHINE,
    ("GET", "/health"): HEALTH,
    ("POST", "/reports"): ANONYMOUS_WRITE,
    ("POST", "/bug-reports"): ANONYMOUS_WRITE,
    ("POST", "/waitlist/join"): ANONYMOUS_WRITE,
    ("POST", "/internal/moderation-sweep"): INTERNAL,
    ("GET", "/embed/place"): MAP_EMBED,
    ("GET", "/embed/point"): MAP_EMBED,
    ("GET", "/embed/search"): MAP_EMBED,
    ("GET", "/embed/directions"): MAP_EMBED,
}

# Static mounts. /uploads serves stored images by key — which is why step 2 of
# the share-teaser work makes those keys impossible to derive from an id.
# /app is the Flutter web build, present only once it has been built.
ALLOWED_MOUNTS = {"/static", "/uploads", "/app"}

# FastAPI's own pages, served only with DEBUG on (main.py).
DEBUG_ONLY_PATHS = {"/openapi.json", "/docs", "/docs/oauth2-redirect", "/redoc"}


def _dependency_names(dependant, seen=None) -> set[str]:
    seen = set() if seen is None else seen
    for dep in dependant.dependencies:
        seen.add(getattr(dep.call, "__name__", type(dep.call).__name__))
        _dependency_names(dep, seen)
    return seen


def _open_routes() -> set[tuple[str, str]]:
    """Every (method, path) the app answers without an account."""
    found = set()
    for route in app.routes:
        if not isinstance(route, APIRoute):
            continue
        names = _dependency_names(route.dependant)
        if names & (AUTH_DEPENDENCIES | ADMIN_DEPENDENCIES):
            continue
        for method in route.methods - {"HEAD"}:
            found.add((method, route.path))
    return found


# ---------------------------------------------------------------------------
# Structural
# ---------------------------------------------------------------------------

def test_every_open_route_is_classified():
    unclassified = _open_routes() - set(PUBLIC_ROUTES)
    assert not unclassified, (
        f"routes reachable without an account that nobody has classified: "
        f"{sorted(unclassified)} — add each to PUBLIC_ROUTES with what it hands "
        f"out, or put it behind get_current_user"
    )


def test_no_classified_route_has_gone_stale():
    stale = set(PUBLIC_ROUTES) - _open_routes()
    assert not stale, f"classified but no longer open (or gone): {sorted(stale)}"


def test_every_admin_route_has_its_own_guard():
    unguarded = [
        (sorted(route.methods), route.path)
        for route in app.routes
        if isinstance(route, APIRoute)
        and route.path.startswith("/admin")
        and not _dependency_names(route.dependant) & ADMIN_DEPENDENCIES
    ]
    assert not unguarded, f"admin routes without the admin guard: {unguarded}"


def test_mounts_are_only_the_static_ones():
    mounts = {route.path for route in app.routes if isinstance(route, Mount)}
    assert mounts <= ALLOWED_MOUNTS, f"unexpected mounts: {mounts - ALLOWED_MOUNTS}"


def test_fastapi_pages_only_in_debug():
    """The schema is a map of every endpoint; production serves none of these."""
    debug = get_settings().DEBUG
    other = {
        route.path for route in app.routes
        if not isinstance(route, (APIRoute, Mount))
    }
    if debug:
        assert other <= DEBUG_ONLY_PATHS
    else:
        assert not other, f"served without DEBUG: {other}"
    assert app.openapi_url == ("/openapi.json" if debug else None)


# ---------------------------------------------------------------------------
# Sentinel
# ---------------------------------------------------------------------------

# Never teaser content: none of these may appear in any answer to a reader
# without an account.
MARKERS = (
    "SENTINEL-STOP-NAME", "SENTINEL-STOP-ADDRESS", "SENTINEL-STOP-NOTE",
    "SENTINEL-TRIP-ANNOTATION", "SENTINEL-STOP-ANNOTATION",
    "SENTINEL-LEG-LINE", "SENTINEL-LEG-NOTE", "SENTINEL-REVIEW",
    "SENTINEL-OWNER-BIO", "SENTINEL-SHY-BIO", "SENTINEL-PROFILE-COVER",
    "SENTINEL-PRIVATE-TITLE", "SENTINEL-PRIVATE-DESC", "SENTINEL-PRIVATE-COVER",
    "SENTINEL-HIDDEN-TITLE",
    "sentowner@example.com", "sentrater@example.com", "sentshy@example.com",
)
# The owner is profile teaser content, never trip teaser content.
OWNER_MARKERS = ("sentowner", "Visible Owner", "owner-avatar.jpg")

PUBLIC_TITLE = "Teaser Title Visible"
PUBLIC_DESCRIPTION = "Teaser description visible."


def _write_rows(model, row_id, **fields):
    db = TestingSessionLocal()
    try:
        row = db.get(model, row_id)
        for name, value in fields.items():
            setattr(row, name, value)
        db.commit()
    finally:
        db.close()


def _seed(client) -> dict:
    owner = register_user(client, "sentowner", "sentowner@example.com",
                          display_name="Visible Owner")
    token = owner["access_token"]
    client.patch("/users/me", json={"is_private": False, "bio": "SENTINEL-OWNER-BIO"},
                 headers=auth_headers(token))
    owner_id = uuid.UUID(client.get("/users/me", headers=auth_headers(token)).json()["id"])
    _write_rows(
        User, owner_id,
        avatar_url="https://images.example/owner-avatar.jpg",
        cover_image_url="https://images.example/SENTINEL-PROFILE-COVER.jpg",
    )

    # The public trip, with every kind of content below the teaser.
    trip = client.post("/itineraries/", json={"title": PUBLIC_TITLE, "visibility": "public"},
                       headers=auth_headers(token)).json()
    tid = trip["id"]
    client.patch(f"/itineraries/{tid}", json={"description": PUBLIC_DESCRIPTION},
                 headers=edit_now(client, tid, auth_headers(token)))
    stops = []
    for _ in range(2):
        r = client.post(
            f"/itineraries/{tid}/stops",
            json={"place_name": "SENTINEL-STOP-NAME",
                  "place_address": "SENTINEL-STOP-ADDRESS",
                  "notes": "SENTINEL-STOP-NOTE"},
            headers=edit_now(client, tid, auth_headers(token)),
        )
        assert r.status_code == 201, r.json()
        stops.append(r.json())
    for url, content in (
        (f"/itineraries/{tid}/annotations", "SENTINEL-TRIP-ANNOTATION"),
        (f"/itineraries/{tid}/stops/{stops[0]['id']}/annotations", "SENTINEL-STOP-ANNOTATION"),
    ):
        r = client.post(url, json={"type": "advice", "content": content},
                        headers=edit_now(client, tid, auth_headers(token)))
        assert r.status_code == 201, r.json()
    r = client.post(
        f"/itineraries/{tid}/segments",
        json={"from_stop_id": stops[0]["id"], "to_stop_id": stops[1]["id"],
              "legs": [{"position": 1, "mode": "bus", "line": "SENTINEL-LEG-LINE",
                        "notes": "SENTINEL-LEG-NOTE"}]},
        headers=edit_now(client, tid, auth_headers(token)),
    )
    assert r.status_code == 201, r.json()

    rater = register_user(client, "sentrater", "sentrater@example.com")
    r = client.post(f"/itineraries/{tid}/ratings", json={"stars": 5, "note": "SENTINEL-REVIEW"},
                    headers=auth_headers(rater["access_token"]))
    assert r.status_code == 201, r.json()

    private = client.post(
        "/itineraries/",
        json={"title": "SENTINEL-PRIVATE-TITLE", "visibility": "followers",
              "description": "SENTINEL-PRIVATE-DESC"},
        headers=auth_headers(token),
    ).json()
    _write_rows(Itinerary, uuid.UUID(private["id"]),
                cover_image_url="https://images.example/SENTINEL-PRIVATE-COVER.jpg")

    hidden = client.post("/itineraries/",
                         json={"title": "SENTINEL-HIDDEN-TITLE", "visibility": "public"},
                         headers=auth_headers(token)).json()
    _write_rows(Itinerary, uuid.UUID(hidden["id"]), hidden_at=datetime.now(timezone.utc))

    shy = register_user(client, "sentshy", "sentshy@example.com", display_name="Shy One")
    client.patch("/users/me", json={"bio": "SENTINEL-SHY-BIO"},
                 headers=auth_headers(shy["access_token"]))

    return {"public": tid, "private": private["id"], "hidden": hidden["id"]}


def _urls(path: str, seed: dict) -> list[str]:
    """Concrete URLs for a route template, filled from the seed."""
    fills = {
        "{itinerary_id}": [seed["public"], seed["private"], seed["hidden"],
                           "00000000-0000-0000-0000-000000000000"],
        "{username}": ["sentowner", "sentshy", "nobody-here"],
        "{slug}": ["share-a-trip-link"],
        "{token}": ["not-a-real-token"],
    }
    for placeholder, values in fills.items():
        if placeholder in path:
            return [path.replace(placeholder, value) for value in values]
    return [path]


def _assert_clean(url: str, response) -> None:
    seen = response.text + "\n" + "\n".join(f"{k}: {v}" for k, v in response.headers.items())
    leaked = [m for m in MARKERS if m in seen]
    if url.startswith("/share/i/"):
        leaked += [m for m in OWNER_MARKERS if m in seen]
    assert not leaked, f"{url} handed a reader without an account: {leaked}"


def test_no_open_route_hands_out_more_than_the_teaser(client):
    seed = _seed(client)

    for method, path in sorted(PUBLIC_ROUTES):
        if method != "GET":
            continue
        for url in _urls(path, seed):
            _assert_clean(url, client.get(url, follow_redirects=False))

    for route in app.routes:
        if isinstance(route, APIRoute) and route.path.startswith("/admin") \
                and "GET" in route.methods:
            for url in _urls(route.path, seed):
                _assert_clean(url, client.get(url, follow_redirects=False))

    report = client.post("/reports", json={"itinerary_id": seed["public"], "reason": "spam"})
    assert report.status_code == 201, report.text
    _assert_clean("/reports", report)


def test_the_teaser_itself_still_reaches_the_reader(client):
    """The other half of the promise: the teaser fields are there."""
    seed = _seed(client)

    trip = client.get(f"/share/i/{seed['public']}").text
    assert PUBLIC_TITLE in trip
    assert PUBLIC_DESCRIPTION in trip
    assert "1 rating" in trip

    profile = client.get("/share/u/sentowner").text
    assert "Visible Owner" in profile
    assert "@sentowner" in profile
    assert "owner-avatar.jpg" in profile
