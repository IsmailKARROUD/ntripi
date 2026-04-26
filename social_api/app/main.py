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

from app.config import get_settings
from app.routers import auth, users, follows, itineraries, share, web

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
# Routers
# ---------------------------------------------------------------------------
# Each router handles a group of related endpoints.
# The prefix is defined in the router file itself for self-containment.

app.include_router(auth.router)    # /auth/register, /auth/login
app.include_router(users.router)   # /users/me, /users/search, /users/{id}
app.include_router(follows.router) # /users/{id}/follow, /users/me/follow-requests, etc.
app.include_router(itineraries.router, prefix="/itineraries")  # /itineraries/...
app.include_router(itineraries.user_itineraries_router, prefix="/users", tags=["Itineraries"])  # /users/{id}/itineraries
app.include_router(share.router)   # /share/i/{id} — public HTML landing pages
app.include_router(web.router)     # /, /login, /register, /privacy, /terms, /app/

# ---------------------------------------------------------------------------
# Static files
# ---------------------------------------------------------------------------
# Serves app/static/ at /static — used for the OG preview image.
_static_dir = Path(__file__).parent / "static"
app.mount("/static", StaticFiles(directory=str(_static_dir)), name="static")


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
# GET / is now handled by the web router (homepage).
# Dedicated health endpoint for deployment platform probes.

@app.get("/health", tags=["Health"])
def health_check() -> dict:
    return {"status": "ok"}
