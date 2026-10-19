# Sharing (public landing pages)

**Status:** shipped
**Tables:** none (reads `itineraries`, `users`)
**Config:** `SHARE_BASE_URL`, `SHARE_RATE_LIMIT`, `STORAGE_PUBLIC_URL_PREFIX`, `R2_PUBLIC_URL`

## Purpose

Server-rendered HTML pages at `/share/i/{id}` and `/share/u/{username}` that give
an itinerary or a profile a link with a rich Open Graph preview on WhatsApp,
iMessage, Twitter and Slack. **No authentication** — these are for people who do
not have the app, or are not signed in. On a phone that has it, the same link
opens the app instead — see [app-links.md](app-links.md).

**They are a teaser, not the content.** Whoever reads one without an account
gets a few fields and a way in; the trip itself is behind a free sign-in.

## Rules

### What a reader without an account sees

**One page for every reader — a person, a chat-card crawler, a search engine, an
AI bot.** Nothing is served to one that is not served to all, so there is no
cloaking question and no second template to keep honest.

| Page | Shows | Never shows |
|---|---|---|
| public trip | title, cover, rating (average + count), description | the owner, stops, addresses, notes, annotations, transport, costs, durations, parallel options, reviews |
| public profile | display name, @username, avatar | bio, counts, trips |
| private profile | the same three, **`noindex`** | — |

