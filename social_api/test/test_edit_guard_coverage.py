"""
test_edit_guard_coverage.py — the structural proof that no itinerary mutation
can escape the collaborative-editing guard.

The behavioural tests in test_itinerary_edit_lock.py prove the guard WORKS.
This file proves it is REACHED, and keeps proving it for endpoints that do not
exist yet: a new route under /itineraries/{itinerary_id} with a mutating method
fails the suite until somebody classifies it into exactly one of three sets.

  EDIT_GUARDED   goes through require_edit_access — permission + edit lock +
                 If-Match. Every write to itinerary content or subcontent.
  OWNER_ONLY     owner's own administration of the itinerary: deleting it,
                 who can see it, who can edit it, its cover. No lock: an editor
                 mid-edit is not holding any of these, and the owner must not
                 have to wait out a claim to manage their own trip.
  VIEWER_WRITE   a viewer acting on somebody else's trip (rating, saving).
                 These write sibling tables, never itinerary content, so a lock
                 would only stop strangers rating a trip while its author edits.

Adding a route to the wrong set is a deliberate act with a code review attached.
Adding one to no set is a test failure.
"""

from fastapi.routing import APIRoute

from app.dependencies import require_edit_access
from app.main import app

MUTATING_METHODS = {"POST", "PATCH", "PUT", "DELETE"}

# Anything under this prefix acts on one specific existing itinerary. POST
# /itineraries/ (create) is not here on purpose: there is no itinerary yet to
# hold a claim on, and its own body sets user_id from the caller.
ITINERARY_PREFIX = "/itineraries/{itinerary_id}"


EDIT_GUARDED = {
    ("PATCH", "/itineraries/{itinerary_id}"),
    ("POST", "/itineraries/{itinerary_id}/stops"),
    ("PATCH", "/itineraries/{itinerary_id}/stops/{stop_id}"),
    ("DELETE", "/itineraries/{itinerary_id}/stops/{stop_id}"),
    ("POST", "/itineraries/{itinerary_id}/reorder"),
    ("POST", "/itineraries/{itinerary_id}/annotations"),
    ("PATCH", "/itineraries/{itinerary_id}/annotations/{annotation_id}"),
    ("DELETE", "/itineraries/{itinerary_id}/annotations/{annotation_id}"),
    ("POST", "/itineraries/{itinerary_id}/stops/{stop_id}/annotations"),
    ("PATCH", "/itineraries/{itinerary_id}/stops/{stop_id}/annotations/{annotation_id}"),
    ("DELETE", "/itineraries/{itinerary_id}/stops/{stop_id}/annotations/{annotation_id}"),
    ("POST", "/itineraries/{itinerary_id}/segments"),
    ("PATCH", "/itineraries/{itinerary_id}/segments/{segment_id}"),
    ("DELETE", "/itineraries/{itinerary_id}/segments/{segment_id}"),
    ("POST", "/itineraries/{itinerary_id}/segments/{segment_id}/legs"),
    ("PATCH", "/itineraries/{itinerary_id}/segments/{segment_id}/legs/{leg_id}"),
    ("DELETE", "/itineraries/{itinerary_id}/segments/{segment_id}/legs/{leg_id}"),
}

OWNER_ONLY = {
    ("DELETE", "/itineraries/{itinerary_id}"),
    ("POST", "/itineraries/{itinerary_id}/allowed-users"),
    ("DELETE", "/itineraries/{itinerary_id}/allowed-users/{user_id}"),
    ("POST", "/itineraries/{itinerary_id}/editors"),
    # Owner-or-self: the owner revokes anyone, an editor may revoke only
    # themselves. Still lock-free — walking away is not editing content.
    ("DELETE", "/itineraries/{itinerary_id}/editors/{user_id}"),
    ("POST", "/itineraries/{itinerary_id}/image"),
    ("DELETE", "/itineraries/{itinerary_id}/image"),
}

