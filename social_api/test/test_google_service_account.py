"""
test_google_service_account.py — the shared Google service-account key helper.

push_service (FCM) and moderation_service (Cloud Vision) each hold their own
key; google_service_account parses it, checks it at startup and caches its
token per (variable, scope). test_push.py patches push's token wholesale, so
this file pins the helper itself: strict=False, push's three startup lines
exactly as they were before the extraction, the per-key cache and its rebuild,
and the Cloud Vision startup check.

No network: google-auth's Credentials class is replaced, and the helper's
cache is emptied for each test that touches it.
"""

from __future__ import annotations

import functools
import json
import logging

import pytest

from app.config import Settings
from app.services import google_service_account, moderation_service, push_service

_PEM = "-----BEGIN PRIVATE KEY-----\nMIIfake\n-----END PRIVATE KEY-----\n"
_KEY = {
    "type": "service_account",
    "project_id": "ntripi-test",
    "client_email": "scanner@ntripi-test.iam.gserviceaccount.com",
    "private_key": _PEM,
    "token_uri": "https://oauth2.googleapis.com/token",
}


def _settings(**overrides) -> Settings:
    # _env_file=None keeps a developer's local .env out of these assertions.
    return Settings(
        DATABASE_URL="postgresql://user:pass@localhost/db", SECRET_KEY="x" * 32,
        _env_file=None, **overrides,
    )


def _errors(caplog, logger: str) -> list[str]:
    return [
        r.getMessage() for r in caplog.records
        if r.name == logger and r.levelno >= logging.ERROR
    ]


def _json_error(raw: str) -> str:
    try:
        json.loads(raw, strict=False)
    except json.JSONDecodeError as exc:
        return str(exc)
    raise AssertionError("expected invalid JSON")


# ---------------------------------------------------------------------------
# Parsing and the startup check
# ---------------------------------------------------------------------------

def test_a_paste_that_unescaped_the_key_parses_to_the_same_key():
    """An env-var paste can turn the key's \\n escapes into real line breaks."""
    escaped = json.dumps(_KEY)
    unescaped = escaped.replace("\\n", "\n")
    assert google_service_account.parse(unescaped) == google_service_account.parse(escaped) == _KEY


@pytest.mark.parametrize("raw, line", [
    ("{not json", "FCM_SERVICE_ACCOUNT_JSON is not valid JSON ({}) — push is off"),
    (json.dumps({"type": "service_account"}),
     "FCM_SERVICE_ACCOUNT_JSON is missing client_email, private_key, token_uri — push is off"),
    (json.dumps({**_KEY, "private_key": _PEM.replace("\n", " ")}),
     "FCM_SERVICE_ACCOUNT_JSON private_key is not a line-broken PEM — "
     "the env var likely lost its newlines; push is off"),
], ids=["not-json", "missing-fields", "single-line-pem"])
def test_push_logs_its_three_startup_lines_as_before(caplog, raw, line):
    settings = _settings(FCM_PROJECT_ID="test-project", FCM_SERVICE_ACCOUNT_JSON=raw)
    with caplog.at_level(logging.ERROR, logger="app.services.push_service"):
        push_service.validate_credentials(settings)
    expected = line.format(_json_error(raw)) if raw.startswith("{not") else line
    assert _errors(caplog, "app.services.push_service") == [expected]


def test_a_key_that_is_not_an_object_is_logged_never_raised(caplog):
    settings = _settings(FCM_PROJECT_ID="test-project", FCM_SERVICE_ACCOUNT_JSON='"a string"')
    with caplog.at_level(logging.ERROR, logger="app.services.push_service"):
        push_service.validate_credentials(settings)  # must not take the boot down
    assert _errors(caplog, "app.services.push_service") == [
        "FCM_SERVICE_ACCOUNT_JSON is not a JSON object — push is off"
    ]


def test_usable_keys_log_nothing(caplog):
    with caplog.at_level(logging.WARNING):
        push_service.validate_credentials(_settings(
            FCM_PROJECT_ID="test-project", FCM_SERVICE_ACCOUNT_JSON=json.dumps(_KEY),
        ))
        moderation_service.validate_credentials(_settings(
            MODERATION_PROVIDER="google_vision",
            MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON=json.dumps(_KEY),
        ))
    assert [r.getMessage() for r in caplog.records if r.levelno >= logging.WARNING] == []


