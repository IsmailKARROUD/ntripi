"""
services/google_people.py — read a birthday from the Google People API.

Google ID tokens carry no birthdate: the claim set is sub / email /
email_verified / name / given_name / family_name / picture / locale / hd and
the JWT registered claims, and nothing else. A birthday needs the People API,
the `user.birthday.read` sensitive scope, and an OAuth access token — which is
a different credential from the ID token /auth/google verifies statelessly.

This module FAILS TO THE FALLBACK, never raises. Every unusable answer — no
birthday set, a birthday with the year hidden, a denied scope, a timeout, a
non-200 — returns None, and the caller asks the user instead. That is not
defensive padding: a large share of Google accounts genuinely have no readable
birth year, so the consent sheet is the normal path, not the error path.

Sync def with a blocking requests.get, deliberately. Every caller is a sync
FastAPI endpoint, which runs in a threadpool, so the blocking call never
touches the event loop. Do NOT convert this or its callers to async def —
that would put the sync SQLAlchemy session on the loop, which is the real
hazard (same reasoning as jira_service and the text-moderation providers).
"""

from __future__ import annotations

import logging
from datetime import date
from typing import Any

import requests

logger = logging.getLogger(__name__)

BIRTHDAY_SCOPE = "https://www.googleapis.com/auth/user.birthday.read"

_PEOPLE_URL = "https://people.googleapis.com/v1/people/me"
_TIMEOUT_SECONDS = 5.0


def _pick_birthday(birthdays: list[dict[str, Any]]) -> dict[str, Any] | None:
    """The entry to trust, or None if none carries a year.

    Google returns up to two: source type ACCOUNT (what the account holder set
    on the account itself, and what Google's own age gating uses) and PROFILE
    (what they chose to display). ACCOUNT wins. Entries without a `year` are
    unusable at any priority — Google lets people publish month and day while
    hiding the year, and a birthday with no year cannot answer "are they 16".
    """
    dated = [
        b for b in birthdays
        if isinstance(b, dict) and isinstance(b.get("date"), dict)
        and b["date"].get("year")
    ]
    if not dated:
        return None
    for entry in dated:
        source = (entry.get("metadata") or {}).get("source") or {}
        if source.get("type") == "ACCOUNT":
            return entry
    return dated[0]


def fetch_birthdate(access_token: str, expected_sub: str) -> date | None:
    """The Google account's birth date, or None if we cannot get a usable one.

    `expected_sub` is the `sub` claim from the already-verified ID token, and
    checking it is load-bearing rather than belt-and-braces: the access token
    arrives from the client as a separate credential, so without this check a
    caller could pair their own ID token with an access token minted for a
    different Google account and inherit that account's birthday. People API
    returns `resourceName: "people/<id>"` where <id> is that same `sub`.
    """
    try:
        response = requests.get(
            _PEOPLE_URL,
            params={"personFields": "birthdays"},
            headers={"Authorization": f"Bearer {access_token}"},
            timeout=_TIMEOUT_SECONDS,
        )
    except requests.RequestException as exc:
        logger.warning("People API request failed: %s", exc.__class__.__name__)
        return None

    if response.status_code != 200:
        # 401/403 is the ordinary shape of a denied or expired scope, not an
        # incident — the user simply gets asked for their birthday instead.
        logger.info("People API returned %s", response.status_code)
        return None

    try:
        payload = response.json()
    except ValueError:
        logger.warning("People API returned a non-JSON body")
        return None

    if payload.get("resourceName") != f"people/{expected_sub}":
        # Never log either identifier — one is a stable Google user id and the
        # other is whatever the caller sent; the mismatch itself is the signal.
        logger.warning("People API resourceName did not match the ID token subject")
        return None

    entry = _pick_birthday(payload.get("birthdays") or [])
    if entry is None:
        return None

    parts = entry["date"]
    try:
        return date(int(parts["year"]), int(parts["month"]), int(parts["day"]))
    except (KeyError, TypeError, ValueError):
        # A year without a month/day is well-formed to Google and useless here.
        logger.info("People API birthday was not a complete date")
        return None
