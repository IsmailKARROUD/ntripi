"""
services/operator_alerts.py — the throttled email to OPERATOR_EMAIL when a
safety tier cannot do its job.

Text moderation's degradation notices and image moderation's outage alerts
both come through here. An alert is about the tier, not about one piece of
content, so it is sent at most once an hour per key: an outage during a busy
hour would otherwise send one email per write. A per-event email (a flagged
image, a report, a bug report) is an item someone has to act on and is never
throttled — those do not come through here.

In-memory is sufficient for the same reason slowapi's store is: the app runs
as one uvicorn process (Dockerfile CMD). A restart or deploy re-arms every key.
"""

from __future__ import annotations

import logging
import threading
from datetime import datetime, timedelta, timezone
from typing import TYPE_CHECKING

from app.services.email_service import send_email

if TYPE_CHECKING:
    from app.config import Settings

logger = logging.getLogger(__name__)

_COOLDOWN = timedelta(minutes=60)
_last_sent: dict[str, datetime] = {}
# Callers run on threadpool workers (sync endpoints) and through
# asyncio.to_thread, so two of them can check the same key at once.
_lock = threading.Lock()


def _now() -> datetime:
    return datetime.now(timezone.utc)


def notify_operator(
    settings: "Settings", key: str, *, subject: str, body: str, log_line: str
) -> None:
    """Tell the operator about `key`, at most once an hour: log `log_line` at
    WARNING, then email `subject` / `body` to OPERATOR_EMAIL when it is set.

    Blocking — send_email is a requests.post with a 10 s timeout — so an async
    caller hands this to asyncio.to_thread, having built `body` on its own
    thread first. Best-effort: a mail failure is logged, never raised, because
    every caller is in the middle of a user's write.
    """
    now = _now()
    with _lock:
        last = _last_sent.get(key)
        if last is not None and now - last < _COOLDOWN:
            return
        _last_sent[key] = now

    logger.warning(log_line)
    if not settings.OPERATOR_EMAIL:
        return  # the WARNING above is the only trace; nowhere to send it
    try:
        send_email(settings.OPERATOR_EMAIL, subject=subject, html=body)
    except Exception:
        logger.exception("operator alert email failed (%s)", key)
