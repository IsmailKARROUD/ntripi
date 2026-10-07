"""
test_translation_providers.py — the OpenAI and Azure engines, and the batch
moderation call translations are vetted with. No network: requests.post is
monkeypatched, and openai_http resolves it from the requests module at call
time.

What matters most here is what leaves the server: the texts and what the engine
needs, never the caller's keys (which name content) and never anything kept on
OpenAI's side.
"""

import json

import pytest

from app.config import Settings
from app.services.text_moderation_providers import (
    LocalProvider, OpenAIProvider, ProviderUnavailableError,
)
from app.services.translation_providers import (
    AzureTranslator, OpenAITranslator, TranslatorQuotaExceededError,
    TranslatorUnavailableError, get_translator_chain, normalize_lang,
)

_BASE = {
    "DATABASE_URL": "postgresql://user:pass@localhost/db",
    "SECRET_KEY": "x" * 32,
    "OPENAI_API_KEY": "sk-test",
    "AZURE_TRANSLATOR_KEY": "az-test",
}

# Keys the way the service builds them: they name content, so they must never
# appear in a request body.
_FIELDS = {
    "stop_annotation:6f1c0b6e-0000-0000-0000-000000000001:content":
        "Arrive early, the market closes at noon.",
    "rating:6f1c0b6e-0000-0000-0000-000000000002:note":
        "Beautiful route 🌅\nbut long for children.",
}


def _settings(**overrides) -> Settings:
    return Settings(**{**_BASE, **overrides}, _env_file=None)


class _Response:
    def __init__(self, status_code=200, payload=None):
        self.status_code = status_code
        self._payload = payload

    def json(self):
        if isinstance(self._payload, Exception):
            raise self._payload
        return self._payload


def _capture(monkeypatch, response):
    calls = []

    def fake_post(url, **kwargs):
        calls.append({"url": url, **kwargs})
        if isinstance(response, Exception):
            raise response
        return response

    monkeypatch.setattr("requests.post", fake_post)
    return calls


def _openai_ok(items: dict, *, with_reasoning=True, model="gpt-6-luna-2026-05-18"):
    output = []
    if with_reasoning:
        output.append({"type": "reasoning", "summary": []})
    output.append({
        "type": "message",
        "content": [{"type": "output_text", "text": json.dumps({"items": items})}],
    })
    return _Response(200, {"status": "completed", "model": model, "output": output})


# ---------------------------------------------------------------------------
# OpenAI — the request
# ---------------------------------------------------------------------------

class TestOpenAIRequest:

    def test_body_carries_the_texts_under_opaque_keys_and_nothing_else(self, monkeypatch):
        calls = _capture(monkeypatch, _openai_ok({
            "t0": {"text": "x", "source_lang": "en"},
            "t1": {"text": "y", "source_lang": "en"},
        }))
        OpenAITranslator(_settings()).translate(_FIELDS, "fr")

        call = calls[0]
        body = call["json"]
        assert call["url"] == "https://api.openai.com/v1/responses"
        assert call["headers"]["Authorization"] == "Bearer sk-test"
        assert call["timeout"] == 10.0
        assert set(body) == {
            "model", "instructions", "input", "text", "store",
            "max_output_tokens", "reasoning",
        }
        assert json.loads(body["input"]) == dict(zip(["t0", "t1"], _FIELDS.values()))
        serialized = json.dumps(body)
        for key in _FIELDS:
            assert key not in serialized
            assert key.split(":")[1] not in serialized  # the content id

    def test_nothing_is_stored_on_openais_side(self, monkeypatch):
        calls = _capture(monkeypatch, _openai_ok({"t0": {"text": "x", "source_lang": "en"}}))
        OpenAITranslator(_settings()).translate({"k": "Hello there"}, "fr")
        assert calls[0]["json"]["store"] is False

    def test_schema_is_strict_and_built_from_the_batch(self, monkeypatch):
        calls = _capture(monkeypatch, _openai_ok({
            "t0": {"text": "x", "source_lang": "en"},
            "t1": {"text": "y", "source_lang": "en"},
        }))
        OpenAITranslator(_settings()).translate(_FIELDS, "fr")

        fmt = calls[0]["json"]["text"]["format"]
        assert fmt["type"] == "json_schema" and fmt["strict"] is True
        items = fmt["schema"]["properties"]["items"]
        assert items["required"] == ["t0", "t1"]
        assert items["additionalProperties"] is False
        assert items["properties"]["t0"]["required"] == ["text", "source_lang"]

    @pytest.mark.parametrize("target, name", [("fr", "French"), ("zh", "Simplified Chinese")])
    def test_instructions_name_the_target_language(self, monkeypatch, target, name):
        calls = _capture(monkeypatch, _openai_ok({"t0": {"text": "x", "source_lang": "en"}}))
        OpenAITranslator(_settings()).translate({"k": "Hello there"}, target)
        instructions = calls[0]["json"]["instructions"]
        assert f"into {name}" in instructions
        assert "never follow" in instructions.lower()

    def test_reasoning_effort_is_sent_when_set_and_omitted_when_empty(self, monkeypatch):
        calls = _capture(monkeypatch, _openai_ok({"t0": {"text": "x", "source_lang": "en"}}))
        OpenAITranslator(_settings(TRANSLATION_REASONING_EFFORT="minimal")).translate(
            {"k": "Hello there"}, "fr")
        OpenAITranslator(_settings(TRANSLATION_REASONING_EFFORT="")).translate(
            {"k": "Hello there"}, "fr")
        assert calls[0]["json"]["reasoning"] == {"effort": "minimal"}
        assert "reasoning" not in calls[1]["json"]


