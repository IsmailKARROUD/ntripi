"""Validators for user-supplied image URL fields (avatar / cover).

The two-tier moderation pipeline (client NSFWJS pre-check + backend AWS
Rekognition) only runs on *uploaded* images that pass through
process_and_store(). A pasted external URL would be stored verbatim,
bypassing every scan. So PATCH /users/me accepts only URLs that point back
at our own storage (i.e. an image we already processed + scanned) or null;
any arbitrary external URL is rejected. Setting an avatar/cover is done via
the POST upload endpoints, clearing via the DELETE endpoints.
"""

from app.config import get_settings


def validate_own_storage_image_url(v: str | None) -> str | None:
    """Allow only null or one of our own storage URLs; reject external links.

    Filesystem backend serves relative URLs under STORAGE_PUBLIC_URL_PREFIX
    (e.g. ``/uploads/…``); R2 serves absolute URLs under R2_PUBLIC_URL. Both
    prefixes are read from settings so this stays backend-agnostic.
    """
    if v is None:
        return None

    settings = get_settings()
    allowed_prefixes = [settings.STORAGE_PUBLIC_URL_PREFIX]
    if settings.R2_PUBLIC_URL:
        allowed_prefixes.append(settings.R2_PUBLIC_URL)

    if any(v.startswith(prefix) for prefix in allowed_prefixes):
        return v

    raise ValueError("avatar/cover images must be uploaded, not set by URL")
