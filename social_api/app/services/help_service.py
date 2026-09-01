"""
services/help_service.py — everything derived from the help articles that is not
Markdown rendering or URL composition: search, the search index, llms.txt and
llms-full.txt.

One rule holds the whole module together: `constants/help/en.py` is the route
table. The sitemap (services/seo.py), llms.txt, the search index and the router
all read the same tuple, so they cannot disagree about which pages exist.
"""

from __future__ import annotations

import json
import re
import unicodedata
from functools import lru_cache

from app.config import Settings
from app.constants.help import articles, by_category, categories, releases
from app.constants.help.models import Article
from app.services import help_render
from app.services.seo import absolute, article_path, canonical_path


# ---------------------------------------------------------------------------
# Table of contents
# ---------------------------------------------------------------------------

def toc(article: Article) -> list[tuple[str, str]]:
    """(anchor, heading) pairs. Derived from the blocks, never from the rendered
    HTML — headings are a structural field precisely so this cannot drift."""
    return [(b.anchor, b.heading) for b in article.blocks]


# ---------------------------------------------------------------------------
# Search
# ---------------------------------------------------------------------------

# Anything that is neither a word character nor whitespace. Punctuation becomes
# a space rather than being deleted, so "itinerary, step" yields two words and
# not "itinerarystep".
_PUNCT = re.compile(r"[^\w\s]", re.UNICODE)


def fold(text: str) -> str:
    """Lowercase, strip diacritics, and split punctuation off words.

    Three steps, and the third is not cosmetic: without it the trailing comma in
    "a trip itinerary, step by step" makes the title word "itinerary," which no
    query for "itinerary" can ever match as a whole word, quietly demoting the
    most relevant article to a prefix hit.

    The client-side dropdown performs the same three steps, so the two agree
    about what a word is.
    """
    decomposed = unicodedata.normalize("NFD", text.lower())
    stripped = "".join(c for c in decomposed if not unicodedata.combining(c))
    return " ".join(_PUNCT.sub(" ", stripped).split())


def tokenize(query: str) -> list[str]:
    """Query -> at most six folded tokens of two characters or more."""
    return [t for t in fold(query).split() if len(t) >= 2][:6]


@lru_cache(maxsize=None)
def _documents(lang: str) -> tuple[dict, ...]:
    """The searchable projection of every article, pre-folded once per language.

    Folding here rather than per request is what lets both the server scorer and
    the browser work on already-normalised text.
    """
    cat_titles = {c.id: c.title for c in categories(lang)}
    docs = []
    for a in articles(lang):
        body = " ".join(
            [help_render.plaintext(a.intro)]
            + [b.heading for b in a.blocks]
            + [help_render.plaintext(b.body) for b in a.blocks]
        )
        docs.append({
            # Display pair, shown verbatim in the dropdown...
            "s": a.slug,
            "n": a.title,
            "x": a.summary,
            # ...and the folded pair, matched against. Both are needed: folding
            # is lossy by design (lowercase, punctuation removed), so a dropdown
            # rendering `t` would read "how to plan two options for the same day".
            "t": fold(a.title),
            "c": fold(cat_titles.get(a.category, "")),
            "d": fold(a.summary),
            "k": fold(" ".join(a.keywords)),
            "b": fold(body)[:600],
        })
    return tuple(docs)


def _score_token(doc: dict, token: str) -> int:
    """Highest-scoring field hit for one token. 0 means the token is absent."""
    title_words = doc["t"].split()
    if token in title_words:
        return 10
    if any(w.startswith(token) for w in title_words):
        return 6
    if token in doc["k"]:
        return 5
    if token in doc["d"]:
        return 3
    if token in doc["t"]:
        return 3
    if token in doc["c"]:
        return 2
    if token in doc["b"]:
        return 1
    return 0


