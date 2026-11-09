"""services/google_avatar.py — a Google sign-up's photo, copied in like an upload.

A Google ID token carries the profile photo as a URL on Google's servers. Until
2026-11-09 a new account stored that URL as its `avatar_url`, which skipped
every check an uploaded photo gets: no image scan, no EXIF strip, and served
from outside our CDN, so Cloudflare's CSAM scan never saw it — the very bypass
validators/image_url.py refuses on `PATCH /users/me`.

So the photo is fetched once, when the account is created, and goes through
`process_and_store` like an upload of the same photo would: a square 800 px
JPEG under the account's own avatar key, scanned before it is stored. Refused,
unreachable, not an image, or anything else that goes wrong → the account
simply starts without a photo; a sign-up never fails over it.

Only Google's photo host is fetched, over https and without following a
redirect: the URL comes from a verified Google token, but the server fetching
whatever URL it is handed is how a request forgery starts.
"""

from __future__ import annotations

import asyncio
import functools
import logging
import re

import anyio
import requests
from sqlalchemy.orm import Session

from app.config import get_settings
from app.models.user import User
from app.services.image_service import (
    MAX_FILE_SIZE,
    ImageProcessingError,
    process_and_store,
    process_imported_avatar_image,
)
from app.services.moderation_service import ModerationContext, ModerationRejectedError

logger = logging.getLogger(__name__)

FETCH_TIMEOUT_SECONDS = 5
_PHOTO_URL = re.compile(
    r"https://(?P<host>lh\d+\.googleusercontent\.com)(?P<path>/[^\s?#]+)"
)
# Google's photo URLs end in sizing options (`=s96-c`, a 96 px square). Asked
# for 800 px — what the avatar is stored at — instead of scaling 96 px up.
_SIZED_PHOTO_PATH = re.compile(r"(?P<photo>/a-?/[^/=]+)(?:=[^/]*)?")
_SIZE_OPTIONS = "=s800-c"


def photo_source(url: str | None) -> str | None:
    """The address to fetch for Google's photo URL `url`, or None when `url`
    is not one: https on Google's photo host only, at 800 px when the URL's
    shape allows asking."""
    if not url:
        return None
    match = _PHOTO_URL.fullmatch(url.strip())
    if match is None:
        return None
    sized = _SIZED_PHOTO_PATH.fullmatch(match["path"])
    path = f"{sized['photo']}{_SIZE_OPTIONS}" if sized else match["path"]
    return f"https://{match['host']}{path}"


def _fetch(source: str) -> bytes | None:
    """The photo's bytes, or None: any answer but a 200, a redirect, an error,
    or a body past the upload limit."""
    try:
        with requests.get(source, timeout=FETCH_TIMEOUT_SECONDS, stream=True,
                          allow_redirects=False) as response:
            if response.status_code != 200:
                return None
            body = bytearray()
            for chunk in response.iter_content(64 * 1024):
                body.extend(chunk)
                if len(body) > MAX_FILE_SIZE:
                    return None
            return bytes(body)
    except requests.RequestException as exc:
        # The class only: the URL names the person's photo.
        logger.warning("google photo fetch failed: %s", type(exc).__name__)
        return None


async def copy_photo(db: Session, user: User, url: str | None) -> str | None:
    """Copy Google's photo `url` into `user`'s avatar; the stored URL, or None
    when nothing was stored. The caller sets `avatar_url` and commits.

    A refused photo commits the session for its audit row (moderate_or_raise),
    so call this with nothing else pending — after the account's own commit.
    """
    source = photo_source(url)
    if source is None:
        return None
    raw = await asyncio.to_thread(_fetch, source)
    if raw is None:
        return None
    key = f"avatars/{user.id}.jpg"
    moderation = ModerationContext(
        db=db, settings=get_settings(), target_kind="avatar",
        uploader=user, storage_key=key,
    )
    try:
        return await process_and_store(
            raw, key, process_imported_avatar_image, cache_bust=True,
            moderation=moderation,
        )
    except (ImageProcessingError, ModerationRejectedError):
        return None
    except Exception as exc:  # storage down: no photo, never a failed sign-up
        logger.warning("google photo copy failed: %s", type(exc).__name__)
        return None


def copy_photo_from_worker(db: Session, user: User, url: str | None) -> str | None:
    """copy_photo for a sync route on its worker thread: the pipeline is async
    and runs on the event loop while this thread waits. Never from the sweep —
    from_thread works only on anyio's own threads (CLAUDE.md, delete_from_sync).
    """
    if photo_source(url) is None:
        return None  # nothing to fetch: no hop onto the event loop
    return anyio.from_thread.run(functools.partial(copy_photo, db, user, url))
