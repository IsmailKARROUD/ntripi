# Discovery feed and search

**Status:** shipped
**Tables:** reads `itineraries`, `users`
**Config:** `FEED_TOP_MIN_RATINGS`

## Purpose

Two ways to find things you do not already have a link to: a public discovery
feed of itineraries with a Top/Recent toggle, and a user search. Place search
(for the stop form) is a third, separate thing that talks to a geocoder, not to
our database.

## Rules

### Feed — `GET /itineraries/feed`

- **Only `visibility == 'public'` is in the feed.** That SQL filter is the cheap
  equivalent of `can_view_itinerary`, which short-circuits `True` for public
  anyway — so the feed avoids an O(n) per-row Python evaluation
  (`itineraries.py:705`).
- **Plus `public_listing_criteria(db, viewer_id)`** for the moderation clauses:
  not soft-deleted, not hidden, owner active, author not blocked. The query
  `join(User)`s the owner, which the criteria require and which the attribution
  wants anyway.
- **Two sorts:**
  | `sort` | Order |
  |---|---|
  | `recent` (default) | `created_at DESC, id DESC` |
  | `top` | `rating_avg DESC, rating_count DESC, created_at DESC, id DESC`, **and** `rating_count >= FEED_TOP_MIN_RATINGS` |
- **`?lang=xx` adds each card's cached title translation.** Every item carries
  the trip's `source_lang`, and — when translation is on, `lang` is a supported
  target and the cache holds a translation of the **current** title —
  `title_translation: {lang, text}`. One extra query per page
  (`translation_service.title_translations_for`). A query parameter, not
  `Accept-Language`, so the URL stays the client cache's whole key. Public
  titles are translated ahead of time, so a card rarely waits on anyone
  ([translations.md](translations.md#titles-translated-ahead-of-the-reader)).
- **`id DESC` is the final tie-breaker on both**, so pagination is stable when
  timestamps or averages collide.
- **The `top` threshold stops a single 5-star trip dominating.** It is an env var
  so the bar can be lowered while the catalogue is young and raised as ratings
  accumulate.
- Eager-loads `tracks → stops` via `selectinload` so `stops_count` costs no N+1.
- Owner attribution goes through `public_profile_text` — the feed is the
  widest-reach surface, so a moderated display name must not ride along with an
  otherwise clean itinerary.
- Rate-limited **30/minute**.

### User search — `GET /users/search`

- Matches `username_lower ILIKE` **OR** `display_name ILIKE`, with `%`, `_` and
  `\` escaped so the query matches literally — `q="_"` used to match every
  account.
- **Blocked accounts are filtered in the query, not after** (`users.py:373`). Two
  reasons: a blocked account must be *unfindable*, not merely unopenable —
  leaving it in the results tells the blocked user the account still exists — and
  filtering after the fact would silently shrink pages under `limit`/`offset`.
- Excludes self and any `is_active == False` account.
- **Ordered exact match → prefix match → `followers_count DESC` →
  `username_lower`.** The last key is unique, so the order is total and
  `offset` pages cannot repeat or skip anyone. Most accounts tie on
  `followers_count = 0`, so without it Postgres was free to shuffle them between
  requests.
- **Results are built by hand, not via `from_attributes`** (`users.py:401`), so a
  moderated `display_name` cannot leak through.
- Rate-limited **30/minute**. `limit` 1–100, `offset` ≥ 0.

### Place search

Not a backend feature. `placeSearchProvider` / `mapPlaceSearchProvider` call
`core/services/geocoding_service.dart` (OpenStreetMap / Nominatim), and results
are localised to the app language. There is no Ntripi endpoint involved and no
Google Maps SDK — see [constraints.md](../constraints.md#frontend).

## Data model

No tables of its own. Two **partial indexes** on `itineraries` exist solely for
the feed sorts, and both live **only in migration `98fa3c7b7229`**, not in the
ORM models:

| Index | Columns | Predicate |
|---|---|---|
| `ix_itineraries_feed_recent` | `created_at DESC, id DESC` | `WHERE visibility = 'public'` |
| `ix_itineraries_feed_top` | `rating_avg DESC, rating_count DESC, created_at DESC, id DESC` | `WHERE visibility = 'public'` |

Being migration-only, **neither is exercised by the test suite** — see
[Migration-only objects](../reference/data-model.md#migration-only-objects).

## API surface

| Method | Path | Auth | Query | Response |
|---|---|---|---|---|
| GET | `/itineraries/feed` | user, 30/min | `sort=top\|recent` (default `recent`), `limit` 1–50 (default 20), `offset` ≥0, `lang` optional (`^[a-z]{2}$`) | `list[ItineraryFeedItem]` — `…, owner, source_lang, title_translation` |
| GET | `/users/search` | user, 30/min | `q` (min 1 char), `limit` 1–100 (default 20), `offset` ≥0 | `list[UserSearchResult]` |

`ItineraryFeedItem` = `ItinerarySummary` + `owner: RaterInfo`.

Both are GETs, so both go through `ETagMiddleware` and answer 304 on an unchanged
page.

## Flutter surface

- **`FeedScreen`** — route `/feed`, its own shell branch (branch 5).
  - `feedProvider` — `AsyncNotifierProvider`, the loaded pages. `loadMore` skips
    ids already shown (one trip published between pages shifted every row down
    one and repeated the last card), drops a page that belongs to a list rebuilt
    under it by a sort change, and never throws — it runs from the scroll
    listener.
  - `feedSortProvider` — `NotifierProvider`, the Top/Recent toggle.
  - `feedProvider` also watches the app language and sends it as `lang` on
    every page and refresh, so a language change refetches page 0 under its own
    cache key.
  - `feedRepositoryProvider` → `FeedRepository`.
  - `FeedCard` + `OwnerAttributionRow` render each row. A card with a
    `title_translation` in the app language renders `FeedTitle`: the title as
    written when its language is among the reader's profile `languages`, else
    the translation with a lit marker — either way one tap, with no request,
    flips it ([translations.md](translations.md#flutter-surface)).
- **`SearchScreen`** — route `/search`, shell branch 1, with nested
  `/search/profile/:userId` and its `followers` / `following` children.
  - `searchQueryProvider` — `NotifierProvider`, the query string.
  - `searchResultsProvider` — `AsyncNotifierProvider`.
  - `searchRepositoryProvider` → `SearchRepository`.
- `OwnerAttributionRow` (`shared/widgets/editorial_widgets.dart`) takes plain
  nullable strings rather than a `FeedOwner`, so `shared/` never imports a
  feature's domain layer.

## Known gaps / TODOs

- **Both feed indexes are untested** (migration-only, and the suite is SQLite).
  A sort regression would not fail any test.
- `test_feed_smoke.py` covers the feed shallowly; there is no test for the `top`
  threshold behaviour at the boundary.
- Search is `ILIKE`-based with no trigram index, so it is a table scan against
  `users`. Fine at current scale; there is no comment recording a plan for when
  it is not.
- `README.md:283` names a "real-time feed" as upcoming — see
  [backlog.md](../backlog.md).

## Related

- [itineraries.md](itineraries.md) — the payload shape
- [visibility-and-access.md](visibility-and-access.md) — `public_listing_criteria`
- [blocking.md](blocking.md) — filtered in both queries
- [ratings.md](ratings.md) — what `top` sorts on
- [accounts-and-profiles.md](accounts-and-profiles.md) — `public_profile_text`, profile reads
- [saved-itineraries.md](saved-itineraries.md) · [sharing.md](sharing.md)
- [etag-concurrency.md](etag-concurrency.md) — 304 on both
- [translations.md](translations.md) — the title translation on each card
- [reference/data-model.md](../reference/data-model.md)
