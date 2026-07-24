"""Shared constants for the middleware stack."""

# Paths under these prefixes are served by Starlette StaticFiles: they bypass
# response-body buffering (ETag) and security-header rewriting because they may
# be large binaries (images, web bundles) with their own headers. Kept here so
# the ETag and security-headers middleware can't drift out of sync.
STATIC_PREFIXES = ("/uploads", "/static", "/app")
