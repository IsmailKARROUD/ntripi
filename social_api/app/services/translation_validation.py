"""
services/translation_validation.py — checks a translation must pass before it
is cached and served to every later reader.

A failed check is not an error: the field falls through to the next engine, and
if every engine fails it is answered "unavailable" and nothing is cached. The
checks are loose on purpose — they catch an engine that dropped a link, merged
paragraphs, summarised, or answered something other than a translation, not a
translation a reader might word differently.
"""

from __future__ import annotations

import re
import unicodedata
from collections import Counter

_URL_RE = re.compile(r"(?:https?://|www\.)[^\s<>()\[\]]+", re.IGNORECASE)
# The lookbehind keeps the domain of an email address from reading as a mention.
_MENTION_RE = re.compile(r"(?<![\w@])@[\w.]+")
_TRAILING_PUNCTUATION = ".,;:!?)»”'\""

# Below this many characters a length ratio says nothing ("Paris" → "París").
_RATIO_MIN_SOURCE_CHARS = 12
# Most language pairs stay well inside this band.
_RATIO_BOUNDS = (0.3, 3.5)
# Chinese, Japanese and Korean pack a word into one or two characters, so a
# CJK side can legitimately be far shorter, or far longer, than the other.
_CJK_RATIO_BOUNDS = (0.12, 7.0)


def failure(source: str, translation: str) -> str | None:
    """Why `translation` cannot stand in for `source`, or None if it can.

    The reason is a short code for the logs — never the text itself.
    """
    if not translation.strip():
        return "empty"
    if not _urls(source) <= _urls(translation):
        return "url"
    if not _mentions(source) <= _mentions(translation):
        return "mention"
    if _symbols(source) != _symbols(translation):
        return "symbols"
    if _line_count(source) != _line_count(translation):
        return "lines"
    if not _length_plausible(source, translation):
        return "length"
    return None


def _urls(text: str) -> set[str]:
    return {match.rstrip(_TRAILING_PUNCTUATION) for match in _URL_RE.findall(text)}


def _mentions(text: str) -> set[str]:
    return {match.rstrip(".") for match in _MENTION_RE.findall(text)}


def _symbols(text: str) -> Counter:
    """Emoji and other pictographic symbols (Unicode category So). Variation
    selectors and joiners are other categories, so an engine that normalises
    them does not fail."""
    return Counter(ch for ch in text if unicodedata.category(ch) == "So")


def _line_count(text: str) -> int:
    return sum(1 for line in text.splitlines() if line.strip())


def _is_cjk(text: str) -> bool:
    letters = [ch for ch in text if ch.isalpha()]
    if not letters:
        return False
    cjk = sum(
        1 for ch in letters
        if "぀" <= ch <= "ヿ"      # kana
        or "㐀" <= ch <= "鿿"      # CJK ideographs
        or "가" <= ch <= "힯"      # hangul syllables
    )
    return cjk / len(letters) > 0.3


def _length_plausible(source: str, translation: str) -> bool:
    if len(source.strip()) < _RATIO_MIN_SOURCE_CHARS:
        return True
    low, high = (
        _CJK_RATIO_BOUNDS if _is_cjk(source) or _is_cjk(translation) else _RATIO_BOUNDS
    )
    ratio = len(translation.strip()) / len(source.strip())
    return low <= ratio <= high
