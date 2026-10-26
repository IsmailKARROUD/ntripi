"""
test_operator_alerts.py — the throttled operator alert, on its own.

notify_operator is shared by text moderation's degradation notices and image
moderation's outage alerts; test_text_moderation_service.py and
test_image_moderation.py test what each tier sends. This file pins the helper's
own contract: one email per key per hour, the WARNING line, the OPERATOR_EMAIL
guard, a mail failure swallowed, and the lock that keeps "once" true when
threadpool workers call it together.

The clock is operator_alerts._now, moved through monkeypatch — nothing sleeps
for the cooldown. conftest's reset_operator_alerts clears the hour between
tests.
"""

from __future__ import annotations

import logging
import threading
import time
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

from app.services import operator_alerts

_OPS = SimpleNamespace(OPERATOR_EMAIL="ops@example.com")
_NOBODY = SimpleNamespace(OPERATOR_EMAIL=None)
_T0 = datetime(2026, 10, 25, 9, 0, tzinfo=timezone.utc)


@pytest.fixture()
def sent(monkeypatch) -> list[dict]:
    emails: list[dict] = []
    monkeypatch.setattr(
        operator_alerts, "send_email",
        lambda to, subject, html: emails.append({"to": to, "subject": subject, "html": html}),
    )
    return emails


@pytest.fixture()
def clock(monkeypatch) -> list[datetime]:
    """clock[0] is the time operator_alerts reads; assign to move it."""
    now = [_T0]
    monkeypatch.setattr(operator_alerts, "_now", lambda: now[0])
    return now


def _alert(settings=_OPS, key="tier:down") -> None:
    operator_alerts.notify_operator(
        settings, key, subject="Tier down", body="<p>Tier down</p>", log_line="tier down",
    )


def _records(caplog) -> list[tuple[int, str]]:
    return [
        (rec.levelno, rec.getMessage()) for rec in caplog.records
        if rec.name == "app.services.operator_alerts"
    ]


def test_one_email_per_key_per_hour(sent, clock):
    _alert()
    clock[0] = _T0 + timedelta(minutes=59, seconds=59)
    _alert()
    assert len(sent) == 1

    clock[0] = _T0 + timedelta(hours=1)  # the hour is up at the hour, not after it
    _alert()
    assert len(sent) == 2
    assert sent[0] == {
        "to": "ops@example.com", "subject": "Tier down", "html": "<p>Tier down</p>",
    }


def test_each_key_has_its_own_hour(sent, clock):
    """A text outage must never silence an image one, nor the reverse."""
    for key in ("text_moderation:fallback", "text_moderation:pending",
                "image_moderation:scan_failed", "image_moderation:not_configured"):
        _alert(key=key)
    assert len(sent) == 4


def test_the_warning_is_logged_once_per_hour_alongside_the_email(sent, clock, caplog):
    with caplog.at_level(logging.WARNING, logger="app.services.operator_alerts"):
        _alert()
        _alert()
    assert len(sent) == 1
    assert _records(caplog) == [(logging.WARNING, "tier down")]


def test_without_operator_email_the_warning_is_the_alert(sent, clock, caplog):
    with caplog.at_level(logging.WARNING, logger="app.services.operator_alerts"):
        _alert(_NOBODY)
        _alert(_NOBODY)  # the hour is taken: an outage logs once, not once per write
    assert sent == []
    assert _records(caplog) == [(logging.WARNING, "tier down")]


def test_a_mail_failure_is_logged_never_raised(monkeypatch, clock, caplog):
    attempts: list[str] = []

    def mail_down(to, subject, html):
        attempts.append(to)
        raise RuntimeError("mail provider down")

    monkeypatch.setattr(operator_alerts, "send_email", mail_down)

    with caplog.at_level(logging.WARNING, logger="app.services.operator_alerts"):
        _alert()  # must not raise
        _alert()  # the hour is spent: no retry on every write while mail is down
    assert attempts == ["ops@example.com"]
    assert _records(caplog) == [
        (logging.WARNING, "tier down"),
        (logging.ERROR, "operator alert email failed (tier:down)"),
    ]


def test_callers_racing_for_one_key_send_once(sent, monkeypatch):
    """Sync endpoints call in from threadpool workers and the image tier
    through asyncio.to_thread: callers that check the key at the same moment
    must not all find it free."""

    class SlowToCheck(dict):
        def get(self, key, default=None):
            value = super().get(key, default)
            time.sleep(0.01)  # between the read and the claim: the race window
            return value

    monkeypatch.setattr(operator_alerts, "_last_sent", SlowToCheck())
    start = threading.Barrier(8)

    def caller() -> None:
        start.wait()
        _alert()

    threads = [threading.Thread(target=caller) for _ in range(8)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    assert len(sent) == 1
