"""
security_headers.py — Adds OWASP-recommended security headers to every response.

Why only frame-ancestors in CSP?
  This is a JSON API consumed by mobile apps and the Flutter web build.
  `default-src 'self'` provides no real protection for JSON responses —
  mobile clients ignore CSP entirely, and there is no browser script execution
  in a pure API context. `frame-ancestors 'none'` is meaningful everywhere:
  it prevents the API from being embedded in iframes regardless of content type.

Why HSTS only over HTTPS?
  Emitting HSTS over HTTP poisons local dev, staging environments, and Railway's
  internal HTTP routing layer. includeSubDomains is omitted because Cloudflare
  and R2 public URLs (*.r2.dev) are not fully under our control.
"""

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.middleware import STATIC_PREFIXES as _SKIP_PREFIXES


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)

        if any(request.url.path.startswith(p) for p in _SKIP_PREFIXES):
            return response

        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Content-Security-Policy"] = "frame-ancestors 'none'"

        if request.url.scheme == "https":
            response.headers["Strict-Transport-Security"] = "max-age=31536000"

        return response
