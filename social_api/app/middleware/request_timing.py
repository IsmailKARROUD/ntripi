"""request_timing.py — where a slow request spent its time.

Railway shows WARNING lines only (the app never configures logging), so until
this nothing recorded how long a request took: on 2026-10-20 a Postgres service
in another region added seconds to every save and the logs stayed silent. Every
request is timed here, and one slower than SLOW_REQUEST_LOG_MS (default 1000;
0 logs every request) gets one WARNING line:

    slow request: POST /itineraries/{itinerary_id}/stops status=201 total=812ms
    db=45ms/14q ext=api.openai.com:610ms/1 other=157ms

`db` is time spent in cursor executes and how many ran; `ext` is outbound HTTP
per host, with its call count; `other` is the rest — Python, templates,
waiting for a worker thread.

Log only, never a Server-Timing header: a query count or a duration in the
response would tell any caller whether an account or a trip exists, undoing the
timing-safe login and the identical 404 pages. The route TEMPLATE is logged,
never the path, so no id or username reaches the log.

Outbound calls are timed at the two seams every integration already passes
through — requests.Session.send (OpenAI, Azure, Google, Resend, HIBP, Jira)
and botocore's URLLib3Session.send (R2, Rekognition) — so a new integration is
timed without anyone remembering to tag it. A client library outside those two
needs a hook here. FCM passes through the same seam but is never counted: the
push worker sends after the request, in a context with no record.

The record rides a ContextVar. anyio copies the context into the worker thread
that runs a sync endpoint and its dependencies, and the copy holds the same
RequestTimings object, so what the thread records is what the middleware reads.
Innermost in the stack: it times routing, dependencies and the handler, and
touches none of the security ordering.
"""

from __future__ import annotations

import functools
import logging
import threading
import time
from contextvars import ContextVar
from dataclasses import dataclass, field
from urllib.parse import urlsplit

from sqlalchemy import event
from sqlalchemy.engine import Engine
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.config import get_settings
from app.middleware import is_static_path

logger = logging.getLogger(__name__)

# Docker's HEALTHCHECK hits /health every 30 s; at a threshold of 0 it would drown the log.
_UNTIMED_PATHS = frozenset({"/health"})

_MARKER = "_request_timing"


@dataclass
class RequestTimings:
    start: float = field(default_factory=time.perf_counter)
    db_seconds: float = 0.0
    db_count: int = 0
    # host -> (seconds, calls)
    ext: dict[str, tuple[float, int]] = field(default_factory=dict)
    _lock: threading.Lock = field(default_factory=threading.Lock, repr=False)

    def add_query(self, seconds: float) -> None:
        with self._lock:
            self.db_seconds += seconds
            self.db_count += 1

    def add_external(self, host: str, seconds: float) -> None:
        with self._lock:
            spent, calls = self.ext.get(host, (0.0, 0))
            self.ext[host] = (spent + seconds, calls + 1)


_current: ContextVar[RequestTimings | None] = ContextVar("request_timings", default=None)
# requests follows a redirect by re-entering send(); only the outermost call is timed.
_in_outbound: ContextVar[bool] = ContextVar("request_timing_in_outbound", default=False)


def _ms(seconds: float) -> int:
    return round(seconds * 1000)


def format_line(method: str, route: str, status: int | None,
                timings: RequestTimings, total: float) -> str:
    ext_seconds = sum(spent for spent, _ in timings.ext.values())
    ext = ",".join(
        f"{host}:{_ms(spent)}ms/{calls}"
        for host, (spent, calls) in sorted(timings.ext.items(), key=lambda item: -item[1][0])
    ) or "-"
    # Clamped: an async upload can wait on a thread and the database at once.
    other = max(0.0, total - timings.db_seconds - ext_seconds)
    return (
        f"slow request: {method} {route} status={status} total={_ms(total)}ms "
        f"db={_ms(timings.db_seconds)}ms/{timings.db_count}q ext={ext} other={_ms(other)}ms"
    )


def _report(scope: Scope, status: int | None, timings: RequestTimings) -> None:
    total = time.perf_counter() - timings.start
    if total * 1000 < get_settings().SLOW_REQUEST_LOG_MS:
        return
    # No route = the router's 404, and a raw path could carry a username or a token.
    route = getattr(scope.get("route"), "path", None) or "<no route>"
    logger.warning(format_line(scope["method"], route, status, timings, total))


class RequestTimingMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if (
            scope["type"] != "http"
            or is_static_path(scope["path"])
            or scope["path"] in _UNTIMED_PATHS
        ):
            await self.app(scope, receive, send)
            return

        timings = RequestTimings()
        token = _current.set(timings)
        status: int | None = None
        reported = False

        async def timed_send(message: Message) -> None:
            nonlocal status, reported
            if message["type"] == "http.response.start":
                status = message["status"]
            await send(message)
            # The last body chunk ends the caller's wait; background tasks run after it.
            if (
                message["type"] == "http.response.body"
                and not message.get("more_body", False)
                and not reported
            ):
                reported = True
                _report(scope, status, timings)

        try:
            await self.app(scope, receive, timed_send)
        except Exception:
            if not reported:
                reported = True
                _report(scope, 500, timings)
            raise
        finally:
            _current.reset(token)


# Class-level, so the suite's SQLite engine counts too; outside a request nothing does.
@event.listens_for(Engine, "before_cursor_execute")
def _before_cursor_execute(conn, cursor, statement, parameters, context, executemany) -> None:
    if _current.get() is not None:
        conn.info["request_timing_t0"] = time.perf_counter()


@event.listens_for(Engine, "after_cursor_execute")
def _after_cursor_execute(conn, cursor, statement, parameters, context, executemany) -> None:
    started = conn.info.pop("request_timing_t0", None)
    timings = _current.get()
    if started is not None and timings is not None:
        timings.add_query(time.perf_counter() - started)


def _timed(send, url_of):
    @functools.wraps(send)
    def timed_send(self, request, *args, **kwargs):
        timings = _current.get()
        if timings is None or _in_outbound.get():
            return send(self, request, *args, **kwargs)
        outer = _in_outbound.set(True)
        started = time.perf_counter()
        try:
            return send(self, request, *args, **kwargs)
        finally:
            _in_outbound.reset(outer)
            host = urlsplit(url_of(request)).hostname or "unknown"
            timings.add_external(host, time.perf_counter() - started)

    setattr(timed_send, _MARKER, True)
    return timed_send


def install_outbound_hooks() -> None:
    """Wrap the two outbound HTTP seams once per process. Idempotent."""
    import requests

    if not getattr(requests.Session.send, _MARKER, False):
        requests.Session.send = _timed(requests.Session.send, lambda request: request.url)

    from botocore.httpsession import URLLib3Session

    if not getattr(URLLib3Session.send, _MARKER, False):
        URLLib3Session.send = _timed(URLLib3Session.send, lambda request: request.url)
