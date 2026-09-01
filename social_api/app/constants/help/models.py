"""
constants/help/models.py — dataclasses shared by every app/constants/help/<lang>.py.

Declared here rather than in __init__.py because the language modules import
these and __init__.py imports the language modules: putting them in __init__.py
is an import cycle at boot. (constants/legal/ dodges this only because its
language modules export bare strings and import nothing.)

Structure lives in the dataclass, prose lives in Markdown. Headings are a field
rather than a `##` inside the body because FAQPage.mainEntity needs discrete
question/answer objects and HowTo.step needs discrete steps — deriving those by
scanning rendered HTML for <h2> breaks silently the moment a translator writes
`###`, and the page still looks perfect while the structured data is empty.
"""

from __future__ import annotations

from dataclasses import dataclass

# ---------------------------------------------------------------------------
# JSON-LD @type selectors.
#
# Plain strings rather than an Enum: the language modules are content files and
# should read as data, not import a symbol per article.
# ---------------------------------------------------------------------------

SCHEMA_ARTICLE = "article"    # -> TechArticle
SCHEMA_HOWTO = "howto"        # -> HowTo
SCHEMA_FAQ = "faq"            # -> FAQPage
SCHEMA_CONTACT = "contact"    # -> ContactPage + Organization.contactPoint
SCHEMA_RELEASES = "releases"  # -> WebPage + ItemList

# Block.kind — how one section maps into its parent article's JSON-LD.
KIND_PROSE = "prose"      # ignored by the FAQPage / HowTo mapping
KIND_FAQ = "faq"          # heading -> Question.name, body -> Answer.text
KIND_STEP = "step"        # heading -> HowToStep.name, body -> HowToStep.text
# Renders an inline SVG from templates/help/_diagrams.html above the body,
# keyed by the block's anchor. The SVG cannot live in the Markdown because the
# renderer is html=False; and it should not, because inline SVG text nodes are
# real text that translates and reaches the accessibility tree, which an
# <img src="…svg"> is not. The body beneath it is the legend, and the legend —
# not the picture — is what survives into the .md and llms-full.txt surfaces.
KIND_DIAGRAM = "diagram"


@dataclass(frozen=True, slots=True)
class Block:
    """One anchored section of an article.

    `body` is CommonMark and MUST NOT contain headings — the anchor, the table
    of contents and the JSON-LD all key off `heading`, so a stray `##` inside
    body would be invisible to every one of them. Pinned by test_help_content.
    """

    anchor: str            # language-independent: the #fragment and the HowToStep url
    heading: str           # translated
    body: str              # CommonMark: paragraphs, lists, links, tables, inline code
    kind: str = KIND_PROSE


@dataclass(frozen=True, slots=True)
class Release:
    """One entry in the What's New feed."""

    version: str                    # "0.3.0"
    date: str                       # ISO
    headline: str
    entries: tuple[str, ...] = ()   # CommonMark bullet bodies, without the leading "-"

    @property
    def anchor(self) -> str:
        return "v" + self.version.replace(".", "-")


@dataclass(frozen=True, slots=True)
class Article:
    """One help page.

    Every collection field is a tuple, not a list: frozen=True alone does not
    make a dataclass hashable if it holds a list, and the lru_cache in
    __init__.py needs these to be hashable.
    """

    slug: str                             # URL segment AND cross-language identity
    title: str                            # problem-shaped; becomes <h1> and <title>
    summary: str                          # <=160 chars: meta description, hub card, llms.txt
    category: str                         # Category.id
    intro: str                            # CommonMark — the direct answer, 40-60 words
    blocks: tuple[Block, ...] = ()
    schema: str = SCHEMA_ARTICLE
    keywords: tuple[str, ...] = ()        # search synonyms absent from the prose
    related: tuple[str, ...] = ()         # slugs; validated by test_help_content
    updated: str = ""                     # ISO date; shown, and dateModified in JSON-LD
    cta: str = ""                         # contextual closing line; empty -> generic
    releases: tuple[Release, ...] = ()    # only when schema == SCHEMA_RELEASES


@dataclass(frozen=True, slots=True)
class Category:
    """A group of articles on the hub. `icon` keys into templates/help/_icons.html."""

    id: str
    title: str
    blurb: str
    icon: str
