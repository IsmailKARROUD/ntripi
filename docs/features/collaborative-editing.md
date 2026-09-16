# Collaborative editing (editors + edit lock)

**Status:** shipped
**Tables:** `itinerary_editors`, `itinerary_edit_locks`
**Config:** `EDIT_LOCK_HEARTBEAT_SECONDS`, `EDIT_LOCK_IDLE_SECONDS`, `EDIT_LOCK_TTL_SECONDS`

## Purpose

An itinerary has one owner and any number of **editors**, plus a server-enforced
**edit lock** so two people never write at once. Everything is decided
server-side; the client renders state and may be stale or hostile.

## Rules

### Editors

- **`can_edit_itinerary()` (`itinerary_access.py:135`) is the single source of
  truth, and it delegates to `can_view_itinerary()` first.** That is what makes
  edit rights *re-derived* rather than stored: a block, a visibility change, a
  moderator hide, a banned owner or a soft delete revokes editing the moment it
  revokes viewing — no rows to clean up, no sweep. **There is one access ladder,
  never two.**
- **Only the owner grants or revokes** someone else. An editor cannot recruit
  more editors — the grant is the owner's trust decision and does not carry the
  power to delegate it. An editor **may** remove themselves.
- **`GET /editors` is readable by editors too** — someone sharing a document
  should see who else holds a pen.
- **Granting to someone who cannot view answers 409 `editor_cannot_view`** with
  `extra = {visibility, can_fix_with_allowlist}`. That is a question, not an
  error: the client asks the owner and re-posts with `grant_view: true`.
- **`grant_view` may only insert an allowlist row, and only for `restricted`.**
  It must never change `visibility` — `followers → restricted` would silently cut
  off every follower, and `only_me → anything` is a privacy decision the owner
  has to make deliberately.
- **Revoking also deletes that user's lock row**, in the same transaction
  (`itineraries.py:1162`) — otherwise a removed editor's claim blocks everyone
  until the TTL runs out.
- **All three editor endpoints call `_touch_itinerary`**, unlike the allowlist.
  They must: `ItineraryDetail.can_edit` rides in a response whose ETag is
  `updated_at`, so without the bump a revoked editor's cached detail would keep
  offering them a pencil.
