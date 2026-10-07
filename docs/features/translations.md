# Translations

**Status:** in progress — shipped dark. The backend translates on request
(`POST /translations`) and the app offers "See translation" wherever there is
text to swap, but both stay invisible until `TRANSLATION_PROVIDERS` is set.
**Tables:** `content_translations`, `translation_user_usage`,
`translation_provider_usage` · `source_lang` on six content tables
**Config:** `TRANSLATION_DETECT_LANGS`, `TRANSLATION_PROVIDERS` and the other
`TRANSLATION_*` / `AZURE_TRANSLATOR_*` settings below

## Purpose

Letting a reader see trips, notes and reviews in their own language. What exists
today is what every later piece depends on: each piece of translatable text
knows which language it is written in, and a cache table whose rows can never
outlive, or drift from, the text they were made from.

## Rules

### What is translatable

`translation_service.REGISTRY` is the single list:

| Content type | Table | Fields |
|---|---|---|
| `itinerary` | `itineraries` | `title`, `description`, `recommended_period_note` |
| `itinerary_annotation` | `itinerary_annotations` | `content` |
| `stop` | `stops` | `notes` |
| `stop_annotation` | `annotations` | `content` |
| `rating` | `itinerary_ratings` | `note` |
| `transport_leg` | `transport_legs` | `notes` |

- **Place names are not translatable** — `stops.place_name`, `place_address`,
  and a leg's `line` and `direction`. Nothing records whether a stop name was
  typed or filled in from OpenStreetMap or a Google Maps link, and either way
  it names a place.
- **Every row of these tables belongs to exactly one itinerary** — stop
  annotations through `stops`, legs through `transit_segments`. That is the
  premise of `content_translations.itinerary_id`.

### Source language

- **Detected at save time**, locally, by `lingua-language-detector`
  (`services/language_detection.py`) — no request, nothing leaves the server.
  High-accuracy mode, because trip titles are short.
- **Stored as `source_lang`**, ISO 639-1, on the row. An itinerary's language is
  read from title + description + period note together; a stop's from its notes
  only, so a French place name cannot make English notes read as French.
- **`NULL` means "not detected confidently"** — the best language must beat the
  runner-up by a margin (`_MIN_RELATIVE_DISTANCE = 0.1`), and text with fewer
  than three letters, or only URLs, mentions and emoji, is never labelled.
  Measured on short trip titles in eight languages: about one confident answer
  in forty was wrong at 0.1, against one in ten at 0.0. An undetected text is
  harmless; a wrong one can hide the translate button from a reader who needs
  it.
- **Detection never raises.** A write must not fail because detection did.

### The cache follows its source text

- A row is keyed by **`(content_type, content_id, field, target_lang,
  source_hash)`**. The hash is sha256 of the NFC-normalised text with `\r\n`
  folded to `\n` and the ends stripped (`translation_service.source_hash`). The
  source text itself is never stored.
- **Every write of translatable text calls `sync_translations`** before the
  commit: it re-detects `source_lang` and deletes the row's translations whose
  hash no longer matches its current text — in the edit's own transaction. Ten
  write paths in `routers/itineraries.py`: `create_itinerary`,
  `update_itinerary`, `add_stop`, `update_stop`, `_save_annotation` (both
  annotation tables, create and update), `upsert_rating`, `create_segment`,
  `update_segment`, `add_leg`, `update_leg`. A body that names no translatable
  field skips it.
- **Deleting a trip or an account needs nothing**: `itinerary_id` is a real FK
  with `ON DELETE CASCADE`.
- **Every delete below the itinerary calls `purge_orphans(db, itinerary_id)`**
  after its flush: `_delete_annotation`, `delete_stop`, `delete_my_rating`,
  `update_segment` (it replaces every leg), `delete_segment`, `delete_leg`, and
  `reorder_itinerary` when it deletes segments. It deletes the trip's
  translations whose content row is gone, rather than naming what was deleted —
  a stop's annotations and its segments' legs are removed by the database, out
  of the application's sight.
