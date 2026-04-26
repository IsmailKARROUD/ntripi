"""
config.py — Application configuration using pydantic-settings.

Why pydantic-settings?
  - Automatically reads from environment variables AND a .env file.
  - Validates types at startup (e.g., int for port, bool for DEBUG).
  - Provides auto-completion and type safety across the codebase.
  - Centralises all configuration in one place — no scattered os.getenv() calls.

Why @lru_cache on get_settings()?
  - Settings parsing happens once at first call, then the result is cached.
  - This means the .env file is read only once, no matter how many modules
    call get_settings(). It behaves like a singleton without a class.
  - FastAPI's Depends() works perfectly with lru_cache'd callables.
"""

from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """
    All application configuration lives here.
    pydantic-settings automatically reads these from environment variables
    (case-insensitive). If a .env file is present, it is loaded first.
    """

    # PostgreSQL connection URL.
    # Format: postgresql://user:password@host:port/dbname
    DATABASE_URL: str

    # Secret key used to sign JWT tokens.
    # Generate a strong one with: openssl rand -hex 32
    SECRET_KEY: str

    # JWT signing algorithm. HS256 uses a symmetric shared secret,
    # which is appropriate when both signing and verifying happen in the same service.
    ALGORITHM: str = "HS256"

    # Token lifespan in minutes. Default is 24 hours (1440 minutes).
    # Lower values improve security but require more frequent re-login.
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440

    # Debug mode: enables verbose errors and relaxed CORS in development.
    # ALWAYS set to False in production.
    DEBUG: bool = False

    # Allowed CORS origins in production mode.
    # In DEBUG mode this is overridden to allow all origins.
    ALLOWED_ORIGINS: str = "https://your-frontend-domain.com"

    # Base URL used to construct share links sent via the share sheet.
    # In production: SHARE_BASE_URL=https://ntripi.app
    share_base_url: str = "http://localhost:8000"

    # Optional URL for Android APK download. None hides the button on the homepage.
    # Set to /downloads/ntripi-latest.apk once Ticket 9 ships the binary.
    ANDROID_DOWNLOAD_URL: str | None = None

    # Tell pydantic-settings to look for a .env file in the working directory.
    # extra="ignore" means unknown .env keys don't cause validation errors.
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    """
    Return the cached Settings singleton.

    Using lru_cache means this function is only ever executed once.
    Every subsequent call returns the same Settings object from the cache.
    This is important for performance and consistency across the app.
    """
    return Settings()
