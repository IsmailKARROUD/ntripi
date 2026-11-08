"""validators/links.py — no user text carries a link, except a stop's map link.

The owner's rule (decisions.md 2026-11-08): a text someone writes on Ntripi —
a title, a description, a note, a stop's name, a review, a bio, a username —
may not hold a link. The one link a user may give is a stop's Google Maps link,
in its own field (validators/map_link.py). Texts only the operator reads (a
report's notes, an appeal's reason, a bug report) keep accepting links: a
reporter often has to paste one as evidence.

A link is, in the owner's own words:
  - anything with an address scheme: `x://…`, `http:`, `https:`,
    `javascript:`, `vbscript:`, `mailto:`, and `data:` before a type/subtype
    (so a plain label such as "Data: 5GB" is not one);
  - anything starting `www.`;
  - markdown link or image syntax, `[label](…)` / `![alt](…)`, and a reference
    definition, `[label]: …`;
  - an e-mail address;
  - a bare site name: dot-separated labels ending in a real top-level domain
    (constants/tlds.py), with at least one letter before it — `booking.com`,
    `hotel-atlas.ma`, `anna.paris`. `3.5km`, `e.g.` and `St.Louis` are not;
    `lunch.Tours` (a missing space) is, and the owner accepted such false
    alarms: the refusal quotes the exact text found, so it is easy to fix.

A link is refused only in a field whose value changes: a text stored before the
rule keeps its link until someone edits that text (`refuse_new_links`).

The app mirrors this detector (lib/core/text/link_rule.dart) and both are held
to one sample list, social_flutter/test/support/link_rule_samples.json.
"""

from __future__ import annotations

import re
from typing import Any, Mapping

from fastapi import status

from app.constants.tlds import IANA_TLDS
from app.errors import ApiError

# Every pattern is written so Python's `re` and Dart's RegExp read it alike:
# explicit character classes instead of \b, ASCII-only matching where only
# ASCII is meant (re.A), and [^\W_] / [\w-] for the Unicode letters and digits
# of a domain label (Dart: [\p{L}\p{N}] / [\p{L}\p{N}_-]).
_SCHEME_SLASHES = re.compile(r"[a-z][a-z0-9+.-]*://\S*", re.I | re.A)
_BARE_SCHEME = re.compile(
    r"(?<![a-z0-9_])(?:(?:https?|javascript|vbscript|mailto):\S+"
    r"|data:[a-z]+/[a-z0-9.+-]+\S*)",
    re.I | re.A,
)
_WWW = re.compile(r"(?<![\w.-])www\.\S+", re.I)
_MD_LINK = re.compile(r"!?\[[^\]\n]*\]\([^)\n]*\)")
_MD_REFERENCE = re.compile(r"^[ ]{0,3}\[[^\]\n]+\]:[ \t]*\S+", re.M)
_EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@(?P<domain>(?:[\w-]+\.)+[\w-]+)")
_SITE_NAME = re.compile(
    r"(?<![\w.-])(?P<domain>(?:[\w-]+\.)+[\w-]+)(?![\w-])(?:/\S*)?"
)

_PATTERNS = (_SCHEME_SLASHES, _BARE_SCHEME, _WWW, _MD_LINK, _MD_REFERENCE)


def _is_site_name(domain: str) -> bool:
    """Labels ending in a real top-level domain, with a letter before it."""
    *names, tld = domain.split(".")
    return tld.lower() in IANA_TLDS and any(ch.isalpha() for ch in "".join(names))


def _first_domain_match(pattern: re.Pattern, text: str) -> re.Match | None:
    for match in pattern.finditer(text):
        if _is_site_name(match["domain"]):
            return match
    return None


def find_link(text: str | None) -> str | None:
    """The first link in `text` — its exact characters, which the refusal
    quotes back — or None. When two kinds start at the same place, the longer
    one is reported."""
    if not text:
        return None
    spans: list[tuple[int, int]] = []
    for pattern in _PATTERNS:
        match = pattern.search(text)
        if match:
            spans.append(match.span())
    for pattern in (_EMAIL, _SITE_NAME):
        match = _first_domain_match(pattern, text)
        if match:
            spans.append(match.span())
    if not spans:
        return None
    start, end = min(spans, key=lambda span: (span[0], -span[1]))
    return text[start:end]


def refuse_new_links(
    fields: Mapping[str, str | None],
    stored: Mapping[str, Any] | Any | None = None,
) -> None:
    """Raises 422 `text_contains_link` (extra: field, match) for the first field
    whose new value holds a link.

    `fields` are the values about to be stored, after the write's own clean-up
    (stripping); `stored` the same fields as they are now — a mapping, or the
    row itself (read by attribute) — or None on a create. A value equal to the
    stored one is never refused: an old link stays until its text is edited, so
    a form that re-sends an untouched field (the trip form always sends the
    note) is not blocked by text it did not change. Callers run this after
    their access checks and before moderation, so a refused write costs no
    provider call.
    """
    def current(field: str) -> Any:
        if stored is None:
            return None
        if isinstance(stored, Mapping):
            return stored.get(field)
        return getattr(stored, field, None)

    for field, value in fields.items():
        if not isinstance(value, str) or value == current(field):
            continue
        match = find_link(value)
        if match is not None:
            raise ApiError(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                "text_contains_link",
                "Links are not allowed in this text.",
                extra={"field": field, "match": match},
            )
