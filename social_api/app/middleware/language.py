"""language.py — Persists the web UI language and marks HTML as language-varying.

On any request carrying a valid `?lang=` override, the resolved language is
written to the `ntripi_lang` cookie so subsequent navigations stay in that
language without repeating the query param. `Vary: Accept-Language` is added to
HTML responses so caches (e.g. Cloudflare) never serve one language's HTML to a
visitor who prefers the other.

Only touches HTML — the JSON API is unaffected. Registered innermost (first
add_middleware call) so it never displaces the security middleware ordering.
"""

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.i18n import SUPPORTED


class LanguageCookieMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)

        content_type = response.headers.get("content-type", "")
        if "text/html" not in content_type:
            return response

        # HTML output depends on the visitor's preferred language.
        response.headers["Vary"] = "Accept-Language"

        lang = request.query_params.get("lang")
        if lang in SUPPORTED and request.cookies.get("ntripi_lang") != lang:
            response.set_cookie(
                key="ntripi_lang",
                value=lang,
                max_age=60 * 60 * 24 * 365,
                path="/",
                samesite="lax",
            )
        return response
