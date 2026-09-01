"""
routers/help.py — the public help centre.

Its own module rather than more routes on web.py, matching share.py / waitlist.py
/ appeals.py. The machine-readable siblings that are not under /help —
/sitemap.xml, /llms.txt, /llms-full.txt — stay in web.py next to robots.txt,
which is what they belong with.

DECLARATION ORDER IS LOAD-BEARING. `/help/{slug}` matches any single segment, so
every literal path must be declared above it, and `{slug}.md` above `{slug}` or
".md" is swallowed into the slug. Regression-tested, because the failure is
silent: /help/search would simply start rendering a "page not found".
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request
from fastapi.responses import HTMLResponse, PlainTextResponse, Response

from app.config import Settings, get_settings
from app.constants.help import article as get_article
from app.constants.help import articles, by_category, category as get_category
from app.constants.help.models import Article
from app.i18n import resolve_lang, translator
from app.services import help_render, help_service
from app.services.seo import HELP_CONTENT_LANGS, article_path, canonical_url
from app.templating import templates

router = APIRouter(tags=["help"])

# The article the "New here?" card points at, and the ones the hub lists as
# popular. Slugs rather than positions so reordering en.ARTICLES cannot silently
# change what the hub promotes.
_QUICKSTART = "getting-started"
_POPULAR = (
    "plan-a-trip-itinerary",
    "plan-alternative-options",
    "share-an-itinerary-privately",
    "permissions",
    "troubleshooting",
)

# Machine surfaces resolve the language from `?lang=` alone and ignore the
# cookie, so the URL is the whole cache key. That is what makes them safe to
# cache publicly: Cloudflare honours Vary only on Accept-Encoding, so anything
# whose language came from a cookie or a header must never be public-cached.
_MACHINE_CACHE = "public, max-age=3600"


def _machine_lang(lang: str) -> str:
    return lang if lang in HELP_CONTENT_LANGS else "en"


def _base_context(lang: str, settings: Settings) -> dict:
    """The context every help page needs: the category listing (used by the hub,
    the search page's no-results fallback and the 404) and the mailboxes."""
    return {
        "grouped": by_category(lang),
        "emails": help_service.contact_emails(settings),
    }


# ---------------------------------------------------------------------------
# Literal paths — all of these must stay above /help/{slug}
# ---------------------------------------------------------------------------

@router.get("/help", response_class=HTMLResponse)
def help_hub(request: Request, settings: Settings = Depends(get_settings)) -> HTMLResponse:
    lang = resolve_lang(request)
    base = settings.share_base_url.rstrip("/")
    ctx = _base_context(lang, settings)
    t = translator(lang)
    jsonld = help_render.jsonld_script([
        {
            "@context": "https://schema.org",
            "@type": "SoftwareApplication",
            "name": "Ntripi",
            "applicationCategory": "TravelApplication",
            "operatingSystem": "iOS, Android, Web",
            "url": base,
            "offers": {"@type": "Offer", "price": "0", "priceCurrency": "EUR"},
        },
        # The single most useful tag for an assistant: it says "this site has a
        # search endpoint, and here is how to call it".
        {
            "@context": "https://schema.org",
            "@type": "WebSite",
            "name": "Ntripi",
            "url": base,
            "potentialAction": {
                "@type": "SearchAction",
                "target": {
                    "@type": "EntryPoint",
                    "urlTemplate": f"{base}/help/search?q={{search_term_string}}",
                },
                "query-input": "required name=search_term_string",
            },
        },
    ])
    return templates.TemplateResponse(request, "help/hub.html", {
        **ctx,
        "page_title": f"{t('help_title')} — Ntripi",
        "page_description": t("help_description"),
        "quickstart": get_article(lang, _QUICKSTART),
        "popular": [a for a in (get_article(lang, s) for s in _POPULAR) if a],
        "jsonld": jsonld,
        "crumbs": [("Ntripi", "/"), (t("help_title"), None)],
    })


@router.get("/help/search", response_class=HTMLResponse)
def help_search(
    request: Request,
    q: str = "",
    settings: Settings = Depends(get_settings),
) -> HTMLResponse:
    lang = resolve_lang(request)
    ctx = _base_context(lang, settings)
    t = translator(lang)
    # Truncated here rather than constrained with Query(max_length=...): a 422 on
    # a crawler's over-long query is a worse answer than a 200 with no results.
    query = q.strip()[:120]
    return templates.TemplateResponse(request, "help/search.html", {
        **ctx,
        "page_title": f"{t('help_search_button')} — {t('help_title')}",
        "page_description": t("help_description"),
        "q": query,
        "results": help_service.search(lang, query) if query else [],
        "crumbs": [("Ntripi", "/"), (t("help_title"), "/help"),
                   (t("help_search_button"), None)],
    })


@router.get("/help/search-index.json")
def help_search_index(lang: str = "en") -> Response:
    """The corpus the browser narrows against.

    `lang` is read from the query string only — the cookie and Accept-Language
    are deliberately ignored, so the URL is the whole cache key and a CDN cannot
    serve one visitor's language to another.
    """
    return Response(
        content=help_service.search_index_json(_machine_lang(lang)),
        media_type="application/json",
        headers={"Cache-Control": _MACHINE_CACHE},
    )


# ---------------------------------------------------------------------------
# /help/{slug}.md — must precede /help/{slug}
# ---------------------------------------------------------------------------

@router.get("/help/{slug}.md", response_class=PlainTextResponse)
def help_article_markdown(
    slug: str,
    lang: str = "en",
    settings: Settings = Depends(get_settings),
) -> PlainTextResponse:
    """The article's Markdown source, verbatim.

    text/plain rather than text/markdown: browsers download the latter instead of
    displaying it, and a link an assistant is meant to follow should render.
    """
    resolved = _machine_lang(lang)
    article = get_article(resolved, slug)
    if article is None:
        return PlainTextResponse("Not found\n", status_code=404)
    url = canonical_url(article_path(slug), resolved, settings)
    return PlainTextResponse(
        help_render.article_markdown(article, url),
        headers={"Cache-Control": _MACHINE_CACHE},
    )


# ---------------------------------------------------------------------------
# The catch-all. Nothing may be declared below it.
# ---------------------------------------------------------------------------

@router.get("/help/{slug}", response_class=HTMLResponse)
def help_article(
    request: Request,
    slug: str,
    settings: Settings = Depends(get_settings),
) -> HTMLResponse:
    lang = resolve_lang(request)
    ctx = _base_context(lang, settings)
    t = translator(lang)
    article: Article | None = get_article(lang, slug)

    if article is None:
        return templates.TemplateResponse(request, "help/not_found.html", {
            **ctx,
            "page_title": f"{t('help_not_found_title')} — Ntripi",
            "crumbs": [("Ntripi", "/"), (t("help_title"), "/help"),
                       (t("help_not_found_title"), None)],
        }, status_code=404)

    category = get_category(lang, article.category)
    canonical = canonical_url(article_path(slug), lang, settings)
    return templates.TemplateResponse(request, "help/article.html", {
        **ctx,
        "page_title": f"{article.title} — Ntripi",
        "page_description": article.summary,
        "article": article,
        "category": category,
        "intro_html": help_render.render_markdown(article.intro) if article.intro else "",
        "blocks": [
            {"anchor": b.anchor, "heading": b.heading, "kind": b.kind,
             "html": help_render.render_markdown(b.body)}
            for b in article.blocks
        ],
        "toc": help_service.toc(article),
        "related": [a for a in (get_article(lang, s) for s in article.related) if a],
        "cta_line": article.cta,
        "render": help_render.render_markdown,
        "jsonld": help_render.jsonld_script(help_render.jsonld_for(
            article, category,
            lang=lang,
            canonical=canonical,
            base=settings.share_base_url.rstrip("/"),
            help_url=f"{settings.share_base_url.rstrip('/')}/help",
            contact_emails=help_service.contact_emails(settings),
        )),
        "crumbs": [
            ("Ntripi", "/"),
            (t("help_title"), "/help"),
            *( [(category.title, f"/help#{category.id}")] if category else [] ),
            (article.title, None),
        ],
    })
