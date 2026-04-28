from functools import lru_cache

from app.storage.base import Storage
from app.storage.filesystem import FilesystemStorage
from app.config import get_settings


@lru_cache(maxsize=1)
def storage() -> Storage:
    """Return the configured storage backend singleton.

    The backend is chosen by STORAGE_BACKEND in config:
      "filesystem" → FilesystemStorage (Phase 1, current)
      Future: "r2" or "s3" — add branches here without touching call sites.
    """
    settings = get_settings()
    if settings.STORAGE_BACKEND == "filesystem":
        return FilesystemStorage(
            base_dir=settings.STORAGE_FILESYSTEM_PATH,
            public_url_prefix=settings.STORAGE_PUBLIC_URL_PREFIX,
        )
    raise ValueError(f"Unknown STORAGE_BACKEND: {settings.STORAGE_BACKEND!r}")
