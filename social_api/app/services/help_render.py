"""
services/help_render.py — the only module that knows Markdown exists.

Turns an Article into the four things that are derived from it: HTML for the
page, plain text for the search index and structured data, Markdown for the
`.md` and llms.txt surfaces, and JSON-LD for search engines.

Everything here is a pure function of module constants, so every result is
cached for the life of the process and nothing ever needs invalidating.
"""

from __future__ import annotations

import json
from functools import lru_cache

from markdown_it import MarkdownIt
from markupsafe import Markup

from app.constants.help.models import (
    KIND_FAQ,
    KIND_STEP,
    SCHEMA_CONTACT,
    SCHEMA_FAQ,
    SCHEMA_HOWTO,
    SCHEMA_RELEASES,
    Article,
    Category,
)

# html=False escapes raw HTML instead of passing it through. The content is
# ours, but a renderer able to emit arbitrary HTML is one careless paste away
# from being an XSS sink, and the site's CSP is frame-ancestors only — it would
# not catch an injected inline script. Pinned by test_help_content.
_MD = (
    MarkdownIt("commonmark", {"html": False, "linkify": False, "typographer": True})
    .enable("table")
)


@lru_cache(maxsize=4096)
def render_markdown(source: str) -> Markup:
    """CommonMark -> safe HTML.

    Returns Markup so Jinja's autoescape leaves it alone without a `| safe` at
    every call site — `| safe` on a variable is the habit that eventually gets
    applied to one that is not safe.
    """
    return Markup(_MD.render(source))


@lru_cache(maxsize=4096)
def plaintext(source: str) -> str:
    """Markdown -> bare text, for the search index, meta descriptions and the
    `text` fields of FAQPage / HowTo, which must not carry markup.

    Walks the token stream rather than stripping tags off the rendered HTML:
    a link's *label* has to survive while its URL must not, and a regex over
    HTML cannot tell those apart.
    """
    parts: list[str] = []
    for token in _MD.parse(source):
        if token.type == "inline":
            for child in token.children or ():
                if child.type in ("text", "code_inline"):
                    parts.append(child.content)
                elif child.type == "softbreak":
                    parts.append(" ")
        elif token.type == "fence":
            parts.append(token.content)
        elif token.type.endswith("_close") and token.block:
            parts.append("\n")
    return " ".join(" ".join(parts).split())


# ---------------------------------------------------------------------------
# Markdown serialization — the payload for /help/{slug}.md and /llms-full.txt
# ---------------------------------------------------------------------------

def article_markdown(article: Article, source_url: str, *, heading_level: int = 1) -> str:
    """Render an Article back to Markdown.

    `heading_level` lets llms-full.txt demote every article one level so the
    whole corpus sits under a single `# Ntripi Help` root.
    """
    h = "#" * heading_level
    out = [f"{h} {article.title}", "", f"> {article.summary}", ""]
    if article.intro:
        out += [article.intro, ""]
    for block in article.blocks:
        out += [f"{h}# {block.heading}", "", block.body, ""]
    for release in article.releases:
        out += [f"{h}# {release.version} — {release.date}", "", release.headline, ""]
        out += [f"- {entry}" for entry in release.entries]
        out.append("")
    out += ["---", f"Source: {source_url}"]
    return "\n".join(out).strip() + "\n"


# ---------------------------------------------------------------------------
# JSON-LD
# ---------------------------------------------------------------------------

def _steps(article: Article, canonical: str) -> list[dict]:
    return [
        {
            "@type": "HowToStep",
            "position": i,
            "name": b.heading,
            "text": plaintext(b.body),
            "url": f"{canonical}#{b.anchor}",
        }
        for i, b in enumerate((b for b in article.blocks if b.kind == KIND_STEP), start=1)
    ]


def _questions(article: Article) -> list[dict]:
    return [
        {
            "@type": "Question",
            "name": b.heading,
            "acceptedAnswer": {"@type": "Answer", "text": plaintext(b.body)},
        }
        for b in article.blocks
        if b.kind == KIND_FAQ
    ]


def _breadcrumbs(article: Article, category: Category | None, base: str, help_url: str) -> dict:
    crumbs = [("Ntripi", base), ("Help", help_url)]
    if category is not None:
        crumbs.append((category.title, f"{help_url}#{category.id}"))
    crumbs.append((article.title, f"{help_url}/{article.slug}"))
    return {
        "@context": "https://schema.org",
        "@type": "BreadcrumbList",
        "itemListElement": [
            {"@type": "ListItem", "position": i, "name": name, "item": url}
            for i, (name, url) in enumerate(crumbs, start=1)
        ],
    }


def jsonld_for(
    article: Article,
    category: Category | None,
    *,
    lang: str,
    canonical: str,
    base: str,
    help_url: str,
    contact_emails: dict[str, str] | None = None,
) -> list[dict]:
    """Structured data for one article: its own type, plus a BreadcrumbList.

    The @type is chosen from `article.schema` rather than sniffed out of the
    rendered HTML — a translator writing `###` instead of `##` must not be able
    to silently empty the structured data.
    """
    common = {
        "@context": "https://schema.org",
        "name": article.title,
        "headline": article.title,
        "description": article.summary,
        "inLanguage": lang,
        "url": canonical,
    }
    if article.updated:
        common["dateModified"] = article.updated

    if article.schema == SCHEMA_HOWTO:
        primary = {**common, "@type": "HowTo", "step": _steps(article, canonical)}
    elif article.schema == SCHEMA_FAQ:
        primary = {**common, "@type": "FAQPage", "mainEntity": _questions(article)}
    elif article.schema == SCHEMA_CONTACT:
        primary = {
            **common,
            "@type": "ContactPage",
            "mainEntity": {
                "@type": "Organization",
                "name": "Ntripi",
                "url": base,
                "contactPoint": [
                    {"@type": "ContactPoint", "contactType": kind, "email": address}
                    for kind, address in (contact_emails or {}).items()
                ],
            },
        }
    elif article.schema == SCHEMA_RELEASES:
        primary = {
            **common,
            "@type": "WebPage",
            "mainEntity": {
                "@type": "ItemList",
                "itemListElement": [
                    {
                        "@type": "ListItem",
                        "position": i,
                        "name": f"{r.version} — {r.headline}",
                        "url": f"{canonical}#{r.anchor}",
                    }
                    for i, r in enumerate(article.releases, start=1)
                ],
            },
        }
    else:
        primary = {
            **common,
            "@type": "TechArticle",
            "articleBody": plaintext(article.intro),
        }

    return [primary, _breadcrumbs(article, category, base, help_url)]


def jsonld_script(payloads: list[dict]) -> Markup:
    """Serialize JSON-LD for embedding in a <script> tag.

    `<` is escaped even though json.dumps does not: a "</script>" inside a
    translated FAQ answer would otherwise close the element and inject the rest
    of the JSON into the document as markup.
    """
    body = json.dumps(payloads, ensure_ascii=False, separators=(",", ":"))
    return Markup(body.replace("<", "\\u003c"))
