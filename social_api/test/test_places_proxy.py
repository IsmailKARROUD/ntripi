"""
test_places_proxy.py — the stop form's Google place search, through our server.

Google is stubbed at `requests` inside services/google_places (no network, no
key). What is pinned here: the feature is invisible without its key, it costs a
verified account one request from an hourly budget, exactly what crosses to
Google (the text, the language, a bias rounded to 0.1° — nothing about the
user), and that Google's answer is never logged or cached.
"""

from __future__ import annotations

import logging

import pytest
import requests

from conftest import auth_headers, register_user
from app.config import get_settings
from app.services import google_places

SENTINEL_INPUT = "SENTINEL-SEARCH-TEXT"
SENTINEL_NAME = "SENTINEL-GOOGLE-PLACE-NAME"


class FakeResponse:
    def __init__(self, status_code=200, payload=None, text_body=None):
        self.status_code = status_code
        self._payload = payload
        self._text = text_body

    def json(self):
        if self._payload is None:
            raise ValueError("no JSON")
        return self._payload


class FakeGoogle:
    """Records every call; answers with one place prediction by default."""

    def __init__(self):
        self.calls: list[dict] = []
        self.response = FakeResponse(200, {"suggestions": [
            {"placePrediction": {
                "placeId": "ChIJLU7jZClu5kcR4PcOOO6p3I0",
                "structuredFormat": {
                    "mainText": {"text": SENTINEL_NAME},
                    "secondaryText": {"text": "Paris, France"},
                },
            }},
            # A query prediction carries no place: dropped.
            {"queryPrediction": {"text": {"text": "pizza near me"}}},
        ]})
        self.error: Exception | None = None

    def post(self, url, json=None, headers=None, timeout=None):
        self.calls.append({"url": url, "json": json, "headers": headers, "timeout": timeout})
        if self.error is not None:
            raise self.error
        return self.response


@pytest.fixture()
def google(monkeypatch):
    fake = FakeGoogle()
    monkeypatch.setattr(google_places.requests, "post", fake.post)
    monkeypatch.setattr(get_settings(), "GOOGLE_PLACES_API_KEY", "test-places-key")
    return fake


@pytest.fixture()
def user(client):
    return auth_headers(register_user(client, "alice", "alice@example.com")["access_token"])


def _search(client, headers, **body):
    payload = {"input": SENTINEL_INPUT, "language": "fr", **body}
    return client.post("/places/google/autocomplete", json=payload, headers=headers)


def test_config_needs_an_account(client):
    assert client.get("/places/config").status_code == 403


def test_config_says_what_is_on(client, user, monkeypatch):
    assert client.get("/places/config", headers=user).json() == {
        "google_search": False, "google_maps": False,
    }
    monkeypatch.setattr(get_settings(), "GOOGLE_PLACES_API_KEY", "k1")
    monkeypatch.setattr(get_settings(), "GOOGLE_MAPS_EMBED_API_KEY", "k2")
    assert client.get("/places/config", headers=user).json() == {
        "google_search": True, "google_maps": True,
    }


def test_without_a_key_the_search_does_not_exist(client, user):
    assert _search(client, user).status_code == 404


def test_an_unverified_account_cannot_spend_a_paid_search(client, google):
    unverified = register_user(client, "bobby", "bob@example.com", verified=False)
    response = _search(client, auth_headers(unverified["access_token"]))
    assert response.status_code == 403
    assert response.json()["code"] == "email_unverified"
    assert google.calls == []


def test_only_the_text_language_and_a_rounded_bias_reach_google(client, user, google):
    response = _search(client, user, bias={"lat": 48.858370, "lng": 2.294481})

    assert response.status_code == 200, response.text
    [call] = google.calls
    assert call["url"] == "https://places.googleapis.com/v1/places:autocomplete"
    assert call["headers"]["X-Goog-Api-Key"] == "test-places-key"
    assert "placeId" in call["headers"]["X-Goog-FieldMask"]
    assert call["json"] == {
        "input": SENTINEL_INPUT,
        "languageCode": "fr",
        "locationBias": {"circle": {
            "center": {"latitude": 48.9, "longitude": 2.3},
            "radius": 50_000.0,
        }},
    }


def test_no_bias_sends_no_location(client, user, google):
    _search(client, user)
    assert "locationBias" not in google.calls[0]["json"]


def test_the_answer_is_the_suggestions_and_nothing_keeps_it(client, user, google):
    response = _search(client, user)

    assert response.headers["cache-control"] == "no-store"
    assert response.json() == {"suggestions": [{
        "place_id": "ChIJLU7jZClu5kcR4PcOOO6p3I0",
        "main_text": SENTINEL_NAME,
        "secondary_text": "Paris, France",
    }]}


def test_the_hourly_budget_refuses_and_counts_nothing_more(client, user, google, monkeypatch):
    monkeypatch.setattr(get_settings(), "GOOGLE_PLACES_USER_HOURLY_LIMIT", 2)
    assert _search(client, user).status_code == 200
    assert _search(client, user).status_code == 200

    refused = _search(client, user)

    assert refused.status_code == 429
    assert refused.json()["code"] == "place_search_rate_limited"
    assert int(refused.headers["retry-after"]) > 0
    assert len(google.calls) == 2


@pytest.mark.parametrize("failure", [
    requests.Timeout("slow"),
    FakeResponse(500),
    FakeResponse(200, payload=None),  # not JSON
])
def test_google_failing_is_a_503(client, user, google, failure):
    if isinstance(failure, Exception):
        google.error = failure
    else:
        google.response = failure

    response = _search(client, user)

    assert response.status_code == 503
    assert response.json()["code"] == "place_search_unavailable"


@pytest.mark.parametrize("body", [
    {"input": "ab"},
    {"input": "   abc   "[:4]},
    {"language": "xx"},
    {"bias": {"lat": 91, "lng": 0}},
])
def test_a_malformed_search_is_refused_before_google(client, user, google, body):
    assert _search(client, user, **body).status_code == 422
    assert google.calls == []


def test_neither_the_search_text_nor_googles_answer_is_ever_logged(
        client, user, google, caplog):
    caplog.set_level(logging.DEBUG)
    _search(client, user)
    google.response = FakeResponse(500)
    _search(client, user)
    google.error = requests.ConnectionError(SENTINEL_INPUT)
    _search(client, user)

    assert SENTINEL_INPUT not in caplog.text
    assert SENTINEL_NAME not in caplog.text
