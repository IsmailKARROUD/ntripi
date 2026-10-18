# Sharing (public landing pages)

**Status:** shipped
**Tables:** none (reads `itineraries`, `users`)
**Config:** `SHARE_BASE_URL`, `STORAGE_PUBLIC_URL_PREFIX`, `R2_PUBLIC_URL`

## Purpose

Server-rendered HTML pages at `/share/i/{id}` and `/share/u/{username}` that give
an itinerary or a profile a link with a rich Open Graph preview on WhatsApp,
iMessage, Twitter and Slack. **No authentication** — these are for people who do
not have the app. On a phone that has it, the same link opens the app instead —
see [app-links.md](app-links.md).

## Rules

### Visibility on a public page

There is **no viewer**, so the ladder collapses to three outcomes
(`share.py:56`):

| `visibility` | Page |
|---|---|
| `public` | the full rich page |
| `followers` / `restricted` | a "this trip is private" page carrying **no title, owner or cover** — on the page or in its preview card |
| `only_me` | **404 — identical to not-found**, so the link reveals nothing |

**A private trip's page names nothing about the trip.** Its preview card is seen
by everyone in the chat the link was pasted into — mostly people who cannot open
the trip — so the title, the `@owner` and the cover stay off the page and out of
the OG/Twitter tags, which carry a generic "Private itinerary — Ntripi" and the
default image. The router enforces it by passing `share_private.html` nothing but
the share URL, the default preview image and the call to action: the template
has no trip to leak. Until 2026-10-18 it showed all three, contradicting the help
centre's promise; see [decisions.md](../decisions.md).

**A malformed id gets the not-found page, not JSON.** `share_itinerary` takes its
id as a string and parses it — typed as `uuid.UUID`, a link cut short in a chat
answered FastAPI's raw 422. A dead profile link gets the not-found page with
**profile** wording ("Account unavailable" — the app's own words); it used to say
"This itinerary is not available".

`admin_service.public_page_live` mirrors this gate exactly, which is how the
dashboard can tell an operator whether a trip is currently reachable from a
shared link.

### URL building

- **`build_share_url(itinerary, settings)` is the only way to build the itinerary
  share URL** — never rebuild the f-string. `build_profile_share_url(user,
  settings)` is its profile twin.
- Both read `SHARE_BASE_URL`.
- The profile URL is built **from the handle**, which is why usernames are
  immutable — see
  [accounts-and-profiles.md](accounts-and-profiles.md).

### Absolute image URLs

**`absolute_storage_url(key, settings)` is the only way to turn a storage key into
a URL fit to leave the site** (emails, Jira tickets, OG crawlers).

Filesystem storage returns a **relative** `/uploads/…` path, which an OG crawler
cannot fetch; R2 URLs are already absolute and pass through.
`absolutize_stored_url` does the same for a URL already stored on a row.

`_resolve_preview_image_url` picks the itinerary's cover if it has one and falls
back to the default OG image in `app/static/`.

### The rendered page

`prepare_share_context` eager-loads `tracks → stops → outgoing_segment → legs` in
one query chain and renders the whole trip. Helpers in `share_service.py` format
it: `_mode_emoji` per transport mode, `_format_duration`, `_format_cost`.

Templates: `share_public.html`, `share_private.html`, `share_not_found.html`,
`share_profile_public.html`, `share_profile_private.html`.

An **anonymous report dialog** appears on the share page — see
[content-reports.md](content-reports.md).

### App first, web second

Every page but not-found carries the same call to action, built by
`app_links.cta_context()` and the `_app_links.html` macros: **Open in app**
(Android only, an `intent://` link with a store-or-waitlist fallback), the store
buttons (the waitlist until `APP_STORE_URL` / `PLAY_STORE_URL` are set), the iOS
Smart App Banner once `IOS_APP_STORE_ID` is set, and **Continue on web** into the
Flutter web app at the same trip or profile. The not-found page carries the store
buttons only. The `ntripi://` links these pages used were dead — the app never
registered the scheme. Details in [app-links.md](app-links.md#the-share-pages-app-first-web-second).

## API surface

| Method | Path | Auth | Response |
|---|---|---|---|
| GET | `/share/i/{itinerary_id}` | **none** | HTML + OG tags, or the private page, or 404 |
| GET | `/share/u/{username}` | **none** | HTML + OG tags, or the private page |

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

## Known gaps / TODOs

- **Auto-generated per-itinerary OG preview images are unbuilt.**
  `app/static/README.md:15` carries the repo's one real code-adjacent TODO:
  *"TODO (Jira Ticket 3): Replace with dynamic per-itinerary preview images
  generated from the itinerary's cover image + title overlay."* The insertion
  point is marked in `share_service.py:170`: *"1. User-uploaded cover image
  (Phase 1 — this release). 2. Auto-generated map image (Phase 2 — future) …
  Phase 2 map-image fallback goes here."* See [backlog.md](../backlog.md).
- `app/static/README.md` says the default OG PNG is "not committed to version
  control", but `ntripi-og-default.png` is on disk and tracked — the README is
  stale on that point.
- **A branching route shows one arbitrary transit segment per stop.** The page
  reads `Stop.outgoing_segment`, declared one-to-one (`uselist=False`), but a stop
  before a track of parallel alternatives has a segment into each of them. The
  page also flattens every track into one numbered list, so the fix needs a
  decision on how a branch should read, not just a relationship change. See
  [backlog.md](../backlog.md).

## Related

- [visibility-and-access.md](visibility-and-access.md) — the ladder, and the no-viewer case
- [itineraries.md](itineraries.md) — what the page renders
- [tracks-and-stops.md](tracks-and-stops.md) · [transit-segments.md](transit-segments.md) — the eager-loaded tree
- [image-pipeline.md](image-pipeline.md) — `absolute_storage_url` and the cover
- [accounts-and-profiles.md](accounts-and-profiles.md) — immutable handles
- [content-reports.md](content-reports.md) — the anonymous report dialog
- [app-links.md](app-links.md) — the same links opening the app, and the call to action on these pages
- [help-centre.md](help-centre.md) — canonical / hreflang / sitemap policy
- [web-and-platform.md](web-and-platform.md) — the surrounding web surfaces