def test_cloud_vision_needs_the_keys_project_at_startup(caplog):
    """`parent` names the key's own project: without project_id every scan fails."""
    key = {k: v for k, v in _KEY.items() if k != "project_id"}
    settings = _settings(
        MODERATION_PROVIDER="google_vision", MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON=json.dumps(key),
    )
    with caplog.at_level(logging.ERROR, logger="app.services.moderation_service"):
        moderation_service.validate_credentials(settings)
    assert _errors(caplog, "app.services.moderation_service") == [
        "MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON is missing project_id — every image scan will fail"
    ]


@pytest.mark.parametrize("overrides", [
    {"MODERATION_PROVIDER": "rekognition", "MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON": "{not json"},
    {"MODERATION_PROVIDER": "google_vision"},
], ids=["rekognition-selected", "key-unset"])
def test_the_cloud_vision_check_stays_quiet_where_it_does_not_apply(caplog, overrides):
    """An unset key is the not_configured alert's job; Rekognition gains no boot line."""
    with caplog.at_level(logging.DEBUG, logger="app.services.moderation_service"):
        moderation_service.validate_credentials(_settings(**overrides))
    assert [r for r in caplog.records if r.name == "app.services.moderation_service"] == []


# ---------------------------------------------------------------------------
# The token cache
# ---------------------------------------------------------------------------

def _fake_credentials(monkeypatch, *, fail: bool = False) -> list:
    """Replace google-auth's service-account Credentials; return every one built."""
    from google.oauth2 import service_account

    built: list = []

    class FakeCredentials:
        def __init__(self, info, scopes):
            self.info, self.scopes = info, scopes
            self.token, self.valid, self.requests = None, False, []
            built.append(self)

        @classmethod
        def from_service_account_info(cls, info, scopes):
            return cls(info, scopes)

        def refresh(self, request):
            self.requests.append(request)
            if fail:
                raise RuntimeError("token endpoint down")
            self.token, self.valid = f"token-{len(built)}", True

    monkeypatch.setattr(service_account, "Credentials", FakeCredentials)
    monkeypatch.setattr(google_service_account, "_slots", {})
    return built


def test_each_key_mints_once_and_reuses_its_token(monkeypatch):
    built = _fake_credentials(monkeypatch)
    raw = json.dumps(_KEY)

    first = google_service_account.access_token("FCM_SERVICE_ACCOUNT_JSON", raw, "scope-a")
    again = google_service_account.access_token("FCM_SERVICE_ACCOUNT_JSON", raw, "scope-a")
    other = google_service_account.access_token(
        "MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON", raw, "scope-b"
    )

    assert first == again != other
    # One credential per (variable, scope): revoking one key never touches the other.
    assert [c.scopes for c in built] == [["scope-a"], ["scope-b"]]
    assert all(len(c.requests) == 1 for c in built)


def test_a_timeout_bounds_each_token_request(monkeypatch):
    built = _fake_credentials(monkeypatch)

    google_service_account.access_token("VISION", json.dumps(_KEY), "s", timeout=(3, 3))
    google_service_account.access_token("PUSH", json.dumps(_KEY), "s")

    bounded, default = built[0].requests[0], built[1].requests[0]
    assert isinstance(bounded, functools.partial) and bounded.keywords == {"timeout": (3, 3)}
    assert not isinstance(default, functools.partial)   # google-auth's own default


def test_a_failed_mint_raises_and_the_next_call_starts_over(monkeypatch):
    built = _fake_credentials(monkeypatch, fail=True)

    for _ in range(2):
        with pytest.raises(RuntimeError):
            google_service_account.access_token("VISION", json.dumps(_KEY), "s")

    assert len(built) == 2   # the bad credentials were dropped, never reused


def test_push_still_fails_open_when_no_token_can_be_minted(monkeypatch, caplog):
    _fake_credentials(monkeypatch, fail=True)
    settings = _settings(FCM_PROJECT_ID="test-project", FCM_SERVICE_ACCOUNT_JSON=json.dumps(_KEY))

    with caplog.at_level(logging.ERROR, logger="app.services.push_service"):
        assert push_service._access_token(settings) is None

    assert _errors(caplog, "app.services.push_service") == ["Could not mint an FCM access token"]