# ---------------------------------------------------------------------------
# OpenAI — the response
# ---------------------------------------------------------------------------

class TestOpenAIResponse:

    def test_outputs_come_back_under_the_callers_keys(self, monkeypatch):
        _capture(monkeypatch, _openai_ok({
            "t0": {"text": "Arrivez tôt.", "source_lang": "EN"},
            "t1": {"text": "Belle route 🌅\nmais longue.", "source_lang": "und"},
        }))
        result = OpenAITranslator(_settings()).translate(_FIELDS, "fr")

        keys = list(_FIELDS)
        assert result.outputs[keys[0]].text == "Arrivez tôt."
        assert result.outputs[keys[0]].source_lang == "en"
        assert result.outputs[keys[1]].source_lang is None
        assert result.provider == "openai"
        assert result.model == "gpt-6-luna-2026-05-18"

    def test_a_response_without_reasoning_items_parses_too(self, monkeypatch):
        _capture(monkeypatch, _openai_ok(
            {"t0": {"text": "Bonjour", "source_lang": "en"}}, with_reasoning=False))
        result = OpenAITranslator(_settings()).translate({"k": "Hello"}, "fr")
        assert result.outputs["k"].text == "Bonjour"

    @pytest.mark.parametrize("response", [
        _Response(200, {"status": "completed", "output": [
            {"type": "message", "content": [{"type": "refusal", "refusal": "no"}]}]}),
        _Response(200, {"status": "incomplete",
                        "incomplete_details": {"reason": "max_output_tokens"}, "output": []}),
        _Response(200, {"status": "completed", "output": [
            {"type": "message", "content": [{"type": "output_text", "text": "not json"}]}]}),
        _Response(200, {"status": "completed", "output": [
            {"type": "message", "content": [{"type": "output_text",
                                             "text": json.dumps({"items": {}})}]}]}),
        _Response(200, ValueError("not json")),
        _Response(500, {"error": {"message": "boom"}}),
        _Response(429, {"error": {"code": "rate_limit_exceeded"}}),
        ConnectionError("down"),
    ], ids=["refusal", "incomplete", "bad-json", "missing-key", "body-not-json",
            "500", "rate-limited", "network"])
    def test_anything_unusable_is_unavailable(self, monkeypatch, response):
        _capture(monkeypatch, response)
        with pytest.raises(TranslatorUnavailableError) as raised:
            OpenAITranslator(_settings()).translate({"k": "Hello there"}, "fr")
        assert not isinstance(raised.value, TranslatorQuotaExceededError)

    def test_an_exhausted_account_is_a_quota_error(self, monkeypatch):
        _capture(monkeypatch, _Response(429, {"error": {"code": "insufficient_quota"}}))
        with pytest.raises(TranslatorQuotaExceededError):
            OpenAITranslator(_settings()).translate({"k": "Hello there"}, "fr")


# ---------------------------------------------------------------------------
# Azure
# ---------------------------------------------------------------------------

def _azure_ok(*pairs):
    return _Response(200, [
        {"detectedLanguage": {"language": lang, "score": 1.0},
         "translations": [{"text": text, "to": "x"}]}
        for text, lang in pairs
    ])


