"""
Tests for the three legal documents and their localisation.

Two things are being pinned here. First, that no language can silently ship an
empty legal page — the accessors fall back to English rather than returning "".
Second, that every non-English rendering carries the prevailing-language
notice, which is the whole basis on which machine translations of a binding
agreement are defensible.
"""

import pytest
from fastapi.testclient import TestClient

from app.constants.guidelines import GUIDELINES_VERSION, get_guidelines
from app.constants.privacy import PRIVACY_VERSION, get_privacy
from app.constants.tos import TOS_VERSION, get_tos
from app.i18n import SUPPORTED, TRANSLATIONS

ACCESSORS = {"tos": get_tos, "privacy": get_privacy, "guidelines": get_guidelines}
NON_ENGLISH = [c for c in SUPPORTED if c != "en"]


class TestDocumentBodies:
    @pytest.mark.parametrize("lang", SUPPORTED)
    @pytest.mark.parametrize("name", sorted(ACCESSORS))
    def test_every_document_exists_in_every_language(self, lang, name):
        body = ACCESSORS[name](lang)
        # 1000 chars, not >0: a stub that fell back to a heading would pass a
        # truthiness check while shipping no actual terms.
        assert len(body) > 1000

    @pytest.mark.parametrize("name", sorted(ACCESSORS))
    def test_unknown_language_falls_back_to_english(self, name):
        assert ACCESSORS[name]("xx") == ACCESSORS[name]("en")

    @pytest.mark.parametrize("lang", NON_ENGLISH)
    @pytest.mark.parametrize("name", sorted(ACCESSORS))
    def test_translations_differ_from_english(self, lang, name):
        assert ACCESSORS[name](lang) != ACCESSORS[name]("en")

    @pytest.mark.parametrize("lang", SUPPORTED)
    def test_tos_states_the_zero_tolerance_policy(self, lang):
        # The App Store 1.2 / Play UGC requirement, in every language it ships.
        assert "Ntripi" in get_tos(lang)
        assert len(get_tos(lang).splitlines()) > 20

    def test_tos_keeps_the_ratings_retention_clause(self):
        # privacy.py and migration e493ea56a71b both cite the ToS as the
        # consent basis for keeping anonymised ratings. Dropping it would cut
        # a stated legal basis out from under two files that name it.
        body = get_tos("en")
        assert "anonymized form (score only, no identifying information)" in body


class TestPrevailingLanguageNotice:
    @pytest.mark.parametrize(
        "key",
        ["legal_notice_terms", "legal_notice_privacy", "legal_notice_guidelines"],
    )
    def test_english_carries_no_notice(self, key):
        # English is the authoritative text — nothing for it to prevail over.
        assert TRANSLATIONS[key]["en"] == ""

    @pytest.mark.parametrize("lang", NON_ENGLISH)
    @pytest.mark.parametrize(
        "key",
        ["legal_notice_terms", "legal_notice_privacy", "legal_notice_guidelines"],
    )
    def test_every_translation_carries_a_notice(self, lang, key):
        assert len(TRANSLATIONS[key][lang]) > 40


class TestLegalPages:
    @pytest.mark.parametrize("path", ["/terms", "/privacy", "/guidelines"])
    @pytest.mark.parametrize("lang", SUPPORTED)
    def test_page_renders_in_every_language(self, client: TestClient, path, lang):
        resp = client.get(f"{path}?lang={lang}")
        assert resp.status_code == 200
        assert f'<html lang="{lang}"' in resp.text

    @pytest.mark.parametrize("path", ["/terms", "/privacy", "/guidelines"])
    def test_arabic_renders_right_to_left(self, client: TestClient, path):
        # The body used to be pinned to dir="ltr" while it was English-only.
        resp = client.get(f"{path}?lang=ar")
        assert 'dir="rtl"' in resp.text
        assert 'class="legal-doc" dir="ltr"' not in resp.text

    @pytest.mark.parametrize("path", ["/terms", "/privacy", "/guidelines"])
    def test_translated_pages_show_the_prevailing_language_notice(
        self, client: TestClient, path
    ):
        assert "prévaut" in client.get(f"{path}?lang=fr").text
        # English shows no banner at all. Match the element, not the class name
        # — _base.html defines .error-banner in its stylesheet on every page.
        assert '<div class="error-banner"' not in client.get(f"{path}?lang=en").text

    def test_pages_show_their_document_version(self, client: TestClient):
        assert TOS_VERSION in client.get("/terms").text
        assert PRIVACY_VERSION in client.get("/privacy").text
        assert GUIDELINES_VERSION in client.get("/guidelines").text

    def test_headings_are_translated(self, client: TestClient):
        assert "Datenschutzerklärung" in client.get("/privacy?lang=de").text
        assert "使用条款" in client.get("/terms?lang=zh").text
        assert "Normas de la comunidad" in client.get("/guidelines?lang=es").text


class TestTosEndpointLocalisation:
    def test_carries_all_three_documents(self, client: TestClient):
        body = client.get("/auth/tos").json()
        for key in ("summary", "guidelines", "privacy"):
            assert len(body[key]) > 1000

    def test_language_follows_the_query_parameter(self, client: TestClient):
        body = client.get("/auth/tos?lang=fr").json()
        assert body["lang"] == "fr"
        assert body["summary"] == get_tos("fr")
        assert body["privacy"] == get_privacy("fr")
        assert "prévaut" in body["notice_terms"]

    def test_unknown_language_serves_english_without_a_notice(
        self, client: TestClient
    ):
        body = client.get("/auth/tos?lang=xx").json()
        assert body["lang"] == "en"
        assert body["summary"] == get_tos("en")
        assert body["notice_terms"] == ""
