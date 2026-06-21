"""
services/email_service.py — Transactional email abstraction.

Calling code uses send_email(to, subject, html) and never cares which backend
is active. Backends (mirrors the storage abstraction):
  - "console": logs the message + any link to stdout. Default for local dev —
    no provider/API key needed; copy the link from the server log.
  - "resend":  POSTs to the Resend HTTP API. No SDK dependency — uses `requests`
    (already pulled in by google-auth[requests]).

Send failures are logged and swallowed, never raised: a transient email outage
must not 500 a registration or password-reset request.
"""

from __future__ import annotations

import logging

from app.config import get_settings

logger = logging.getLogger(__name__)

_RESEND_ENDPOINT = "https://api.resend.com/emails"


def send_email(to: str, subject: str, html: str) -> None:
    """Send a transactional email via the configured backend. Best-effort."""
    settings = get_settings()
    backend = (settings.EMAIL_BACKEND or "console").lower()

    if backend == "resend":
        _send_resend(to, subject, html, settings.RESEND_API_KEY, settings.EMAIL_FROM)
    else:
        _send_console(to, subject, html, settings.EMAIL_FROM)


def _send_console(to: str, subject: str, html: str, sender: str) -> None:
    # Dev backend: surface the email (and its link) in the server log so the
    # whole flow is testable without a provider.
    logger.warning(
        "[email:console] from=%s to=%s subject=%r\n%s", sender, to, subject, html
    )


def _send_resend(to: str, subject: str, html: str, api_key: str | None, sender: str) -> None:
    if not api_key:
        logger.error("EMAIL_BACKEND=resend but RESEND_API_KEY is unset; email not sent to %s", to)
        return
    try:
        import requests  # local import: only the resend path needs it

        resp = requests.post(
            _RESEND_ENDPOINT,
            headers={"Authorization": f"Bearer {api_key}"},
            json={"from": sender, "to": [to], "subject": subject, "html": html},
            timeout=10,
        )
        if resp.status_code >= 400:
            logger.error("Resend send failed (%s): %s", resp.status_code, resp.text[:500])
    except Exception as exc:  # network error, timeout — never break the caller
        logger.error("Resend send raised for %s: %r", to, exc)
