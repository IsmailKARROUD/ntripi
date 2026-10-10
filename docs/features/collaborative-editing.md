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
- **Across a block in either direction the grant answers 404 `user_not_found`**
  (`require_not_blocked_or_404`), the same body as a missing account. The 409
  below, naming `visibility: public`, could only have meant the target had
  blocked the owner (until 2026-09-28).
- **Granting to someone who cannot view answers 409 `editor_cannot_view`** with
  `extra = {visibility, can_fix_with_allowlist}`. That is a question, not an
  error: the client asks the owner and re-posts with `grant_view: true`.
- **`can_fix_with_allowlist` is true only when an allowlist row would actually
  help** — the itinerary is `restricted` **and** the target is not already on the
  allowlist. An allowlisted target who still cannot view is blocked by something
  else (a moderator hide, a block in either direction), so the answer is false.
- **After `grant_view` inserts its row, `add_editor` re-runs
  `can_view_itinerary`** and refuses with the same 409 if the target is still
  blind. The raise rolls the allowlist row back, so a refused grant leaves no
  allowlist row, no editor row and no notification behind. Before 2026-09-27 a
  re-post for an already-allowlisted target inserted a duplicate row and 500'd
  on the composite PK, and a blocked target was granted edit rights — and
  notified — for a trip that 403'd them.
- **`grant_view` may only insert an allowlist row, and only for `restricted`.**
  It must never change `visibility` — `followers → restricted` would silently cut
  off every follower, and `only_me → anything` is a privacy decision the owner
  has to make deliberately.
- **Removing someone from the allowlist releases their claim when it ends their
  edit rights** (a restricted trip, where the allowlist row is what let them see
  it) — the same reason `remove_editor` releases; before 2026-09-28 their claim
  blocked every other editor until the TTL.
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
- **A lost first-claim race answers 423, not 500.** `FOR UPDATE` locks nothing
  while no claim row exists, so two first claims could both pass the check; the
  insert is `ON CONFLICT DO NOTHING` (`database.upsert_insert`) and the loser is
  told who won, exactly as if it had arrived second.
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
- **The claim follows the screens editing under it.** The detail screen and the
  stop page `attach()` in `initState` and `detach()` in `dispose` (through a
  notifier held in a field — never `ref` in dispose). When the last screen
  detaches, the claim is released after `kEditLockDetachGrace` (3 s) unless one
  re-attaches — a `router.go()` that rebuilds the detail screen does, well within
  it. A claim that lands after every screen has gone (the user backed out while
  the acquire was in flight) starts the same grace. Before 2026-09-28 nothing
  stopped the heartbeat: a claim left behind by a push tap or a deleted itinerary
  stayed "active" for as long as the app lived.
- **Edit mode is this device holding the claim, wherever it was taken.** A
  rebuilt detail screen resumes a claim it already holds (starts in edit mode),
  and `_enterEditMode` never re-acquires a held claim — asking again used to earn
  a 423 saying this very device was editing "elsewhere". A claim taken while the
  detail screen is covered (from the stop page) flips it into edit mode through a
  `ref.listen` on the acquire edge; a lost claim does not flip it back, so the
  banner can offer the claim back.
- **The heartbeat stops for good on 403 and 404.** 403 means edit rights were
  revoked (the server checks them before the claim) and is surfaced as a lost
  claim; 404 means the itinerary is gone. Both used to be swallowed as dropped
  pings. The heartbeat, and the detail screen's lock poll, also skip while the app
  is not in the foreground; a matching token past its TTL is honoured when the
  user comes back.
- **Sign-out releases every claim this device holds** (`releaseAllEditClaims`),
  before the access token is discarded.
