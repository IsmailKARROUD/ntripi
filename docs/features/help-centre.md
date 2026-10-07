# Help centre (`/help`) and sitewide SEO

**Status:** shipped (all six languages translated)
**Tables:** none
**Config:** `SUPPORT_CONTACT_EMAIL`, `ABUSE_CONTACT_EMAIL`, `PRIVACY_CONTACT_EMAIL`, `GENERAL_CONTACT_EMAIL`

## Purpose

Public documentation at `/help` — **27 articles** across **8 categories**, written
once and rendered five ways: HTML for people, Markdown for AI assistants, JSON-LD
for search engines, a search index, and the sitemap. Nothing is authored twice.
`services/seo.py` additionally owns canonical URLs, hreflang and the sitemap
**sitewide**, because the homepage and legal pages need them too.

## Rules

### Content shape

- **`app/constants/help/en.py` is the route table.** The router, `sitemap.xml`,
  `llms.txt` and the search index all read the same tuple, so they cannot
  disagree about which pages exist. **A slug that is not there does not exist.**
- **Content is Python string constants, never `.md` files on disk.**
  `.dockerignore` strips `**/*.md`, so on-disk Markdown would build an image with
  an empty help centre and nothing would fail until production served a blank
  page.
- **The dataclasses live in `constants/help/models.py`, not `__init__.py`** — the
  language modules import them and `__init__.py` imports the language modules.
  `constants/legal/` dodges this only because its modules export bare strings.
- **Structure in dataclasses, prose in Markdown.** A `Block` carries its `anchor`,
  `heading` and `kind` as fields, and **its `body` must contain no headings**.
  `FAQPage.mainEntity` and `HowTo.step` are built from `kind`, so deriving them by
  scanning rendered HTML for `<h2>` would let a translator writing `###` silently
  empty the structured data while the page still looked perfect. Pinned by
  `test_help_content.py`.
- Article models are `frozen=True, slots=True` with tuple collections — required
  for the `lru_cache`s to be safe.
- **`whats-new` is a normal `Article`** with `schema=SCHEMA_RELEASES`;
  `templates/help/whats_new.html` is an **include** from `article.html`, not a
  route.

### Translation

- **`articles(lang)` falls back per *slug*, not per module** — a half-finished
  translation ships what it has beside English for the rest, the same way
  `translator()` falls back per key. This is also what makes hreflang and the
  sitemap honest: every alternate they advertise resolves. `en.ARTICLES` stays the
  spine, so **a slug present only in a translated module is dropped**.
- **All six languages are registered** (`en fr ar de es zh`), and a module belongs
  in `_MODULES` **only once every slug in it is translated**. Registration is what
  puts a language into `seo.HELP_CONTENT_LANGS`, and therefore into hreflang, the
  sitemap and `llms.txt` — advertising a language whose articles are still English
  is a duplicate-content signal, not a localisation one.
  `test_help_content.py::test_a_registered_module_translates_every_article`
  makes a half-finished registration fail the suite.
- **Structure is identical across languages, by construction.** `slug`,
  `category`, `schema`, `related`, `updated`, `Category.id`/`icon`,
  `Release.version`/`date` and every `Block.anchor`/`kind` are **copied** from
  `en.py`; only the prose fields are translated. The anchor is both the in-page
  fragment and the `HowToStep.url`, and `kind` is what the structured data is
  built from, so a translator who renumbers one empties the structured data and
  breaks the table of contents **while the page still renders perfectly**. Pinned
  by `test_structure_is_identical_across_languages`.
- **`keywords` are the one field that is NOT translated — they are re-chosen.**
  They are search synonyms, so they have to be the words someone types in *that*
  language. This matters most for Chinese, where the substring tier is what
  carries a query.
- **Every prose invariant runs per language**: `summary` ≤ 160 characters (German
  needs real rewrites here, not translations), no `#` heading inside a
  `Block.body`, `mailto:` limited to the four real mailboxes, external links
  host-allowlisted.

### Rendering and safety

- **`MarkdownIt` stays `html=False`.** The content is ours, so this is not defence
  against a hostile author — it is defence against the flag being flipped for a
  one-off embed, which would turn every article into an injection point. The
  site's CSP is `frame-ancestors` only and would not catch it.