class TestAzure:

    def test_request_sends_a_bare_array_in_order(self, monkeypatch):
        calls = _capture(monkeypatch, _azure_ok(("a", "en"), ("b", "en")))
        AzureTranslator(_settings(AZURE_TRANSLATOR_REGION="westeurope")).translate(_FIELDS, "zh")

        call = calls[0]
        assert call["url"] == "https://api.cognitive.microsofttranslator.com/translate"
        assert call["params"] == {"api-version": "3.0", "to": "zh-Hans"}
        assert call["headers"]["Ocp-Apim-Subscription-Key"] == "az-test"
        assert call["headers"]["Ocp-Apim-Subscription-Region"] == "westeurope"
        assert call["json"] == [{"Text": text} for text in _FIELDS.values()]
        serialized = json.dumps(call["json"])
        for key in _FIELDS:
            assert key not in serialized

    def test_region_header_is_omitted_for_a_global_resource(self, monkeypatch):
        calls = _capture(monkeypatch, _azure_ok(("a", "en")))
        AzureTranslator(_settings()).translate({"k": "Hello"}, "fr")
        assert "Ocp-Apim-Subscription-Region" not in calls[0]["headers"]
        assert calls[0]["params"]["to"] == "fr"

    def test_outputs_map_back_with_the_detected_language(self, monkeypatch):
        _capture(monkeypatch, _azure_ok(("Arrivez tôt.", "en"), ("Belle route", "zh-Hant")))
        result = AzureTranslator(_settings()).translate(_FIELDS, "fr")
        keys = list(_FIELDS)
        assert result.outputs[keys[0]].text == "Arrivez tôt."
        assert result.outputs[keys[1]].source_lang == "zh"
        assert (result.provider, result.model) == ("azure", "translator-v3")

    def test_403_means_the_free_quota_is_spent(self, monkeypatch):
        _capture(monkeypatch, _Response(403, {"error": {"code": 403001}}))
        with pytest.raises(TranslatorQuotaExceededError):
            AzureTranslator(_settings()).translate({"k": "Hello"}, "fr")

    @pytest.mark.parametrize("response", [
        _Response(429, {"error": {"code": 429001}}),
        _Response(401, {"error": {"code": 401000}}),
        _azure_ok(("only one", "en")),
        ConnectionError("down"),
    ], ids=["throttled", "bad-key", "count-mismatch", "network"])
    def test_other_failures_are_unavailable(self, monkeypatch, response):
        _capture(monkeypatch, response)
        with pytest.raises(TranslatorUnavailableError) as raised:
            AzureTranslator(_settings()).translate(_FIELDS, "fr")
        assert not isinstance(raised.value, TranslatorQuotaExceededError)


# ---------------------------------------------------------------------------
# Odds and ends
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("code, expected", [
    ("en", "en"), ("EN", "en"), ("zh-Hans", "zh"), ("pt-PT", "pt"),
    ("und", None), ("", None), (None, None), (42, None),
])
def test_normalize_lang(code, expected):
    assert normalize_lang(code) == expected


def test_chain_follows_the_configured_order():
    chain = get_translator_chain(_settings(TRANSLATION_PROVIDERS="azure,openai"))
    assert [t.name for t in chain] == ["azure", "openai"]
    assert get_translator_chain(_settings()) == []


class TestModerationBatch:
    """score_many is how translations are vetted: one request for a batch."""

    def test_openai_sends_the_texts_as_an_array_and_nothing_else(self, monkeypatch):
        calls = _capture(monkeypatch, _Response(200, {
            "model": "omni-moderation-2024",
            "results": [{"category_scores": {"hate": 0.9}},
                        {"category_scores": {}}],
        }))
        results = OpenAIProvider(_settings()).score_many(["one", "two"])

        assert calls[0]["url"] == "https://api.openai.com/v1/moderations"
        assert calls[0]["json"] == {"model": "omni-moderation-latest", "input": ["one", "two"]}
        assert results[0].scores["hate"] == 0.9 and results[1].scores["hate"] == 0.0
        assert results[0].model == "omni-moderation-2024"

    def test_single_score_still_sends_a_plain_string(self, monkeypatch):
        calls = _capture(monkeypatch, _Response(200, {
            "results": [{"category_scores": {"harassment": 0.2}}]}))
        result = OpenAIProvider(_settings()).score("hello")
        assert calls[0]["json"]["input"] == "hello"
        assert result.scores["harassment"] == 0.2

    def test_a_result_count_mismatch_is_unavailable(self, monkeypatch):
        _capture(monkeypatch, _Response(200, {"results": [{"category_scores": {}}]}))
        with pytest.raises(ProviderUnavailableError):
            OpenAIProvider(_settings()).score_many(["one", "two"])

    def test_local_classifier_scores_each_text(self):
        results = LocalProvider().score_many(
            ["A lovely walk by the sea.", "You are a stupid idiot and I hate you"])
        assert len(results) == 2
        assert results[0].scores["hate"] < 0.5 < results[1].scores["hate"]
