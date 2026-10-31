# Places and maps

> **Status:** shipped (off by default). Google place search is off until
> `GOOGLE_PLACES_API_KEY` is set; Google maps are off until
> `GOOGLE_MAPS_EMBED_API_KEY` is set. OpenStreetMap search always works.

## Purpose

How a stop gets its location, and every map that shows one. A stop is placed
by an OpenStreetMap search, a pin on Ntripi's own map, a Google Places search,
or a pasted Google Maps link. Google places and links are shown on Google's
free Maps Embed API, never on an OpenStreetMap map. The trip page's map is
Google's route through the stops on screen.

## Rules

### OpenStreetMap first, on submit

- **OSM is always asked first**, and only when the user submits the search
  (the keyboard's Search key or the arrow), never as they type — in the form's
  Coordinates segment, its Google Maps segment, and the map picker.
  Nominatim's usage policy forbids search-as-you-type, and its one request per
  second is for the whole app (`PlaceSearchBox`, `map_picker_screen.dart`
  `_submitSearch`).
- **Google is the Google Maps segment's fallback**: a **Search on Google Maps**
  row under OSM's results, and a switch of its own when a *submitted* OSM search
  comes back empty. Once on Google, suggestions follow the typing after a 500 ms
  pause, from 3 characters (`GooglePlaceSearchNotifier`); clearing the field
  goes back to OSM. The Coordinates segment never asks Google.
- **A submitted OSM search always answers**, in all three boxes: its places,
  "No places found", or why it failed (offline, Nominatim down) — never
  nothing, and in the map picker never just the pin instructions. In the
  Google Maps segment the **Search on Google Maps** row stays under a failure.
  A failure never asks Google by itself — only an empty answer does, so a
  Nominatim outage cannot spend paid requests.
- **Each list carries its source's attribution**: "© OpenStreetMap
  contributors" under OSM's results, "Google Maps" under Google's (Google's
  policy for predictions shown without a Google map).
- **A pick folds the list away, it does not delete it**, in all three boxes:
  the field keeps the words, the answer stays in memory, and the list comes
  back when the user is in the field again — a tap, or focus, since a screen
  reader's activation and Tab never call `onTap`. Choosing another place from
  the same search sends no request. The form's two answers live in
  `autoDispose` providers and go with the form — Google's with the Google Maps
  segment too — so the next form never opens on the last search. Only the map
  picker's pin, which did not come from the list, empties the form's box.

### What a stop may store

- **The only Google content a stop keeps is a place ID** (Google's terms allow
  storing place IDs indefinitely, nothing else). A Google pick stores
  `google_place_id` and `google_place_query` — the text the *user* typed, never
  Google's suggestion — and no coordinates, address or link.
- **The stop's name is always typed by the user** for a Google pick or a link.
  An OSM pick fills the name only when it is empty, plus the address and the
  coordinates (OSM data is open); the Coordinates segment and the map picker
  follow the same rule (`_applySuggestion`).
- **A pasted link is stored as typed and never fetched by the form**, and no
  coordinates are ever stored beside it. The server reads a `ChIJ…` place ID
  out of the link's own text into `google_place_id`
  (`services/stop_location.extract_place_id`). The stop page still unfurls a
  link for its preview, by the user's choice (decisions.md 2026-10-31).
- **`services/stop_location.normalize` holds every client to this**, including
  installed builds that still send a link's coordinates: a `map_url` clears
  `lat`/`lng`; a Google stop stays Google while a body without `place_source`
  sends null coordinates; non-null coordinates on a Google stop make it an
  ordinary one. The refresh stamps move only when the stored ID changes.
- **The database enforces it too**: `ck_stops_place_id_no_coords` and
  `ck_stops_link_no_coords`.
- **`place_source`** records where every location saved since 2026-10-31 came
  from: `osm`, `google`, `link` or `typed`. The stop page prints a credit line
  under the location: "Place data © OpenStreetMap contributors" for `osm`,
  "Google Maps" for `google` and `link`. Older rows have none.
- **The search text is moderated** with the stop's name, address and notes
  (`_STOP_TEXT_FIELDS`), and re-checked by the sweep after an outage. Readers'
  devices receive it: it is the fallback query of Open in Google Maps.

### Asking Google

- **Only through our server** (`POST /places/google/autocomplete`): the key
  never ships in an app build. A verified account; 60 requests per user per
  clock hour (`GOOGLE_PLACES_USER_HOURLY_LIMIT`, conditional upsert in
  `database.reserve_within_limit`); a per-IP slowapi guard in front.
