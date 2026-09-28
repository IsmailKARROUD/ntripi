"""client_ip.py — take the client IP from a header the edge proxy owns.

uvicorn's ProxyHeadersMiddleware with trusted_hosts="*" answers the LEFTMOST
X-Forwarded-For entry, and Cloudflare appends to a client-supplied header rather
than replacing it — so any caller could name its own IP and walk past every
per-IP rate limit (login, register, reports, appeals). Cloudflare sets
CF-Connecting-IP itself and discards a client's copy, so behind the proxied zone
it is the one value a caller cannot forge.

Registered just inside ProxyHeadersMiddleware so it has the last word on
scope["client"]; without the header (local dev, a non-Cloudflare deploy) the
X-Forwarded-For answer stands, exactly as before. Pure ASGI rather than
BaseHTTPMiddleware: it only rewrites the scope.
"""

import ipaddress

from starlette.types import ASGIApp, Receive, Scope, Send


class ClientIPHeaderMiddleware:
    def __init__(self, app: ASGIApp, header: str) -> None:
        self.app = app
        self.header = header.strip().lower().encode("latin-1")

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if self.header and scope["type"] in ("http", "websocket"):
            for name, value in scope.get("headers", []):
                if name != self.header:
                    continue
                ip = value.decode("latin-1").strip()
                try:
                    ipaddress.ip_address(ip)
                except ValueError:
                    break  # not an address — keep what ProxyHeaders decided
                port = scope["client"][1] if scope.get("client") else 0
                scope["client"] = (ip, port)
                break
        await self.app(scope, receive, send)