- `render_markdown` returns `Markup`, so no `| safe` is needed at call sites —
  `| safe` on a variable is the habit that eventually gets applied to one that is
  not safe.
- `plaintext` walks the **token stream**, not the rendered HTML: a link's label
  must survive while its URL must not.
- **Diagrams are inline SVG in the template, never `/static/*.svg`.** An
  `<img src="…svg">` is opaque to a screen reader and to the crawlers this section
  exists to serve, and cannot inherit `currentColor`. **Every diagram is followed
  by a text legend — the diagram is decoration, the legend is content.**
- **`/help/app-map`'s diagram labels are `help_diag_*` i18n keys**, and
  `article.html` imports the macro
  `{% from "help/_diagrams.html" import diagram with context %}`. **`_` is a
  context-processor value, not `env.globals`**, so a plain `import` leaves it
  undefined and every `_()` in the macro raises. The SVG geometry stays
  left-to-right in every language including Arabic.

### Routing and caching

- **Declaration order in `routers/help.py` is load-bearing.** `/help/{slug}`
  matches any single segment, so every literal path must be declared above it and
  **`{slug}.md` above `{slug}`**. The failure is silent: `/help/search` simply
  starts rendering "page not found".
- **Cloudflare honours `Vary` only on `Accept-Encoding`.** So help HTML — whose
  language can come from a cookie or `Accept-Language` — **must never carry
  `Cache-Control: public`**, or one visitor's language is served to everyone. The
  machine surfaces (`.md`, `search-index.json`, `llms-full.txt`) read `?lang=`
  **only**, ignoring the cookie, which is what makes the URL the whole cache key
  and public caching safe there. `ETagMiddleware` preserves an endpoint-set
  `Cache-Control`, the same way it already preserved a set `ETag`.
- **`.md` is served as `text/plain`, not `text/markdown`** — browsers download the
  latter, and a link an assistant is meant to follow should render.
- **`/help/search`'s `q` is truncated to 120 chars**, not `Query(max_length=)` — a
  422 on a crawler's long query is worse than a 200 with no results.
  **It is deliberately not rate-limited**: the limiter is in-memory and
  single-instance, the endpoint touches no DB, and a 429 on a crawler-facing page
  is a self-inflicted SEO wound.
- **`sitemap.xml` is served with `media_type="application/xml"` explicitly** — a
  sitemap served as HTML is silently ignored.
- **No named crawler groups in `robots.txt`.** A named user-agent group
  *replaces* the `*` group rather than adding to it, so an `Allow: /` block
  written to welcome an AI crawler would also hand it `/admin`.
- **Deep links into the app use the hash form** (`/app/#/settings/help`). Flutter
  web has no `usePathUrlStrategy()` call, so the path form lands on the app's home
  screen instead.

### Search

`help_service.py`. `fold()` lowercases, strips diacritics, converts punctuation
to spaces, **normalises six Arabic orthographic variants plus tatweel**, and
strips the Arabic definite article from tokens ≥5 chars.

- **Both normalisations are recall fixes, not polish.** `_score_token` asks
  whether the token is *in* the field, so a search for `المسار` scores zero
  against a title carrying `مسار` — containment runs the wrong way.
- **CJK has no spaces**, so a Chinese question folds to one long token that
  appears verbatim nowhere. `_score_token` scores it by **character bigrams, but
  only when a majority of them are present**, so sharing one character is not a
  match. Relaxing that to "any gram hits" would match a large share of the corpus
  — worse than the empty result the fallback exists to fix.
- Field tiers: exact title word **10**, title prefix **6**, keywords **5**,
  summary **3**, title substring **3**, category **2**, body **1**. Total =
  `sum(hits) + 3 × matched`.
- `required_matches`: ≤2 tokens → all must hit; ≥3 → `ceil(n × 0.6)`.
- **`_search_js.html` mirrors both rules**, and its punctuation class must be
  `\p{L}\p{N}` with the `u` flag — **JavaScript's `\w` is ASCII-only** and would
  erase every Arabic and Chinese character rather than the punctuation.
- `search_index_json` is cached as the **finished JSON string**, so the hot path
  is a `Response` over a constant.

### SEO

