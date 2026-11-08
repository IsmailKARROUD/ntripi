"""
test_moderation_pieces.py — a long text is moderated in pieces, its worst piece
deciding (text_moderation_service.split_for_moderation / score_text /
score_texts).

Coverage:
  TestSplitting     — a piece never passes 2,000 characters or 4,000 UTF-8
                      bytes, cuts fall at paragraphs, sentences, then spaces,
                      and no word is lost — in English, Arabic and Chinese
  TestWrites        — a short write is still today's single score() request; a
                      long one is one score_many call, and a bad sentence in
                      any piece refuses it, through the API too; the cache keys
                      on the whole text
  TestTranslations  — translated output is read in pieces as well
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from conftest import TestingSessionLocal, auth_headers, edit_now, register_user
from app.config import get_settings
from app.models.user import User
from app.services import text_moderation_service as tms
from app.services import translation_service
from app.services.text_moderation_providers import ProviderResult

BAD = "zzbadword"


class PieceProvider:
    """Scores `hate` high for any piece holding BAD; records every call."""

    name = "stub"
    model = "stub-model"

    def __init__(self):
        self.calls: list[tuple[str, object]] = []

    def _one(self, text: str) -> ProviderResult:
        return ProviderResult(scores={"hate": 0.99 if BAD in text else 0.01},
                              provider=self.name, model=self.model)

    def score(self, text: str) -> ProviderResult:
        self.calls.append(("score", text))
        return self._one(text)

    def score_many(self, texts: list[str]) -> list[ProviderResult]:
        self.calls.append(("many", list(texts)))
        return [self._one(text) for text in texts]


@pytest.fixture()
def provider(monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "TEXT_MODERATION_PROVIDER", "openai")
    monkeypatch.setattr(settings, "OPENAI_API_KEY", "test-key")
    stub = PieceProvider()
    monkeypatch.setattr(tms, "get_provider_chain", lambda settings: [stub])
    return stub


@pytest.fixture()
def db(client):
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture()
def author(client, db) -> User:
    register_user(client, username="writer", email="writer@example.com")
    return db.query(User).filter(User.username_lower == "writer").one()


def _ctx(db, author) -> tms.TextModerationContext:
    return tms.TextModerationContext(
        db=db, settings=get_settings(), target_type="itinerary", author=author,
    )


def _paragraphs(count: int, words: int = 70, *, bad_at: int | None = None) -> str:
    """`count` paragraphs of plain sentences, each word unique; BAD planted in
    paragraph `bad_at`."""
    paragraphs = []
    for p in range(count):
        sentence_words = [f"word{p}x{w}" for w in range(words)]
        if p == bad_at:
            sentence_words[words // 2] = BAD
        sentences = [" ".join(sentence_words[i:i + 10]) + "."
                     for i in range(0, words, 10)]
        paragraphs.append(" ".join(sentences))
    return "\n\n".join(paragraphs)


def _within_bounds(piece: str) -> bool:
    return (len(piece) <= tms.PIECE_MAX_CHARS
            and len(piece.encode("utf-8")) <= tms.PIECE_MAX_BYTES)


class TestSplitting:
    def test_a_text_that_fits_is_one_piece(self):
        assert tms.split_for_moderation("Bring cash.") == ["Bring cash."]

    def test_english_pieces_respect_the_bounds_and_lose_no_word(self):
        text = _paragraphs(20)  # ~12,000 characters
        pieces = tms.split_for_moderation(text)
        assert len(pieces) > 1 and all(_within_bounds(p) for p in pieces)
        assert " ".join(pieces).split() == text.split()
        # Cut between paragraphs where one fits: no piece starts mid-paragraph.
        assert all(piece.startswith("word") and piece.split()[0].endswith("x0")
                   for piece in pieces)

    def test_arabic_pieces_stay_under_the_byte_bound(self):
        text = " ".join(["هذه جملة عربية قصيرة عن الرحلة."] * 400)
        pieces = tms.split_for_moderation(text)
        assert len(pieces) > 1 and all(_within_bounds(p) for p in pieces)
        assert " ".join(pieces).split() == text.split()

    def test_chinese_pieces_are_cut_at_sentence_marks(self):
        text = "这是一个关于旅行的句子。" * 900  # no spaces, ~32,000 bytes
        pieces = tms.split_for_moderation(text)
        assert len(pieces) > 1 and all(_within_bounds(p) for p in pieces)
        assert all(p.endswith("。") for p in pieces)
        assert "".join(p.replace(" ", "") for p in pieces) == text

    def test_a_word_longer_than_a_piece_is_cut_where_it_must_be(self):
        pieces = tms.split_for_moderation("x" * 5000)
        assert [len(p) for p in pieces] == [2000, 2000, 1000]


class TestWrites:
    def test_a_short_write_is_still_one_score_request(self, db, author, provider):
        tms.moderate_fields_or_raise({"title": "A calm trip"}, _ctx(db, author))
        assert provider.calls == [("score", "A calm trip")]

    def test_a_long_write_is_one_batch_and_its_worst_piece_decides(
        self, db, author, provider,
    ):
        text = _paragraphs(12, bad_at=8)
        with pytest.raises(tms.TextModerationRejectedError):
            tms.moderate_fields_or_raise({"description": text}, _ctx(db, author))
        assert len(provider.calls) == 1
        kind, pieces = provider.calls[0]
        assert kind == "many" and len(pieces) > 2
        assert BAD not in pieces[0] and any(BAD in piece for piece in pieces)

    def test_many_fields_together_are_read_in_pieces(self, db, author, provider):
        # The sweep's re-check hands a whole trip over as one field map.
        fields = {f"stop:{i}:notes": _paragraphs(1, words=60) for i in range(15)}
        tms.moderate_fields_or_raise(fields, _ctx(db, author))
        assert [kind for kind, _ in provider.calls] == ["many"]

    def test_the_cache_keys_on_the_whole_text(self, db, author, provider):
        text = _paragraphs(12)
        tms.moderate_fields_or_raise({"description": text}, _ctx(db, author))
        db.commit()
        provider.calls.clear()
        tms.moderate_fields_or_raise({"description": text}, _ctx(db, author))
        assert provider.calls == []

    def test_through_the_api_a_bad_sentence_far_down_is_refused(
        self, client: TestClient, provider,
    ):
        owner = register_user(client, "owner", "owner@example.com")
        hdrs = auth_headers(owner["access_token"])
        r = client.post("/itineraries/", json={"title": "Long", "currency": "EUR"},
                        headers=hdrs)
        assert r.status_code == 201, r.text
        trip = r.json()["id"]
        description = _paragraphs(5, words=70, bad_at=4)[:3900]
        assert BAD in description[2100:]
        provider.calls.clear()

        r = client.patch(f"/itineraries/{trip}", json={"description": description},
                         headers=edit_now(client, trip, hdrs))

        assert r.status_code == 422, r.text
        assert r.json()["code"] == "text_moderation_rejected"


class TestTranslations:
    def test_translated_output_is_read_in_pieces(self, monkeypatch, provider):
        settings = get_settings()
        monkeypatch.setattr(settings, "TRANSLATION_MODERATE_OUTPUT", True)
        monkeypatch.setattr(translation_service, "get_moderation_chain",
                            lambda settings: [provider])
        refusals = translation_service._moderation_refusals(
            {"t0": _paragraphs(8), "t1": _paragraphs(8, bad_at=6), "t2": "Short."},
            settings,
        )
        assert refusals == {"t1": "moderation"}
        assert all(kind == "many" for kind, _ in provider.calls)
        assert sum(len(batch) for _, batch in provider.calls) > 3