- **No Place Details call, ever.** Each suggestion already carries its
  `placeId`. A session ended by a paid Place Details call would still bill
  every request (up to 12) plus the call; one ended by the free IDs-only call
  is billed exactly like no session.
- **What crosses to Google**: the text, the app language, and a bias circle
  (50 km) whose centre is rounded to 0.1° on the server — never a user, stop or
  trip identifier. The answer is passed through with `Cache-Control: no-store`,
  never logged (`services/google_places.py` logs status codes and exception
  classes only), and the POST is never kept by the app's HTTP cache.
- **The bias** is the trip itself: the alternative in the same track, else the
  nearest earlier track's stop, else the trip's first stop with coordinates.
  Only a trip with no coordinates at all falls back to the device's position,
  rounded to 0.1° (`domain/search_bias.dart`). OSM gets the same anchor as its
  preferred `viewbox`. The Privacy Policy discloses both.

### Showing a place

- **Every Google map is a page on our server**: `/embed/place?id=`,
  `/embed/point?lat=&lng=`, `/embed/search?q=` (only the stop page's link
  preview, for a link it could name but not place) and
  `/embed/directions?points=` (2–22 points). The page frames Google's Maps
  Embed API with `GOOGLE_MAPS_EMBED_API_KEY`. Phones load it in a WebView,
  which finally gives Google a real referrer; the web app frames it.
  `GoogleEmbed` (`data/google_embed_urls.dart`) is the only builder of these
  addresses.
- **The parameter is `language`, never `lang`**: `LanguageCookieMiddleware`
  would write the site's cookie from `?lang=`. That middleware leaves `/embed`
  alone entirely.
- **Strict input**: only the documented parameters, each validated (place-ID
  alphabet, finite coordinates in range, ≤ 200-character queries,
  `i18n.SUPPORTED` languages). Anything else is a 400 that echoes nothing.
  Unset key → 404, and `/places/config` tells the app to draw no Google map.
- **`/embed/*` is the only path family our own pages may frame**: CSP
  `frame-ancestors` from `EMBED_FRAME_ANCESTORS` (default `'self'`; a bare
  `self` is quoted), `X-Frame-Options: SAMEORIGIN` for old browsers, and nothing
  loadable but Google's frame. Every other path keeps `DENY` / `'none'`.
- **Maps are display-only** on both platforms; the card or route around them
  takes the tap.

### Opening in Google Maps

- A Google place opens by its ID:
  `maps/search/?api=1&query=<search text>&query_place_id=<id>` (`query` is
  required; Google reads it only if the ID fails). A place Google lost searches
  its text alone.
- The route link carries `origin_place_id` / `destination_place_id`, and
  `waypoint_place_ids` only when every waypoint has one (they pair one to one).

### The trip page's map

- **The List/Map toggle's Map view is Google's route**: one point per track —
  the alternative on screen, as the route link — through `tripRoute`; up to 22
  points (past that the first 21 and the last, with the truncation note); one
  point shows that place; none shows an empty state. The toggle is hidden
  while Google maps are off.
- **Stops nothing locates are left out and counted**: a short link (its text
  names no place) and a place Google lost. The form warns when a short link is
  pasted that it cannot appear on the map.

### The yearly refresh

- The sweep (`sweep_service._refresh_place_ids`) confirms place IDs checked
  more than `GOOGLE_PLACE_REFRESH_DAYS` (365) ago, at most
  `GOOGLE_PLACE_REFRESH_BATCH` (100) per run, with the free IDs-only Place
  Details call. It commits before calling Google; each write is conditional on
  the ID it read, so an editor's new pick wins. The itinerary's `updated_at`
  never moves.
- Same ID → stamped; a new ID → stored; `NOT_FOUND` (or a 400 naming the place
  ID) → `google_place_missing_at`, and the place is never re-found
  automatically; anything else stops the batch.
- A lost place shows no map. Its readers' Open in Google Maps searches the
  stored text; an editor sees "Google can't find this place anymore" with
  **Search again**, and the form opens with the search pre-filled.

## Data model