- **A review outlives its author anonymised, and so do its translations.**
  Account deletion sets `itinerary_ratings.user_id` to NULL; the review and its
  translation stay.
- **No user reference** anywhere in `content_translations`.

### The engines

- **`translation_service.run_chain(fields, target_lang, settings)`** translates
  a batch: each engine in `TRANSLATION_PROVIDERS` order gets only the fields the
  engines before it could not translate, split into batches it can take. A
  field nobody translated is reported back, never invented.
- **Two engines** (`services/translation_providers.py`), behind one
  `Translator` protocol — a new provider is a class plus an entry in
  `_FACTORIES`:

  | Name | What | Notes |
  |---|---|---|
  | `openai` | Responses API, `TRANSLATION_MODEL` (default `gpt-6-luna`) | strict `json_schema` built from the batch's keys; `store: false`; `reasoning.effort` from `TRANSLATION_REASONING_EFFORT` (empty omits it); a 429 `insufficient_quota` counts as quota exhausted |
  | `azure` | Azure AI Translator, REST v3 | a bare `[{"Text": …}]` array, no `from` so Azure reports the source per text; `zh` is sent as `zh-Hans`; a 403 means the free tier's characters are spent |

- **What leaves the server** is the texts, the target language and what the
  engine needs to process them — never a user id, an email, a content id or a
  field name. OpenAI receives the texts under opaque keys (`t0`, `t1`, …) and
  is told not to store the response.
- **Every translation is checked before it counts**
  (`services/translation_validation.py`): not empty; every URL and @mention
  kept verbatim; the same emoji and pictographic symbols; the same number of
  non-empty lines; and a length ratio inside 0.3–3.5 (0.12–7 when either side
  is Chinese, Japanese or Korean; skipped under 12 characters). A failure sends
  that field — only that field — to the next engine.
- **Output moderation**, when text moderation is on and
  `TRANSLATION_MODERATE_OUTPUT` is true: the batch's translations are scored in
  one call (`score_many`) and anything the policy would `reject` or
  `hide_escalate` fails. A translation is machine output served to every later
  reader, so an instruction hidden in the source must not be able to talk a
  model into caching something nobody typed. **It fails closed** — with no
  classifier answering, nothing new is translated and the original stays on
  screen. No decision rows are written: this is not user content.
- **An engine that fails a batch is not retried for the rest of the request**
  — an outage or an empty quota does not clear in a second.
- **Logs carry sizes and outcomes only**: provider, model, field count,
  characters in and out, latency, and failure reasons by count. Never a text,
  a key or a content id.

### Who may have what translated

- **A reader can only ever have translated what they can read.** The client
  names content (`content_type` + `content_id` + fields) and never sends text;
  the server loads the text itself.
- Access is the one ladder, checked **once per trip** for a batch:
  `can_view_itinerary` for every content type (a stop annotation through its
  stop, a leg through its segment), plus `can_view_rating` for a review — the
  row-level twin of the ratings page's filters (`itinerary_access.py`).
- **Content under a takedown is never translated, even for its author** — a
  trip with `hidden_at` or a hidden/rejected `moderation_status`, a review with
  a hidden/rejected status. The owner may still see it; nothing legitimate
  needs it translated, and translating it would send taken-down text to a
  third party.
- **Missing, forbidden and taken down all answer `not_found`**, item by item —
  nothing is learnt by asking.

### Answering a request

`translation_service.translate_items`, in order:

1. Load the named rows, one query per content type.
2. Check access per trip (above).
3. Answer `empty` for a blank field and `same_language` when the row's
   `source_lang` already is the target — neither reaches an engine.
4. Answer from `content_translations` where `(type, id, field, target)` matches
   the **current** text's hash.
5. Reserve the misses against the reader's hourly quota (below); over it, the
   misses answer `rate_limited` and the cache hits are still served.
6. **Commit before any engine is called** — the reservation lands, and no
   pooled connection waits on a provider.
