"""
security_headers.py — Adds OWASP-recommended security headers to every response.

Why only frame-ancestors in CSP?
  This is a JSON API consumed by mobile apps and the Flutter web build.
  `default-src 'self'` provides no real protection for JSON responses —
  mobile clients ignore CSP entirely, and there is no browser script execution
  in a pure API context. `frame-ancestors 'none'` is meaningful everywhere:
  it prevents the API from being embedded in iframes regardless of content type.

Why does /embed differ?
  The Google map pages (routers/embed.py) exist to be framed — by the web app,
  which shares their origin, and by a local web build listed in
  EMBED_FRAME_ANCESTORS. They get their own CSP: frame-ancestors from that
  setting, and nothing loadable but Google's map frame. X-Frame-Options
  SAMEORIGIN is for browsers too old to read frame-ancestors; every current one
  obeys the CSP instead.

Why HSTS only over HTTPS?
  Emitting HSTS over HTTP poisons local dev, staging environments, and Railway's
  internal HTTP routing layer. includeSubDomains is omitted because Cloudflare
  and R2 public URLs (*.r2.dev) are not fully under our control.
"""

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.config import get_settings
from app.middleware import is_embed_path, is_static_path


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)

        if is_static_path(request.url.path):
            return response

        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        if is_embed_path(request.url.path):
            response.headers["X-Frame-Options"] = "SAMEORIGIN"
            response.headers["Content-Security-Policy"] = (
                "default-src 'none'; frame-src https://www.google.com; "
                "style-src 'unsafe-inline'; base-uri 'none'; "
                f"frame-ancestors {get_settings().embed_frame_ancestors}"
            )
            response.headers["X-Robots-Tag"] = "noindex"
        else:
            response.headers["X-Frame-Options"] = "DENY"
            response.headers["Content-Security-Policy"] = "frame-ancestors 'none'"

        # Admin dashboard: never indexed, never cached. Set here rather than in
        # the router because these pages return TemplateResponse directly, which
        # bypasses a dependency-injected Response object's headers.
        path = request.url.path
        if path == "/admin" or path.startswith("/admin/"):
            response.headers["X-Robots-Tag"] = "noindex, nofollow"
            response.headers["Cache-Control"] = "no-store"

        if request.url.scheme == "https":
            response.headers["Strict-Transport-Security"] = "max-age=31536000"

        return response
