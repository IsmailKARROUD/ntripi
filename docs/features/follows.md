# Follows

**Status:** shipped
**Tables:** `follows`
**Config:** none

## Purpose

A hybrid follow model: following a **public** account is immediate, following a
**private** one creates a request the owner approves or rejects. Accepted follows
are what the `followers` visibility level reads. Either side can end a follow:
the follower unfollows, or the followed account **removes** them.

## Rules

### The model

```
A taps Follow on B
        │
   Is B private?
        │
  no ───┴─── yes
   │          │
status=accepted      status=pending
A.following_count +1  counters NOT touched
B.followers_count +1         │
                    B reviews the request
                             │
                    ┌────────┴────────┐
                  ACCEPT            REJECT
                    │                 │
              status=accepted    row DELETED
              counters +1        (A may retry)
```

- **There is no `rejected` status.** Rejecting **deletes** the row
  (`models/follow.py:6`), so the requester can try again without obstruction and
  no "bad" relationship data accumulates.
- **Reject acts on a *pending* row only.** A stale Decline — the request was
  accepted meanwhile, on another device or by the account going public — answers
  404 `follow_request_not_found` and leaves the follow alone. Deleting it would
  have removed a live follower without the counter decrement, so
  `followers_count` drifted high for good (fixed 2026-09-26). The status is
  checked again inside the DELETE (`delete_follow(…, only_if=pending)`), so an
  accept landing between the router's check and the statement cannot slip
  through either (2026-10-18).
- **`status` is a native PostgreSQL ENUM `followstatus`** — the only native enum
  in the schema.
- **Counters move only on accepted transitions** — up in `follow_user` and
  `accept_follow_request` (`follows.py:145,335`) and the going-public auto-accept
  (`users.py:205`), down only in `delete_follow` (`user_service.py:111`).
- Flipping an account private → public **auto-accepts every pending request** and
  notifies each requester once.

### Removing a follower

`DELETE /users/me/followers/{user_id}` — the followed account ends someone's
follow of them.

- **The removed follower is not told.** No notification, no push — the same
  silence as a declined request or a block.
- **Accepted follows only.** A pending request is left alone: refusing one is
  Decline's job, and a Remove from a stale list must never refuse a request the
  owner has not seen.
- **Idempotent — always 204.** Nothing to remove (they never followed, already
  left, were blocked; yourself; an unknown id) is the state the user asked for,
  so a stale list row does not become an error. No error code exists for it.
- **Keyed by user id**, not follow id: neither the list item
  (`FollowerListItem`) nor the profile carries a follow id.
- **Access goes at once.** `followers`-visibility trips — and, on a private
  account, the profile's content — are re-derived from the follow row on every
  read, so they go the moment it does.
- **Editing goes with viewing.** On a followers-only trip the follow is what let
  an editor see it, so a removal revokes their editing too (`can_edit_itinerary`
  delegates to `can_view_itinerary`). `edit_lock_service.release_claims_lost_by`
  drops any claim they hold on the owner's trips that they can no longer edit,
  in the same transaction — as removing an allowlist entry does — or it would
  block every other editor until the TTL. Their `itinerary_editors` row stays,
  so following again restores editing.
- **It is not a barrier.** On a public account the removed follower can follow
  again straight away; on a private one they would need a new request. Block is
  the tool for keeping someone out, and the confirm dialog says so.
- `UserPublicProfile.follows_you` (does this account follow *me*, accepted) is
  what lets the profile's ⋯ menu offer the action only when it applies.

### Counter arithmetic

**`bump_follow_counters` (`user_service.py:80`) is the only way to touch
`followers_count` / `following_count`**, and the arithmetic is an **atomic SQL
`UPDATE`, never Python**. A read-then-write (`count = count + 1` into an int and
back) is a lost update under READ COMMITTED: two people following one account in
the same moment both read N and both write N+1, and the count drifts low
forever.

Three details are load-bearing:

- The clamp is a **`case()` expression, not `GREATEST()`** — the suite runs on
  SQLite, which has no `GREATEST`.
- It sets **`synchronize_session=False`** — the default `'auto'` would reconcile
  the identity map only by re-`SELECT`ing the row it just wrote.
- It then **`db.expire()`s the attribute**, which is why the loaded object still
  reads correctly afterwards.

The **one exception** is `delete_my_account`'s bulk `UPDATE`s (clamped the same
way) — see [accounts-and-profiles.md](accounts-and-profiles.md).

**The state change that justifies a bump is conditional too.** Accept flips the
row with `UPDATE … WHERE status = 'pending'` and bumps only if it changed a row.
Two concurrent accepts (a double tap) or two concurrent unfollows used to both
pass the Python check and count twice.

