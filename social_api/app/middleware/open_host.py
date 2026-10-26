"""open_host.py — the second host behind the share pages' iPhone button.

iOS opens an app only for a tap on a link to another domain than the page's own,
so a share page's "Open in Ntripi" points at APP_OPEN_HOST (open.ntripi.app),
which the iOS app claims beside ntripi.app (Runner.entitlements). When the app
opens, this host is never asked for the page. When Safari loads it instead — no
app installed, or links on this device sent to Safari — the request lands here:

  /.well-known/*   answered as on the main host: Apple's CDN must get the
                   association file with a 200, never a redirect
  /share/i|u/...   302 to the same page on SHARE_BASE_URL with ?app=missing,
                   which the page reads to say the app did not open
  anything else    301 to SHARE_BASE_URL. The host is never a second copy of
                   the site: its own localStorage would hide the web session
                   the share pages look for

Pure ASGI, like client_ip.py. Reads the settings on every request, so an unset
APP_OPEN_HOST costs one comparison and changes nothing.
"""

from starlette.datastructures import Headers
from starlette.responses import RedirectResponse
from starlette.types import ASGIApp, Receive, Scope, Send

from app.config import get_settings

_SHARE_PREFIXES = ("/share/i/", "/share/u/")


class OpenHostMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] == "http":
            settings = get_settings()
            open_host = settings.app_open_host
            path = scope["path"]
            if (
                open_host
                and _host(scope) == open_host
                and not path.startswith("/.well-known/")
            ):
                await _redirect(scope, path, settings.share_base_url)(scope, receive, send)
                return
        await self.app(scope, receive, send)


def _host(scope: Scope) -> str:
    return Headers(scope=scope).get("host", "").split(":")[0].lower()


def _redirect(scope: Scope, path: str, share_base_url: str) -> RedirectResponse:
    # raw_path keeps the request's own percent-encoding, which RedirectResponse
    # leaves alone; the decoded path would be re-encoded differently.
    raw = scope.get("raw_path")
    target = share_base_url.rstrip("/") + (raw.decode("latin-1") if raw else path)
    if path.startswith(_SHARE_PREFIXES):
        # Not permanent: whether the app opens depends on the device, not the link.
        return RedirectResponse(f"{target}?app=missing", status_code=302)
    query = scope.get("query_string", b"").decode("latin-1")
    return RedirectResponse(f"{target}?{query}" if query else target, status_code=301)
