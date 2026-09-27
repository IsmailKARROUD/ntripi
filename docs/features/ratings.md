# Ratings

**Status:** shipped
**Tables:** `itinerary_ratings`
**Config:** none (see [feed-and-search.md](feed-and-search.md) for `FEED_TOP_MIN_RATINGS`)

## Purpose

Community ratings on an itinerary. One required overall score plus five optional
dimensions, one rating per user per trip, editable in place. Replaced an earlier
owner-declared `safety_rating` — the author scoring their own trip's safety was
not information anyone could use.

## Rules

- **One rating per user per itinerary**, UNIQUE `uq_itinerary_rating
  (itinerary_id, user_id)`. `POST /ratings` is an **upsert**.
- **`stars` (1–5) is required; all five dimensions are optional.** `NULL` means
  "not rated", not zero. Columns are `*_stars`; the API exposes them as
  `*_score` in `RatingWithUser`.
- **Every dimension is higher-is-better**, crowdedness included — 5 means
  pleasantly uncrowded, 1 means overcrowded — so a single `ratingColor` ramp
  keeps "green is good" true across all six.
- **Averages are computed in SQL, never in Python.** `recalculate_rating()`
  (`itinerary_access.py:167`) runs `func.count` + `func.avg` and writes
  `rating_avg` / `rating_count` back onto the itinerary. Call it after every
  insert, update, delete **and after any change to a rating's
  `moderation_status`**.
- **The aggregate write never moves `updated_at`.** `recalculate_rating` writes
  through `admin_service.set_preserving_etag`, because `updated_at` is the
  itinerary's `If-Match` ETag and a rater or a moderator is never the owner's
  editing session — before 2026-09-26 every rating 412'd the owner's open editor.
  Trade-off: the detail GET's validator is that same ETag, so a viewer holding a
  cached detail can see a stale average until a content edit or a pull-to-refresh
  (which skips the conditional GET). The rater's own post-submit refresh is
  always fresh. See [decisions.md](../decisions.md).
- **Hidden ratings are excluded from the public aggregate, including the
  author's own.** `recalculate_rating` passes `visible_rating_criteria(None)` —
  no viewer — because an aggregate is public and even its author's hidden rating
  must not move the number strangers see.
- **A rating carries its own `moderation_status`** (`itineraries.py:1756`). A
  stranger's abusive review must never take down the owner's trip, so the status
  lives on the rating, not the itinerary.