# The lock endpoints administer the claim itself. Guarding them with the claim
# would mean you need a claim to get a claim.
LOCK_ENDPOINTS = {
    ("POST", "/itineraries/{itinerary_id}/lock"),
    ("POST", "/itineraries/{itinerary_id}/lock/heartbeat"),
    ("DELETE", "/itineraries/{itinerary_id}/lock"),
}

VIEWER_WRITE = {
    ("POST", "/itineraries/{itinerary_id}/ratings"),
    ("DELETE", "/itineraries/{itinerary_id}/ratings/me"),
    ("POST", "/itineraries/{itinerary_id}/save"),
    ("DELETE", "/itineraries/{itinerary_id}/save"),
}

UNGUARDED = OWNER_ONLY | LOCK_ENDPOINTS | VIEWER_WRITE


def _mutating_itinerary_routes() -> set[tuple[str, str]]:
    """Every (method, path) on the live app that writes to one itinerary."""
    found = set()
    for route in app.routes:
        if not isinstance(route, APIRoute):
            continue
        if not route.path.startswith(ITINERARY_PREFIX):
            continue
        for method in route.methods & MUTATING_METHODS:
            found.add((method, route.path))
    return found


def _dependency_callables(route: APIRoute) -> set:
    """Every callable in a route's dependency tree, at any depth.

    Walking the tree rather than reading the signature is what makes this
    robust: the guard is found whether it is declared on the endpoint, nested
    inside another dependency, or attached to the router.
    """
    seen = set()
    pending = list(route.dependant.dependencies)
    while pending:
        dependant = pending.pop()
        if dependant.call is not None:
            seen.add(dependant.call)
        pending.extend(dependant.dependencies)
    return seen


def _route_for(method: str, path: str) -> APIRoute:
    for route in app.routes:
        if isinstance(route, APIRoute) and route.path == path and method in route.methods:
            return route
    raise AssertionError(f"no route registered for {method} {path}")


def test_every_mutating_itinerary_route_is_classified():
    """A new mutating endpoint must be put in one of the sets above.

    This is the test that keeps 'no exceptions' true over time — it fails on
    endpoints nobody has written yet.
    """
    classified = EDIT_GUARDED | UNGUARDED
    live = _mutating_itinerary_routes()

    unclassified = live - classified
    assert not unclassified, (
        "These itinerary mutations are not classified in "
        "test_edit_guard_coverage.py. Decide whether each one needs the edit "
        "guard (require_edit_access) or is genuinely owner-only / viewer-side, "
        f"then add it to the matching set: {sorted(unclassified)}"
    )

    stale = classified - live
    assert not stale, (
        f"These classified routes no longer exist and should be removed: {sorted(stale)}"
    )


def test_classification_sets_do_not_overlap():
    """Exactly one set per route — otherwise 'classified' proves nothing."""
    assert not (EDIT_GUARDED & UNGUARDED)
    assert not (OWNER_ONLY & LOCK_ENDPOINTS)
    assert not (OWNER_ONLY & VIEWER_WRITE)
    assert not (LOCK_ENDPOINTS & VIEWER_WRITE)


def test_every_content_mutation_goes_through_the_guard():
    """The whole point: no write to itinerary content skips permission + lock."""
    for method, path in sorted(EDIT_GUARDED):
        route = _route_for(method, path)
        assert require_edit_access in _dependency_callables(route), (
            f"{method} {path} mutates itinerary content but does not depend on "
            "require_edit_access — it would accept a write from someone holding "
            "no edit claim."
        )


def test_unguarded_routes_stay_deliberately_unguarded():
    """Catches the opposite drift: a lock endpoint that starts requiring a lock
    to get a lock, or a rating that starts 423ing strangers."""
    for method, path in sorted(UNGUARDED):
        route = _route_for(method, path)
        assert require_edit_access not in _dependency_callables(route), (
            f"{method} {path} is classified as not needing the edit guard but "
            "now depends on it. Either move it to EDIT_GUARDED or drop the "
            "dependency."
        )
