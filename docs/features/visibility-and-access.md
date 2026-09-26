# Visibility and access control

**Status:** shipped
**Tables:** `itineraries.visibility`, `itinerary_allowed_users`
**Config:** none

## Purpose

Decides who may see an itinerary. Four visibility levels plus an explicit
allowlist, resolved by one function that every read path calls. This is the
foundation the edit ladder, the feed, search, sharing and moderation all sit on:
nothing in the project answers "can this person see this" for itself.

## Rules

- **`can_view_itinerary()` in `services/itinerary_access.py:74` is the single
  source of truth.** No router re-implements the ladder inline.
- **Evaluation order is load-bearing** (`itinerary_access.py:88`–`132`):
  1. `deleted_at is not None` → **False for everyone, owner included.** The row
     survives as evidence but is gone for every caller.
  2. Owner → **True**, short-circuiting everything below. An owner sees their own
     hidden content; a banned owner cannot authenticate to become a viewer, so
     there is no case to handle.
  3. `hidden_at is not None` → False (moderator-hidden is owner-only).
  4. `is_blocked_either_way` → False, in **both** directions.
  5. Owner `is_active == False` (banned) → False.
  6. Then the ladder.
- **The ladder** (`itinerary_access.py:114`):
  | `visibility` | Who else can view |
  |---|---|
  | `public` | any authenticated user |
  | `followers` | accepted followers of the owner (`is_accepted_follower`) |
  | `restricted` | users with an `itinerary_allowed_users` row |
  | `only_me` | nobody — the default |
- **`only_me` is the default** (`itineraries.visibility` server default), so a
  newly created trip is private until the owner says otherwise.
- An **unrecognised `visibility` value falls through to deny** — the final
  `return False` at `itinerary_access.py:132` is the `only_me` branch and also
  the catch-all.
- **`public_listing_criteria()` (`itinerary_access.py:30`) is the query-level
  twin** and must stay in lock-step with the row-level check. It emits: not
  soft-deleted, not hidden, owner active, and (when passed `db` + `viewer_id`)
  author not blocked. **The caller MUST `join(User)`** or the banned-owner clause
  cannot resolve. It does **not** cover the visibility ladder — callers that need
  that run `can_view_itinerary` per row as well.
