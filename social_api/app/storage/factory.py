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

    If STORAGE_BACKEND="r2" but any R2_* variable is missing, falls back to
    FilesystemStorage and logs a warning so misconfiguration is obvious.
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
            logger.warning(
                "STORAGE_BACKEND=r2 but missing env vars: %s — "
                "falling back to FilesystemStorage",
                ", ".join(missing),
            )
        else:
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
