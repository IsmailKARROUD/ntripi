# Follows

**Status:** shipped
**Tables:** `follows`
**Config:** none

## Purpose

A hybrid follow model: following a **public** account is immediate, following a
**private** one creates a request the owner approves or rejects. Accepted follows
are what the `followers` visibility level reads.

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
- **`status` is a native PostgreSQL ENUM `followstatus`** — the only native enum
  in the schema.
- **Counters move only on accepted transitions** (`follows.py:141,195`,
  `users.py:176`, `block_service.py:949`).
- Flipping an account private → public **auto-accepts every pending request** and
  notifies each requester once.

### Counter arithmetic

**`bump_follow_counters` (`user_service.py:778`) is the only way to touch
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

The **one exception** is `delete_my_account`'s bulk `UPDATE`s — see
[accounts-and-profiles.md](accounts-and-profiles.md).

### Privacy and leak avoidance

- **Never write an inline `Follow` query.** Use `get_follow` /
  `is_accepted_follower` from `user_service.py`.
- **Follower/following lists on a private account are owner-or-accepted-follower
  only** (`follows.py:47`) → 403 `account_private`.
- **Blocked users are filtered in the query** on both list endpoints
  (`follows.py:381,423`), not after, so pagination does not silently shrink.
- **Following a blocked user 404s as `user_not_found`** — identical to a deleted
  account, so the blocked user is never told.
- `accept_follow_request` answers **404 `follow_request_not_found`** even when the
  request exists but belongs to someone else, explicitly to avoid leaking the
  existence of other users' requests (`follows.py:275`).
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
| GET | `/users/me/follow-requests` | Bearer | `list[FollowRequestItem]` | — |
| POST | `/users/me/follow-requests/{follow_id}/accept` | Bearer | `FollowResponse` | 404 `follow_request_not_found`, 400 `follow_request_already_accepted` |
| DELETE | `/users/me/follow-requests/{follow_id}` | Bearer | 204 | 404 `follow_request_not_found`, **403 `cannot_reject_request`** |
| GET | `/users/{user_id}/followers` | Bearer | `list[FollowerListItem]` | 404 `user_not_found`, 403 `account_private` |
| GET | `/users/{user_id}/following` | Bearer | `list[FollowerListItem]` | same |

`FollowResponse` = `{id, follower_id, following_id, status, created_at}`.
`FollowRequestItem` = `{follow_id, follower_id, username, display_name,
avatar_url, requested_at}`.
Both list endpoints take `limit` / `offset`.

Note the follows router has **no prefix** — its paths are literal `/users/…`
(`main.py:279`).

## Flutter surface

- **Screens** — `FollowListScreen` (routes `/profile/:userId/followers` and
  `/following`, plus the `/search/profile/:userId/...` nested pair),
  `FollowRequestsScreen` (`/follow-requests`).
- **Providers** (`features/follows/providers/follow_provider.dart`):
  | Provider | Type | Holds |
  |---|---|---|
  | `followRepositoryProvider` | `Provider` | `FollowRepository` |
  | `followRequestsProvider` | `AsyncNotifierProvider` | incoming requests (**keep-alive**) |
  | `followersProvider` | `AsyncNotifierProvider.family` | a user's followers |
  | `followingProvider` | `AsyncNotifierProvider.family` | who a user follows |
- **`FollowButton`** (`shared/widgets/follow_button.dart`) — three states:
  Follow / Following / Requested.
- **`followRequestsProvider` is keep-alive, so the screen refetches on open** —
  a second visit would otherwise render the first visit's data.
- Unfollowing is a confirm dialog, not an undo snackbar (changed by `bded915`).
- A private profile can be followed **from its locked view** (`5227f49`).
- **Models** — `Follow`, `FollowRequestItem`, `FollowerListItem`
  (`shared/models/follow.dart`).

## Known gaps / TODOs

- **`reject_follow_request` answers 403 `cannot_reject_request` where `accept`
  answers 404 for the identical condition** (`follows.py:338` vs `:275`). The
  accept path carries an explicit comment saying 404 exists to avoid leaking
  other users' requests; **the reject path leaks it.**
- The 409 on "already following / already pending"
  (`follows.py:125`) is a bare `HTTPException` with no error code, so the client
  shows the server's English `detail`.
- `test_follows.py` and `test_follow_counter_atomicity.py` both run — the
  atomicity test was added with `2e8e5c6`.

## Related

- [accounts-and-profiles.md](accounts-and-profiles.md) — the counters, the privacy flip
- [visibility-and-access.md](visibility-and-access.md) — `is_accepted_follower` powers the `followers` level
- [blocking.md](blocking.md) — a block severs follows both ways
- [notifications.md](notifications.md) — `follow_request`, `new_follower`, `follow_accepted`
- [feed-and-search.md](feed-and-search.md) — `followers_count` is a search sort key
- [reference/error-codes.md](../reference/error-codes.md#follows)
- [reference/data-model.md](../reference/data-model.md#follows)