def required_matches(token_count: int) -> int:
    """How many of the query's tokens a document must match to be shown.

    Short queries are precise, long ones are prose. One or two tokens is somebody
    naming a thing, so every token must hit or the results are noise. Three or
    more is a sentence — "who can see my trip" carries words no article contains
    — and demanding all of them returns nothing for exactly the natural-language
    questions the search box invites.
    """
    if token_count <= 2:
        return token_count
    return -(-token_count * 3 // 5)  # ceil(n * 0.6)


def search(lang: str, query: str, *, limit: int = 8) -> list[Article]:
    """Rank articles for `query`. The authoritative scorer — the browser's
    dropdown narrows with the same rules, but this is what decides.
    """
    tokens = tokenize(query)
    if not tokens:
        return []
    needed = required_matches(len(tokens))
    index = {a.slug: a for a in articles(lang)}
    order = {a.slug: i for i, a in enumerate(articles(lang))}

    scored: list[tuple[int, int, str]] = []
    for doc in _documents(lang):
        hits = [_score_token(doc, token) for token in tokens]
        matched = sum(1 for h in hits if h)
        if matched < needed:
            continue
        # Coverage is weighted alongside field strength: for a prose query, an
        # article touching four of the words beats one that matches a single
        # word in its title.
        total = sum(hits) + 3 * matched
        scored.append((-total, order[doc["s"]], doc["s"]))

    scored.sort()
    return [index[slug] for _, _, slug in scored[:limit]]


@lru_cache(maxsize=None)
def search_index_json(lang: str) -> str:
    """The browser's copy of the corpus, serialized once per language.

    Cached as the finished JSON string so the hot path is a Response over a
    constant, with no json.dumps per request.
    """
    payload = {"lang": lang, "docs": [dict(d) for d in _documents(lang)]}
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


# ---------------------------------------------------------------------------
# Machine-readable surfaces
# ---------------------------------------------------------------------------

def llms_txt(settings: Settings) -> str:
    """The llmstxt.org index: what this site is, and where the source lives.

    Article links point at the `.md` variants — handing an assistant the source
    rather than the rendered page is the entire reason those exist.
    """
    lines = [
        "# Ntripi",
        "",
        "> Ntripi is a travel app for building trip plans out of real stops — what",
        "> each one costs, how long it takes, and how you travel between them — and",
        "> sharing them with a chosen audience. Trips can hold parallel alternatives,",
        "> so one plan can carry a wet-weather option and a dry one side by side.",
        "",
    ]
    for category, members in by_category("en"):
        lines += [f"## {category.title}", ""]
        for a in members:
            url = absolute(f"{article_path(a.slug)}.md", settings)
            lines.append(f"- [{a.title}]({url}): {a.summary}")
        lines.append("")

    lines += [
        "## Policies",
        "",
        f"- [Terms of Service]({absolute('/terms', settings)}): The agreement between Ntripi and its users.",
        f"- [Privacy Policy]({absolute('/privacy', settings)}): What data Ntripi stores and why.",
        f"- [Community Guidelines]({absolute('/guidelines', settings)}): What may and may not be published.",
        "",
        "## Optional",
        "",
        f"- [Every help article in one file]({absolute('/llms-full.txt', settings)})",
        "",
    ]
    return "\n".join(lines)


def llms_full_txt(lang: str, settings: Settings) -> str:
    """The whole corpus as one Markdown document, every article demoted one
    level so it sits under a single root heading."""
    out = [
        "# Ntripi Help",
        "",
        "> Every help article for Ntripi, a travel app for building and sharing",
        "> trip itineraries. Generated from the same source as the website.",
        "",
    ]
    for a in articles(lang):
        url = absolute(canonical_path(article_path(a.slug), lang), settings)
        out.append(help_render.article_markdown(a, url, heading_level=2))
        out.append("")
    return "\n".join(out)


def contact_emails(settings: Settings) -> dict[str, str]:
    """The published mailboxes, keyed by the schema.org contactType they map to."""
    return {
        "customer support": settings.SUPPORT_CONTACT_EMAIL,
        "abuse": settings.ABUSE_CONTACT_EMAIL,
        "privacy": settings.PRIVACY_CONTACT_EMAIL,
        "general": settings.GENERAL_CONTACT_EMAIL,
    }


def latest_release_date(lang: str) -> str:
    rels = releases(lang)
    return rels[0].date if rels else ""
