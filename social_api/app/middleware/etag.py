"""
middleware/etag.py — Conditional GET / 304 Not Modified middleware.

Saves bandwidth on warm requests: the server hashes every JSON GET response
body to a short opaque ETag. On the next request the client sends back
`If-None-Match: "<digest>"`, and if the resource is unchanged the middleware
returns `304 Not Modified` with empty body — the client renders from its
local cache.

Why a body hash instead of `updated_at`?
  - Cross-stack format drift kills byte-compared ETags (`Z` vs `+00:00`,
    microsecond truncation, naive-vs-aware datetimes). Hashes are opaque.
  - Lists / search / feeds have no single `updated_at` to derive from.
    A body hash works for every response shape without schema coupling.

Endpoints that need ETag for *concurrency* (If-Match) still set their own
ETag explicitly (see `_etag_value` in `app/dependencies.py`). That token alone
cannot validate a cache: a rating or a moderator hide changes the body while
deliberately leaving `updated_at` alone, so a 304 against it served stale
averages indefinitely. The middleware therefore emits `"<token>;<body hash>"`
for those — `require_etag` reads only the part before `;`, so the header still
works as an If-Match. An endpoint that sets `Cache-Control` keeps it, so a
public document is not forced down to `private, no-cache`.
"""

import hashlib

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response
from starlette.types import ASGIApp

from app.dependencies import _normalize_etag
from app.middleware import is_static_path


class ETagMiddleware(BaseHTTPMiddleware):
    """Add `ETag` + `Cache-Control` to GET JSON responses; serve 304 on match."""

    def __init__(self, app: ASGIApp) -> None:
        super().__init__(app)

    async def dispatch(self, request: Request, call_next):  # type: ignore[override]
        # Fast bail-outs that avoid buffering the response body unnecessarily.
        if request.method != "GET":
            return await call_next(request)
        if is_static_path(request.url.path):
            return await call_next(request)

        response = await call_next(request)

        # Only ETag successful JSON responses. HTML pages, redirects, and
        # error bodies are skipped — caching them is rarely useful and 304
        # on a non-JSON response can confuse clients.
        if not (200 <= response.status_code < 300):
            return response
        content_type = response.headers.get("content-type", "")
        if not content_type.startswith("application/json"):
            return response

        # Buffer the streamed body so we can hash it. FastAPI/Starlette routes
        # return non-streaming bodies, so this is cheap (one chunk) in practice.
        body = b"".join([chunk async for chunk in response.body_iterator])

        # A manually-set ETag (`GET /itineraries/{id}`) is the If-Match
        # concurrency token, which moderation and the rating aggregate leave
        # unmoved — suffix the body hash so a 304 still means "body unchanged".
        digest = hashlib.sha256(body).hexdigest()[:16]
        endpoint_etag = response.headers.get("etag")
        if endpoint_etag is None:
            etag = f'"{digest}"'
        else:
            etag = f'"{_normalize_etag(endpoint_etag)};{digest}"'

        # `no-cache` here means "store but always revalidate" — exactly what
        # we want for the Dio cache interceptor: it will keep the body around
        # for offline fallback and emit If-None-Match on every fresh request.
        headers = dict(response.headers)
        headers["etag"] = etag
        # Same principle as the manually-set ETag above: an endpoint that has
        # declared its own caching wins. `private, no-cache` is the right
        # default for user-scoped JSON, but it is wrong for a public, immutable,
        # language-in-the-URL document like /help/search-index.json, which a CDN
        # should be free to hold.
        headers.setdefault("cache-control", "private, no-cache")

        # Weak-compare per RFC 7232 §2.3.2: intermediaries (Cloudflare,
        # nginx) downgrade strong ETags to `W/"…"` when they recompress.
        # _normalize_etag strips the `W/` prefix and surrounding quotes so
        # the comparison still succeeds.
        client_etag = request.headers.get("if-none-match")
        if client_etag and _normalize_etag(client_etag) == _normalize_etag(etag):
            # Body unchanged: send headers only. Strip content-length since
            # 304 must not carry one matching a non-empty body.
            headers.pop("content-length", None)
            return Response(status_code=304, headers=headers)

        return Response(
            content=body,
            status_code=response.status_code,
            headers=headers,
            media_type=content_type,
        )
