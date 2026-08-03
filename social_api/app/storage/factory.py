import logging
from functools import lru_cache

from app.storage.base import Storage
from app.storage.filesystem import FilesystemStorage
from app.config import get_settings

logger = logging.getLogger(__name__)


@lru_cache(maxsize=1)
def storage() -> Storage:
    """Return the configured storage backend singleton.

    STORAGE_BACKEND="r2"  → R2Storage (Cloudflare R2, requires R2_* env vars)
    STORAGE_BACKEND="filesystem" → FilesystemStorage (local disk / Railway volume)

    A missing R2_* variable raises rather than falling back: silently writing to
    a filesystem path that production no longer serves (the /uploads mount is
    filesystem-only) would strand every upload, and it would also take the
    images out from behind Cloudflare, where the CSAM scan happens.
    """
    settings = get_settings()

    if settings.STORAGE_BACKEND == "r2":
        r2_vars = {
            "R2_ACCESS_KEY_ID": settings.R2_ACCESS_KEY_ID,
            "R2_SECRET_ACCESS_KEY": settings.R2_SECRET_ACCESS_KEY,
            "R2_BUCKET": settings.R2_BUCKET,
            "R2_ENDPOINT": settings.R2_ENDPOINT,
            "R2_PUBLIC_URL": settings.R2_PUBLIC_URL,
        }
        missing = [k for k, v in r2_vars.items() if not v]
        if missing:
            raise ValueError(
                f"STORAGE_BACKEND=r2 but missing env vars: {', '.join(missing)}"
            )

        from app.storage.r2_storage import R2Storage

        backend = R2Storage(
            bucket=settings.R2_BUCKET,  # type: ignore[arg-type]
            endpoint_url=settings.R2_ENDPOINT,  # type: ignore[arg-type]
            access_key_id=settings.R2_ACCESS_KEY_ID,  # type: ignore[arg-type]
            secret_access_key=settings.R2_SECRET_ACCESS_KEY,  # type: ignore[arg-type]
            public_url=settings.R2_PUBLIC_URL,  # type: ignore[arg-type]
        )
        logger.info(
            "Storage backend: R2 (bucket=%r endpoint=%r)",
            settings.R2_BUCKET,
            settings.R2_ENDPOINT,
        )
        if ".r2.dev" in (settings.R2_PUBLIC_URL or ""):
            # r2.dev bypasses the zone, so Cloudflare's CSAM scan never sees the
            # images — fine locally, a compliance hole in production.
            logger.warning(
                "R2_PUBLIC_URL is an r2.dev domain — traffic bypasses Cloudflare, "
                "so CSAM scanning does not run. Use a proxied custom domain."
            )
        return backend

    if settings.STORAGE_BACKEND not in ("filesystem", "r2"):
        raise ValueError(f"Unknown STORAGE_BACKEND: {settings.STORAGE_BACKEND!r}")

    backend = FilesystemStorage(
        base_dir=settings.STORAGE_FILESYSTEM_PATH,
        public_url_prefix=settings.STORAGE_PUBLIC_URL_PREFIX,
    )
    logger.info(
        "Storage backend: filesystem (path=%r prefix=%r)",
        settings.STORAGE_FILESYSTEM_PATH,
        settings.STORAGE_PUBLIC_URL_PREFIX,
    )
    return backend
