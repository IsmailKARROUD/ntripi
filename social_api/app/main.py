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

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.routers import auth, users, follows

settings = get_settings()

# Create the FastAPI application with descriptive metadata.
# These appear in the auto-generated /docs (Swagger UI) and /redoc pages.
app = FastAPI(
    title="Ntripi API",
    description=(
        "Social media backend for Ntripi. "
        "V0.1 covers: authentication, user profiles, and the follow system."
    ),
    version="0.1.0",
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
# Why allow all origins in DEBUG?
#   During development, the frontend might run on localhost:3000, localhost:8080,
#   or various other ports. Allowing all origins makes local development frictionless.
#
# Why restrict in production?
#   Allowing all origins in production would let any website make authenticated
#   requests to the API using a logged-in user's browser cookies (CSRF risk).
#   By restricting to only our known frontend domain, we limit exposure.

if settings.DEBUG:
    # Development: allow everything.
    allowed_origins = ["*"]
else:
    # Production: restrict to the configured frontend domain.
    allowed_origins = [settings.ALLOWED_ORIGINS]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,   # Allow cookies and Authorization headers
    allow_methods=["*"],      # Allow all HTTP methods (GET, POST, PUT, DELETE, etc.)
    allow_headers=["*"],      # Allow all headers (including Authorization)
)

# ---------------------------------------------------------------------------
# Routers
# ---------------------------------------------------------------------------
# Each router handles a group of related endpoints.
# The prefix is defined in the router file itself for self-containment.

app.include_router(auth.router)    # /auth/register, /auth/login
app.include_router(users.router)   # /users/me, /users/search, /users/{id}
app.include_router(follows.router) # /users/{id}/follow, /users/me/follow-requests, etc.


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------

@app.get("/", tags=["Health"])
def health_check() -> dict:
    """
    Lightweight health check endpoint.
    Used by deployment platforms (Railway, Render, Fly.io) to verify the app is running.
    No authentication required — monitoring systems need to call this anonymously.
    """
    return {"status": "ok"}
