"""
main.py — FastAPI application entry point.

This file:
  1. Creates the FastAPI app instance with metadata.
  2. Configures middleware stack (outermost → innermost):
       ProxyHeaders → TrustedHost → ContentSizeLimit → SecurityHeaders → CORS → ETag
  3. Registers all routers.
  4. Defines the health-check endpoint.

Why a separate main.py?
  - Keeps app configuration in one place.
  - Makes it easy to import the app object for testing (test client, etc.).
  - The uvicorn command points here: uvicorn app.main:app
"""

import asyncio
import logging
import re
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from starlette.exceptions import HTTPException
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.middleware.trustedhost import TrustedHostMiddleware
from starlette.requests import Request
from starlette.responses import Response
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware

from app.config import get_settings
from app.errors import ApiError
from app.limiter import limiter
from app.middleware.etag import ETagMiddleware
from app.middleware.language import LanguageCookieMiddleware
from app.middleware.security_headers import SecurityHeadersMiddleware
from app.routers import (
    admin, appeals, auth, bug_reports, devices, users, follows, internal,
    itineraries, notifications, share, web, waitlist, reports,
)
from app.services import push_service
from app.storage.factory import storage

logger = logging.getLogger(__name__)

settings = get_settings()


# ---------------------------------------------------------------------------
# SPA static files helper
# ---------------------------------------------------------------------------
# The google_sign_in_web plugin reads its OAuth client id from this meta tag —
# the backend injects the deployed value at serve time (see _SPAStaticFiles).
_GSI_META_RE = re.compile(r'(<meta name="google-signin-client_id" content=")[^"]*(")')


class _SPAStaticFiles(StaticFiles):
    """StaticFiles with SPA fallback: returns index.html for any unmatched path.

    Starlette ≥0.52 removed the automatic index.html fallback from html=True.
    Flutter's client-side router requires the server to return index.html for
    every path under /app/ so deep links and page refreshes work correctly.

    index.html is served from an in-memory copy with GOOGLE_WEB_CLIENT_ID
    injected into the google-signin-client_id meta tag — the same env var the
    backend uses as the Google ID-token audience, keeping one source of truth.
    """

    _index_html: bytes | None = None

    def _index_response(self) -> Response:
        if self._index_html is None:
            html = (Path(self.directory) / "index.html").read_text(encoding="utf-8")
            client_id = get_settings().GOOGLE_WEB_CLIENT_ID
            if client_id:
                # lambda, not a template string — keeps any regex metachars in the id inert
                html = _GSI_META_RE.sub(
                    lambda m: m.group(1) + client_id + m.group(2), html
                )
            # cached in memory — the image can be read-only for appuser, so never write back
            self._index_html = html.encode("utf-8")
        return Response(
            self._index_html,
            media_type="text/html",
            # no-cache: index.html references content-hashed assets and carries the
            # injected client id — clients must revalidate after every redeploy.
            headers={"Cache-Control": "no-cache"},
        )

    async def get_response(self, path: str, scope):  # type: ignore[override]
        try:
            response = await super().get_response(path, scope)
        except HTTPException as exc:
            if exc.status_code == 404:
                return self._index_response()
            raise
        # html=True resolves "/" (and explicit index.html) to the file on disk —
        # swap in the injected in-memory copy instead.
        actual_path = getattr(response, "path", None)
        if actual_path and Path(actual_path).name == "index.html":
            return self._index_response()
        return response


# ---------------------------------------------------------------------------
# Content-size limit middleware
# ---------------------------------------------------------------------------
# Reject requests whose Content-Length header exceeds 10 MB before they
# reach CORS or any handler. This is a secondary backstop — the primary
# protection layer is Cloudflare/Railway ingress. Chunked transfer encoding
# can omit Content-Length, so this check does not catch all oversized bodies;
# the image-upload endpoint has its own 10 MB guard in image_service.py.
_MAX_BODY_BYTES = 10 * 1024 * 1024  # 10 MB


class ContentSizeLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        # Only check methods that can carry a body — GET/HEAD/OPTIONS never have one.
        if request.method in ("POST", "PUT", "PATCH", "DELETE"):
            content_length = request.headers.get("content-length")
            if content_length and int(content_length) > _MAX_BODY_BYTES:
                return Response("Payload too large", status_code=413)
        return await call_next(request)