- **Editor rights are content only.** Owner-only: delete the itinerary,
  `visibility`, the allowlist, the editor list, and the **cover image** (the
  trip's public face, and every upload spends a paid Rekognition scan).

### The edit lock

- **`itinerary_edit_locks.itinerary_id` is the PRIMARY KEY**, so "at most one
  holder" is a database invariant rather than something app code remembers.
- **The claim is identified by a rotating opaque token, never by `user_id`.**
  `token_hash` stores only the SHA-256; the raw token is returned exactly once, by
  the claim endpoint. **Every takeover mints a fresh one, and that rotation is the
  entire mechanism** behind "the displaced device cannot save": it still holds the
  old token, still believes it is editing, and fails closed on its next write. A
  `user_id` comparison could not express this — the same person on a second device
  looks identical.
- **No `expires_at` column.** Staleness is derived from `last_heartbeat_at`
  against the config windows at read time, so raising the TTL takes effect on
  claims that already exist.
- **`state` is computed server-side and shipped as a word** — `active` (heartbeat
  current) / `idle` (quiet, claim still stands, **presentational only**) /
  `takeable` (past the TTL, any editor may take it). The client renders it and
  counts down against absolute timestamps; it never derives it.
- **The GET body carries absolute timestamps and no remaining-seconds field**, so
  it stays byte-identical between polls and `ETagMiddleware` can answer 304.
- **`takeover` defaults `false` on every displacing path.** A takeable claim, your
  own other device, and the owner's immediate reclaim all need the explicit flag,
  so a steal is always a deliberate second call the UI confirmed. `may_displace`
  (`edit_lock_service.py:216`) = not live **or** same user **or** owner — *and*
  `takeover=True` regardless.
- **A matching token past its TTL is honoured** and its heartbeat refreshed
  (`edit_lock_service.py:246`) — nobody took the claim, so refusing would discard
  real work to enforce a deadline that was not holding anyone up.
- **`touch()` writes `last_heartbeat_at` only** — never `Itinerary.updated_at`,
  which IS the concurrency ETag and would 412 every open client once a minute.
- **Lock state is deliberately not on `ItineraryDetail`** — it changes every
  heartbeat while that response's ETag does not.
- **`DELETE /lock` is idempotent and never 404s** — the client fires it from
  teardown. The owner may release **without** a token: that is the "unlock it from
  my other device" path.
- `sweep_service` purges rows older than `TTL × 24` — housekeeping only; a
  surviving row still reads `takeable`.

### The guard

`require_edit_access` in `app/dependencies.py` is **the same object** as
`require_etag`, which keeps its name for the endpoints and docs that already use
it. Order is load-bearing:

| # | Status | Condition |
|---|---|---|
| 1 | **404** `itinerary_not_found` | missing **or** `deleted_at is not None` (loaded `FOR UPDATE`) |
| 2 | **403** `itinerary_not_owner` | `can_edit_itinerary()` false |
| 3 | **428** `edit_lock_required` | no `X-Edit-Lock` header |
| 4 | **409** `edit_lock_lost` | no lock row, or the token does not match |
| 5 | **428** `if_match_required` / **412** `itinerary_stale` | the `If-Match` check |
| 6 | — | refresh the claim's heartbeat — saving is activity |

- **Step 4 sits above step 5 deliberately.** After a takeover the ETag has usually
  moved too, and 412 would send the user to reload into a screen they still cannot
  save from. "You lost the claim" is the more specific truth and the only
  actionable one.
- **409, not 423, on the write path.** 423 `itinerary_locked` means "you asked to
  claim and cannot" — answerable by waiting or taking over. 409 `edit_lock_lost`
  means "you believed you held it and do not" — protect the unsaved input. The
  client reacts differently to each, so they must never be collapsed.
- Step 2's code and wording are identical whether the caller was never granted
  edit rights or was granted them and then lost view access — which of the two it
  is is not something to spell out to them.
- **`X-Edit-Lock` must stay in `main.py`'s CORS `allow_headers`** or the browser
  preflight fails before the request is sent.

### `test_edit_guard_coverage.py` — the structural proof

Introspects `app.main.app.routes` and asserts every mutating route under
`/itineraries/{itinerary_id}` is in **exactly one** of four sets, that every
`EDIT_GUARDED` one depends on `require_edit_access`, and that none of the others
do. **A new endpoint fails the suite until somebody classifies it** — that is what
keeps "no exceptions" true for code nobody has written yet.

| Set | Count | Contents |
|---|---|---|
| `EDIT_GUARDED` | 17 | PATCH itinerary, all stop writes, reorder, both annotation systems, all segment and leg writes |
| `OWNER_ONLY` | 7 | DELETE itinerary, allowlist ×2, editors ×2, image ×2 — **no lock, no If-Match** |
| `VIEWER_WRITE` | 3–4 | ratings POST/DELETE, save POST/DELETE — they write sibling tables, never itinerary content |
| `LOCK_ENDPOINTS` | 3 | you would need a claim to get a claim |

`classified - live` is asserted empty, so **adding a READ route to any set fails
the suite**.

## Data model

`itinerary_editors` — composite PK `(itinerary_id, user_id)`, both CASCADE, plus
`granted_by` FK **SET NULL** (audit only). `ix_itinerary_editors_user (user_id)`
is the one index the allowlist does not need: this table *is* queried by its
trailing column, for `shared-with-me`.

`itinerary_edit_locks` — `itinerary_id` PK, `user_id` CASCADE,
`token_hash` VARCHAR(64), `acquired_at`, `last_heartbeat_at`, index on the
heartbeat.

Migrations: `192d73531acf` created both (and runs
`DELETE FROM notifications WHERE type = 'itinerary_editor_added'` to clear rows
written for a then-new type); `393a6b3179ce` merges it with the device-token
branch.

Full columns:
[reference/data-model.md](../reference/data-model.md#itinerary_editors).

## API surface

### Editors

| Method | Path | Auth | Request | Response | Errors |
|---|---|---|---|---|---|
| POST | `/itineraries/{id}/editors` | **owner** | `EditorAdd{user_id, grant_view=false}` | `EditorResponse` 201 | 400 `editor_is_owner`, 404 `user_not_found`, 409 `editor_exists`, 409 `editor_cannot_view` (+`extra`) |
| GET | `/itineraries/{id}/editors` | **can_edit** | — | `list[EditorResponse]` | 403 `itinerary_not_owner` |
| DELETE | `/itineraries/{id}/editors/{user_id}` | owner **or self** | — | 204 | 403, 404 `editor_not_found` |

### Lock

| Method | Path | Auth | Request | Response | Errors |
|---|---|---|---|---|---|
| POST | `/itineraries/{id}/lock` | can_edit | `LockClaimRequest{takeover=false}` (body optional) | `LockClaimResponse{token, lock, heartbeat_interval_seconds, ttl_seconds}` | 403, **423 `itinerary_locked`** (+`extra.lock`) |
| POST | `/itineraries/{id}/lock/heartbeat` | can_edit + `X-Edit-Lock` | — | `LockHolder` | 428 `edit_lock_required`, 409 `edit_lock_lost` |
| DELETE | `/itineraries/{id}/lock` | can_edit | — | 204, **never 404** | 403 |
| GET | `/itineraries/{id}/lock` | **can_view** | — | `LockStateResponse{can_edit, lock?, heartbeat_interval_seconds, ttl_seconds}` | 403 `itinerary_access_denied` |

`LockHolder` = `{holder_id, holder_username, holder_display_name,
holder_avatar_url, is_you, state, acquired_at, last_heartbeat_at, idle_at,
takeover_available_at}`.

### Finding a shared trip again

`GET /itineraries/shared-with-me` → `list[ItineraryFeedItem]`.

- The grant notification cannot be the only way back: a `restricted` itinerary is
  in no feed and no search, and notifications are purged (90 days read / 365 hard
  cap). This is the durable surface, and the only query that reads
  `itinerary_editors` by its trailing column.
- **Reuses `ItineraryFeedItem` and `_to_feed_item`**, not a new schema — summary
  + `owner: RaterInfo` is exactly this payload. `ItinerarySummary` gains **no**
  `can_edit`, which would churn the key order of `/me`, `/saved` and `/feed` for
  a flag only this list needs.
- Two filters, like `/saved`: `public_listing_criteria` in SQL, then
  **`can_edit_itinerary` per row** — the SQL half does not cover the visibility
  ladder, and a granted editor's access is usually `restricted` or `followers`.
  Its re-lookup of the editor row the join already proved is deliberate: one
  access ladder beats saving a query.
- Mine and Shared are **disjoint by construction** (`add_editor` 400s on the
  owner), so the merged view needs no de-duplication.
- It is a read, so `test_edit_guard_coverage.py` neither covers nor wants it.

## Config

| Var | Default | Meaning |
|---|---|---|
| `EDIT_LOCK_HEARTBEAT_SECONDS` | 30 | the ping interval the server tells the client to use |
| `EDIT_LOCK_IDLE_SECONDS` | 90 | three missed beats → renders as "inactive"; nobody may take it yet |
| `EDIT_LOCK_TTL_SECONDS` | 300 | silence this long → any editor may take over |

**A startup validator raises** (`config.py:304`) on `TTL <= IDLE`,
`IDLE < 2 × HEARTBEAT`, or `HEARTBEAT < 5`. A claim that became takeable before
it even read as inactive would be stolen out from under someone the UI still
showed as editing.

## Flutter surface

- **`EditLockNotifier`** (`features/itineraries/providers/edit_lock_provider.dart`)
  — `NotifierProvider.family` by itinerary id, **not `autoDispose`**. It owns the
  token and the heartbeat, and lives in a provider because the claim must survive
  the detail screen being covered by the stop form. **The token is memory only** —
  any takeover rotates it, so persisting it would only create a way to resurrect
  a dead session.
- **`EditorsScreen`** — route `/itineraries/:id/editors`; `editorsProvider`
  (`AsyncNotifierProvider.family`).
- **`sharedWithMeProvider`** stays a **separate provider** from
  `myItinerariesProvider` — two endpoints that fail independently, and the active
  segment decides which must be settled, so a dead `shared-with-me` can never
  blank the Mine segment. The scope selector, loader and error therefore all live
  **inside** the list: replacing the screen wholesale would take the control away
  with it and strand the user on a scope they cannot leave. Client-side filter
  only — flipping segments must not refetch.
- **A row's provenance, not an id comparison, gates the owner-only chrome.**
  `/itineraries/me` is owner-only by construction, so a null `owner` is a stronger
  signal than `currentUser?.id == itinerary.userId` and needs no profile load.
  Shared rows get `SharedItineraryCard` (attribution + an Editor badge, no share
  action) and never the long-press delete.
- `mayEdit = isOwner || itinerary.canEdit`. Ownership is OR-ed in because it is
  the one case the client can derive itself, and a summary payload (no `can_edit`
  key) must not take the owner's own pencil away.
- **`itinerary_form_screen.dart` in edit mode opens on `mayEdit`; each owner-only
  control inside gates on `isOwner`.** The screen is not one permission — title,
  currency and the recommended period are an editor's to change; cover,
  visibility, the editor list and delete are not. An editor's `else` branch of the
  danger zone is `EditorAccessRow` (removing themselves — the way out that *is*
  theirs). `_CannotEditNotice` refuses only someone who can neither own nor edit,
  and fires **only on evidence** — a still-loading profile falls through to the
  form, or a cold deep link would lock the owner out of their own trip.
  **`visibility` must be absent from the PATCH body for a non-owner**: the server
  refuses the key, not the value.
- **Any surface that pushes an editing route claims the lock first.**
  `_openStopForm` and `_openDetailsForm` do the round trip before pushing and
  abandon the push if the claim is refused — the "someone else is editing" banner
  is the honest answer at that point, not an error after the user has typed.
- **A lock loss must never pop a route or clear a controller.** The ejected user
  is mid-edit and their unsaved text is now the only copy: `EditLockLostNotice` is
  a **persistent banner** — not a snackbar, it has to still be visible two minutes
  later — Save is disabled, every field stays populated and editable, and there
  are two ways out that both preserve the work: reclaim, or copy.
- `extractErrorMessage` maps the three typed lock exceptions, so every compose
  surface explains itself without its own branch. Forms that must *also* protect
  unsaved input catch the type instead.
- **`EditLockState.fromString` degrades unknown values to `active`** — the
  conservative direction, so a newer backend never makes an older client offer a
  takeover it does not understand.
- **`X-Edit-Lock` is never attached from a Dio interceptor.** A blanket one would
  send a dead token onto requests that must not carry one.
- Regression tests: `test/widgets/itinerary_edit_form_access_test.dart`.

## Known gaps / TODOs

- **`de`, `es` and `zh` are each missing all 36 edit-lock / editor l10n keys** —
  `apiErrorEditLockLost`, `apiErrorEditorCannotView`, `editLockAvailableIn` and
  33 more. `fr` and `ar` are complete. Measured by diffing the `.arb` files. See
  [backlog.md](../backlog.md).
- `moderate_or_422`'s docstring says the caller "must not have added rows to the
  session", but this guard's step 6 writes the heartbeat before the endpoint body
  runs — see OPEN QUESTIONS in [text-moderation.md](text-moderation.md).

## Related

- [visibility-and-access.md](visibility-and-access.md) — the ladder this delegates to
- [etag-concurrency.md](etag-concurrency.md) — steps 5–6 of the same guard
- [itineraries.md](itineraries.md) — what an editor may and may not change
- [tracks-and-stops.md](tracks-and-stops.md) · [annotations.md](annotations.md) · [transit-segments.md](transit-segments.md) — the guarded content
- [notifications.md](notifications.md) — `itinerary_editor_added`
- [reference/error-codes.md](../reference/error-codes.md#edit-lock-and-editors)
- [reference/data-model.md](../reference/data-model.md)