- **Editing a review cannot un-hide it.** The upsert sets the status through
  `apply_author_edit_status`: a rewritten note that passes still clears an
  automated flag, but a `hidden` / `rejected` review stays down until a moderator
  or an appeal lifts it ([text-moderation.md](text-moderation.md#escalate-only)).
- **Only the first rating notifies the owner.** `is_first_rating`
  (`itineraries.py:1768`) is set on the insert branch; editing an existing rating
  is silent.
- **Rating endpoints are `VIEWER_WRITE`** — no edit lock, no `If-Match`. They
  write a sibling table, never itinerary content, which is why
  `test_edit_guard_coverage.py:77` exempts them.
- `GET /ratings/me` and `DELETE /ratings/me` deliberately skip `_require_viewable`
  — your own rating is your own data.
- Show dimension averages only when the count is ≥ 3.

### What `GET /ratings` does, in order (`itineraries.py:1935`)

1. Applies `visible_rating_criteria(current_user.id)` — a moderated note is
   visible to its author and nobody else.
2. Computes the **distribution over the returned rows *before* the block
   filter**, so the histogram cannot disagree between two viewers. It skips the
   viewer's **own** hidden rating: step 1 keeps that row so its author can see
   and appeal it, but `recalculate_rating` excludes it, and the bars must sum to
   `rating_count` for the author too (before 2026-09-27 they came to one more).
3. Filters out blocked authors' rows **after** that.
4. Forces every other viewer's `moderation_status` to `"approved"` — `pending`
   and `flagged` are internal and never leak.
5. Blanks `display_name` when the rater's own `moderation_status` is hidden or
   rejected.

`RatingWithUser.id` is appended **last** in the field list so a reader can report
an individual review without the key order of the rest changing.

## Data model

`itinerary_ratings` — `user_id` is FK **SET NULL**, so a deleted account's rating
survives anonymised: the trip keeps its score and the reviewer disappears. That
is the GDPR trade-off, and `delete_my_account` nulls the column explicitly as
well as relying on the constraint.

Seven CHECK constraints: `ck_rating_stars BETWEEN 1 AND 5`, one
`<dim> IS NULL OR BETWEEN 1 AND 5` per dimension, and
`ck_rating_moderation_status`.

Full columns:
[reference/data-model.md](../reference/data-model.md#itinerary_ratings).

Migration history: `07035928fd6c` created it · `a1b2c3d4e5f6` added the
sub-ratings · `c1d2e3f4a5b6` added `note` · `72e6d3947e49` added crowdedness ·
`e493ea56a71b` made `user_id` SET NULL · `d3db17c28b44` added
`moderation_status` · `b7c8d9e0f1a2` dropped `itineraries.safety_rating`.

**Adding a dimension** means: a nullable `*_stars` column (model + migration +
schemas + router mapping) plus a `DimensionKey` enum value, which auto-wires the
viewer and aggregate screens.

## API surface

| Method | Path | Auth | Request | Response | Errors |
|---|---|---|---|---|---|
| POST | `/itineraries/{id}/ratings` | verified email | `RatingSubmit` | `RatingResponse` 201 | 404, 403 `itinerary_access_denied`, 422 `text_moderation_rejected` |
| GET | `/itineraries/{id}/ratings/me` | user | — | `RatingResponse` | 404 `rating_not_found` |
| DELETE | `/itineraries/{id}/ratings/me` | user | — | 204 | 404 `rating_not_found` |
| GET | `/itineraries/{id}/ratings` | user | — | `RatingsPageResponse` | 403 `itinerary_access_denied` |

`RatingSubmit` = `{stars (1–5, required), safety_stars?, experience_stars?,
accessibility_stars?, family_friendly_stars?, crowdedness_stars?, note? (≤2000)}`.

`RatingsPageResponse` = `{rating_avg, rating_count,
distribution: RatingDistribution{five, four, three, two, one},
ratings: [RatingWithUser]}`.

`RaterInfo` = `{user_id, username, display_name, avatar_url}` — reused by
`ItineraryFeedItem.owner`.

## Flutter surface

- **Screens** — `RatingsHubScreen` (`ratings_page_screen.dart`, route
  `/itineraries/:id/ratings`), `DimensionRatingsScreen` (route
  `/itineraries/:id/ratings/:dimension`).
- **`rate_itinerary_dialog.dart`** — shows Overall plus the review note first,
  and reveals the five optional dimensions only once Overall is rated.
  Crowdedness renders **person glyphs instead of stars**.
- **`DimensionKey`** (`features/itineraries/domain/dimension_key.dart:9`) —
  `overall, safety, experience, accessibility, familyFriendly, crowdedness`, with
  `fromPath()` mapping the route segment (`family_friendly` → `familyFriendly`).
  Adding an enum value wires both screens.
- **Providers** — `myRatingProvider` and `ratingsPageProvider`, both
  `AsyncNotifierProvider.family` keyed by itinerary id.

## Known gaps / TODOs

- `social_api/README.md` still documents the dropped `itineraries.safety_rating`
  column.
- The dimension-average "≥ 3 ratings" threshold is a client-side rendering rule,
  not a server-enforced one — the aggregate endpoint returns whatever it has.

## Related

- [itineraries.md](itineraries.md) — holds `rating_avg` / `rating_count`
- [visibility-and-access.md](visibility-and-access.md) — `visible_rating_criteria`
- [blocking.md](blocking.md) — blocked authors' rows are filtered from the page
- [text-moderation.md](text-moderation.md) — `note` is scanned; the status is per-rating
- [content-reports.md](content-reports.md) — a rating is a reportable target
- [admin-and-appeals.md](admin-and-appeals.md) — `/admin/ratings/{id}/unhide`
- [notifications.md](notifications.md) — `itinerary_rated`, first rating only
- [accounts-and-profiles.md](accounts-and-profiles.md) — SET NULL on deletion
- [reference/data-model.md](../reference/data-model.md)
