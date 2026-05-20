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
from app.limiter import limiter
from app.middleware.etag import ETagMiddleware
from app.middleware.security_headers import SecurityHeadersMiddleware
from app.routers import auth, users, follows, itineraries, share, web, waitlist
from app.storage.factory import storage

logger = logging.getLogger(__name__)

settings = get_settings()


# ---------------------------------------------------------------------------
# SPA static files helper
# ---------------------------------------------------------------------------
class _SPAStaticFiles(StaticFiles):
    """StaticFiles with SPA fallback: returns index.html for any unmatched path.

    Starlette ≥0.52 removed the automatic index.html fallback from html=True.
    Flutter's client-side router requires the server to return index.html for
    every path under /app/ so deep links and page refreshes work correctly.
    """
    async def get_response(self, path: str, scope):  # type: ignore[override]
        try:
            return await super().get_response(path, scope)
        except HTTPException as exc:
            if exc.status_code == 404:
                return await super().get_response("index.html", scope)
            raise


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
# FastAPI application
# ---------------------------------------------------------------------------
app = FastAPI(
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

# ETag / 304 Not Modified (innermost — closest to handlers)
# Hash JSON GET response bodies; serve 304 when client returns If-None-Match.
# Added first so it sits innermost in the stack.
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
    allow_headers=["Content-Type", "Authorization", "If-Match", "If-None-Match"],
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
@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    if isinstance(exc, (asyncio.CancelledError, KeyboardInterrupt, SystemExit)):
        raise exc
    logger.exception("Unhandled exception on %s %s", request.method, request.url.path)
    if settings.DEBUG:
        raise exc
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})