- **`services/seo.py` owns canonical, hreflang and the sitemap sitewide.**
  `templating.py`'s context processor injects `canonical_url`, `alternates` and
  `switch_lang` into **every** render, because Starlette applies context
  processors *after* the caller's context — **a route cannot override what the
  processor sets.** `alternates_for()` therefore makes the per-path decision: help
  articles advertise only the languages whose prose is translated; everything else
  advertises all six.
- `canonical_path`: English is the bare path; every other language carries
  `?lang=`. `hreflang_alternates` appends `x-default` last.
- **The language switcher uses `switch_lang(code)`, not a bare `?lang=`** — the
  bare form replaces the whole query string, which drops `q` on `/help/search`.
- `sitemap_paths()`: `/`, `/help`, `/privacy`, `/terms`, `/guidelines`, plus every
  `en` article. **Deliberately absent**: `/help/search`, `/admin`, `/appeal`,
  `/reset-password`, `/verify-email`, `/app`, `/share/*`.
- **`llms.txt` is per-language and its links carry `?lang=`.** The index is the
  first thing an assistant reads; English titles under `?lang=de` would advertise
  a corpus that does not match the pages behind it.

### Page furniture

- **The CTA and the contact strip are included by `_layout.html`, not by each
  page**, so they reach the hub, every article, the search page and the 404 — the
  last two being exactly where a reader is most likely to leave. A page that
  *also* includes one renders it twice; `test_furniture_is_not_duplicated` pins
  it.
- **The CTA's download button points at `/#get-the-app`, never a store URL.** The
  app is pre-launch, so the homepage's own download buttons open the waitlist; a
  hardcoded store link would ship dead.
- **The contact strip prints each address as text beside its `mailto:`.** A
  `mailto:` with no registered handler does nothing at all — the common case on
  desktop — which silently turned all four support routes into dead ends. The copy
  button falls back to a `<textarea>` + `execCommand`, because
  `navigator.clipboard` is undefined on plain http.
- **Only `a.hc-card` gets the hover lift.** A category card is a `<section>` with
  nowhere to go; the unscoped rule lifted it anyway, which made the blurb read as
  the card's first link and earned a click that could never do anything. The
  article links inside a card carry a **standing underline** for the same reason:
  blurb and links sit at the same size in two shades of the same green, and an
  underline is direction-neutral where a chevron is not.
- **No "was this helpful" form** — free text from the public site drags in
  `moderate_or_422`, rate limits, a retention policy and a new table, for a signal
  nothing consumes. A `mailto:` with the slug in the subject costs nothing.

### Titles and intros

- **Titles are problem-shaped, not feature-shaped.** Someone who has never heard
  of Ntripi searches for "plan two options for the same day", not for our word for
  it. The feature name lives in a block heading and in `keywords`.
- **`intro` is the direct answer in 40–60 words** — what a search engine lifts
  into a featured snippet and what an assistant quotes, so it must stand alone.
- **Never name internal state** (`edit_lock_lost`, a status code) in a
  troubleshooting article — describe the message the user saw and what to do; the
  internal name goes stale on the next refactor.

### The in-app FAQ is separate

`social_flutter/lib/features/help/` stays as it is and is **not** replaced by
this. Its eight answers ship with the binary so they cannot describe a version the
reader is not holding; the web centre is the fuller, deploy-updated resource,
reached from one row in `HelpCenterScreen`.

**The "do NOT ship a legal document in HTML" rule is specific to *legal*
documents**, whose strings must also render in a bare Flutter `Text`. Help
articles have no such consumer, which is why Markdown is free here.