`stops` — [reference/data-model.md](../reference/data-model.md#stops):
`place_source`, `google_place_id`, `google_place_query`,
`google_place_checked_at`, `google_place_missing_at`, the three CHECKs and the
partial index `ix_stops_google_place_refresh`.

`place_search_usage (user_id, hour_start, requests)` — the hourly budget.
Holds no text; purged by the sweep after 2 days.

Migrations `70035c01ad25` (columns, the one-time clearing of coordinates
beside every existing link, `NOT VALID` checks, the table) and `87528b459c5b`
(`VALIDATE CONSTRAINT` and the index built `CONCURRENTLY`).

## API surface

| Method | Path | Notes |
|---|---|---|
| GET | `/places/config` | `{google_search, google_maps}`; signed in |
| POST | `/places/google/autocomplete` | `{input 3–200, language, bias?}` → `{suggestions: [{place_id, main_text, secondary_text}]}`; verified email; 429 `place_search_rate_limited` (with `Retry-After`), 503 `place_search_unavailable`, 404 without the key |
| GET | `/embed/place`, `/embed/point`, `/embed/search`, `/embed/directions` | public HTML frames (`MAP_EMBED` in `test_public_surface.py`) |
| POST / PATCH | `/itineraries/{id}/stops[/{stop_id}]` | gain `place_source`, `google_place_id`, `google_place_query`; the answer gains them plus `google_place_missing`, after `source_lang` |

## Flutter surface

- `presentation/widgets/place_search_box.dart` — the one search box (OSM on
  submit, Google fallback, attributions; a pick folds its list).
- `presentation/stop_form_screen.dart` — `_LocationMode { coordinates, google }`;
  `_locationPayload()` sends `place_source` and the Google fields only when the
  location changed this session, so an ID the refresh replaced meanwhile is
  never written back.
- `presentation/widgets/google_map_embed.dart` + `map_embed_web_view_web.dart`
  — every Google map; `link_preview_card.dart` — the stop page's card (link,
  coordinates, Google place).
- `domain/map_point.dart`, `domain/trip_route.dart`, `domain/search_bias.dart`,
  `data/google_maps_links.dart` (string parsing only), `data/places_repository.dart`,
  `providers/places_providers.dart`.
- Guards: `test/stop_form_link_fetch_guard_test.dart` (the form never reaches
  the link fetcher), `test/google_embed_source_guard_test.dart` (no embed URL or
  key in `lib/`, the Dockerfile or the scripts).

## Config

`GOOGLE_PLACES_API_KEY` (server only; restrict to Places API (New)),
`GOOGLE_MAPS_EMBED_API_KEY` (restrict to the Maps Embed API and the website
referrers `https://ntripi.app/*` plus the dev API host),
`GOOGLE_PLACES_USER_HOURLY_LIMIT=60`, `GOOGLE_PLACES_TIMEOUT_SECONDS=5`,
`GOOGLE_PLACE_REFRESH_DAYS=365`, `GOOGLE_PLACE_REFRESH_BATCH=100`,
`PLACE_SEARCH_RATE_LIMIT=60/minute`, `EMBED_RATE_LIMIT=240/minute`,
`EMBED_FRAME_ANCESTORS=self`. Autocomplete past the 10,000 free requests a
month is paid: watch it with a Google Cloud budget alert.

## Known gaps / TODOs

- **The Google attribution is the text "Google Maps"**, which Google's policy
  allows where space is short; the logo asset is not vendored.
- **A bug-report screenshot can capture Google's suggestions** while they are on
  screen; it is kept under bug-report retention (see backlog.md).
- **The stop page's link preview still fetches the link** for every reader, by
  the user's choice; only the form stopped.
- **Nominatim's one request per second is for the whole app**: past early
  traffic, OSM search needs a self-hosted or paid geocoder (backlog.md).
- **Mixed waypoint lists** send the text of the place waypoints instead of
  their IDs (`waypoint_place_ids` pairs one to one); not yet checked on a
  device.

## Related

- [tracks-and-stops.md](tracks-and-stops.md) — the stop columns and `map_url`
- [feed-and-search.md](feed-and-search.md) — the place search
- [itineraries.md](itineraries.md) — the route link and the trip page's map
- [text-moderation.md](text-moderation.md) — the search text is scanned
- [legal-and-age-gate.md](legal-and-age-gate.md) — Terms 3.2 and Privacy 2.5 name Google Maps Platform
- [web-and-platform.md](web-and-platform.md) — `/embed/*` headers and the framing exception
- [admin-and-appeals.md](admin-and-appeals.md) — the sweep that refreshes place IDs
- [help-centre.md](help-centre.md) — `/help/add-locations-from-google-maps`
- [reference/error-codes.md](../reference/error-codes.md) — `place_search_rate_limited`, `place_search_unavailable`
- [decisions.md](../decisions.md) — 2026-10-31
