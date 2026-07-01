"""
services/pwned_service.py — "Have I Been Pwned" breached-password check.

Uses the k-anonymity range API: we SHA-1 the password, send only the first 5
hex chars of the digest, and match the returned suffixes locally. The full
password (and its full hash) never leaves this process.

The check FAILS OPEN: any network error, timeout, or disabled config returns
False (treated as "not breached"). A breach-lookup outage must never block a
user from setting a legitimate password. `requests` is already available via
google-auth[requests] — no new dependency (mirrors email_service).
"""

from __future__ import annotations

import hashlib
import logging

from app.config import get_settings

logger = logging.getLogger(__name__)

_RANGE_ENDPOINT = "https://api.pwnedpasswords.com/range/"


def is_pwned(password: str) -> bool:
    """Return True if `password` appears in the HIBP breach corpus.

    Returns False when the check is disabled or on any lookup failure
    (fail-open — see module docstring)."""
    if not get_settings().PWNED_CHECK_ENABLED:
        return False

    digest = hashlib.sha1(password.encode("utf-8")).hexdigest().upper()
    prefix, suffix = digest[:5], digest[5:]

    try:
        import requests  # local import: only this path needs it

        resp = requests.get(
            f"{_RANGE_ENDPOINT}{prefix}",
            # Add-Padding hides the exact result-set size from a network observer.
            headers={"Add-Padding": "true"},
            timeout=2,
        )
        if resp.status_code != 200:
            logger.warning("HIBP range lookup returned %s", resp.status_code)
            return False
        # Each line is "SUFFIX:COUNT". A padding row has count 0 — ignore it.
        for line in resp.text.splitlines():
            candidate, _, count = line.partition(":")
            if candidate.strip().upper() == suffix and count.strip() not in ("", "0"):
                return True
        return False
    except Exception as exc:  # network error, timeout — fail open
        logger.warning("HIBP lookup failed, allowing password: %r", exc)
        return False
