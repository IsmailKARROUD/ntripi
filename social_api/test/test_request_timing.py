"""
test_request_timing.py — the slow-request log.

Railway shows WARNING lines only, so this log is the one place production says
where a request's time went. On 2026-10-20 a Postgres service in another region
made every save take four to six seconds, and nothing in the logs said so.
"""

import logging
import re
import uuid

import pytest
import requests
from pydantic import ValidationError

from app.config import Settings, get_settings
from app.middleware import request_timing
from app.middleware.request_timing import RequestTimings, install_outbound_hooks
from conftest import auth_headers, register_user

LOGGER = "app.middleware.request_timing"


@pytest.fixture()
def log_every_request(monkeypatch):
    monkeypatch.setattr(get_settings(), "SLOW_REQUEST_LOG_MS", 0)


def _lines(caplog) -> list[str]:
    return [r.getMessage() for r in caplog.records if r.name == LOGGER]


def _queries(line: str) -> int:
    return int(re.search(r" db=\d+ms/(\d+)q ", line).group(1))


# ---------------------------------------------------------------------------
# The line
# ---------------------------------------------------------------------------

def test_a_request_past_the_threshold_logs_one_line(client, caplog, log_every_request):
    trip_id = uuid.uuid4()
    with caplog.at_level(logging.WARNING, logger=LOGGER):
        assert client.get(f"/share/i/{trip_id}").status_code == 404

    lines = _lines(caplog)
    assert len(lines) == 1
    assert lines[0].startswith("slow request: GET /share/i/{itinerary_id} status=404 total=")
    assert _queries(lines[0]) == 1  # the one db.get behind the 404
    assert " ext=- " in lines[0]


def test_the_route_template_is_logged_never_the_path(client, caplog, log_every_request):
    trip_id = uuid.uuid4()
    with caplog.at_level(logging.WARNING, logger=LOGGER):
        client.get(f"/share/i/{trip_id}")
        client.get("/no/such/page/a-secret-token")

    logged = "\n".join(_lines(caplog))
    assert str(trip_id) not in logged
    assert "a-secret-token" not in logged
    assert "GET <no route> status=404" in logged


def test_a_request_with_no_query_counts_none(client, caplog, log_every_request):
    with caplog.at_level(logging.WARNING, logger=LOGGER):
        client.get("/share/i/not-a-uuid")  # refused before any query

    [line] = _lines(caplog)
    assert _queries(line) == 0


def test_a_request_under_the_threshold_logs_nothing(client, caplog, monkeypatch):
    monkeypatch.setattr(get_settings(), "SLOW_REQUEST_LOG_MS", 60_000)
    with caplog.at_level(logging.WARNING, logger=LOGGER):
        client.get(f"/share/i/{uuid.uuid4()}")
    assert _lines(caplog) == []


def test_health_and_static_files_are_never_timed(client, caplog, log_every_request):
    with caplog.at_level(logging.WARNING, logger=LOGGER):
        client.get("/health")
        client.get("/static/no-such-file.png")
    assert _lines(caplog) == []


# ---------------------------------------------------------------------------
# Outbound HTTP
# ---------------------------------------------------------------------------

class _FakeAdapter(requests.adapters.BaseAdapter):
    """Answers without a network: a 302 for any URL ending in /start, else 200."""

    def __init__(self):
        super().__init__()
        self.calls = 0

    def send(self, request, **kwargs):
        self.calls += 1
        response = requests.Response()
        response.request = request
        response.url = request.url
        response._content = b""
        if request.url.endswith("/start"):
            response.status_code = 302
            response.headers["Location"] = "https://api.example.com/end"
        else:
            response.status_code = 200
        return response

    def close(self):
        pass


def _session(adapter) -> requests.Session:
    session = requests.Session()
    session.mount("https://", adapter)
    return session


def test_both_outbound_seams_are_wrapped():
    from botocore.httpsession import URLLib3Session

    install_outbound_hooks()  # idempotent: the app already ran it at import
    assert getattr(requests.Session.send, "_request_timing", False)
    assert getattr(URLLib3Session.send, "_request_timing", False)


def test_an_outbound_call_is_timed_per_host_and_a_redirect_counts_once():
    adapter = _FakeAdapter()
    timings = RequestTimings()
    token = request_timing._current.set(timings)
    try:
        _session(adapter).get("https://api.example.com/start")
    finally:
        request_timing._current.reset(token)

    assert adapter.calls == 2  # the redirect really was followed
    assert list(timings.ext) == ["api.example.com"]
    assert timings.ext["api.example.com"][1] == 1


def test_an_outbound_call_outside_a_request_records_nothing():
    timings = RequestTimings()
    _session(_FakeAdapter()).get("https://api.example.com/end")
    assert timings.ext == {}
    assert request_timing._current.get() is None


def test_a_request_names_the_host_it_waited_on(client, caplog, monkeypatch, log_every_request):
    # A password change checks the new password against Have I Been Pwned.
    token = register_user(client, "timing_user", "timing_user@example.com")["access_token"]
    adapter = _FakeAdapter()
    monkeypatch.setattr(get_settings(), "PWNED_CHECK_ENABLED", True)
    monkeypatch.setattr(requests.adapters.HTTPAdapter, "send",
                        lambda self, request, **kwargs: adapter.send(request))
    with caplog.at_level(logging.WARNING, logger=LOGGER):
        r = client.post(
            "/auth/change-password",
            json={"current_password": "test1234", "new_password": "Correct-horse-battery-9"},
            headers=auth_headers(token),
        )
    assert r.status_code == 200, r.text
    assert adapter.calls == 1

    [line] = [l for l in _lines(caplog) if " /auth/change-password " in l]
    assert re.search(r" ext=api\.pwnedpasswords\.com:\d+ms/1 ", line)
    assert _queries(line) >= 1


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

_BASE = {"DATABASE_URL": "postgresql://user:pass@localhost/db", "SECRET_KEY": "x" * 32}


def test_the_threshold_defaults_to_one_second():
    assert Settings(**_BASE, _env_file=None).SLOW_REQUEST_LOG_MS == 1000


def test_a_negative_threshold_refuses_to_boot():
    with pytest.raises(ValidationError):
        Settings(**_BASE, SLOW_REQUEST_LOG_MS=-1, _env_file=None)