# ---------------------------------------------------------------------------
# In-process moderation sweep
# ---------------------------------------------------------------------------
# Something has to drive the sweep on a schedule, or SLA auto-hides and
# post-outage re-checks simply never happen. Two supported ways, same code path:
#
#   SWEEP_IN_PROCESS=True    a timer in this process. Nothing external to set
#                            up, so it is the sensible choice for a single
#                            instance (and for local dev, which has no
#                            scheduler at all).
#   An external scheduler    POSTing /internal/moderation-sweep. Independent of
#                            this process, so it keeps to a wall-clock schedule
#                            across deploys — each restart resets the timer
#                            below, which can starve a long interval on a busy
#                            deploy day.
#
# Both may be enabled at once: the advisory lock makes the duplicate run skip
# rather than race.

async def _sweep_loop() -> None:
    interval = max(60, get_settings().SWEEP_INTERVAL_MINUTES * 60)
    while True:
        await asyncio.sleep(interval)
        try:
            # to_thread: the sweep uses a sync Session, which would block the loop.
            await asyncio.to_thread(_run_sweep_with_own_session)
        except asyncio.CancelledError:
            raise  # shutdown — never swallow this (breaks Starlette's lifespan)
        except Exception:
            logger.exception("in-process moderation sweep failed")


def _run_sweep_with_own_session() -> None:
    from app.database import SessionLocal
    from app.services import sweep_service

    db = SessionLocal()
    try:
        sweep_service.run_moderation_sweep(db, get_settings())
    finally:
        db.close()


@asynccontextmanager
async def lifespan(_app: FastAPI):
    task = None
    if settings.SWEEP_IN_PROCESS:
        logger.info(
            "starting in-process moderation sweep every %s minutes",
            settings.SWEEP_INTERVAL_MINUTES,
        )
        task = asyncio.create_task(_sweep_loop())
    try:
        yield
    finally:
        if task is not None:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass  # expected: we just cancelled it


# ---------------------------------------------------------------------------
# FastAPI application
# ---------------------------------------------------------------------------
app = FastAPI(
    lifespan=lifespan,
    title="Ntripi API",
    description=(
        "Social travel backend for Ntripi. "
        "Covers: authentication, user profiles, follow system, "
        "itineraries with stops/annotations, transit segments with legs, "
        "community ratings, restricted-access allowlists, and GDPR account deletion."
    ),
    version="0.2.0",
    # Hide Swagger UI and ReDoc in production — API schema should not be
    # publicly browsable. Set DEBUG=True in .env to re-enable during development.
    docs_url="/docs" if settings.DEBUG else None,
    redoc_url="/redoc" if settings.DEBUG else None,
)

# ---------------------------------------------------------------------------
# Rate limiting
# ---------------------------------------------------------------------------
# slowapi uses an in-memory store — sufficient for the current single-instance
# Railway deployment. If horizontally scaled, swap for a Redis-backed store.
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ---------------------------------------------------------------------------
# Middleware stack (add_middleware is LIFO — last added = outermost)
# ---------------------------------------------------------------------------
# Desired request order: ProxyHeaders → TrustedHost → ContentSizeLimit →
#   SecurityHeaders → CORS → ETag → handlers

# Language cookie + Vary: Accept-Language on HTML (innermost — touches only
# text/html responses, never the JSON API, so it does not affect the security
# stack ordering below).
app.add_middleware(LanguageCookieMiddleware)

# ETag / 304 Not Modified — closest to handlers among the JSON-API layers.
# Hash JSON GET response bodies; serve 304 when client returns If-None-Match.
app.add_middleware(ETagMiddleware)

# CORS — whitelist Flutter app domain only; never wildcard
allowed_origins = [
    o.strip()
    for o in settings.ALLOWED_ORIGINS.split(",")
    if o.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    # Explicit list, never ["*"]. X-Edit-Lock carries the edit claim on every
    # itinerary mutation — omitting it here would fail the browser preflight.
    allow_headers=[
        "Content-Type", "Authorization", "If-Match", "If-None-Match", "X-Edit-Lock",
    ],
)

# Security headers (CSP frame-ancestors, X-Frame-Options, HSTS, etc.)
app.add_middleware(SecurityHeadersMiddleware)

# Body size limit (outer to CORS — rejects oversized payloads before CORS runs)
app.add_middleware(ContentSizeLimitMiddleware)

