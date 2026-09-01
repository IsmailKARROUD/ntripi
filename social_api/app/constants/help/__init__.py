"""
constants/help/ — the help centre content, one module per language.

Mirrors constants/legal/: a reviewer for fr.py reads everything a French visitor
will ever see, in one place.

Content is Python string constants, NOT .md files on disk. This is deliberate
and not an accident to "improve": .dockerignore strips `**/*.md`, so on-disk
Markdown would build an image with an empty help centre and nothing would fail
until production served a blank page.

English is authoritative. articles() substitutes English per *slug*, so a
half-finished translation ships the articles it has beside English for the rest.
"""

from __future__ import annotations

from functools import lru_cache

from app.constants.help import en
from app.constants.help.models import Article, Category, Release

# Translated modules land here as they are written; the accessors need no change.
_MODULES: dict[str, object] = {"en": en}


@lru_cache(maxsize=None)
def articles(lang: str) -> tuple[Article, ...]:
    """Every article in `lang`, English-substituted per slug.

    Three fallbacks, not legal.document()'s two: an unsupported language code, a
    module missing the attribute, and — the one that matters — a language that
    translated some articles but not others, which must ship what it has rather
    than reverting the whole section to English.

    en.ARTICLES is the route table. A slug present only in a translated module
    is dropped: it would 404 for every other visitor and desync the sitemap from
    the router.
    """
    module = _MODULES.get(lang, en)
    localized = {a.slug: a for a in getattr(module, "ARTICLES", ())}
    return tuple(localized.get(a.slug, a) for a in en.ARTICLES)


@lru_cache(maxsize=None)
def categories(lang: str) -> tuple[Category, ...]:
    """Every category in `lang`, English-substituted per id. Same rule as above."""
    module = _MODULES.get(lang, en)
    localized = {c.id: c for c in getattr(module, "CATEGORIES", ())}
    return tuple(localized.get(c.id, c) for c in en.CATEGORIES)


@lru_cache(maxsize=None)
def releases(lang: str) -> tuple[Release, ...]:
    """Release notes in `lang`. Falls back whole, not per entry — a release note
    is a short list and a half-translated one reads worse than an English one."""
    module = _MODULES.get(lang, en)
    return tuple(getattr(module, "RELEASES", ()) or en.RELEASES)


@lru_cache(maxsize=None)
def _index(lang: str) -> dict[str, Article]:
    # Every value here is an immutable tuple of frozen dataclasses, which is the
    # only reason caching these is safe: a returned list would hand every caller
    # the same mutable object.
    return {a.slug: a for a in articles(lang)}


def article(lang: str, slug: str) -> Article | None:
    return _index(lang).get(slug)


@lru_cache(maxsize=None)
def _category_index(lang: str) -> dict[str, Category]:
    return {c.id: c for c in categories(lang)}


def category(lang: str, cat_id: str) -> Category | None:
    return _category_index(lang).get(cat_id)


@lru_cache(maxsize=None)
def by_category(lang: str) -> tuple[tuple[Category, tuple[Article, ...]], ...]:
    """Categories paired with their articles, in declared order.

    Categories with no articles are dropped, so CATEGORIES can run ahead of the
    content without leaving an empty card on the hub.
    """
    grouped = []
    for cat in categories(lang):
        members = tuple(a for a in articles(lang) if a.category == cat.id)
        if members:
            grouped.append((cat, members))
    return tuple(grouped)
