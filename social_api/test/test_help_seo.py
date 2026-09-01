"""test_help_seo.py — the crawler-facing surface: sitemap, robots, canonical,
hreflang, JSON-LD and the llms.txt pair.

The through-line is that constants/help/en.py is the route table. Every
assertion here compares one derived surface against it, so a new article cannot
appear on the site while staying invisible to the sitemap, and a removed one
cannot linger in llms.txt.
"""

import json
import re
import xml.etree.ElementTree as ET

import pytest
from fastapi.testclient import TestClient

from app.constants.help import en
from app.i18n import SUPPORTED

ALL_ARTICLES = en.ARTICLES
SLUGS = [a.slug for a in ALL_ARTICLES]

SITEMAP_NS = {"sm": "http://www.sitemaps.org/schemas/sitemap/0.9",
              "xhtml": "http://www.w3.org/1999/xhtml"}

LD_RE = re.compile(
    r'<script type="application/ld\+json">(.*?)</script>', re.DOTALL
)
CANONICAL_RE = re.compile(r'<link rel="canonical" href="([^"]+)"')
ALTERNATE_RE = re.compile(r'<link rel="alternate" hreflang="([^"]+)" href="([^"]+)"')


def _paths(urls):
    return {u.split("/", 3)[-1] if u.count("/") > 2 else "" for u in urls}


class TestSitemap:
    def test_is_xml_not_html(self, client: TestClient):
        resp = client.get("/sitemap.xml")
        assert resp.status_code == 200
        # TemplateResponse defaults to text/html, and a sitemap served as HTML
        # is silently ignored by every crawler.
        assert "xml" in resp.headers["content-type"]

    def test_lists_exactly_the_public_pages(self, client: TestClient):
        root = ET.fromstring(client.get("/sitemap.xml").text)
        locs = [el.text for el in root.findall(".//sm:loc", SITEMAP_NS)]
        paths = {"/" + loc.split("/", 3)[3] if loc.count("/") > 2 else "/" for loc in locs}
        expected = {"/", "/help", "/privacy", "/terms", "/guidelines"} | {
            f"/help/{s}" for s in SLUGS
        }
        assert paths == expected

    def test_excludes_private_and_unbounded_routes(self, client: TestClient):
        text = client.get("/sitemap.xml").text
        for path in ("/admin", "/appeal", "/reset-password", "/verify-email",
                     "/help/search", "/share/"):
            assert path not in text, path

    @pytest.mark.parametrize("slug", SLUGS)
    def test_every_listed_url_resolves(self, client: TestClient, slug):
        assert client.get(f"/help/{slug}").status_code == 200

    def test_each_entry_carries_alternates_including_x_default(self, client: TestClient):
        root = ET.fromstring(client.get("/sitemap.xml").text)
        for url in root.findall("sm:url", SITEMAP_NS):
            codes = [a.get("hreflang") for a in url.findall("xhtml:link", SITEMAP_NS)]
            assert "x-default" in codes
            # Each variant must list every variant including itself, or Google
            # treats the cluster as inconsistent and drops the annotations.
            assert "en" in codes


class TestRobots:
    def test_still_disallows_admin(self, client: TestClient):
        assert "Disallow: /admin/" in client.get("/robots.txt").text

    def test_names_the_sitemap(self, client: TestClient):
        assert "Sitemap:" in client.get("/robots.txt").text
        assert "/sitemap.xml" in client.get("/robots.txt").text

    def test_declares_no_named_crawler_groups(self, client: TestClient):
        """A named user-agent group *replaces* the `*` group for that crawler
        rather than adding to it, so an "Allow: /" block written to welcome an
        AI crawler would also hand it /admin."""
        text = client.get("/robots.txt").text
        assert text.count("User-agent:") == 1


class TestCanonicalAndHreflang:
    @pytest.mark.parametrize("slug", SLUGS[:3])
    def test_exactly_one_canonical(self, client: TestClient, slug):
        assert len(CANONICAL_RE.findall(client.get(f"/help/{slug}").text)) == 1

    def test_english_canonical_is_the_bare_path(self, client: TestClient):
        (href,) = CANONICAL_RE.findall(client.get("/help/getting-started").text)
        assert href.endswith("/help/getting-started")
        assert "?lang=" not in href

    def test_non_english_canonical_carries_the_lang(self, client: TestClient):
        (href,) = CANONICAL_RE.findall(client.get("/help/getting-started?lang=fr").text)
        assert href.endswith("/help/getting-started?lang=fr")

    def test_help_advertises_only_translated_languages(self, client: TestClient):
        """Articles are English-only today, so claiming six alternates that all
        serve the same English prose would be a duplicate-content signal. The
        set grows on its own as constants/help/<lang>.py modules land."""
        codes = [c for c, _ in ALTERNATE_RE.findall(client.get("/help/contact").text)]
        assert set(codes) == {"en", "x-default"}

    def test_legal_pages_advertise_all_six(self, client: TestClient):
        # The legal bodies *are* translated into all six, so these genuinely differ.
        codes = [c for c, _ in ALTERNATE_RE.findall(client.get("/terms").text)]
        assert set(codes) == set(SUPPORTED) | {"x-default"}

    def test_legal_pages_have_a_meta_description(self, client: TestClient):
        for path in ("/terms", "/privacy", "/guidelines"):
            text = client.get(path).text
            assert '<meta name="description"' in text
            assert 'content=""' not in text


