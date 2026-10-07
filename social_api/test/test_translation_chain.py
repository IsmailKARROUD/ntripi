"""
test_translation_chain.py — translation_service.run_chain, the engine chain.

Each engine only gets what the engines before it could not translate; a field
counts as translated once it passes the output checks (and, when on, output
moderation); a field nobody translated is reported, never invented. Engines are
FakeTranslators — no network.
"""

import logging

import pytest

from app.config import Settings
from app.services import translation_service
from app.services.text_moderation_providers import ProviderResult, ProviderUnavailableError
from app.services.translation_providers import (
    TranslatorQuotaExceededError, TranslatorUnavailableError,
)
from app.services.translation_service import run_chain
from translation_fakes import FakeTranslator

_BASE = {
    "DATABASE_URL": "postgresql://user:pass@localhost/db",
    "SECRET_KEY": "x" * 32,
}

FIELDS = {
    "a": "Walk along the harbour at sunset, it is beautiful.",
    "b": "Bring cash for the ferry, cards are not accepted.",
    "c": "The market closes at noon on Sundays.",
}


def _settings(**overrides) -> Settings:
    return Settings(**{**_BASE, **overrides}, _env_file=None)


def test_the_first_engine_translates_everything_it_can():
    first, second = FakeTranslator("first"), FakeTranslator("second")
    outcome = run_chain(FIELDS, "fr", _settings(), chain=[first, second])

    assert set(outcome.translated) == set(FIELDS)
    assert outcome.failed == {}
    assert outcome.translated["a"].text == f"[fr] {FIELDS['a']}"
    assert outcome.translated["a"].provider == "first"
    assert outcome.translated["a"].model == "first-model"
    assert outcome.translated["a"].source_lang == "en"
    assert second.calls == []


@pytest.mark.parametrize("error", [
    TranslatorUnavailableError("HTTP 500"),
    TranslatorQuotaExceededError("quota"),
    RuntimeError("provider bug"),
], ids=["unavailable", "quota", "bug"])
def test_a_failing_engine_hands_everything_to_the_next(error):
    first = FakeTranslator("first", fail=error)
    second = FakeTranslator("second")
    outcome = run_chain(FIELDS, "fr", _settings(), chain=[first, second])

    assert {t.provider for t in outcome.translated.values()} == {"second"}
    assert set(second.keys_seen) == set(FIELDS)


def test_only_the_fields_that_failed_a_check_go_to_the_next_engine():
    # The first engine drops the URL from one field and nothing else.
    source = "Book ahead: https://example.com/tickets"
    first = FakeTranslator("first", overrides={source: "Réservez à l'avance."})
    second = FakeTranslator("second")
    outcome = run_chain({**FIELDS, "url": source}, "fr", _settings(), chain=[first, second])

    assert outcome.translated["url"].provider == "second"
    assert outcome.translated["a"].provider == "first"
    assert second.keys_seen == ["url"]


def test_a_field_missing_from_the_answer_goes_to_the_next_engine():
    first = FakeTranslator("first", overrides={FIELDS["b"]: None})
    second = FakeTranslator("second")
    outcome = run_chain(FIELDS, "fr", _settings(), chain=[first, second])

    assert outcome.translated["b"].provider == "second"
    assert second.keys_seen == ["b"]


def test_nothing_is_invented_when_every_engine_fails():
    first = FakeTranslator("first", fail=TranslatorUnavailableError("down"))
    second = FakeTranslator("second", overrides={FIELDS["a"]: "  "})
    outcome = run_chain({"a": FIELDS["a"]}, "fr", _settings(), chain=[first, second])

    assert outcome.translated == {}
    assert outcome.failed == {"a": "second:empty"}


def test_no_engine_configured_translates_nothing():
    outcome = run_chain(FIELDS, "fr", _settings(), chain=[])
    assert outcome.translated == {}
    assert set(outcome.failed) == set(FIELDS)