- **`visible_rating_criteria()` (`itinerary_access.py:60`) is separate on
  purpose.** Ratings carry their own `moderation_status` so a stranger's abusive
  review cannot take down the owner's trip. `HIDDEN_STATUSES = ("hidden",
  "rejected")` — `pending` and `flagged` stay visible, being internal states.
- **Aggregates obey the same rule.** `recalculate_rating()`
  (`itinerary_access.py:167`) passes `visible_rating_criteria(None)` — no viewer —
  so even the author's own hidden rating cannot move the average others see.
- **The allowlist only applies to `restricted`.** `POST /allowed-users` answers
  400 `allowlist_restricted_only` otherwise (`itineraries.py:920`).
- **Allowlist names go through `public_profile_text`**, like the editor list: a
  display name that moderation hid comes back `null` (the client shows
  `@username`). Both allowlist endpoints read it raw until 2026-09-26.
- **Allowlist mutations are owner-only** (`_require_owner`) and are the one
  itinerary sub-resource that does **not** bump `updated_at`: the allowlist
  changes nothing in `ItineraryDetail`, and bumping it would 412 the owner's open
  editor (`itineraries.py:935` comment).
- Adding a viewer sends an `itinerary_viewer_added` notification that **names the
  itinerary in the sentence** — a restricted trip is in no feed and no search, so
  a notice that does not name it cannot be acted on.

## Data model

`itineraries.visibility` — `VARCHAR(20)`, NOT NULL, default `'only_me'`.
`itinerary_allowed_users` — composite PK `(itinerary_id, user_id)`, both FKs
CASCADE, plus `ix_itinerary_allowed_users_user_id` because the trailing PK column
cannot use the PK index. Full columns in
[reference/data-model.md](../reference/data-model.md#itinerary_allowed_users).

## API surface

| Method | Path | Auth | Request | Response | Errors |
|---|---|---|---|---|---|
| POST | `/itineraries/{id}/allowed-users` | owner | `AllowedUserAdd` `{user_id}` | `AllowedUserResponse` 201 | 400 `allowlist_restricted_only`, 404 `user_not_found`, 409 `allowlist_user_exists` |
| GET | `/itineraries/{id}/allowed-users` | owner | — | `list[AllowedUserResponse]`, oldest first | 403 `itinerary_not_owner` |
| DELETE | `/itineraries/{id}/allowed-users/{user_id}` | owner | — | 204 | 404 `allowlist_user_not_found` |

`AllowedUserResponse` = `{user_id, username, display_name, created_at}`.

`visibility` itself is set through `PATCH /itineraries/{id}` and is **owner-only**
— the guard admits editors, the request body does not. See
[collaborative-editing.md](collaborative-editing.md).

## Flutter surface

- **`VisibilityScreen`** (`features/itineraries/presentation/visibility_screen.dart:29`)
  — pushed with `Navigator.push<ItineraryVisibility>`, **not a go_router route**;
  pops with the selection. Four option cards from a static list at line 191.
- **`ItineraryVisibility`** enum (`features/itineraries/domain/itinerary.dart:15`)
  — `public, followers, restricted, onlyMe`; `label` / `description` resolve
  through `AppLocalizations`.
- **`allowedUsersProvider`** — `AsyncNotifierProvider.family<AllowedUsersNotifier,
  List<AllowedUser>, String>` keyed by itinerary id
  (`itinerary_providers.dart:435`).
- **Restricted is committed before the allowlist opens.** `visibility_screen.dart:64`
  saves `{'visibility': 'restricted'}` first, because the allowlist endpoints 400
  on an itinerary that is not restricted yet. The allowlist section only renders
  in edit mode (`visibility_screen.dart:136`); create mode shows a hint instead.

## Known gaps / TODOs

- `_VISIBILITY` is a Pydantic `Literal` (`schemas/itinerary.py:31`) while
  `_NOTE_TYPE_PATTERN` and `_PLACE_TYPE_PATTERN` are `pattern=` regexes, against
  the rule in [constraints.md](../constraints.md#api-contract-stability) that
  constrained strings stay `pattern=` so the 422 body does not change shape.

## Related

- [itineraries.md](itineraries.md) — owns the `visibility` column and its PATCH
- [collaborative-editing.md](collaborative-editing.md) — `can_edit_itinerary` delegates here first
- [blocking.md](blocking.md) — consulted inside `can_view_itinerary`
- [follows.md](follows.md) — supplies `is_accepted_follower` for the `followers` level
- [ratings.md](ratings.md) — `visible_rating_criteria` and the aggregate rule
- [feed-and-search.md](feed-and-search.md) — the main `public_listing_criteria` consumer
- [sharing.md](sharing.md) — public pages resolve access without a viewer
- [admin-and-appeals.md](admin-and-appeals.md) — sets `hidden_at` / `deleted_at`
- [reference/data-model.md](../reference/data-model.md)

## OPEN QUESTIONS

- **`itineraries.visibility` has no CHECK constraint** although every other
  enumerated column in the schema does. Enforcement is the Pydantic `Literal`
  plus the deny-by-default fallthrough. The column predates the CHECK convention
  (added 2026-03-15, `c3d2e1f0a9b8`); whether leaving it out is deliberate is not
  recorded.
- `public_listing_criteria`'s `db` and `viewer_id` parameters default to `None`,
  with the comment *"omitted only for call sites with no viewer (there are none
  today; the defaults exist so an older caller cannot silently lose the
  moderation clauses)"*. Since no such caller exists, whether the defaults should
  now be made required is an open call.