class TestStructuredData:
    @pytest.mark.parametrize("slug", SLUGS)
    def test_jsonld_parses_and_matches_the_declared_schema(self, client: TestClient, slug):
        art = next(a for a in ALL_ARTICLES if a.slug == slug)
        blobs = LD_RE.findall(client.get(f"/help/{slug}").text)
        assert blobs, slug
        payload = json.loads(blobs[0])
        types = [entry["@type"] for entry in payload]
        expected = {
            "howto": "HowTo", "faq": "FAQPage", "contact": "ContactPage",
            "releases": "WebPage", "article": "TechArticle",
        }[art.schema]
        assert expected in types
        # Breadcrumbs ride along on every article — they show in the result row.
        assert "BreadcrumbList" in types

    def test_faq_article_emits_real_questions(self, client: TestClient):
        payload = json.loads(LD_RE.findall(client.get("/help/troubleshooting").text)[0])
        faq = next(e for e in payload if e["@type"] == "FAQPage")
        assert len(faq["mainEntity"]) >= 3
        for question in faq["mainEntity"]:
            assert question["acceptedAnswer"]["text"].strip()

    def test_howto_article_emits_ordered_steps(self, client: TestClient):
        payload = json.loads(LD_RE.findall(client.get("/help/plan-a-trip-itinerary").text)[0])
        howto = next(e for e in payload if e["@type"] == "HowTo")
        assert len(howto["step"]) >= 2
        assert [s["position"] for s in howto["step"]] == list(range(1, len(howto["step"]) + 1))
        for step in howto["step"]:
            assert "#" in step["url"]  # deep-links to the block it describes

    def test_hub_declares_the_app_and_its_search_endpoint(self, client: TestClient):
        payload = json.loads(LD_RE.findall(client.get("/help").text)[0])
        types = [e["@type"] for e in payload]
        assert "SoftwareApplication" in types
        # The single most useful tag for an assistant: it says the site has a
        # search endpoint and how to call it.
        website = next(e for e in payload if e["@type"] == "WebSite")
        target = website["potentialAction"]["target"]["urlTemplate"]
        assert target.endswith("/help/search?q={search_term_string}")

    def test_no_fabricated_ratings(self, client: TestClient):
        # An invented aggregateRating is a structured-data policy violation, not
        # a shortcut. There are no real ratings for the app itself yet.
        assert "aggregateRating" not in client.get("/help").text

    @pytest.mark.parametrize("slug", SLUGS)
    def test_serialized_jsonld_contains_no_raw_angle_bracket(self, client: TestClient, slug):
        """A "</script>" inside a translated answer would close the element and
        inject the rest of the JSON into the document as markup."""
        for blob in LD_RE.findall(client.get(f"/help/{slug}").text):
            assert "<" not in blob


class TestLlmsSurfaces:
    def test_llms_txt_lists_every_article_as_markdown(self, client: TestClient):
        text = client.get("/llms.txt").text
        for art in ALL_ARTICLES:
            assert f"/help/{art.slug}.md" in text, art.slug
            assert art.title in text

    def test_llms_txt_links_all_resolve(self, client: TestClient):
        text = client.get("/llms.txt").text
        for path in re.findall(r"\((?:https?://[^/]+)?(/[^)\s]*)\)", text):
            if path.endswith(".txt"):
                continue  # llms-full.txt is checked below
            assert client.get(path).status_code == 200, path

    def test_llms_txt_names_the_policies(self, client: TestClient):
        text = client.get("/llms.txt").text
        for path in ("/terms", "/privacy", "/guidelines"):
            assert path in text

    def test_llms_full_contains_every_article_body(self, client: TestClient):
        text = client.get("/llms-full.txt").text
        for art in ALL_ARTICLES:
            assert art.title in text, art.slug
            for block in art.blocks:
                assert block.heading in text, f"{art.slug}/{block.anchor}"

    def test_llms_full_is_markdown_not_html(self, client: TestClient):
        text = client.get("/llms-full.txt").text
        assert text.startswith("# Ntripi Help")
        assert "<p>" not in text

    def test_llms_full_language_comes_from_the_query(self, client: TestClient):
        assert client.get("/llms-full.txt?lang=xx").status_code == 200


class TestStandaloneTemplates:
    """home.html and the share pages do not extend _base.html, so they inherit
    none of its head block — every SEO tag has to be repeated in each, and a
    test is the only thing that notices when one of them is forgotten."""

    def test_homepage_has_canonical_and_alternates(self, client: TestClient):
        text = client.get("/").text
        assert len(CANONICAL_RE.findall(text)) == 1
        codes = [c for c, _ in ALTERNATE_RE.findall(text)]
        assert set(codes) == set(SUPPORTED) | {"x-default"}

    def test_homepage_og_url_agrees_with_the_canonical(self, client: TestClient):
        text = client.get("/").text
        (canonical,) = CANONICAL_RE.findall(text)
        assert f'content="{canonical}"' in text

    def test_homepage_links_to_help(self, client: TestClient):
        assert 'href="/help"' in client.get("/").text

    def test_homepage_footer_offers_all_three_documents(self, client: TestClient):
        # /guidelines was missing here while _base.html's footer carried it.
        text = client.get("/").text
        for path in ("/privacy", "/terms", "/guidelines"):
            assert f'href="{path}"' in text