**The routes pass the templates those fields and nothing else** —
`share_service.prepare_share_context` / `prepare_profile_share_context` build a
dict of them, never hand over the row — so a template cannot leak what it was
never given. `test_public_surface.py` holds every open route to it; see
[web-and-platform.md](web-and-platform.md#the-public-surface).

**The chat card says what the page says.** A public trip's `og:description` is
`★ 4.6 (12) · <start of the description>` — the rating when it has one, the
first ~150 characters of the description cut on a word — and "A trip on Ntripi"
when it has neither; title and cover are the card's title and image. A profile's
card is its display name, `@username · Ntripi` and the avatar. Until 2026-10-19
the trip card carried duration, cost and stop count, which the page no longer
shows.

Decided 2026-10-19 — see [decisions.md](../decisions.md). Before then the page
rendered the whole trip to anyone, in a design of its own.

### Visibility on a public page

There is **no viewer**, so the ladder collapses to three outcomes
(`share.py` `share_itinerary`):

| `visibility` | Page |
|---|---|
| `public` | the teaser |
| `followers` / `restricted` | a "this trip is private" page carrying **no title, owner or cover** — on the page or in its preview card — and `noindex` |
| `only_me` | **404 — identical to not-found**, so the link reveals nothing |

Moderator-hidden, soft-deleted and banned-owner trips answer the same 404.

**A private trip's page names nothing about it.** Its preview card is seen by
everyone in the chat the link was pasted into — mostly people who cannot open the
trip — so the title, the `@owner` and the cover stay off the page and out of
the OG/Twitter tags, which carry a generic "Private itinerary — Ntripi" and the
default image. The router enforces it by passing `share_private.html` nothing but
the share URL, the default preview image and the call to action: the template
has no trip to leak. Until 2026-10-18 it showed all three, contradicting the help
centre's promise; see [decisions.md](../decisions.md).

**A malformed id gets the not-found page, not JSON.** `share_itinerary` takes its
id as a string and parses it — typed as `uuid.UUID`, a link cut short in a chat
answered FastAPI's raw 422. A dead profile link gets the not-found page with
**profile** wording ("Account unavailable" — the app's own words).

`admin_service.public_page_live` mirrors this gate exactly, which is how the
dashboard can tell an operator whether a trip is currently reachable from a
shared link.

### The way in

Every page but not-found carries the same gate (`_app_links.html`
`teaser_gate`), built from `app_links.cta_context()`:

- **"See the full trip"** / **"See the full profile"** → `/app/#/share/i/<id>`
  (or `/u/`), with "Free account needed" under it. The web app runs the same
  router hooks as the phones: a signed-in visitor lands on the trip at once; a
  signed-out one is sent to sign in — **Create account** one tap away, and a
  line above the form saying what is waiting (`ParkedLinkNotice`) — and lands on
  it after. One neutral label because the page cannot know whether the visitor
  already has an account.
- **The store buttons**, then **Open in app** on Android. **A phone is shown its
  own store only** — Google Play on Android, the App Store on an iPhone or an
  iPad — decided once in `<head>` by `platform_head`; a laptop, an unknown device
  and a browser without JavaScript get both, and both are always in the HTML.
  Before launch the stores are the homepage waitlist, so the web button leads.
  **Once a store URL is set, a phone of that platform gets its store first**
  (`store-first`, set by `app_links_script` from `app_store_live` /
  `play_store_live`), with the hint "Once it's installed, tap the link again to
  open it in the app" — installing does not carry the link into the app (no
  deferred deep linking). A desktop always keeps the web button first: it cannot
  install from a store page.
- The not-found page carries the store buttons and **Go to Ntripi** only.

Details of the store and intent links in [app-links.md](app-links.md#the-share-pages-a-teaser-and-one-way-in).

### URL building

- **`build_share_url(itinerary, settings)` is the only way to build the itinerary
  share URL** — never rebuild the f-string. `build_profile_share_url(user,
  settings)` is its profile twin.
- Both read `SHARE_BASE_URL`.
- The profile URL is built **from the handle**, which is why usernames are
  immutable — see
  [accounts-and-profiles.md](accounts-and-profiles.md).
- **The canonical is the bare share URL**, whatever `?lang=` the visitor came
  with: the content is the user's own, in one language however the chrome is
  translated, so the pages declare no hreflang set.

### Absolute image URLs

**`absolute_storage_url(key, settings)` is the only way to turn a storage key into
a URL fit to leave the site** (emails, Jira tickets, OG crawlers).

Filesystem storage returns a **relative** `/uploads/…` path, which an OG crawler
cannot fetch; R2 URLs are already absolute and pass through.
`absolutize_stored_url` does the same for a URL already stored on a row.

`_resolve_preview_image_url` picks the itinerary's cover if it has one and falls
back to the default OG image in `app/static/`.

### The rendered pages

**One layout, `_share_layout.html`, in the app's own design** — the
`NtripiColors.light` tokens from `app_theme.dart` as CSS variables, DM Sans, a
white ground with 18 px hairline cards in a phone-width column, the trip
screen's cover hero (240 px, the ink scrim, the title at 22/700, the visibility
badge and a glass report button). Light only: no page on the site has a dark
theme yet. Developer notes in it are Jinja comments, never CSS comments — those
would ship to every visitor.

Templates: `share_public.html`, `share_private.html`, `share_profile.html` (public
and private accounts), `share_not_found.html`, `share_rate_limited.html`.

The trip route loads **the itinerary row alone** — no tracks, stops, segments or
legs — plus the owner, for the banned-owner check only.

A count-bearing string uses `_n(key, count)` (`i18n.PLURALS`, CLDR categories
for the six languages) — "12 ratings", copied from the app's ICU plurals.

An **anonymous report dialog** appears on the trip teaser — see
[content-reports.md](content-reports.md). It stays because the title, cover and
description it shows can be what someone needs to report, and the EU DSA expects
a notice mechanism open to non-users.

### Rate limit

`SHARE_RATE_LIMIT` (default `120/minute`, per client IP) on both routes. A person
never reaches it and a search engine spreads its crawl over many addresses; it
exists so one scraper cannot hammer the origin. The answer is an HTML 429 page
with `Retry-After`, not slowapi's JSON — see
[web-and-platform.md](web-and-platform.md#rate-limiting).

## API surface

| Method | Path | Auth | Response |
|---|---|---|---|
| GET | `/share/i/{itinerary_id}` | **none** (rate-limited) | HTML + OG tags, or the private page, or 404 |
| GET | `/share/u/{username}` | **none** (rate-limited) | HTML + OG tags, or 404 |

Both are HTML, so `ETagMiddleware` (JSON only) does not touch them. Both are also
the paths the apps claim — see [app-links.md](app-links.md).

`/share/*` paths are **deliberately absent from `sitemap.xml`** — see
[help-centre.md](help-centre.md).

## Flutter surface

- **`shareServiceProvider`** (`features/itineraries/providers/itinerary_providers.dart`)
  → the share-sheet wrapper, built on `share_plus`.
- The share action is offered from `ItineraryDetailScreen` and `FeedCard`, and
  **never from `SharedItineraryCard`** — an editor's row has no share action.
- `SHARE_BASE_URL` reaches the client as a `--dart-define`.
- **`ParkedLinkNotice`** (`features/auth/presentation/widgets/`) — the line above
  the sign-in and sign-up forms while a shared link waits for the sign-in. It
  listens to `parkedAppLink` (`core/router/app_links.dart`), so a link tapped
  while the screen is open shows it too.

## Known gaps / TODOs

- **Auto-generated per-itinerary OG preview images are unbuilt.**
  `app/static/README.md:15` carries the repo's one real code-adjacent TODO:
  *"TODO (Jira Ticket 3): Replace with dynamic per-itinerary preview images
  generated from the itinerary's cover image + title overlay."* The insertion
  point is marked in `share_service.py` `_resolve_preview_image_url`: *"Phase 2
  map-image fallback goes here."* See [backlog.md](../backlog.md).
- `app/static/README.md` says the default OG PNG is "not committed to version
  control", but `ntripi-og-default.png` is on disk and tracked — the README is
  stale on that point.
- **A trip with no description is thin for a search engine** — a title, a photo
  and a rating. Whether Google indexes such pages is for Search Console to show;
  opening more is a template change. See [backlog.md](../backlog.md).
- **No edge cache.** The pages' chrome language comes from a cookie or
  `Accept-Language`, and Cloudflare varies its cache on `Accept-Encoding` only,
  so they cannot be cached at the edge as they stand. See
  [backlog.md](../backlog.md).
- **Image keys are derived from ids.** A trip's cover is at
  `itineraries/<trip id>.jpg` on the public image domain, so a private trip's
  share link leads to its cover, and an avatar's URL gives the user id and with
  it the profile cover. Being fixed as step 2 of the share-teaser work.

## Related

- [visibility-and-access.md](visibility-and-access.md) — the ladder, and the no-viewer case
- [itineraries.md](itineraries.md) — what the page renders
- [image-pipeline.md](image-pipeline.md) — `absolute_storage_url` and the cover
- [accounts-and-profiles.md](accounts-and-profiles.md) — immutable handles
- [content-reports.md](content-reports.md) — the anonymous report dialog
- [app-links.md](app-links.md) — the same links opening the app, and the store and intent links on these pages
- [authentication.md](authentication.md) — the sign-in the gate leads to
- [web-and-platform.md](web-and-platform.md) — the rate limit, and the public-surface test
- [help-centre.md](help-centre.md) — canonical / hreflang / sitemap policy
