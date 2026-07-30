"""
test_text_moderation_config.py — startup validation for moderation settings.

A misconfigured moderation tier must refuse to boot rather than degrade
silently in production: selecting OpenAI without a key would quietly scan
nothing but the fallback wordlist, and an unparseable threshold string would
only surface the first time somebody filed a report.

Settings is instantiated directly (not via get_settings()) so the lru_cache
singleton the rest of the suite shares is never disturbed.
"""

import pytest
from pydantic import ValidationError

from app.config import Settings

# Minimum viable config — every test varies one field on top of this.
_BASE = {
    "DATABASE_URL": "postgresql://user:pass@localhost/db",
    "SECRET_KEY": "x" * 32,
}


def _settings(**overrides) -> Settings:
    # _env_file=None keeps a developer's local .env out of these assertions.
    return Settings(**{**_BASE, **overrides}, _env_file=None)


def test_defaults_are_disabled_and_valid():
    settings = _settings()
    assert settings.TEXT_MODERATION_PROVIDER == "disabled"
    assert settings.MODERATION_SLA_HOURS == 20


def test_openai_without_key_refuses_to_start():
    with pytest.raises(ValidationError, match="OPENAI_API_KEY"):
        _settings(TEXT_MODERATION_PROVIDER="openai")


def test_openai_with_key_is_accepted():
    settings = _settings(TEXT_MODERATION_PROVIDER="openai", OPENAI_API_KEY="sk-test")
    assert settings.TEXT_MODERATION_PROVIDER == "openai"


def test_local_provider_needs_no_key():
    assert _settings(TEXT_MODERATION_PROVIDER="local").TEXT_MODERATION_PROVIDER == "local"


def test_unknown_provider_name_is_rejected():
    with pytest.raises(ValidationError, match="TEXT_MODERATION_PROVIDER"):
        _settings(TEXT_MODERATION_PROVIDER="perspective")


@pytest.mark.parametrize("hours", [23, 24, 48, 0])
def test_sla_hours_outside_the_safe_window_are_rejected(hours):
    """The DSA clock starts when the report is filed, not when the sweep runs,
    so the threshold must leave room for a missed sweep before 24h."""
    with pytest.raises(ValidationError):
        _settings(MODERATION_SLA_HOURS=hours)


@pytest.mark.parametrize("hours", [1, 20, 22])
def test_sla_hours_inside_the_safe_window_are_accepted(hours):
    assert _settings(MODERATION_SLA_HOURS=hours).MODERATION_SLA_HOURS == hours


def test_report_thresholds_parse_into_a_dict():
    thresholds = _settings().report_hide_thresholds
    assert thresholds["csam"] == 1
    assert thresholds["spam"] == 4
    assert set(thresholds) == {
        "csam", "sexual_content", "violence_threat",
        "hate_speech", "harassment", "other", "spam",
    }


def test_report_thresholds_are_overridable():
    thresholds = _settings(
        REPORT_HIDE_THRESHOLDS="csam:1,spam:9"
    ).report_hide_thresholds
    assert thresholds == {"csam": 1, "spam": 9}


@pytest.mark.parametrize("value", [
    "csam",           # missing count
    "csam:zero",      # non-numeric
    "csam:0",         # zero reporters would hide everything instantly
    "csam:-1",
])
def test_malformed_thresholds_fail_at_startup_not_at_report_time(value):
    with pytest.raises(ValidationError):
        _settings(REPORT_HIDE_THRESHOLDS=value)
