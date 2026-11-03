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
from html import escape

from app.config import get_settings
from app.i18n import RTL_LANGS, translator

logger = logging.getLogger(__name__)

_RESEND_ENDPOINT = "https://api.resend.com/emails"


def branded_email_html(
    heading: str, body: str, button_label: str, link: str, *, lang: str = "en",
) -> str:
    """The branded HTML body every Ntripi email uses: a heading, a paragraph and
    one button, with the link printed beneath it for clients that drop buttons.

    `lang` translates that last line and turns Arabic right to left; English
    output is what it has always been, byte for byte. The radius is a typed
    number, not a CSS variable — email clients drop variables, and
    test_radius_scale holds it to the app's button token.

    The link is escaped here: a raw `&lang=` is the entity `&lang;` to some mail
    clients, which turn the URL into `…〈=en` and break the link. `heading` and
    `body` are HTML, escaped by their callers.
    """
    direction = ' dir="rtl"' if lang in RTL_LANGS else ""
    fallback = translator(lang)("email_button_fallback")
    link = escape(link, quote=True)
    return f"""\
<div{direction} style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:480px;margin:0 auto;padding:24px;color:#1b2a22">
  <h2 style="color:#1F5E3A;margin:0 0 12px">Ntripi</h2>
  <h3 style="margin:0 0 8px">{heading}</h3>
  <p style="color:#52615a;font-size:14px;margin:0 0 20px">{body}</p>
  <a href="{link}" style="display:inline-block;background:#1F5E3A;color:#fff;
     text-decoration:none;font-weight:700;padding:12px 22px;border-radius:14px">{button_label}</a>
  <p style="color:#8a9690;font-size:12px;margin:24px 0 0">
    {fallback}<br>{link}
  </p>
</div>"""


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
