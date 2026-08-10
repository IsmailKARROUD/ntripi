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
from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Accepted values for TEXT_MODERATION_PROVIDER. "local" needs no network;
# "disabled" is the dev/test default and skips every scan.
TEXT_MODERATION_PROVIDERS = ("openai", "local", "disabled")


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

    # Known-CSAM hash matching is NOT done here: Cloudflare's CSAM Scanning Tool
    # does it at the edge on served content (dashboard toggle, no app config).
    # It requires R2 behind a proxied custom domain — see docs/media_pipeline_spec.md.

    # Text moderation — scans user prose (titles, descriptions, notes, bios…)
    # before the write. Swapping providers is a config change only:
    #   "openai"   — OpenAI Moderation API, falls back to "local" on failure
    #   "local"    — alt-profanity-check, self-contained, no network
    #   "disabled" — no scanning at all (dev/test default)
    TEXT_MODERATION_PROVIDER: str = "disabled"
    OPENAI_API_KEY: str | None = None
    TEXT_MODERATION_MODEL: str = "omni-moderation-latest"
    TEXT_MODERATION_TIMEOUT_SECONDS: float = 5.0
    # Verdicts are cached by hash(text + model + policy version) so identical
    # text is never re-submitted; entries expire after this many days.
    TEXT_MODERATION_CACHE_TTL_DAYS: int = 30
    # Reviewed decision rows are purged after this long (unreviewed rows are
    # never purged — they are the moderator queue).
    TEXT_MODERATION_LOG_RETENTION_DAYS: int = 90

    # Hours after which an unreviewed report is auto-actioned. The DSA clock is
    # 24h from when the report is *filed*, and the sweep only runs periodically,
    # so the cap is 22 to leave margin for a missed run during a deploy.
    MODERATION_SLA_HOURS: int = Field(default=20, ge=1, le=22)

    # Moderation sweep (SLA enforcement, pending re-checks, cache purge). One of
    # the two must be configured or the sweep never runs: SWEEP_IN_PROCESS for a
    # timer inside the app (simplest on a single instance), or an external
    # scheduler POSTing the endpoint (unaffected by deploys, which restart the
    # in-process timer).
    # SWEEP_TOKEN unset = POST /internal/moderation-sweep returns 404 (the
    # endpoint is invisible, not merely locked — same rule as /admin).
    SWEEP_TOKEN: str | None = None
    SWEEP_IN_PROCESS: bool = False
    SWEEP_INTERVAL_MINUTES: int = 30

    # Distinct reporters required before content is hidden immediately, per
    # report category. One user reporting repeatedly counts once.
    REPORT_HIDE_THRESHOLDS: str = (
        "csam:1,sexual_content:1,violence_threat:1,"
        "hate_speech:2,harassment:2,other:3,spam:4"
    )
    # slowapi limit string for POST /reports — blunts report griefing.
    REPORT_RATE_LIMIT: str = "10/hour"

    # Published abuse contact. Must match the app-store listing; use the domain
    # address, never a personal one.
    ABUSE_CONTACT_EMAIL: str = "abuse@ntripi.app"

    # ── In-app bug reports (shake to report) ────────────────────────────────
    # slowapi limit string for POST /bug-reports. Lower than the report limit:
    # each one carries a screenshot upload.
    BUG_REPORT_RATE_LIMIT: str = "5/hour"
    # How long a CLOSED bug report and its screenshot are kept. A screenshot can
    # contain another user's content, so unbounded retention is a liability, not
    # just clutter. Open reports are never purged — they haven't been read yet.
    BUG_REPORT_RETENTION_DAYS: int = 180

    # ── Jira hand-off (/admin/bugs → "Create Jira issue") ───────────────────
    # Feature is OFF unless all four of BASE_URL/EMAIL/API_TOKEN/PROJECT_KEY are
    # set — the button is simply not rendered, same "unset = invisible" rule as
    # ADMIN_BASIC_*. Free to use: the Jira Cloud REST API carries no per-call
    # charge and the token is minted at id.atlassian.com → API tokens.
    JIRA_BASE_URL: str | None = None
    JIRA_EMAIL: str | None = None
    JIRA_API_TOKEN: str | None = None
    # The project KEY (e.g. "NTRIPI"), not a numeric id — REST v3 accepts either
    # but the key is what an operator can read off their own board.
    JIRA_PROJECT_KEY: str | None = None
    # Issue type NAME. Must exist in that project; a wrong value is the most
    # likely first failure and Jira's 400 body names the field.
    JIRA_ISSUE_TYPE: str = "Bug"
    JIRA_TIMEOUT_SECONDS: float = 10.0

    # ── In-app notifications ────────────────────────────────────────────────
    # How long a READ notification is kept before the sweep purges it. An unread
    # row survives this window however old: an author who has not opened the app
    # since their content was hidden still needs to find out why. No feature
    # flag — this is core UX, not an optional integration.
    NOTIFICATION_RETENTION_DAYS: int = 90
    # Hard ceiling regardless of read state. The read window above is the normal
    # path; this exists so a feed nobody ever opens cannot grow forever. A
    # year-old unread notice is not actionable — and the moderation record it
    # might carry lives permanently on /settings/account-status either way.
    NOTIFICATION_MAX_AGE_DAYS: int = 365

    # Tell pydantic-settings to look for a .env file in the working directory.
    # extra="ignore" means unknown .env keys don't cause validation errors.
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @model_validator(mode="after")
    def _validate_text_moderation(self) -> "Settings":
        """Fail fast at startup rather than silently degrading later: an unknown
        provider name, an OpenAI selection with no key, or an unparseable
        threshold string are all misconfigurations we cannot recover from."""
        if self.TEXT_MODERATION_PROVIDER not in TEXT_MODERATION_PROVIDERS:
            raise ValueError(
                f"TEXT_MODERATION_PROVIDER must be one of "
                f"{', '.join(TEXT_MODERATION_PROVIDERS)}"
            )
        if self.TEXT_MODERATION_PROVIDER == "openai" and not self.OPENAI_API_KEY:
            raise ValueError(
                "TEXT_MODERATION_PROVIDER='openai' requires OPENAI_API_KEY"
            )
        self.report_hide_thresholds  # noqa: B018 — parse now so a typo fails at boot
        return self

    @model_validator(mode="after")
    def _validate_notification_retention(self) -> "Settings":
        # A cap below the read window would silently shorten it — a
        # misconfiguration that looks like working retention right up until
        # someone loses a notice early.
        if self.NOTIFICATION_MAX_AGE_DAYS < self.NOTIFICATION_RETENTION_DAYS:
            raise ValueError(
                "NOTIFICATION_MAX_AGE_DAYS must be >= NOTIFICATION_RETENTION_DAYS"
            )
        return self

    @property
    def report_hide_thresholds(self) -> dict[str, int]:
        """Parsed REPORT_HIDE_THRESHOLDS as {category: distinct_reporters}.
        Comma-separated `name:count` pairs — same env-string convention as
        ALLOWED_ORIGINS, so no JSON-in-env."""
        thresholds: dict[str, int] = {}
        for pair in self.REPORT_HIDE_THRESHOLDS.split(","):
            pair = pair.strip()
            if not pair:
                continue
            name, _, count = pair.partition(":")
            if not _ or not count.strip().isdigit() or int(count) < 1:
                raise ValueError(
                    f"REPORT_HIDE_THRESHOLDS entry {pair!r} must be 'category:positive_int'"
                )
            thresholds[name.strip()] = int(count)
        return thresholds

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