def test_batches_respect_the_engines_limits():
    engine = FakeTranslator("first", max_batch_fields=2)
    fields = {f"k{i}": f"Sentence number {i} about the harbour." for i in range(5)}
    outcome = run_chain(fields, "fr", _settings(), chain=[engine])

    assert [len(batch) for batch, _ in engine.calls] == [2, 2, 1]
    assert len(outcome.translated) == 5


def test_an_engine_that_fails_a_batch_is_not_retried_for_the_rest():
    first = FakeTranslator("first", fail=TranslatorUnavailableError("down"),
                           max_batch_fields=1)
    second = FakeTranslator("second")
    run_chain(FIELDS, "fr", _settings(), chain=[first, second])

    assert len(first.calls) == 1
    assert set(second.keys_seen) == set(FIELDS)


def test_sources_are_normalised_before_they_are_sent():
    engine = FakeTranslator("first")
    run_chain({"a": "  Line one.\r\nLine two.  "}, "fr", _settings(), chain=[engine])
    assert engine.calls[0][0] == {"a": "Line one.\nLine two."}


def test_no_text_reaches_the_logs(caplog):
    first = FakeTranslator("first", fail=TranslatorUnavailableError("HTTP 503"))
    second = FakeTranslator("second")
    with caplog.at_level(logging.INFO, logger="app.services.translation_service"):
        run_chain(FIELDS, "fr", _settings(), chain=[first, second])

    logged = " ".join(record.getMessage() for record in caplog.records)
    assert "provider=first" in logged and "provider=second" in logged
    for key, text in FIELDS.items():
        assert text not in logged
        assert text[:20] not in logged


# ---------------------------------------------------------------------------
# Output moderation
# ---------------------------------------------------------------------------

class _Classifier:
    """Scores any text containing "HATE" as hate, everything else as clean."""

    name = "stub"
    model = "stub"

    def __init__(self, fail=False):
        self.fail = fail
        self.batches = []

    def score_many(self, texts):
        self.batches.append(list(texts))
        if self.fail:
            raise ProviderUnavailableError("down")
        return [
            ProviderResult(scores={"hate": 0.99 if "HATE" in t else 0.0},
                           provider="stub", model="stub")
            for t in texts
        ]


@pytest.fixture()
def classifier(monkeypatch):
    stub = _Classifier()
    monkeypatch.setattr(translation_service, "get_moderation_chain", lambda s: [stub])
    return stub


def test_a_translation_the_policy_refuses_goes_to_the_next_engine(classifier):
    first = FakeTranslator("first", overrides={FIELDS["a"]: "HATE " + FIELDS["a"]})
    second = FakeTranslator("second")
    outcome = run_chain(FIELDS, "fr", _settings(TEXT_MODERATION_PROVIDER="local"),
                        chain=[first, second])

    assert outcome.translated["a"].provider == "second"
    assert outcome.translated["b"].provider == "first"
    assert classifier.batches[0] and len(classifier.batches) == 2  # one call per batch


def test_with_moderation_down_nothing_new_is_cached(monkeypatch):
    stub = _Classifier(fail=True)
    monkeypatch.setattr(translation_service, "get_moderation_chain", lambda s: [stub])
    outcome = run_chain(FIELDS, "fr", _settings(TEXT_MODERATION_PROVIDER="local"),
                        chain=[FakeTranslator("first")])

    assert outcome.translated == {}
    assert set(outcome.failed.values()) == {"first:moderation_unavailable"}


@pytest.mark.parametrize("overrides", [
    {"TEXT_MODERATION_PROVIDER": "disabled"},
    {"TEXT_MODERATION_PROVIDER": "local", "TRANSLATION_MODERATE_OUTPUT": False},
], ids=["moderation-off", "output-check-off"])
def test_output_moderation_can_be_off(classifier, overrides):
    outcome = run_chain(FIELDS, "fr", _settings(**overrides),
                        chain=[FakeTranslator("first")])
    assert len(outcome.translated) == 3
    assert classifier.batches == []