## API surface

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/help` | none | hub; JSON-LD `SoftwareApplication` + `WebSite` with a `SearchAction` |
| GET | `/help/search?q=` | none | `q` truncated to 120 chars; **not rate-limited** |
| GET | `/help/search-index.json?lang=` | none | `Cache-Control: public, max-age=3600` |
| GET | `/help/{slug}.md?lang=` | none | **`text/plain`**; 404 as plaintext |
| GET | `/help/{slug}` | none | article; 404 renders `help/not_found.html` |
| GET | `/sitemap.xml` | none | `application/xml` |
| GET | `/llms.txt?lang=`, `/llms-full.txt?lang=` | none | per-language |
| GET | `/robots.txt` | none | disallows only `/admin/` |

## Content inventory

**8 categories**: `getting-started`, `building`, `sharing`, `community`,
`account`, `safety`, `troubleshooting`, `about`.

**27 slugs**: getting-started · plan-a-trip-itinerary · app-map ·
plan-alternative-options · add-places-to-an-itinerary ·
add-locations-from-google-maps · plan-transport-between-stops ·
travel-notes-and-warnings · trip-cover-photos · plan-a-trip-with-friends ·
share-an-itinerary-privately · share-a-trip-link · follow-and-private-accounts ·
rate-a-trip · save-trips-and-find-new-ones · read-trips-in-another-language ·
notifications · app-settings · permissions · your-data-and-privacy ·
sign-in-and-account-security · report-and-block · hidden-content-and-appeals ·
troubleshooting · report-a-bug · contact · whats-new

**`RELEASES` currently holds 2 entries** — `0.3.0` and `0.4.0` (translation).
`0.4.0` was dated the day it was written; set the real version and date when it
ships.

## Every user-facing change updates the help centre (CRITICAL)

The help centre is the record of how the app works **today**, so keeping it true
is part of the change, not follow-up work. **A commit that alters what a user sees
or does is not finished until `app/constants/help/` says so.** An article
describing last month's UI is worse than no article: the reader follows it, the
step is not where it says, and they conclude the app is broken. A refactor, an
index or a migration with no visible surface needs none of this — the test is
whether a reader could notice.

For each article the change touches:

- **Edit the prose in all six languages, not just `en.py`.** `articles()` falls
  back per *slug*, so a translated module goes on serving its own stale text
  forever — the page still renders perfectly and nothing fails. Only a wholly
  missing slug is caught.
- **Bump `updated`, in all six.** `test_structure_is_identical_across_languages`
  asserts it matches `en.py` exactly, so the date bump is what makes the suite
  refuse a one-language edit. It is also `dateModified` in the JSON-LD.
- **Re-check `summary` (≤160), `keywords` and `related`.** If the change renamed
  something, the old word is what people still type. A new article also needs
  `related` links *from* its neighbours; a page nothing points at is reachable
  only by search.
- **A new capability needs a new `Article` in `en.py` and in every registered
  language, in the same commit.**
- **Add a `Release` to `RELEASES` for `/help/whats-new` — in all six modules.**
  `releases()` falls back **whole**, not per entry, so an entry added only to
  `en.py` silently leaves the other five showing an outdated What's New **with no
  test to catch it**.
- **Fix the in-app FAQ when the change contradicts one of its eight answers.** It
  is built from `AppLocalizations` (`faq*Q` / `faq*A` in the `.arb` files), ships
  with the binary and **cannot be corrected by a deploy**.
- **Renamed routes and screens count too** — `/help/app-map`'s labels are
  `help_diag_*` keys, and every deep link is `/app/#/…`.

## Flutter surface

- **`HelpCenterScreen`** (`/settings/help`) — the in-app FAQ, eight answers from
  `AppLocalizations`, plus one row that opens the web centre in a browser with
  `?lang=<app locale>`.
- **`AboutScreen`** (`/settings/about`), **`ReportBugScreen`**
  (`/settings/help/report-bug`).
- `features/help/presentation/widgets/faq_row.dart`.
- `core/api/api_endpoints.dart` holds `kSupportContactEmail` /
  `kGeneralContactEmail`, whose defaults **must match** the backend's
  `SUPPORT_CONTACT_EMAIL` / `GENERAL_CONTACT_EMAIL`.

## Known gaps / TODOs

- `RELEASES` holds a single entry, so `/help/whats-new` is thin.
- Tests: `test_help_content.py`, `test_help_routes.py`, `test_help_seo.py` all
  run and pin the invariants above.

## Related

- [legal-and-age-gate.md](legal-and-age-gate.md) — shares `i18n.py` `SUPPORTED` and the SEO layer
- [web-and-platform.md](web-and-platform.md) — the homepage, `robots.txt`, the language cookie
- [sharing.md](sharing.md) — why `/share/*` is absent from the sitemap
- [etag-concurrency.md](etag-concurrency.md) — the `Cache-Control` preservation rule
- [bug-reports.md](bug-reports.md) — the Support row's destination
- [translations.md](translations.md) — `read-trips-in-another-language`, the article that explains it
- [admin-and-appeals.md](admin-and-appeals.md) — why `robots.txt` names no crawlers
- [constraints.md](../constraints.md)
