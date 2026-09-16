# ETags: concurrency and caching

**Status:** shipped
**Tables:** none (reads `itineraries.updated_at`)
**Config:** none

## Purpose

Two unrelated mechanisms that both use the `ETag` header:

1. **Optimistic concurrency** (`If-Match`) — stops two devices silently
   overwriting each other's itinerary edits.
2. **Cache validation** (`If-None-Match`) — saves bandwidth by answering
   `304 Not Modified` when a GET response has not changed.

They **do not share a value format**. The concurrency token is a quoted ISO
datetime; the cache token is a 16-char body hash. Keeping them straight matters,
because one endpoint emits both.

---

## 1. Concurrency — `If-Match`

### Rules

- **Scope is the whole itinerary.** Any mutation anywhere in the tree — a stop, a
  leg, an annotation — bumps `itineraries.updated_at`.
- **`updated_at` IS the ETag.** The value is the quoted ISO datetime:
  `"2026-05-11T14:18:05.079393+00:00"` (`dependencies.py:131`).
- **Every GET returns an `ETag`; every mutation requires `If-Match`.**
  Missing → **428 `if_match_required`**. Mismatch → **412 `itinerary_stale`**
  with detail `"itinerary modified, please reload"`.
- **`_touch_itinerary` (`itineraries.py:128`) bumps it manually** because
  SQLAlchemy's `onupdate` does not fire when only a child row changed.
- **`_normalize_etag` (`dependencies.py:137`) handles three intermediary
  mutations** before the byte compare:
  | Problem | Source |
  |---|---|
  | surrounding whitespace | proxies |
  | `W/` weak-validator prefix | Cloudflare, when it recompresses the body |
  | trailing `Z` vs `+00:00` | Dart's `toIso8601String()` vs Python's `isoformat()` |
- **The row is loaded `SELECT … FOR UPDATE`** (`dependencies.py:168`) so two
  concurrent requests cannot both pass the check and both write. Silently skipped
  on SQLite, which is what the test suite runs on.
- **A moderation write from outside the owner's request must not move
  `updated_at`.** That is what `admin_service.set_preserving_etag` exists for —
  13 call sites — because moving it would 412 the author's open editor over a
  change they cannot see.
- **A heartbeat or a takeover must never touch `updated_at`** either, or every
  open client would 412 once a minute.
- `_etag_json_response` (`itineraries.py:137`) is the only way to build a
  response carrying the concurrency ETag. In `reorder_itinerary` it must be
  passed the **freshly reloaded** detail, not the stale itinerary.
- **The seven `OWNER_ONLY` endpoints take no `If-Match`** — DELETE itinerary,
  the allowlist pair, the editors pair, the image pair. See
  [collaborative-editing.md](collaborative-editing.md#test_edit_guard_coveragepy--the-structural-proof).

### Where it lives

`require_etag` in `app/dependencies.py` — **the same object as
`require_edit_access`**. Steps 5 and 6 of that guard are the `If-Match` check and
the heartbeat refresh; steps 1–4 are permission and lock. The full ordered table
is in [collaborative-editing.md](collaborative-editing.md#the-guard).

---

## 2. Caching — `If-None-Match` / 304

### Rules

`ETagMiddleware` (`app/middleware/etag.py`):

- **GET only**, and only `2xx` responses whose `content-type` is
  `application/json*`.
- **Skips the static mounts** — `STATIC_PREFIXES = ("/uploads", "/static",
  "/app")`, shared with the security-headers middleware via
  `app/middleware/__init__.py` so a new static mount is registered once, not
  twice.
- Buffers the body, hashes it, and sets `ETag` to `sha256(body)[:16]` — an
  **opaque 16-char token**, unrelated to the concurrency format.
- Sets `Cache-Control: private, no-cache`.
- When the client returns the value in `If-None-Match`, replies **304 with an
  empty body**.
- **If an endpoint already set its own `ETag`, the middleware leaves it alone.**
  `GET /itineraries/{id}` sets the ISO concurrency token, and the 304 round-trip
  still works against it because the middleware runs `_normalize_etag` on **both**
  sides of the comparison — so Cloudflare's `W/` downgrade still matches.
- **It also preserves an endpoint-set `Cache-Control`**, which is what lets the
  help centre's machine surfaces be `public, max-age=3600` while help HTML must
  never be.
- It is the **innermost** of the JSON-API layers, closest to the handlers.

### What this buys

The edit-lock `GET` was designed around it: the body carries absolute timestamps
and **no remaining-seconds field**, so it is byte-identical between polls and the
304 path fires on every one. A `seconds_remaining` field would have defeated it.

### Flutter side

`CachePolicy.request` in `lib/core/api/api_client.dart` honours `Cache-Control`
and `ETag` automatically — no per-call changes. `cache_evict_interceptor.dart`
drops cached entries on mutation. Pull-to-refresh deliberately bypasses the
validator so a manual refresh is never answered from cache.

---

## API surface

No endpoints of its own. It applies to:

- **Concurrency** — the 17 `EDIT_GUARDED` mutations, all under
  `/itineraries/{itinerary_id}`.
- **Caching** — every JSON GET in the application except the static mounts.

## Known gaps / TODOs

- `test_etag_middleware.py` and `test_etag_value_hash.py` cover the caching half
  and the value format. The concurrency half has no dedicated test file; it is
  exercised incidentally by `test_itinerary_edit_lock.py` and
  `test_edit_guard_coverage.py`.
- `SELECT … FOR UPDATE` — the actual race protection — **cannot be tested**,
  because the suite runs on SQLite where it is a no-op.

## Related

- [collaborative-editing.md](collaborative-editing.md) — the rest of the same guard
- [itineraries.md](itineraries.md) — owns `updated_at`
- [admin-and-appeals.md](admin-and-appeals.md) — `set_preserving_etag`
- [text-moderation.md](text-moderation.md) — why moderation writes must preserve it
- [help-centre.md](help-centre.md) — the `Cache-Control` preservation rule
- [web-and-platform.md](web-and-platform.md) — middleware ordering
- [reference/error-codes.md](../reference/error-codes.md#concurrency-etag--if-match)

## OPEN QUESTIONS

- **The two mechanisms share a header name and a normalisation function but not a
  value format.** `_normalize_etag` is applied to both, and it is written for the
  ISO form (it rewrites a trailing `Z`). Applied to a 16-hex body hash the `Z`
  branch can never fire, so it is harmless — but whether one function serving two
  formats is intentional economy or an accident is not recorded anywhere.
