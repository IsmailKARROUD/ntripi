"""
test_translation_config.py — startup validation for the translation settings.

Like test_text_moderation_config.py: a setup that would quietly translate
nothing must refuse to boot. Settings is instantiated directly so the shared
get_settings() singleton is never disturbed.
"""

import pytest
from pydantic import ValidationError

from app.config import TRANSLATION_PROVIDER_NAMES, Settings
from app.constants.translation_languages import TARGET_LANGUAGES
from app.services import translation_providers

_BASE = {
    "DATABASE_URL": "postgresql://user:pass@localhost/db",
    "SECRET_KEY": "x" * 32,
}


def _settings(**overrides) -> Settings:
    # _env_file=None keeps a developer's local .env out of these assertions.
    return Settings(**{**_BASE, **overrides}, _env_file=None)


def test_translation_is_off_by_default():
    settings = _settings()
    assert settings.translation_providers == []
    assert settings.translation_enabled is False
    assert settings.translation_supported_langs == ["en", "fr", "es", "de", "ar", "zh"]


def test_providers_keep_their_order():
    settings = _settings(
        TRANSLATION_PROVIDERS=" Azure , openai ",
        OPENAI_API_KEY="sk-test", AZURE_TRANSLATOR_KEY="az-test",
    )
    assert settings.translation_providers == ["azure", "openai"]
    assert settings.translation_enabled is True


def test_openai_without_key_refuses_to_start():
    with pytest.raises(ValidationError, match="OPENAI_API_KEY"):
        _settings(TRANSLATION_PROVIDERS="openai")


def test_azure_without_key_refuses_to_start():
    with pytest.raises(ValidationError, match="AZURE_TRANSLATOR_KEY"):
        _settings(TRANSLATION_PROVIDERS="azure")


@pytest.mark.parametrize("value", ["deepl", "openai,openai"])
def test_unknown_or_repeated_provider_refuses_to_start(value):
    with pytest.raises(ValidationError, match="TRANSLATION_PROVIDERS"):
        _settings(TRANSLATION_PROVIDERS=value, OPENAI_API_KEY="sk-test")


@pytest.mark.parametrize("value", ["", "en,xx", "english"])
def test_unsupported_target_language_refuses_to_start(value):
    with pytest.raises(ValidationError, match="TRANSLATION_SUPPORTED_LANGS"):
        _settings(TRANSLATION_SUPPORTED_LANGS=value)


def test_non_positive_timeout_refuses_to_start():
    with pytest.raises(ValidationError, match="TRANSLATION_TIMEOUT_SECONDS"):
        _settings(TRANSLATION_TIMEOUT_SECONDS=0)


def test_every_accepted_provider_name_has_an_engine():
    """A name config accepts but the chain cannot build would boot fine and
    then fail on the first translation."""
    assert set(TRANSLATION_PROVIDER_NAMES) == set(translation_providers._FACTORIES)


def test_every_target_language_has_a_name_and_an_azure_code():
    for code, (name, azure_code) in TARGET_LANGUAGES.items():
        assert len(code) == 2 and name and azure_code
