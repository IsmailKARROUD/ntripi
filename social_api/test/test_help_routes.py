"""test_help_routes.py — the help centre's HTTP surface.

Route-ordering and caching get their own tests because both fail silently: a
reordered decorator turns /help/search into a 404 page that still renders, and a
`public` Cache-Control turns the language switcher into a coin flip for everyone
behind the CDN.
"""

import json

import pytest
from fastapi.testclient import TestClient

from app.constants.help import articles, en
from app.i18n import SUPPORTED

ALL_ARTICLES = en.ARTICLES
SLUGS = [a.slug for a in ALL_ARTICLES]


class TestHub:
    def test_hub_renders(self, client: TestClient):
        resp = client.get("/help")
        assert resp.status_code == 200
        assert "Help Centre" in resp.text

    def test_hub_lists_every_category_in_use(self, client: TestClient):
        text = client.get("/help").text
        used = {a.category for a in ALL_ARTICLES}
        for category in en.CATEGORIES:
            if category.id in used:
                assert category.title in text, category.id

    def test_hub_carries_the_search_form(self, client: TestClient):
        text = client.get("/help").text
        # A real GET form, so search works with JavaScript off and a crawler can
        # follow it. The dropdown is layered on top of this, never instead of it.
        assert 'action="/help/search"' in text
        assert 'name="q"' in text


class TestArticles:
    @pytest.mark.parametrize("slug", SLUGS)
    @pytest.mark.parametrize("lang", SUPPORTED)
    def test_article_renders_in_every_language(self, client: TestClient, slug, lang):
        # Catches a translated module that dropped a field: the fallback keeps
        # the slug resolvable, and this proves the page still builds.
        resp = client.get(f"/help/{slug}?lang={lang}")
        assert resp.status_code == 200

    @pytest.mark.parametrize("slug", SLUGS)
    def test_article_shows_its_title_and_headings(self, client: TestClient, slug):
        art = next(a for a in ALL_ARTICLES if a.slug == slug)
        text = client.get(f"/help/{slug}").text
        assert art.title in text
        for block in art.blocks:
            assert f'id="{block.anchor}"' in text

    def test_unknown_slug_renders_the_help_404(self, client: TestClient):
        resp = client.get("/help/no-such-page")
        assert resp.status_code == 404
        # A help-shaped 404 with a search box, not a bare JSON error: the most
        # likely visitor is following a stale link and still needs the answer.
        assert 'action="/help/search"' in resp.text
        assert "noindex" in resp.text

    def test_arabic_flips_direction(self, client: TestClient):
        resp = client.get("/help/getting-started?lang=ar")
        assert resp.status_code == 200
        assert 'dir="rtl"' in resp.text
        assert "مركز المساعدة" in resp.text


class TestMarkdownSurface:
    @pytest.mark.parametrize("slug", SLUGS)
    def test_markdown_twin(self, client: TestClient, slug):
        art = next(a for a in ALL_ARTICLES if a.slug == slug)
        resp = client.get(f"/help/{slug}.md")
        assert resp.status_code == 200
        # text/plain, not text/markdown: browsers download the latter, and this
        # link is meant to render for a human as readily as for a crawler.
        assert resp.headers["content-type"].startswith("text/plain")
        assert art.title in resp.text
        assert "<" not in resp.text, "markdown surface must carry no HTML"

    def test_markdown_unknown_slug_is_404(self, client: TestClient):
        assert client.get("/help/no-such-page.md").status_code == 404


class TestRouteOrdering:
    """`/help/{slug}` matches any single segment, so the literals must stay
    above it. Both failures below are silent — the page still renders, just the
    wrong one."""

    def test_search_is_not_swallowed_by_the_article_route(self, client: TestClient):
        resp = client.get("/help/search?q=track")
        assert resp.status_code == 200
        assert "noindex" in resp.text  # the search page, not an article

    def test_search_index_is_not_swallowed(self, client: TestClient):
        resp = client.get("/help/search-index.json")
        assert resp.status_code == 200
        assert resp.headers["content-type"].startswith("application/json")

    def test_md_suffix_is_not_swallowed_into_the_slug(self, client: TestClient):
        resp = client.get("/help/getting-started.md")
        assert resp.headers["content-type"].startswith("text/plain")


