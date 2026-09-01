"""test_help_content.py — invariants of the help corpus itself.

These are data assertions, not route assertions: they hold for content that has
not been wired to a URL yet, and they fail on a bad *article* rather than on the
page that happens to render it. The route-level suite is test_help_routes.py.

Nothing here touches the database. The `client` fixture appears only where a
link has to be resolved against the live route table.
"""

import re

import pytest
from fastapi.testclient import TestClient

from app.constants.help import article, articles, by_category, categories, en
from app.constants.help.models import KIND_FAQ, KIND_STEP
from app.i18n import SUPPORTED
from app.services import help_render

ALL_ARTICLES = en.ARTICLES
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")

# Markdown links to somewhere on this site.
INTERNAL_LINK_RE = re.compile(r"\]\((/[^)\s]*)\)")
MAILTO_RE = re.compile(r"\]\(mailto:([^)\s]+)\)")
EXTERNAL_LINK_RE = re.compile(r"\]\((https?://[^)\s]+)\)")

# The four published mailboxes. An invented address (help@, hello@) has no MX
# entry behind it and bounces silently forever, which is worse than no link.
REAL_MAILBOXES = {
    "support@ntripi.app",
    "abuse@ntripi.app",
    "privacy@ntripi.app",
    "contact@ntripi.app",
}

# Hosts an article may link out to. Never fetched — the assertion is on the
# host, so the suite stays offline.
ALLOWED_HOSTS = {"ntripi.app", "apps.apple.com", "play.google.com"}


def _all_markdown(art):
    return [art.intro, *(b.body for b in art.blocks)]


class TestSlugsAndShape:
    def test_slugs_are_unique(self):
        slugs = [a.slug for a in ALL_ARTICLES]
        assert len(slugs) == len(set(slugs))

    @pytest.mark.parametrize("art", ALL_ARTICLES, ids=lambda a: a.slug)
    def test_slug_is_url_safe(self, art):
        assert SLUG_RE.match(art.slug), art.slug

    @pytest.mark.parametrize("art", ALL_ARTICLES, ids=lambda a: a.slug)
    def test_summary_fits_a_meta_description(self, art):
        # Google truncates around 160 characters; a summary is also the hub card
        # and the llms.txt line, so it has to work standing alone.
        assert 0 < len(art.summary) <= 160, len(art.summary)

    @pytest.mark.parametrize("art", ALL_ARTICLES, ids=lambda a: a.slug)
    def test_category_exists(self, art):
        assert art.category in {c.id for c in categories("en")}

    @pytest.mark.parametrize("art", ALL_ARTICLES, ids=lambda a: a.slug)
    def test_related_slugs_resolve(self, art):
        for slug in art.related:
            assert article("en", slug) is not None, f"{art.slug} -> {slug}"

    def test_every_category_with_articles_is_grouped(self):
        grouped_ids = {c.id for c, _ in by_category("en")}
        used = {a.category for a in ALL_ARTICLES}
        assert grouped_ids == used


class TestBlockContract:
    """The machine contract: headings are a field, so JSON-LD cannot be emptied
    by editing prose."""

    @pytest.mark.parametrize("art", ALL_ARTICLES, ids=lambda a: a.slug)
    def test_no_headings_inside_a_block_body(self, art):
        # A `##` in a body is invisible to the anchor, the table of contents and
        # the structured data, all of which key off Block.heading. The page would
        # still look right, which is exactly why this needs a test.
        for block in art.blocks:
            for line in block.body.splitlines():
                assert not line.lstrip().startswith("#"), f"{art.slug}/{block.anchor}: {line!r}"

    @pytest.mark.parametrize("art", ALL_ARTICLES, ids=lambda a: a.slug)
    def test_block_anchors_are_unique_and_url_safe(self, art):
        anchors = [b.anchor for b in art.blocks]
        assert len(anchors) == len(set(anchors)), art.slug
        for anchor in anchors:
            assert SLUG_RE.match(anchor), f"{art.slug}: {anchor}"

    @pytest.mark.parametrize(
        "art", [a for a in ALL_ARTICLES if a.schema == "faq"], ids=lambda a: a.slug
    )
    def test_faq_articles_have_questions(self, art):
        assert [b for b in art.blocks if b.kind == KIND_FAQ], art.slug

    @pytest.mark.parametrize(
        "art", [a for a in ALL_ARTICLES if a.schema == "howto"], ids=lambda a: a.slug
    )
    def test_howto_articles_have_at_least_two_steps(self, art):
        # A one-step HowTo is not a procedure, and Google rejects it.
        assert len([b for b in art.blocks if b.kind == KIND_STEP]) >= 2, art.slug


class TestTranslationFallback:
    @pytest.mark.parametrize("lang", [*SUPPORTED, "xx"])
    def test_every_language_serves_every_slug(self, lang):
        # The per-slug fallback exists so a half-finished translation cannot
        # leave a hole. This is also what makes hreflang and the sitemap honest:
        # every alternate they advertise resolves.
        assert [a.slug for a in articles(lang)] == [a.slug for a in articles("en")]

    def test_unknown_language_is_english(self):
        assert articles("xx") == articles("en")
        assert categories("xx") == categories("en")


class TestLinks:
    def test_internal_links_resolve(self, client: TestClient):
        """Every ](/…) in every body reaches a live route.

        Introspecting the running app rather than a hardcoded list, the same
        trick test_edit_guard_coverage.py uses: a route someone renames later
        breaks this test instead of quietly shipping a 404 in the docs.
        """
        broken = []
        for lang in SUPPORTED:
            for art in articles(lang):
                for text in _all_markdown(art):
                    for path in INTERNAL_LINK_RE.findall(text):
                        # /app/ is the Flutter build, absent in tests.
                        if path.startswith("/app"):
                            continue
                        if client.get(path).status_code >= 400:
                            broken.append(f"{lang}:{art.slug} -> {path}")
        assert not broken, broken

    def test_mailto_links_are_real_mailboxes(self):
        for art in ALL_ARTICLES:
            for text in _all_markdown(art):
                for address in MAILTO_RE.findall(text):
                    assert address in REAL_MAILBOXES, f"{art.slug}: {address}"

    def test_external_links_are_allowlisted(self):
        for art in ALL_ARTICLES:
            for text in _all_markdown(art):
                for url in EXTERNAL_LINK_RE.findall(text):
                    host = url.split("/")[2]
                    assert host in ALLOWED_HOSTS, f"{art.slug}: {host}"


class TestRendererSafety:
    def test_raw_html_is_escaped(self):
        """Pins MarkdownIt(html=False).

        The content is ours, so this is not defence against a hostile author —
        it is defence against the setting being flipped for a one-off embed and
        turning every article into an injection point.
        """
        out = str(help_render.render_markdown("<img src=x onerror=alert(1)>"))
        assert "<img" not in out
        assert "&lt;img" in out

    def test_script_tags_are_escaped(self):
        out = str(help_render.render_markdown("<script>alert(1)</script>"))
        assert "<script" not in out

    def test_plaintext_keeps_link_labels_and_drops_urls(self):
        text = help_render.plaintext("See the [community guidelines](/guidelines).")
        assert "community guidelines" in text
        assert "/guidelines" not in text
