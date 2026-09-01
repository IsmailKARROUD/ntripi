"""templating.py — Single Jinja2Templates instance shared by web.py and share.py.

A context processor injects `_` (the translator) and `lang` into every template
render based on the request's resolved language, plus the `current_year` global.

It also injects the SEO values every page needs — `canonical_url`,
`alternates` and `switch_lang` — so no route has to remember to pass them and no
template can quietly ship without them. Note a route *cannot* override these:
Starlette applies context processors after the caller's context, so the
processor always wins. That is why the per-path decision (a help article
advertises only the languages whose prose is translated; everything else
advertises all six) lives in `seo.alternates_for()` rather than in a route.
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

from fastapi.templating import Jinja2Templates
from starlette.requests import Request

from app.config import get_settings
from app.i18n import LANG_NAMES, RTL_LANGS, SUPPORTED, resolve_lang, translator
from app.services.seo import alternates_for, canonical_url, switch_language_path

_TEMPLATES_DIR = Path(__file__).parent / "templates"


def _i18n_context(request: Request) -> dict:
    lang = resolve_lang(request)
    settings = get_settings()
    # request.url.path drops the query string on purpose: /help/search?q=x and
    # /help/search are the same document, and a canonical carrying the query
    # would ask a crawler to index one URL per search anyone ever ran.
    path = request.url.path
    return {
        "_": translator(lang),
        "lang": lang,
        "dir": "rtl" if lang in RTL_LANGS else "ltr",
        "supported": SUPPORTED,
        "lang_names": LANG_NAMES,
        "canonical_url": canonical_url(path, lang, settings),
        "alternates": alternates_for(path, settings),
        "switch_lang": lambda code: switch_language_path(request.url, code),
    }


templates = Jinja2Templates(
    directory=str(_TEMPLATES_DIR),
    context_processors=[_i18n_context],
)
templates.env.globals["current_year"] = datetime.now().year
