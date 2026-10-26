"""
services/google_service_account.py — a Google service-account key held in an
env var, and the bearer tokens it mints.

Two integrations hold one, each its own: FCM push (FCM_SERVICE_ACCOUNT_JSON)
and Cloud Vision image moderation (MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON). One
key per job, so revoking either never stops the other — which is why the token
cache is keyed by the variable and the scope, and why each key refreshes under
its own lock: a token request stalled for push must never hold up an upload's
scan.

NO SDK. google-auth (installed for Sign-In) mints the token from the key, and
every caller POSTs with plain `requests`, so the outbound timing hook on
requests.Session.send sees each call — the token request included.
"""

from __future__ import annotations

import functools
import json
import logging
import threading
from dataclasses import dataclass, field
from typing import Any, Sequence

# What google-auth needs to mint a token. A caller that reads more of the key
# (Cloud Vision's project_id) adds it to `required`.
REQUIRED_FIELDS = ("client_email", "private_key", "token_uri")


def parse(raw: str | None) -> dict[str, Any]:
    """Parse a service-account key read from an env var. The only parser — the
    startup check and the token mint must agree on what counts as readable.

    `strict=False` because the value reaches us through an env var: a paste that
    turns the private_key's `\\n` escapes into real line breaks is JSON's
    "Invalid control character" and nothing else. Tolerating those raw newlines
    yields a byte-identical key to a correctly-escaped parse, which is why this
    is safe where rewriting the string would not be.
    """
    return json.loads(raw or "{}", strict=False)


def validate(
    var_name: str, raw: str | None, *, consequence: str, log: logging.Logger,
    required: Sequence[str] = REQUIRED_FIELDS,
) -> None:
    """Log at ERROR — never raise — when the key in `var_name` cannot be used,
    each line ending in `consequence`: what the integration loses. Logged
    through the caller's `log`, so a line keeps its integration's logger.

    Never raises: each key serves a best-effort or fail-open channel, and a bad
    paste must not cost the whole deploy. But it must not be silent either —
    without this the first sign of a broken key is a traceback under someone's
    first follow or upload.
    """
    try:
        info = parse(raw)
    except json.JSONDecodeError as exc:
        log.error("%s is not valid JSON (%s) — %s", var_name, exc, consequence)
        return
    if not isinstance(info, dict):
        log.error("%s is not a JSON object — %s", var_name, consequence)
        return

    missing = [k for k in required if not info.get(k)]
    if missing:
        log.error("%s is missing %s — %s", var_name, ", ".join(missing), consequence)
        return

    # The failure strict=False cannot catch: a paste that dropped the escapes
    # entirely leaves a single-line PEM that parses fine here and only dies
    # later, inside google-auth, with nothing pointing back at the env var.
    key = info["private_key"]
    if not isinstance(key, str) or "\n" not in key.strip() or "-----BEGIN" not in key:
        log.error(
            "%s private_key is not a line-broken PEM — "
            "the env var likely lost its newlines; %s", var_name, consequence,
        )


@dataclass
class _Slot:
    """One key's credentials, and the lock its refresh runs under."""

    lock: threading.Lock = field(default_factory=threading.Lock)
    creds: Any = None


_slots: dict[tuple[str, str], _Slot] = {}
_slots_lock = threading.Lock()


def access_token(
    var_name: str, raw: str | None, scope: str, *,
    timeout: float | tuple[float, float] | None = None,
) -> str:
    """A bearer token for `scope`, minted from the key in `var_name` and reused
    until it expires. google-auth keeps the token on the Credentials object and
    knows its own expiry (~1 h), so this refreshes rarely.

    `timeout` bounds each token request. None keeps google-auth's 120 s —
    harmless on a background worker, far too long inside an upload.

    Raises on any failure — bad JSON, a revoked key, no network — having first
    dropped the cached credentials, so the next call rebuilds from scratch
    rather than reusing a bad one.
    """
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    with _slots_lock:
        slot = _slots.setdefault((var_name, scope), _Slot())
    with slot.lock:
        try:
            if slot.creds is None:
                slot.creds = service_account.Credentials.from_service_account_info(
                    parse(raw), scopes=[scope]
                )
            # `valid` is False both before the first refresh and after expiry.
            if not slot.creds.valid:
                request = Request()
                slot.creds.refresh(
                    request if timeout is None
                    else functools.partial(request, timeout=timeout)
                )
            return slot.creds.token
        except Exception:
            slot.creds = None
            raise
