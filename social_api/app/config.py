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
from pydantic import Field
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
    # min_length=32 ensures startup fails fast if a weak or placeholder key is used.
    SECRET_KEY: str = Field(min_length=32)

    # JWT signing algorithm. HS256 uses a symmetric shared secret,
    # which is appropriate when both signing and verifying happen in the same service.
    ALGORITHM: str = "HS256"

    # Mobile JWT access-token lifespan in minutes. Short by design:
    # paired with a refresh token, the access token is what protects API
    # calls, and short windows limit damage if it leaks. The Flutter
    # client refreshes transparently before expiry.
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 15

    # Refresh-token lifespan in days. After this much inactivity the user
    # must log in again. Rotates on every refresh (RFC 6749 best practice).
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # Debug mode: enables verbose errors and relaxed CORS in development.
    # ALWAYS set to False in production.
    DEBUG: bool = False

    # Allowed CORS origins in production mode.
    # In DEBUG mode this is overridden to allow all origins.
    ALLOWED_ORIGINS: str = "https://your-frontend-domain.com"

    # Allowed Host headers for TrustedHostMiddleware (host-header injection prevention).
    # List apex and wildcard separately — the wildcard alone does not match the apex
    # in Starlette's TrustedHostMiddleware.
    ALLOWED_HOSTS: str = "ntripi.app,*.ntripi.app"

    # Base URL used to construct share links sent via the share sheet.
    # In production: SHARE_BASE_URL=https://ntripi.app
    share_base_url: str = "http://localhost:8000"

    # Optional URL for Android APK download. None hides the button on the homepage.
    # Set to /downloads/ntripi-latest.apk once Ticket 9 ships the binary.
    ANDROID_DOWNLOAD_URL: str | None = None

    # Minimum number of ratings an itinerary needs before it can surface in the
    # "Top" discovery feed — stops a single 5-star trip from dominating. Kept as
    # an env var so the bar can be lowered while the catalogue is young and raised
    # as ratings accumulate.
    FEED_TOP_MIN_RATINGS: int = 3

    # Google Sign-In OAuth 2.0 client IDs (from Google Cloud Console). A verified
    # Google ID token's `aud` must match one of these. Android tokens carry the
    # WEB client id as `aud` (via serverClientId); the Android id is listed for
    # completeness. All empty = Google sign-in effectively disabled.
    GOOGLE_WEB_CLIENT_ID: str = ""
    GOOGLE_IOS_CLIENT_ID: str = ""
    GOOGLE_ANDROID_CLIENT_ID: str = ""

    # Transactional email (password reset, email verification).
    # EMAIL_BACKEND: "console" logs the message + link to stdout (dev default,
    # no provider needed); "resend" sends via the Resend HTTP API.
    EMAIL_BACKEND: str = "console"
    RESEND_API_KEY: str | None = None
    EMAIL_FROM: str = "Ntripi <noreply@ntripi.app>"

    # Where new-content-report notification emails go. Unset = reports are only
    # logged to the DB and the email step is skipped with a warning.
    OPERATOR_EMAIL: str | None = None

    # Admin moderation dashboard (/admin). Feature is OFF unless BOTH basic-auth
    # credentials are set — otherwise every /admin route returns 404 (the panel
    # is invisible, not merely locked). The HTTP Basic layer is a coarse gate in
    # front of the per-admin session login. ADMIN_SESSION_EXPIRE_MINUTES is the
    # admin session-cookie lifetime (default 12h).
    ADMIN_BASIC_USERNAME: str | None = None
    ADMIN_BASIC_PASSWORD: str | None = None
    ADMIN_SESSION_EXPIRE_MINUTES: int = 720

    # When True, new passwords are checked against Have I Been Pwned's breach
    # corpus (k-anonymity range API) and rejected if seen. The check fails open
    # (a HIBP outage never blocks a change). Disable in offline dev / tests.
    PWNED_CHECK_ENABLED: bool = True

    # Storage configuration — where user-uploaded files (cover images, etc.) are kept.
    # Set STORAGE_BACKEND="r2" and supply the R2_* vars below to activate Cloudflare R2.
    # "filesystem" is the local/fallback default and requires a Railway persistent volume.
    STORAGE_BACKEND: str = "filesystem"
    STORAGE_FILESYSTEM_PATH: str = "/app/uploads"
    STORAGE_PUBLIC_URL_PREFIX: str = "/uploads"

    # Cloudflare R2 credentials — only required when STORAGE_BACKEND="r2".
    # R2_ENDPOINT: https://<account-id>.r2.cloudflarestorage.com
    # R2_PUBLIC_URL: public serving URL — either the r2.dev subdomain
    #   (https://pub-<hash>.r2.dev) or a custom domain (https://images.ntripi.app).
    R2_ACCESS_KEY_ID: str | None = None
    R2_SECRET_ACCESS_KEY: str | None = None
    R2_BUCKET: str | None = None
    R2_ENDPOINT: str | None = None
    R2_PUBLIC_URL: str | None = None

    # Image moderation (AWS Rekognition) — scans processed uploads before storage.
    # Disabled (or missing creds) = uploads are stored unscanned, exactly as before.
    # Thresholds are 0-100 confidence percentages, tunable without redeploy.
    MODERATION_ENABLED: bool = False
    MODERATION_AWS_ACCESS_KEY_ID: str | None = None
    MODERATION_AWS_SECRET_ACCESS_KEY: str | None = None
    MODERATION_AWS_REGION: str | None = None
    MODERATION_REJECT_THRESHOLD: float = 80.0  # hard reject: image not stored, 422
    MODERATION_FLAG_THRESHOLD: float = 50.0  # soft flag: stored + logged + operator email

    # Tell pydantic-settings to look for a .env file in the working directory.
    # extra="ignore" means unknown .env keys don't cause validation errors.
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def google_client_ids(self) -> set[str]:
        """Accepted Google OAuth audiences — a verified ID token's `aud` must be
        one of these. We accept any of our own client ids defensively."""
        return {
            cid.strip()
            for cid in (
                self.GOOGLE_WEB_CLIENT_ID,
                self.GOOGLE_IOS_CLIENT_ID,
                self.GOOGLE_ANDROID_CLIENT_ID,
            )
            if cid.strip()
        }


@lru_cache
def get_settings() -> Settings:
    """
    Return the cached Settings singleton.

    Using lru_cache means this function is only ever executed once.
    Every subsequent call returns the same Settings object from the cache.
    This is important for performance and consistency across the app.
    """
    return Settings()
