"""
constants/legal/ — the three legal documents, one module per language.

Each language module exports exactly three plain-text strings: TOS, PRIVACY,
GUIDELINES. One file per *language* rather than per document so a translation
can be reviewed as a unit — the reviewer for `fr.py` reads everything a French
user will ever be shown, in one place.

Plain text, never HTML: the same string has to render on the web page
(white-space: pre-wrap) and inside the Flutter sheet, which is a bare Text
widget. An HTML body would need a renderer package on the client or a second
copy of every document to keep in sync.

English is authoritative. Every other language carries a prevailing-language
notice, rendered from i18n.py rather than baked into the bodies so the wording
lives in one place. Version constants and the public accessors stay in the three
app/constants/{tos,privacy,guidelines}.py modules — import from there, not
from here.
"""

from app.constants.legal import ar, de, en, es, fr, zh

_MODULES = {"en": en, "fr": fr, "ar": ar, "de": de, "es": es, "zh": zh}


def document(lang: str, name: str) -> str:
    """Return document `name` in `lang`, falling back to English.

    Two fallbacks, not one: an unsupported language code, and a language whose
    module is missing that document (a half-finished translation must degrade
    to English rather than serve an empty legal page).
    """
    module = _MODULES.get(lang, en)
    return getattr(module, name, "") or getattr(en, name)