7. Run the chain on the misses, then cache the successes with
   `INSERT … ON CONFLICT DO NOTHING` — two readers missing the same text at once
   both insert, and the second is a no-op. An engine that found the text
   already in the target language is cached as such and answered
   `same_language`. A trip deleted while its text was out for translation fails
   the foreign key; the reader still gets the answer, the cache does not keep
   it. **Failures are never cached.**

### What it may cost

- **Per reader: `TRANSLATION_USER_HOURLY_LIMIT` fields per clock hour** (200),
  counting only fields that reach an engine — a translation somebody already
  paid for is free to read. All-or-nothing per request.
- **Per engine: characters per UTC day** — `TRANSLATION_DAILY_CHAR_BUDGET` for
  OpenAI (500k), `AZURE_TRANSLATOR_DAILY_CHAR_BUDGET` for Azure (60k, which
  keeps the F0 tier inside its 2M characters a month). Each batch reserves its
  characters before the call; a refused reservation skips that engine. An
  engine that answers that its own quota is gone (OpenAI's 429
  `insufficient_quota`, Azure's 403) has its day filled so it is not asked again
  before midnight UTC. Every engine spent → `unavailable`, and the reader keeps
  the original.
- **Both are one atomic conditional upsert** (`services/translation_usage.py`):
  the UPDATE fires only while the new total stays within the limit, so a
  refused reservation counts nothing and no total can pass its cap. Each
  reservation commits at once — characters sent are spent, whatever happens to
  the request.
- `POST /translations` is also `60/minute` per IP, against request floods —
  cache hits cost nothing to serve but a query.

### Titles translated ahead of the reader

- **A public trip's title is translated into `TRANSLATION_PRETRANSLATE_LANGS`**
  (all six by default, minus the title's own language) in a FastAPI background
  task, so a feed card needs no request of its own.
- **Only when strangers start to read a title**: a public trip created, a trip
  made public, or a public trip's title changed. Drafts are `only_me` by
  default, so saving one never spends a translation; `followers` and
  `restricted` trips, description and note edits, and stop or annotation saves
  never schedule it.
- The task runs after the response, on **its own session** (the request's is
  gone by then; `_session_factory` is the test seam, as in push). It re-reads
  the trip and skips it unless it is public, live, not taken down and its owner
  not banned; it translates only the languages not already cached for the
  current title. Engine budgets apply; no reader's quota does. It never raises
  — a reader tapping "See translation" is the fallback.

### Housekeeping

- The moderation sweep's `_purge` runs `translation_service.purge_for_sweep`
  (counter `translations_purged`): translations whose content row is gone (the
  safety net behind every delete path's `purge_orphans`), translations of
  trips a moderator removed (`deleted_at` — restoring one just means translating
  again), reader counters older than 2 days and engine counters older than 90.
- `scripts/purge_translation_orphans.py [--dry-run]` runs the same thing by
  hand; the sweep already runs whichever driver is configured, so no extra
  scheduler is needed.

### API contract

`source_lang` is **appended last** to `ItineraryDetail` (after `can_edit`),
`StopResponse`, `AnnotationResponse`, `ItineraryAnnotationResponse`,
`TransportLegResponse` and `RatingWithUser`. `ItinerarySummary` is unchanged —
a new key there would reorder `/me`, `/saved` and `/feed`.
`ItineraryFeedItem` gains `source_lang` and `title_translation` **after
`owner`** (so `/feed` and `/shared-with-me` keep their order up to there).

## Data model

`content_translations`, plus a nullable `source_lang` TEXT column on
`itineraries`, `itinerary_annotations`, `stops`, `annotations`,
`itinerary_ratings` and `transport_legs`; the two usage counters. Full columns:
[reference/data-model.md](../reference/data-model.md#content_translations).
Migrations: `f05c373d1b6c` (columns and cache), `1afc3c26511a` (counters).

## API surface

| Method | Path | Auth | Request | Response | Errors |
|---|---|---|---|---|---|
| GET | `/translations/config` | user | — | `{enabled, target_langs}` — `target_langs` empty when off | 403 signed out |
| GET | `/itineraries/feed?lang=xx` | user | `lang` optional, `^[a-z]{2}$` | each item adds `source_lang` and `title_translation: {lang, text} \| null` | 422 malformed `lang` |
| POST | `/translations` | user, `60/minute` per IP | `{target_lang, items: [{content_type, content_id, fields}]}` — at most 50 items, fields from the registry for that type | `{target_lang, items: [{content_type, content_id, status, fields: {name: {status, text, provider, source_lang}}}]}` | **404 when `TRANSLATION_PROVIDERS` is empty**; 400 `translation_language_unsupported`; 422 malformed |

- Item `status`: `ok` or `not_found`.
- Field `status`: `translated` (with `text`), `same_language`, `empty`,
  `rate_limited` (the reader's hourly quota is spent) or `unavailable` (every
  engine failed or is out of budget — the client keeps the original).
- The feed carries a `title_translation` only when translation is on, `lang` is
  a supported target, the cache holds one for the **current** title, and
  neither the trip nor the cached row says the title already is in `lang`.
  `shared-with-me` reuses the item schema and always carries `null` there.
- The language travels **in the body** of the POST and **in the query string**
  of the feed, never in `Accept-Language`: one explicit, validated value, and
  the feed's URL stays the client cache's whole key (`<JWT sub>:<url>`).
- `source_lang` also rides in the six content responses listed above.

## Flutter surface

`lib/features/translation/`: `domain/translation.dart` (statuses, results,
config), `data/translation_repository.dart`,
`providers/translation_providers.dart`, `presentation/translatable_text.dart`.

| Surface | Group (its anchor) | What swaps | Toggle |
|---|---|---|---|
| Trip detail | `('itinerary', id)` | hero title, description, best-time note, every trip-wide note chip | under the description; read mode only |
| Stop page | `('stop', id)` | notes and every annotation — never the place name | under the time and cost stats |
| Ratings page | `('rating', id)`, one per review | the review note | under the note |
| Feed card | none — the feed page carries it | the title, by the spoken-languages rule | the translate icon beside the title |

- **One toggle per group, one request per tap.** `TranslationToggle` names the
  group's members; every `TranslatableText` in the group watches the same
  `contentTranslationProvider((contentType, contentId, targetLang))` notifier,
  so the whole group swaps at once. A one-line note chip has no room for a link
  of its own.
- **The toggle is absent when a tap could do nothing:** the config is off or
  unread (`translationConfigProvider` falls back to `TranslationConfig.disabled`),
  the app language is not a server target, or every member's `sourceLang`
  already is the app language. An undetected (`null`) `sourceLang` still offers
  it; when the server then answers `same_language` for everything, the toggle
  hides until the text changes.
- **The target is always the app language** (`localeProvider`), the same rule
  as the server's.
- **The client names content and never sends text.** It asks only for members
  not already in the reader's language, only for non-blank fields, and only for
  fields with no answer for their current text. More than 50 members go out in
  several requests (`kMaxTranslationItemsPerRequest` mirrors the server).
- **An answer shows only while the original it was made from is still on
  screen.** The notifier keeps, per field, the text each answer was made from.
  An edit or a refresh that changes the text makes it stale: the original
  shows, and the next tap asks for that field alone.
- **Transient answers are never kept.** `unavailable`, `rate_limited`,
  `not_found` and a failed request leave the original on screen with a one-line
  reason, and the next tap asks again — the client half of "failures are never
  cached". A partly translated group still shows what did translate.
- **A 404 or 400 from the POST re-reads the config**: translation was switched
  off, or the language withdrawn, since the button was drawn — and the button
  goes with it.
- **Offline**, a tap that needs the network shows `showOfflineHint`;
  translations already held still swap instantly.
- **Read mode only.** On the trip detail screen every `TranslatableText` takes
  `enabled: !_editMode`, so whoever is editing reads what they are changing. The
  stop page has no edit mode.
- **Never offered on a takedown the client can see** — the author's own hidden
  review, or a trip whose `hidden` flag is set (the trip detail screen and its
  stop pages). The server would answer `not_found`, since a takedown is never
  sent to an engine; status-only takedowns the client cannot see still meet
  that answer, shown as "unavailable".
- **A translation is wrapped in a `Directionality` set by its own language.**
  Today that is always the app's, so it restates the ambient direction; it keeps
  translations right if the two ever differ.
- **The feed rule** (`FeedTitle` in `feed_card.dart`): a title whose
  `source_lang` is among the reader's profile `languages` (stored upper case,
  compared lower-cased) shows as written, with a quiet translate icon that flips
  it. Any other title shows translated, with the icon lit as a marker whose
  screen-reader label is "Translated title. See original". The flip is local
  state: no request. A page fetched before a language switch
  (`titleTranslation.lang` differs from the app language) shows the original.
- **`FeedNotifier` watches the app language** and sends it as `lang` on every
  page and refresh, so changing language refetches page 0 under its own cache
  key.
- **Session:** both providers are keep-alive and in `_userScopedProviders`
  (reset on sign-in and sign-out). Signed out, the config answers "off" without
  a request. A failed config read also answers "off", and is asked again on the
  next return to the foreground or the network — never on a timer, since
  auto-retry is off app-wide.
- `translation_language_unsupported` maps to
  `apiErrorTranslationLanguageUnsupported`.
- `TransportLeg` carries no `sourceLang`: no screen shows leg notes to a viewer.
- Tests: `test/models/translation_models_test.dart`,
  `test/repositories/translation_repository_test.dart`,
  `test/providers/content_translation_test.dart`,
  `test/widgets/translation_toggle_test.dart`,
  `test/widgets/feed_title_test.dart`.

## Operations

- **Switching it on**, in this order — the feature ships dark:
  1. Run the backfill below in the Railway container, dry run first.
  2. Create an Azure Translator resource on the free F0 tier; set
     `AZURE_TRANSLATOR_KEY` and `AZURE_TRANSLATOR_REGION`. Confirm
     `OPENAI_API_KEY` is set and add a budget alert on the OpenAI project.
  3. Deploy Privacy 2.3 and the help article **before** the next step: an
     engine the privacy policy does not name is an undisclosed processor.
  4. Set `TRANSLATION_PROVIDERS=openai,azure` and redeploy. Smoke-test with the
     app in French and in Arabic: trip detail, stop page, ratings, feed.
  5. For a week, watch the fallback reasons and latency in the logs,
     `translation_provider_usage`, and both providers' usage dashboards.
  6. Update the App Store privacy label and Play Data safety: Microsoft is a
     new processor.
- **Switching it off**: unset `TRANSLATION_PROVIDERS`. The POST 404s, the
  config answers `enabled: false`, and the feed stops carrying titles. A running
  app reads the config once per session, so its buttons go at the next launch
  or sign-in — or the moment a tap meets the 404, which re-reads it. Cached rows
  are harmless and can be purged.
- **Backfill**, once per environment after the migration:
  `python scripts/backfill_source_lang.py --dry-run`, then without
  `--dry-run`, from `social_api/`. It walks each table in id order, reads only
  rows whose `source_lang` is NULL, and writes with a Core `UPDATE` that sets
  `updated_at` to itself, so neither the itinerary ETag nor a review's date
  moves. Safe to re-run.
- **Clean-up by hand**: `python scripts/purge_translation_orphans.py --dry-run`
  prints exactly what the sweep would remove (it does the work and rolls back).
- **Memory**: detection loads lingua's models lazily, per candidate language.
  With all 75 languages enabled, the process grew from about 10 MB to about
  76 MB on macOS after detecting a 14-language sample. `TRANSLATION_DETECT_LANGS`
  narrows the list if memory becomes tight.

## Config

| Var | Default | Notes |
|---|---|---|
| `TRANSLATION_DETECT_LANGS` | `all` | `all`, or comma-separated ISO 639-1 codes; a malformed value **raises at startup**. A shorter list loads fewer models, but text in another language is then forced onto its nearest neighbour in the list |
| `TRANSLATION_PROVIDERS` | empty | engines in the order to try them: `openai`, `azure`. Empty = translation off. An unknown or repeated name, or a provider without its key, **raises at startup** |
| `TRANSLATION_MODEL` | `gpt-6-luna` | reuses `OPENAI_API_KEY` |
| `TRANSLATION_REASONING_EFFORT` | `none` | empty omits the parameter; the lowest value differs per model (`minimal` for the gpt-5 family) |
| `TRANSLATION_TIMEOUT_SECONDS` | `10.0` | per engine call; must be positive |
| `AZURE_TRANSLATOR_KEY` / `_REGION` / `_ENDPOINT` | — / — / `https://api.cognitive.microsofttranslator.com` | the region is required for a regional or multi-service resource |
| `TRANSLATION_SUPPORTED_LANGS` | `en,fr,es,de,ar,zh` | target languages; each must be in `constants/translation_languages.py`, or startup **raises** |
| `TRANSLATION_MODERATE_OUTPUT` | `True` | only acts while `TEXT_MODERATION_PROVIDER` is not `disabled` |
| `TRANSLATION_USER_HOURLY_LIMIT` | `200` | fields per reader per clock hour that reach an engine; ≥ 1 |
| `TRANSLATION_DAILY_CHAR_BUDGET` | `500000` | OpenAI's characters per UTC day |
| `AZURE_TRANSLATOR_DAILY_CHAR_BUDGET` | `60000` | Azure's characters per UTC day — inside F0's 2M a month |
| `TRANSLATION_PRETRANSLATE_LANGS` | `en,fr,es,de,ar,zh` | languages public titles are translated into ahead of time; empty = off; must be a subset of the supported languages, or startup **raises** |

## Known gaps / TODOs

- **Only the feed carries translated titles.** Saved, profile and
  shared-with-me lists show the title as written.
- **An original is laid out by the app's direction, not its own.** An Arabic
  review reads left to right in an English app; only translations are wrapped
  by their language.
- **A feed card's flip is per card instance.** Scrolled far enough to be
  rebuilt, the card goes back to the spoken-languages rule.
- **Three-letter spoken-language codes never match** a detected ISO 639-1
  code, so those readers get the translated feed title.
- **Transport-leg notes are translatable on the server only** — no screen shows
  leg notes to a viewer today.
- **lingua reports Chinese without telling Simplified from Traditional** — both
  are stored as `zh`.
- **Azure's quota is read off HTTP 403.** Microsoft documents a 403 as
  "often" meaning the free characters are spent; a 403 for another reason (a
  resource misconfigured in the portal) reads the same way, and the field falls
  through to `unavailable` like any other failure.
- **Rows that stay undetected are re-read by every backfill run.** Harmless
  (the run is bounded and changes nothing for them), but not free.

## Related

- [itineraries.md](itineraries.md) · [annotations.md](annotations.md) ·
  [ratings.md](ratings.md) · [tracks-and-stops.md](tracks-and-stops.md) ·
  [transit-segments.md](transit-segments.md) — the translatable fields
- [accounts-and-profiles.md](accounts-and-profiles.md) — account deletion, and
  the anonymised review
- [text-moderation.md](text-moderation.md) — `score_many` vets every
  translation before it is cached
- [visibility-and-access.md](visibility-and-access.md) — the ladder every request is checked against
- [feed-and-search.md](feed-and-search.md) — `?lang=` and the title translation on each card
- [legal-and-age-gate.md](legal-and-age-gate.md) — Privacy 2.3 names both engines
- [help-centre.md](help-centre.md) — `/help/read-trips-in-another-language`
- [admin-and-appeals.md](admin-and-appeals.md) — the sweep that runs the clean-up
- [reference/error-codes.md](../reference/error-codes.md#translations) — `translation_language_unsupported`
- [reference/data-model.md](../reference/data-model.md#content_translations)
- [decisions.md](../decisions.md) — why the cache cascades from the itinerary
