# Blocking

**Status:** shipped
**Tables:** `user_blocks`
**Config:** none

## Purpose

One user blocks another. Visibility is cut in **both** directions, and a blocked
profile becomes indistinguishable from a deleted one, so the blocked user is
never told.

## Rules

- **`is_blocked_either_way` (`block_service.py:840`) is the predicate.**
  Direction never matters for visibility: a one-sided cut would let the blocked
  user keep reading someone who asked to be left alone.
- **A blocked profile 404s as `user_not_found`** — `require_not_blocked_or_404`
  (`block_service.py:857`) returns exactly the code and body a deleted account
  returns. The client's `isGoneError()` keys off the HTTP status, so it can tell
  "gone" from "broken" but never *why*.
- **Blocking severs follows in both directions and fixes both users' counters**
  (`block_service.py:893`). Idempotent.
- **Unblocking does not restore the follows** (`block_service.py:914`). The
  relationship is gone, not suspended.
- **You can block someone who has already blocked you.** `block_user` uses a bare
  `db.get(User, …)` rather than the blocked-aware helper (`users.py:629`) —
  deliberate, since otherwise the first block would prevent the second and leave
  the second user unable to express the same preference.
- **`user_blocks` CASCADEs on both FKs** — a block is a *preference*, not
  evidence, so it dies with either account.
- `DELETE /users/{id}/block` is idempotent.

### Where blocking is consulted

Twelve places, which is why the predicate lives in one function:

| Surface | Mechanism |
|---|---|
| `can_view_itinerary` | `is_blocked_either_way` (`itinerary_access.py:104`) |
| `public_listing_criteria` | `blocked_user_ids` as a SQL `NOT IN` (`itinerary_access.py:45`) |
| `notification_service.notify` | one of its three suppression rules |
| user search | filtered **in the query** |
| follower / following lists | filtered in the query |
| `get_ratings_page` | filtered **after** the distribution is computed |
| `get_user_itineraries`, `get_user_locations`, `_build_public_profile` | 404 or filter |

## Data model

`user_blocks` — `id` PK, `blocker_user_id` / `blocked_user_id` both FK CASCADE
and indexed, `created_at`.

- UNIQUE `uq_user_block (blocker_user_id, blocked_user_id)`
- CHECK `ck_no_self_block`

Full columns:
[reference/data-model.md](../reference/data-model.md#user_blocks). Migration:
`9dcbd2b7d34c`.

## API surface

| Method | Path | Auth | Response | Errors |
|---|---|---|---|---|
| GET | `/users/me/blocks` | Bearer | `list[UserSearchResult]`, newest first | — |
| POST | `/users/{user_id}/block` | Bearer | 204 | 400 `cannot_block_self`, 404 `user_not_found` |
| DELETE | `/users/{user_id}/block` | Bearer | 204, idempotent | — |

## Flutter surface

- **`BlockedUsersScreen`** — route `/settings/blocked-users`.
- **Providers** (`features/reports/data/report_repository.dart` — blocking lives
  in the reports feature directory, not its own):
  | Provider | Type | Holds |
  |---|---|---|
  | `reportRepositoryProvider` | `Provider` | `ReportRepository` |
  | `blockedUsersProvider` | `FutureProvider` | the blocked list |
  | `blockedUserIdsProvider` | `Provider` | id set derived from the list |
- Block and unblock are offered from `ugc_actions.dart`, alongside reporting.
- **A blocked account reads as gone, not as a cached profile** — `708cc28` fixed
  a case where a stale cache still rendered the profile.

## Known gaps / TODOs

- Blocking has no dedicated feature directory on the client; it shares
  `features/reports/`. That is a reasonable pairing (both are "act on another
  user") but it means `blockedUsersProvider` is not where a reader would look.
- `test_blocks.py` runs and is not skipped.

## Related

- [visibility-and-access.md](visibility-and-access.md) — the main consumer
- [follows.md](follows.md) — a block severs follows both ways
- [accounts-and-profiles.md](accounts-and-profiles.md) — the counters it fixes
- [feed-and-search.md](feed-and-search.md) — filtered in both queries
- [ratings.md](ratings.md) — filtered after the distribution
- [notifications.md](notifications.md) — one of the three suppression rules
- [content-reports.md](content-reports.md) — the sibling action, same client sheet
- [reference/data-model.md](../reference/data-model.md#user_blocks)
