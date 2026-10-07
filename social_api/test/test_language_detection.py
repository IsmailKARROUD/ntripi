"""
test_language_detection.py — the save-time source-language detector.

detect() decides whether a reader is offered "See translation", so the cases
that matter are: prose is labelled correctly, text that carries no language is
left unlabelled (None, which still offers the button), and nothing the detector
does can fail the write it runs inside.

Settings is instantiated directly for the config cases, like
test_text_moderation_config.py, so the shared get_settings() singleton is never
disturbed.
"""

import pytest
from pydantic import ValidationError

from app.config import Settings
from app.services import language_detection
from app.services.language_detection import detect


@pytest.mark.parametrize("text, expected", [
    ("Lovely sunset walk along the harbour, bring a warm jacket.", "en"),
    ("Balade magnifique le long du port au coucher du soleil.", "fr"),
    ("Paseo precioso por el puerto al atardecer, lleva chaqueta.", "es"),
    ("Wunderschöner Spaziergang am Hafen bei Sonnenuntergang.", "de"),
    ("نزهة جميلة على طول الميناء عند غروب الشمس", "ar"),
    ("日落时沿着港口散步，记得带外套。", "zh"),
    ("Bellissima passeggiata lungo il porto al tramonto.", "it"),
    ("夕暮れ時の港沿いの素敵な散歩。", "ja"),
])
def test_detects_the_language_of_prose(text, expected):
    assert detect(text) == expected


@pytest.mark.parametrize("text", [
    None, "", "   ", "OK", "🙂🙂🙂", "12:30 – 14:00",
    "https://example.com/a/long/english/looking/path",
    "@marie #paris",
])
def test_text_without_language_signal_is_left_undetected(text):
    assert detect(text) is None


def test_a_url_does_not_outvote_the_prose_around_it():
    text = (
        "Super adresse, réservez la veille : "
        "https://example.com/the-best-english-guide-for-walking-tours-in-the-city"
    )
    assert detect(text) == "fr"


def test_a_failing_detector_never_fails_the_caller(monkeypatch):
    class _Broken:
        def detect_language_of(self, text):
            raise RuntimeError("language model missing")

    monkeypatch.setattr(language_detection, "_get_detector", lambda: _Broken())
    assert detect("Lovely sunset walk along the harbour.") is None


def test_a_restricted_list_answers_only_from_that_list(monkeypatch):
    """A shorter TRANSLATION_DETECT_LANGS loads fewer models, at the price of
    forcing other languages onto their nearest neighbour in the list."""
    class _Settings:
        translation_detect_langs = ["en", "fr"]

    monkeypatch.setattr(language_detection, "get_settings", lambda: _Settings())
    monkeypatch.setattr(language_detection, "_detector", None)
    assert detect("Balade magnifique le long du port au coucher du soleil.") == "fr"
    assert detect("Paseo precioso por el puerto al atardecer.") in ("en", "fr", None)


# ---------------------------------------------------------------------------
# TRANSLATION_DETECT_LANGS
# ---------------------------------------------------------------------------

_BASE = {
    "DATABASE_URL": "postgresql://user:pass@localhost/db",
    "SECRET_KEY": "x" * 32,
}


def _settings(**overrides) -> Settings:
    # _env_file=None keeps a developer's local .env out of these assertions.
    return Settings(**{**_BASE, **overrides}, _env_file=None)


def test_detect_langs_defaults_to_every_language():
    assert _settings().translation_detect_langs is None


def test_detect_langs_list_is_normalised():
    settings = _settings(TRANSLATION_DETECT_LANGS=" EN, fr ,de ")
    assert settings.translation_detect_langs == ["en", "fr", "de"]


@pytest.mark.parametrize("value", ["", "english", "en,,fra", "e", "en;fr"])
def test_malformed_detect_langs_refuses_to_boot(value):
    with pytest.raises(ValidationError, match="TRANSLATION_DETECT_LANGS"):
        _settings(TRANSLATION_DETECT_LANGS=value)