# TrustedHost — reject requests with unexpected Host headers (host-header injection)
allowed_hosts = [h.strip() for h in settings.ALLOWED_HOSTS.split(",") if h.strip()]
app.add_middleware(TrustedHostMiddleware, allowed_hosts=allowed_hosts)

# ProxyHeaders (outermost — must run first to rewrite X-Forwarded-For into
# request.client.host before TrustedHost and slowapi read the client IP).
# trusted_hosts="*" is safe: Railway does not expose the container directly
# to the public internet; all traffic passes through its proxy tier.
app.add_middleware(ProxyHeadersMiddleware, trusted_hosts="*")


# ---------------------------------------------------------------------------
# Routers
# ---------------------------------------------------------------------------
app.include_router(auth.router)    # /auth/register, /auth/login
app.include_router(users.router)   # /users/me, /users/search, /users/{id}
app.include_router(follows.router) # /users/{id}/follow, /users/me/follow-requests, etc.
app.include_router(itineraries.router, prefix="/itineraries")  # /itineraries/...
app.include_router(itineraries.user_itineraries_router, prefix="/users", tags=["Itineraries"])  # /users/{id}/itineraries
app.include_router(share.router)    # /share/i/{id} — public HTML landing pages
app.include_router(waitlist.router) # /waitlist/join — pre-launch waitlist
app.include_router(reports.router)  # POST /reports — content reporting
app.include_router(bug_reports.router)  # POST /bug-reports — in-app bug reports
app.include_router(notifications.router)  # /notifications — in-app notification feed
app.include_router(devices.router)  # /devices — FCM push registration
app.include_router(appeals.router)  # /appeals — user appeals against moderation
app.include_router(admin.router)    # /admin — internal moderation dashboard (HTML)
app.include_router(internal.router) # /internal/moderation-sweep — scheduler-triggered
app.include_router(web.router)      # /, /login, /register, /privacy, /terms

# ---------------------------------------------------------------------------
# Static files
# ---------------------------------------------------------------------------
# Serves app/static/ at /static — used for the OG preview image.
_static_dir = Path(__file__).parent / "static"
app.mount("/static", StaticFiles(directory=str(_static_dir)), name="static")

# User-uploaded files — only needed when using the local filesystem backend.
# With R2, images are served directly from the R2 public URL; no local mount required.
if settings.STORAGE_BACKEND == "filesystem":
    _uploads_dir = Path(settings.STORAGE_FILESYSTEM_PATH)
    _uploads_dir.mkdir(parents=True, exist_ok=True)
    app.mount(
        settings.STORAGE_PUBLIC_URL_PREFIX,
        StaticFiles(directory=str(_uploads_dir)),
        name="uploads",
    )

# Eagerly initialise the storage singleton so any misconfiguration surfaces
# at startup rather than on the first upload request.
storage()

# Same reasoning, one severity down: a broken service-account key is logged and
# push stays off, rather than taking the deploy with it.
push_service.validate_credentials(settings)

# Flutter web build served at /app/.
_flutter_web_dir = Path("/app/web_build")
if _flutter_web_dir.exists():
    app.mount(
        "/app",
        _SPAStaticFiles(directory=str(_flutter_web_dir), html=True),
        name="flutter_web",
    )


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
@app.get("/health", tags=["Health"])
def health_check() -> dict:
    return {"status": "ok"}


# ---------------------------------------------------------------------------
# Generic exception handler
# ---------------------------------------------------------------------------
# FastAPI's own handlers for HTTPException and RequestValidationError take
# precedence over this handler, so it only fires for truly unhandled exceptions.
# Async cancellation must be re-raised — intercepting it breaks Starlette's
# lifespan and request lifecycle.
@app.exception_handler(ApiError)
async def api_error_handler(request: Request, exc: ApiError) -> JSONResponse:
    # detail stays byte-identical to the old HTTPException body; `code` is added
    # so the Flutter client can localize without string-matching the message.
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail, "code": exc.code, **exc.extra},
        headers=exc.headers,
    )


@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    if isinstance(exc, (asyncio.CancelledError, KeyboardInterrupt, SystemExit)):
        raise exc
    logger.exception("Unhandled exception on %s %s", request.method, request.url.path)
    if settings.DEBUG:
        raise exc
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})