- **Leaving edit mode never hands the claim back under a running save**
  (2026-10-10). Every write that carries the claim goes through
  `ItineraryDetailNotifier._write`, which hands it the token — readable nowhere
  else, so no write can skip it — and counts the write until it and its refresh
  are done (`hasWritesInFlight`, `writesSettled()`). ✓ and Back call
  `_requestExitEditMode`: with nothing running it leaves at once; otherwise the
  page goes under `SavingOverlay` with "Saving your changes… You'll leave edit
  mode as soon as they're saved." (`editModeLeaveAfterSave`), takes no new edit,
  and leaves once every write has landed. A write that failed keeps the page in
  edit mode with the claim, under that write's own error and then "Your change
  wasn't saved, so you're still in edit mode." (`editModeStayedAfterFailedSave`)
  — the only word on it when the save came from the stop page, already gone, whose
  `LegEditor` has no screen left to report on. Before, ✓ released
  at once; if the release reached the server first the write was refused, and
  its error had no card left to show on — the change was lost without a word.
  Regression tests: `test/providers/itinerary_writes_in_flight_test.dart`,
  `test/widgets/edit_mode_exit_while_saving_test.dart`.
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
  is the honest answer at that point, not an error after the user has typed. The
  read-mode long-presses on the description and on an itinerary-level note claim
  the same way, and the long-press on a stop awaits the claim before pushing its
  form (until 2026-09-28 all three could open an editor whose Save 428'd).
- **Editing from the stop page enters the trip's edit mode.** Its chrome gates on
  `mayEdit`, not ownership (owner-only gating handed an editor the report flag
  instead of the pencil), in both modes. The pencil, the hero and note
  long-presses and the leg editor all run through `_inEditMode`: when this device
  holds no claim it acquires one — never with `takeover` — and **keeps it**, so
  the detail screen underneath is in edit mode when the user goes back and they
  leave it with ✓ there. Until 2026-10-08 this was `_withClaim`, which claimed per
  edit and handed the claim back, so a stop could be edited while the trip stayed
  in read mode. While the claim is held the page shows originals, never a
  translation.
- **A refused claim on the stop page is a pop-up, not a snackbar.** It names the
  holder in the banner's own words (`editLockCopy`, shared with
  `EditLockBanner`) and offers the takeover the banner would: the owner always,
  the user's own other device always (**Continue here**), an editor only once the
  server calls the claim `takeable`. The pop-up is the confirmation; confirming
  calls `acquire(takeover: true)` and opens nothing — the user taps Edit after.
  When takeover is not allowed it is `ConfirmDialog.inform`: when it will be, and
  a single OK. Regression test: `test/widgets/stop_detail_edit_lock_test.dart`.
- **"Change visibility" in the grant dialog opens the picker.** For an `only_me`
  or `followers` trip the dialog's confirm pops `EditorsScreenResult.openVisibility`
  and the Edit Itinerary form opens its visibility picker; the button used to just
  close the dialog. The results list's `Flexible` sits outside `OfflineGate`,
  whose offline `AbsorbPointer` otherwise broke the Flex parent data and crashed
  the dialog when the signal dropped (`test/widgets/editors_dialog_offline_test.dart`).
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
- Regression tests: `test/widgets/itinerary_edit_form_access_test.dart`,
  `test/widgets/stop_detail_edit_lock_test.dart`.

## Known gaps / TODOs

- `moderate_or_422`'s docstring says the caller "must not have added rows to the
  session", but this guard's step 6 writes the heartbeat before the endpoint body
  runs — see OPEN QUESTIONS in [text-moderation.md](text-moderation.md).
- The stop page has no persistent lock banner. A claim lost while it is open
  shows nothing until the next Edit (which then explains itself in the pop-up),
  and the pop-up's "take over in m:ss" is a snapshot, not a ticking countdown.
- **A flow that saves twice in a row can still be cut between its writes.**
  Adding a stop between two segment-joined tracks deletes the orphaned
  segment(s), then opens the stop form; ✓ or Back pressed during the deletes
  leaves edit mode once they land — before the form opens, which then has no
  claim to save with. The window is the length of the deletes.

## Related

- [visibility-and-access.md](visibility-and-access.md) — the ladder this delegates to
- [etag-concurrency.md](etag-concurrency.md) — steps 5–6 of the same guard
- [itineraries.md](itineraries.md) — what an editor may and may not change
- [tracks-and-stops.md](tracks-and-stops.md) · [annotations.md](annotations.md) · [transit-segments.md](transit-segments.md) — the guarded content
- [notifications.md](notifications.md) — `itinerary_editor_added`
- [reference/error-codes.md](../reference/error-codes.md#edit-lock-and-editors)
- [reference/data-model.md](../reference/data-model.md)
