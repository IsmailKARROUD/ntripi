"""
services/language_detection.py — which language a piece of user text is in.

Runs at save time on every translatable field, so the client can tell whether
to offer "See translation" without asking anyone: the answer is stored on the
row as `source_lang`. A local library rather than a provider — no request, no
text leaves the server, and it answers in milliseconds.

lingua, in high-accuracy mode: trip titles are short, and its low-accuracy mode
loses most of its accuracy under ~120 characters. Language models load lazily,
per candidate language, the first time a text needs them.

Never raises. A write must not fail because detection did: an undetected
language is stored as NULL, which the client treats as "offer the button" and
the translation provider then settles.
"""

from __future__ import annotations

import logging
import re
import threading

from app.config import get_settings

logger = logging.getLogger(__name__)

# The best language must beat the runner-up by this margin, or the answer is
# None. Measured on short trip titles in eight languages: at 0.1 about one
# confident answer in forty was wrong and a quarter came back undetected; at
# 0.0 one in ten was wrong. Undetected is harmless (the button still shows); a
# wrong answer can hide the button from a reader who needs it.
_MIN_RELATIVE_DISTANCE = 0.1

# Fewer letters than this carry no language signal ("OK", "B&B", "🙂🙂").
_MIN_LETTERS = 3

# Removed before detecting: they are the same in every language, and a URL's
# English path words would otherwise outvote a short French note around it.
_URL_RE = re.compile(r"https?://\S+|www\.\S+", re.IGNORECASE)
_HANDLE_RE = re.compile(r"[@#][\w.]+")

_detector = None
_detector_lock = threading.Lock()


def detect(text: str | None) -> str | None:
    """The lowercase ISO 639-1 code `text` is written in, or None when it
    cannot be told reliably."""
    if not text:
        return None
    cleaned = _HANDLE_RE.sub(" ", _URL_RE.sub(" ", text))
    if sum(ch.isalpha() for ch in cleaned) < _MIN_LETTERS:
        return None
    try:
        language = _get_detector().detect_language_of(cleaned)
    except Exception:
        logger.exception("language detection failed")
        return None
    if language is None:
        return None
    return language.iso_code_639_1.name.lower()


def _get_detector():
    """Build the detector once per process. It is thread-safe, and every
    request thread shares it — the models are the expensive part."""
    global _detector
    if _detector is None:
        with _detector_lock:
            if _detector is None:
                _detector = _build_detector()
    return _detector


def _build_detector():
    from lingua import IsoCode639_1, LanguageDetectorBuilder

    codes = get_settings().translation_detect_langs
    if codes is None:
        builder = LanguageDetectorBuilder.from_all_languages()
    else:
        isos = []
        for code in codes:
            try:
                isos.append(IsoCode639_1.from_str(code))
            except ValueError:
                # Well-formed but unknown to lingua (config validation only
                # checks the shape): skip it rather than refuse to detect.
                logger.warning("TRANSLATION_DETECT_LANGS: lingua has no %r; skipped", code)
        if not isos:
            raise ValueError("TRANSLATION_DETECT_LANGS names no language lingua knows")
        builder = LanguageDetectorBuilder.from_iso_codes_639_1(*isos)
    return builder.with_minimum_relative_distance(_MIN_RELATIVE_DISTANCE).build()
