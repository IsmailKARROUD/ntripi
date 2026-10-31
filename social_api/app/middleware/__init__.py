"""Shared constants for the middleware stack."""

# Paths under these prefixes are served by Starlette StaticFiles: they bypass
# response-body buffering (ETag) and security-header rewriting because they may
# be large binaries (images, web bundles) with their own headers. Kept here so
# the ETag and security-headers middleware can't drift out of sync.
STATIC_PREFIXES = ("/uploads", "/static", "/app")


def is_static_path(path: str) -> bool:
    """True for a path under one of STATIC_PREFIXES.

    Matched on a segment boundary: a bare startswith("/app") also swallowed
    /appeal/{token} and /appeals/*, stripping their security headers.
    """
    return any(path == p or path.startswith(p + "/") for p in STATIC_PREFIXES)


# The Google map pages (routers/embed.py): the only paths our own pages may
# frame. Everything else answers X-Frame-Options: DENY.
EMBED_PREFIX = "/embed"


def is_embed_path(path: str) -> bool:
    """True for /embed and below — on a segment boundary, so /embedded is not."""
    return path == EMBED_PREFIX or path.startswith(EMBED_PREFIX + "/")