**`delete_follow` (`user_service.py:111`) is the only way to delete a follow
row** — unfollow, remove-follower, decline and a block's sever all end there.
It deletes with a statement, `DELETE … WHERE id = :id RETURNING status`, and
decrements only if *this* call removed the row **and the row was accepted when
it went**. Both halves close a race (2026-10-18):

- the block sever used ORM `db.delete()`, which only warns on a DELETE that
  matches nothing — a block racing an unfollow decremented twice;
- deciding from the status *loaded* earlier, a request accepted between a
  cancel's read and its delete went without its decrement, and the counts
  stayed high for good.

`only_if=` makes the delete conditional on a status — decline passes `pending`.

### Privacy and leak avoidance

- **Never write an inline `Follow` query.** Use `get_follow` /
  `is_accepted_follower` from `user_service.py`.
- **Follower/following lists on a private account are owner-or-accepted-follower
  only** (`follows.py:49`) → 403 `account_private`.
- **Blocked users are filtered in the query** on both list endpoints
  (`follows.py:435,480`), not after, so pagination does not silently shrink.
- **Following a blocked user 404s as `user_not_found`** — identical to a deleted
  account, so the blocked user is never told.
- `accept_follow_request` answers **404 `follow_request_not_found`** even when the
  request exists but belongs to someone else, explicitly to avoid leaking the
  existence of other users' requests (`follows.py:308`).
- Following someone requires a **verified email**.

## Data model

`follows` — `id` PK, `follower_id` / `following_id` both FK CASCADE and **both
indexed**, `status` ENUM, timestamps.

- UNIQUE `uq_follower_following (follower_id, following_id)` — the DB-level
  duplicate guard; the application checks too.
- CHECK `ck_no_self_follow (follower_id != following_id)`.

Full columns: [reference/data-model.md](../reference/data-model.md#follows).

## API surface

| Method | Path | Auth | Response | Errors |
|---|---|---|---|---|
| POST | `/users/{user_id}/follow` | **verified email** | `FollowResponse` 201 | 400 `cannot_follow_self`, 404 `user_not_found`, 409 (uncoded) already following / pending |
| DELETE | `/users/{user_id}/follow` | Bearer | 204 | 404 `not_following` |
| DELETE | `/users/me/followers/{user_id}` | Bearer | 204 | — (idempotent: nothing to remove is 204 too) |
| GET | `/users/me/follow-requests` | Bearer | `list[FollowRequestItem]` | — |
| POST | `/users/me/follow-requests/{follow_id}/accept` | Bearer | `FollowResponse` | 404 `follow_request_not_found`, 400 `follow_request_already_accepted` |
| DELETE | `/users/me/follow-requests/{follow_id}` | Bearer | 204 | 404 `follow_request_not_found` (missing, **or no longer pending**), **403 `cannot_reject_request`** |
| GET | `/users/{user_id}/followers` | Bearer | `list[FollowerListItem]` | 404 `user_not_found`, 403 `account_private` |
| GET | `/users/{user_id}/following` | Bearer | `list[FollowerListItem]` | same |

`FollowResponse` = `{id, follower_id, following_id, status, created_at}`.
`FollowRequestItem` = `{follow_id, follower_id, username, display_name,
avatar_url, requested_at}`.
Both list endpoints take `limit` (default 20, max 100) / `offset` and return
**newest follow first**, with `Follow.id` breaking `created_at` ties — without a
total order Postgres may repeat or skip rows between offset pages.

Note the follows router has **no prefix** — its paths are literal `/users/…`
(`main.py:279`).

## Flutter surface

- **Screens** — `FollowListScreen` (routes `/profile/:userId/followers` and
  `/following`, plus the `/search/profile/:userId/...` nested pair),
  `FollowRequestsScreen` (`/follow-requests`).
- **Own lists carry a row action** in place of the chevron: **Remove** on each
  follower, **Following** on each followed account (which unfollows). Someone
  else's lists get none. The pill confirms, shows a spinner from confirmation
  until the request settles, and on success the row leaves the list in place.
  It is a `Semantics` button labelled "Remove @x from your followers" /
  "Unfollow @x" — a bare "Remove" in a list says nothing about whom.
- **The profile's ⋯ menu offers Remove follower** while that account follows
  you (`User.followsYou`, from `follows_you`). It is an optional
  `onRemoveFollower` on the shared `UgcActionsMenu`, so the menu stays one
  widget across every surface.
- **`features/follows/presentation/follow_actions.dart` runs both row flows** —
  `confirmAndRemoveFollower` (the list and the menu) and `confirmAndUnfollow`
  (the Following list; it shares the profile button's dialog through
  `confirmUnfollow`). Shaped like `confirmAndBlock`: what it needs is captured
  before the first await, so the cache sync happens even if the screen has gone.
  After a success it edits **my** affected list in place with `removeLocally`,
  invalidates the other person's profile and lists (plus their trips, on an
  unfollow), and **refetches my own profile for the counts** — never a local
  `-1`, which would count twice from a stale row. A 404 `not_following` on an
  unfollow means the row was stale and counts as done.
