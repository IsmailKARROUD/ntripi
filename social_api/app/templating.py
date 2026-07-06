"""templating.py — Single Jinja2Templates instance shared by web.py and share.py.

A context processor injects `_` (the translator) and `lang` into every template
render based on the request's resolved language, plus the `current_year` global.
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

from fastapi.templating import Jinja2Templates
from starlette.requests import Request

from app.i18n import resolve_lang, translator

_TEMPLATES_DIR = Path(__file__).parent / "templates"


def _i18n_context(request: Request) -> dict:
    lang = resolve_lang(request)
    return {"_": translator(lang), "lang": lang}


templates = Jinja2Templates(
    directory=str(_TEMPLATES_DIR),
    context_processors=[_i18n_context],
)
templates.env.globals["current_year"] = datetime.now().year
