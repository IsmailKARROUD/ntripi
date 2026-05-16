"""
main.py — FastAPI application entry point.

This file:
  1. Creates the FastAPI app instance with metadata.
  2. Configures CORS middleware.
  3. Registers all routers.
  4. Defines the health-check endpoint.

Why a separate main.py?
  - Keeps app configuration in one place.
  - Makes it easy to import the app object for testing (test client, etc.).
  - The uvicorn command points here: uvicorn app.main:app
"""

from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from starlette.exceptions import HTTPException

from app.config import get_settings
from app.middleware.etag import ETagMiddleware
from app.routers import auth, users, follows, itineraries, share, web, waitlist
from app.storage.factory import storage


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

settings = get_settings()

# Create the FastAPI application with descriptive metadata.
# These appear in the auto-generated /docs (Swagger UI) and /redoc pages.
app = FastAPI(
    title="Ntripi API",
    description=(
        "Social travel backend for Ntripi. "
        "Covers: authentication, user profiles, follow system, "
        "itineraries with stops/annotations, transit segments with legs, "
        "community ratings, restricted-access allowlists, and GDPR account deletion."
    ),
    version="0.2.0",
    # In production, you may want to disable the docs endpoints:
    # docs_url=None if not settings.DEBUG else "/docs",
    # redoc_url=None if not settings.DEBUG else "/redoc",
)

# ---------------------------------------------------------------------------
# CORS Middleware
# ---------------------------------------------------------------------------
# CORS (Cross-Origin Resource Sharing) controls which domains can make
# requests to this API from a browser.
#
allowed_origins = [
    o.strip()
    for o in settings.ALLOWED_ORIGINS.split(",")
    if o.strip()
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# ETag / 304 Not Modified
# ---------------------------------------------------------------------------
# Hash JSON GET response bodies into a short opaque ETag and serve 304 when
# the client returns it via If-None-Match. Added after CORS so CORS runs
# inner — its response headers are then copied into 304 replies by ETagMiddleware.
app.add_middleware(ETagMiddleware)

# ---------------------------------------------------------------------------
# Routers
# ---------------------------------------------------------------------------
# Each router handles a group of related endpoints.
# The prefix is defined in the router file itself for self-containment.

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
# html=True makes StaticFiles return index.html for any unmatched sub-path,
# which is required for Flutter's client-side router (deep links on refresh).
# The conditional check keeps the backend functional in local dev without a build.
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
# GET / is now handled by the web router (homepage).
# Dedicated health endpoint for deployment platform probes.

@app.get("/health", tags=["Health"])
def health_check() -> dict:
    return {"status": "ok"}
