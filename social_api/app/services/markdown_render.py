"""services/markdown_render.py — the one place Markdown becomes HTML.

Two renderers from one factory:

  HELP_MD  the help centre's own articles: CommonMark plus tables, typographic
           quotes, links and images as written — the content is ours.
  USER_MD  text a user wrote, shown on a public page (a trip's description on
           its share page): links, images and autolinks are switched off, so
           `[label](url)` and `![alt](url)` stay the literal characters that
           were typed and nothing is ever fetched or made clickable; single
           newlines stay line breaks, as in the app; headings are demoted two
           levels so a user's `#` never competes with the page's own title.

Both keep html=False: raw HTML in the source is escaped, never passed through.
A renderer able to emit arbitrary HTML is one careless paste away from being an
XSS sink, and the site's CSP is frame-ancestors only — it would not catch an
injected inline script. Pinned by test_help_content and test_share.
"""

from __future__ import annotations

from functools import lru_cache

from markdown_it import MarkdownIt
from markupsafe import Markup


def _renderer(**options) -> MarkdownIt:
    return MarkdownIt("commonmark", {"html": False, "linkify": False, **options})


def _demote_headings(state) -> None:
    """h1 → h3 … h4 → h6: the page around user text owns h1 and h2."""
    for token in state.tokens:
        if token.type in ("heading_open", "heading_close"):
            token.tag = f"h{min(int(token.tag[1]) + 2, 6)}"


HELP_MD = _renderer(typographer=True).enable("table")

USER_MD = _renderer(typographer=False, breaks=True).disable(["link", "image", "autolink"])
USER_MD.core.ruler.push("demote_headings", _demote_headings)


@lru_cache(maxsize=1024)
def render_user_markdown(source: str) -> Markup:
    """A user's Markdown → safe HTML, with no link and no image (USER_MD).

    Returns Markup so Jinja's autoescape leaves it alone without a `| safe`.
    """
    return Markup(USER_MD.render(source))


def plain_text(md: MarkdownIt, source: str) -> str:
    """Markdown → bare text: what a search index, a meta description or a
    preview card may carry.

    Walks the token stream rather than stripping tags off the rendered HTML:
    a link's *label* has to survive while its URL must not, and a regex over
    HTML cannot tell those apart.
    """
    parts: list[str] = []
    for token in md.parse(source):
        if token.type == "inline":
            for child in token.children or ():
                if child.type in ("text", "code_inline"):
                    parts.append(child.content)
                elif child.type in ("softbreak", "hardbreak"):
                    parts.append(" ")
        elif token.type == "fence":
            parts.append(token.content)
        elif token.type.endswith("_close") and token.block:
            parts.append("\n")
    return " ".join(" ".join(parts).split())
