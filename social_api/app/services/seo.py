"""
services/seo.py — canonical URLs, hreflang alternates and the sitemap.

Sitewide, not help-specific: the homepage and the three legal pages need the
same canonical and alternate tags, and the sitemap lists all of them. Kept in
one module so the URL for a page is composed in exactly one place — the same
reason share_service owns build_share_url.
"""

from __future__ import annotations

from app.config import Settings
from app.constants.help import _MODULES as _HELP_MODULES
from app.constants.help import articles
from app.i18n import SUPPORTED

HELP_PREFIX = "/help"

# Languages whose *help articles* are translated. The chrome (nav, headings,
# search box) is translated for all six via i18n.py, but hreflang describes the
# page's content, and claiming six alternates that all serve the same English
# prose is a duplicate-content signal rather than a localisation one. Grows on
# its own as constants/help/<lang>.py modules land.
HELP_CONTENT_LANGS: tuple[str, ...] = tuple(c for c in SUPPORTED if c in _HELP_MODULES)


def absolute(path: str, settings: Settings) -> str:
    """Site-relative path -> absolute URL. The only place the base is joined."""
    return f"{settings.share_base_url.rstrip('/')}{path}"


def canonical_path(path: str, lang: str) -> str:
    """The canonical form of `path` in `lang`.

    English is the bare path; every other language carries `?lang=`. Consistent
    across all three ways the language gets resolved, and correct for the
    cookie-served case too: a crawler sends no cookies, so it only ever sees the
    `?lang=` form it was pointed at.
    """
    return path if lang == "en" else f"{path}?lang={lang}"


def canonical_url(path: str, lang: str, settings: Settings) -> str:
    return absolute(canonical_path(path, lang), settings)


def hreflang_alternates(
    path: str,
    settings: Settings,
    *,
    langs: tuple[str, ...] = SUPPORTED,
) -> list[tuple[str, str]]:
    """(hreflang, url) pairs for `path`, x-default last.

    `langs` differs by page: the homepage and legal documents are translated
    into all six, help articles only into the ones with a content module.
    """
    pairs = [(code, canonical_url(path, code, settings)) for code in langs]
    pairs.append(("x-default", absolute(path, settings)))
    return pairs


def alternates_for(path: str, settings: Settings) -> list[tuple[str, str]]:
    """The alternate set appropriate to `path`.

    Decided here rather than passed in by each route: Starlette applies context
    processors *after* the caller's context, so a route cannot override a value
    the processor sets — and every page must carry alternates, so the processor
    is where it has to live.

    Help articles advertise only the languages whose prose is translated; the
    homepage and legal documents are translated into all six.
    """
    langs = HELP_CONTENT_LANGS if path.startswith(HELP_PREFIX) else SUPPORTED
    return hreflang_alternates(path, settings, langs=langs)


def switch_language_path(url, code: str) -> str:
    """The current page in another language, as a site-relative URL.

    Relative rather than the absolute form `request.url.include_query_params`
    returns: the switcher should not bake the request's host into the markup.
    And built by merging rather than as a bare "?lang=xx", because the bare
    form replaces the whole query string — which silently drops `q` when you
    switch language on /help/search.
    """
    merged = url.include_query_params(lang=code)
    return merged.path + (f"?{merged.query}" if merged.query else "")


def article_path(slug: str) -> str:
    return f"{HELP_PREFIX}/{slug}"


def sitemap_paths() -> list[tuple[str, str, str]]:
    """(path, changefreq, priority) for every indexable public page.

    /help/search is deliberately absent: a search-results URL burns crawl budget
    and the page carries noindex anyway. So are /admin, /appeal, /reset-password,
    /verify-email, /app and /share/* — private, per-user, or unbounded.
    """
    pages = [
        ("/", "weekly", "1.0"),
        (HELP_PREFIX, "weekly", "0.9"),
        ("/privacy", "yearly", "0.3"),
        ("/terms", "yearly", "0.3"),
        ("/guidelines", "yearly", "0.3"),
    ]
    pages += [(article_path(a.slug), "monthly", "0.8") for a in articles("en")]
    return pages