- **Following or unfollowing from a profile invalidates my profile and my
  Following list**, so the list's Following pill never offers to unfollow
  someone already unfollowed there.
- **Providers** (`features/follows/providers/follow_provider.dart`):
  | Provider | Type | Holds |
  |---|---|---|
  | `followRepositoryProvider` | `Provider` | `FollowRepository` |
  | `followRequestsProvider` | `AsyncNotifierProvider` | incoming requests (**keep-alive**) |
  | `followersProvider` | `AsyncNotifierProvider.family` | a user's followers, paged |
  | `followingProvider` | `AsyncNotifierProvider.family` | who a user follows, paged |
- **The two lists page like the feed.** Both notifiers extend
  `FollowListNotifier`: `kFollowListPageSize` (50) rows per request, `loadMore()`
  appends at the current offset, skipping ids already shown (a follow between
  pages shifts every row down one), and `hasMore` drives a trailing loader.
  `FollowListScreen` asks for the next page as a tab nears its end. Before
  2026-09-26 the app sent no `limit`, so every list silently stopped at the
  server's default 20. **`removeLocally` steps the offset back one** — the
  server's list shrank before it, so the next page would otherwise skip the row
  that slid into the gap — and `loadMore` merges into the rows on screen *now*,
  so a row removed while a page was loading stays removed.
- **Tab labels show the profile's totals** (`followers_count` /
  `following_count`), not the loaded list's length, which counts only the pages
  fetched so far.
- **`FollowButton`** (`shared/widgets/follow_button.dart`) — three states:
  Follow / Following / Requested. Its unfollow dialog is `confirmUnfollow`, and
  it says what unfollowing takes away: the trips that account shares with
  followers. (Until 2026-10-18 it said "you'll stop seeing their itineraries in
  your feed" — the feed is public-only, so following never fed it.)
- **`followRequestsProvider` is keep-alive, so the screen refetches on open** —
  a second visit would otherwise render the first visit's data.
- Unfollowing is a confirm dialog, not an undo snackbar (changed by `bded915`).
- A private profile can be followed **from its locked view** (`5227f49`).
- **Models** — `Follow`, `FollowRequestItem`, `FollowerListItem`
  (`shared/models/follow.dart`).

## Known gaps / TODOs

- **`reject_follow_request` answers 403 `cannot_reject_request` where `accept`
  answers 404 for the identical condition** (`follows.py:381` vs `:308`). The
  accept path carries an explicit comment saying 404 exists to avoid leaking
  other users' requests; **the reject path leaks it.**
- The 409 on "already following / already pending"
  (`follows.py:127`) is a bare `HTTPException` with no error code, so the client
  shows the server's English `detail`.
- **Removing a follower is not a barrier on a public account** — they can
  follow again at once. Block is the tool for that; the confirm dialog says so.
- **Accepting a request does not add the person to ALL FOLLOWERS** until a
  pull-to-refresh; and following someone from their profile does not refresh
  their Followers list or the trips shown on their profile. Both predate the
  row actions.
- The Decline ✕ pill on a request row has no accessible label: it now reads as
  a button, but not as which request it declines.
- `test_follows.py` and `test_follow_counter_atomicity.py` both run — the
  atomicity test was added with `2e8e5c6`.

## Related

- [accounts-and-profiles.md](accounts-and-profiles.md) — the counters, the privacy flip
- [visibility-and-access.md](visibility-and-access.md) — `is_accepted_follower` powers the `followers` level
- [blocking.md](blocking.md) — a block severs follows both ways
- [collaborative-editing.md](collaborative-editing.md) — a removed follower's editing of followers-only trips
- [notifications.md](notifications.md) — `follow_request`, `new_follower`, `follow_accepted`
- [feed-and-search.md](feed-and-search.md) — `followers_count` is a search sort key
- [reference/error-codes.md](../reference/error-codes.md#follows)
- [reference/data-model.md](../reference/data-model.md#follows)