class TestSearch:
    def test_ranks_a_title_match_above_a_body_match(self, client: TestClient):
        resp = client.get("/help/search?q=itinerary")
        assert resp.status_code == 200
        body = resp.text
        first = body.index("/help/plan-a-trip-itinerary")
        # troubleshooting mentions itineraries only in passing.
        assert first < body.index("/help/troubleshooting")

    def test_short_query_requires_every_token(self, client: TestClient):
        # Two tokens is somebody naming a thing; one miss means no match.
        resp = client.get("/help/search?q=track+zzzzqqqq")
        assert "Nothing matched" in resp.text

    def test_prose_query_tolerates_words_no_article_contains(self, client: TestClient):
        # "who" and "my" appear nowhere; the question must still find its answer.
        resp = client.get("/help/search?q=who+can+see+my+trip")
        assert "/help/share-an-itinerary-privately" in resp.text

    def test_empty_query_prompts_instead_of_erroring(self, client: TestClient):
        resp = client.get("/help/search")
        assert resp.status_code == 200
        assert "Type a few words" in resp.text

    def test_overlong_query_is_truncated_not_rejected(self, client: TestClient):
        # A 422 on a crawler's runaway query is a worse answer than no results.
        assert client.get("/help/search?q=" + "a" * 5000).status_code == 200

    def test_search_page_is_noindex(self, client: TestClient):
        assert "noindex" in client.get("/help/search?q=track").text

    def test_arabic_definite_article_still_finds_the_bare_noun(self, client: TestClient):
        """المسار is how the word is actually typed; مسار is how the titles carry it.

        _score_token asks whether the token is *in* the field, so without the
        article being stripped on both sides the containment runs the wrong way
        and every Arabic query beginning with ال scores zero.
        """
        resp = client.get("/help/search?q=%D8%A7%D9%84%D8%A3%D8%B0%D9%88%D9%86%D8%A7%D8%AA&lang=ar")
        assert resp.status_code == 200
        assert "/help/permissions" in resp.text

    def test_arabic_orthographic_variants_are_folded(self, client: TestClient):
        # Written with a bare alef rather than the hamza the article uses.
        resp = client.get("/help/search?q=%D8%A7%D8%B0%D9%88%D9%86%D8%A7%D8%AA&lang=ar")
        assert "/help/permissions" in resp.text

    def test_chinese_keyword_finds_its_article(self, client: TestClient):
        # 权限 = permissions. Short terms are what the zh keyword lists carry.
        resp = client.get("/help/search?q=%E6%9D%83%E9%99%90&lang=zh")
        assert resp.status_code == 200
        assert "/help/permissions" in resp.text

    def test_chinese_sentence_is_not_one_unmatchable_token(self, client: TestClient):
        """怎么和朋友一起规划行程 — "how do I plan a trip with friends".

        CJK has no spaces, so this folds to a single token that appears verbatim
        in no document. Without the bigram fallback the most natural way to ask a
        question in Chinese returns nothing at all, and search would only work
        for people who already knew our vocabulary.
        """
        q = "%E6%80%8E%E4%B9%88%E5%92%8C%E6%9C%8B%E5%8F%8B%E4%B8%80%E8%B5%B7%E8%A7%84%E5%88%92%E8%A1%8C%E7%A8%8B"
        resp = client.get(f"/help/search?q={q}&lang=zh")
        assert resp.status_code == 200
        assert "/help/plan-a-trip-with-friends" in resp.text

    def test_a_partial_bigram_overlap_is_not_a_match(self, client: TestClient):
        """行星探测器 ("planetary probe") shares the character 行 with 行程 but no
        whole bigram with anything we publish.

        The fallback must stay a majority-of-bigrams rule: relaxed to "any gram
        hits" it would match a large share of the corpus on one shared character,
        which is worse than the empty result it was added to fix.
        """
        q = "%E8%A1%8C%E6%98%9F%E6%8E%A2%E6%B5%8B%E5%99%A8"
        resp = client.get(f"/help/search?q={q}&lang=zh")
        assert resp.status_code == 200
        assert "没有匹配" in resp.text


class TestSearchIndex:
    def test_one_entry_per_article_with_every_field(self, client: TestClient):
        payload = client.get("/help/search-index.json").json()
        assert payload["lang"] == "en"
        assert len(payload["docs"]) == len(ALL_ARTICLES)
        for doc in payload["docs"]:
            assert set(doc) == {"s", "n", "x", "t", "c", "d", "k", "b"}

    def test_display_fields_are_not_folded(self, client: TestClient):
        docs = client.get("/help/search-index.json").json()["docs"]
        by_slug = {d["s"]: d for d in docs}
        art = next(a for a in ALL_ARTICLES if a.slug == "getting-started")
        # `n` is what the dropdown renders; folding is lossy and would show
        # "how to start planning a trip in ntripi".
        assert by_slug["getting-started"]["n"] == art.title

    def test_language_comes_from_the_query_not_the_cookie(self, client: TestClient):
        """Pins the rule that makes public caching of this endpoint safe.

        Cloudflare honours Vary only on Accept-Encoding, so anything whose
        language is decided by a cookie must never be public-cached. This
        endpoint reads `?lang=` alone, which is why it may be.
        """
        client.cookies.set("ntripi_lang", "fr")
        try:
            payload = client.get("/help/search-index.json?lang=en").json()
            assert payload["lang"] == "en"
        finally:
            client.cookies.clear()

    def test_unknown_language_falls_back_rather_than_erroring(self, client: TestClient):
        assert client.get("/help/search-index.json?lang=xx").json()["lang"] == "en"


class TestCaching:
    @pytest.mark.parametrize("slug", SLUGS[:3])
    def test_html_is_never_public_cached(self, client: TestClient, slug):
        # The language of an HTML page can come from a cookie or Accept-Language,
        # and a CDN that ignores Vary would then serve one visitor's language to
        # everyone. Pinned so nobody "optimizes" a public max-age onto it later.
        assert "public" not in client.get(f"/help/{slug}").headers.get("cache-control", "")

    def test_machine_surfaces_may_be_public_cached(self, client: TestClient):
        # Safe precisely because `?lang=` is the whole cache key.
        assert "public" in client.get("/help/search-index.json").headers["cache-control"]
        assert "public" in client.get("/help/getting-started.md").headers["cache-control"]
