# Notifications (in-app feed + FCM push)

**Status:** shipped (push **off unless configured**)
**Tables:** `notifications`, `device_tokens`, three `notify_*` columns on `users`
**Config:** `NOTIFICATION_RETENTION_DAYS`, `NOTIFICATION_MAX_AGE_DAYS`, `FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT_JSON`, `FCM_TIMEOUT_SECONDS`, `DEVICE_TOKEN_RETENTION_DAYS`

## Purpose

A bell beside the profile settings gear opens `/notifications`. Eight event types
land there; three can be switched off. Delivery is a foreground poll **plus** FCM
push on iOS and Android; web is poll-only.

## Rules

### The eight types

| Type | Trigger | Switchable |
|---|---|---|
| `follow_request` / `new_follower` | `follow_user` — branches on `is_private` | no |
| `follow_accepted` | `accept_follow_request` + the bulk auto-accept in `update_me` | **yes** |
| `itinerary_rated` | `upsert_rating`, **insert branch only** | **yes** |
| `itinerary_saved` | `save_itinerary`, **below the idempotent early return** | **yes** |
| `moderation_action` | `moderation_actions.auto_hide` + `hide_itinerary` / `soft_delete_itinerary` / `warn_user` | no |
| `itinerary_editor_added` | `add_editor` | no |
| `itinerary_viewer_added` | `add_allowed_user` | no |

**No switch for follow requests or moderation notices** — an unseen request
cannot be answered and an unseen takedown cannot be appealed in time.

### Rows are structured references, never rendered sentences

A row is `(type, subtype, actor_id, entity_type, entity_id)`; the text is built
client-side in `AppNotification.title()` from `AppLocalizations`. A stored English
string would be wrong in the other five locales, would freeze a display name
moderation later hides, and would need a backfill to reword.

### `notify()` is the only writer

`notification_service.notify` (`notification_service.py:41`). Its **three
suppression rules — self, muted, blocked** — only hold because there is one door.

**It does `db.add()` and nothing else: no commit, no flush.** This is the
opposite of the email senders' post-commit-and-swallow, deliberately — a mail
outage must not fail a user's write, but a notification belongs in the **same
transaction** as the event that caused it.

Nine call sites: `follows.py:147,294`, `users.py:181`,
`itineraries.py:942,1099,1810,1899`, `moderation_actions.py:215`,
`admin_service.py:226/275/302`.

### Per-type details

- **`moderation_action` carries the action name in `subtype`**, aligned with
  `ViolationItem.action`, so a new moderation action needs no new notification
  type. **`actor_id` stays null** — naming the reporter to the author would out
  them. Tapping routes to `/settings/account-status`, where the appeal button
  already lives.
- **`warn_user` is the deliberate exception to idempotency** — a second warning
  writes a second row, because escalation *is* the mechanism and collapsing it
  would hide that this has happened before. Warnings carry `entity_type="user"`
  and no title, and `_moderationTitle` must branch on `subtype == 'warn'`
  **before** the hide fallthrough or a warning renders as "your itinerary was
  hidden". They wear `cautionBg`/`cautionFg`, not `dangerTint` — nothing was
  taken down.
- **`ban_user` writes no notification and must not.** `deactivate_account` sets
  `is_active=False`, which 403s every authenticated request, so a banned account
  can never load `/notifications`. Suspended users get the email and the public
  token appeal form.
- **`auto_hide` returns `None` when the content was already hidden**, so hanging
  the notify off a non-`None` return makes a repeat sweep idempotent for free.
- **The two access grants name the itinerary in the sentence itself**, not in the
  subtitle: a restricted trip is in no feed and no search, so "you were added as
  an editor" leaves the reader with nothing to act on. The subtitle is spent on
  what the access *allows* (edit vs view) — the one thing the two rows do not
  share. Naming someone else's itinerary is safe here and only here: the grant
  being announced is what confers the right to see it. `add_editor`'s `grant_view`
  writes its allowlist row inline and sends **only** the editor notice.

### Preferences

**Three boolean columns on `users`** (`notify_ratings`, `notify_saves`,
`notify_follow_accepted`), checked at **write** time, exposed through the existing
`PATCH /users/me` and `UserPrivateProfile`. A muted type writes **no row at
all**. A separate table buys nothing — adding a type alters the `type` CHECK
constraint regardless.

### Reads and deletes

- **`badge_state` is one query** returning
  `COUNT(CASE WHEN read_at IS NULL)` and `MAX(created_at)`. `case`, not `FILTER`,
  so SQLite takes it.
- **`latest_at` is the arrival signal, not the count.** A count rise looks like
  the same thing and is not: reading one notification on another device while
  another arrives leaves the count untouched, so the arrival would be swallowed.
  The count is only ever the number on the bell.
- **`user_id` is in the `WHERE` as the IDOR guard** on mark-read and delete —
  matching on id alone would let anyone clear anyone's badge, and the 204 would
  not tell them. It also means another user's id is indistinguishable from a
  missing one.
- **`DELETE /notifications/{id}` and `DELETE /notifications` are idempotent and
  never 404.** The client removes the row on screen and sends the request only
  after a **five-second undo window**, so a retry or a row the sweep already took
  must not raise. Deletion is **hard** — a notification is a nudge, not evidence,
  and a moderation notice it pointed at survives on `/settings/account-status`.
- **The client marks read by id, never "everything".** `POST /notifications/read`
  with no `ids` marks every unread row; the app used to send exactly that, so rows
  past the first page, or arriving between the reload and the POST, were marked
  read without ever being shown. Since 2026-09-28 `markAllRead` names the unread
  rows actually loaded (batches of 200, the request's cap), and each page loaded
  by scrolling is marked as it arrives.
- **The feed pages** — 30 rows at a time (`kNotificationPageSize`), more loaded as
  the list nears its end, ids already shown skipped. It used to stop at the first
  page with no way to reach older rows. A background `silentRefresh` re-reads the
  first page only and keeps the older pages already loaded.
- `_resolve` resolves actor and entity in **two queries per page, not 2N**;
  actor display names go through `public_profile_text`; `entity_title` is null
  when the entity is gone.

### Retention — two cutoffs

- **`NOTIFICATION_RETENTION_DAYS = 90`** takes **read** rows.
- **`NOTIFICATION_MAX_AGE_DAYS = 365`** is a hard cap taking any row regardless
  of read state.

An unread notice outlives the first, because it is the recipient's only record
that something happened to them. It does not outlive the second, because a
year-old unread row is not something anyone can still act on and the feed would
grow forever. **Startup refuses a cap below the read window** (`config.py:293`).

---

## Push (FCM HTTP v1)

**OFF unless `FCM_PROJECT_ID` and `FCM_SERVICE_ACCOUNT_JSON` are both set.**
Unset, nothing is sent, nothing raises, and the poll is the only channel.

- **Push is a latency improvement over the poll, never a replacement.** FCM
  delivery is best-effort: OEM battery managers kill background processes, iOS
  throttles, tokens go stale silently, permission can be denied. `NotificationPoller`
  stays, and stays **unconditional** — gating it on push would inherit push's
  failure modes. **Nothing may be load-bearing on a push arriving.**
- **Zero new backend dependencies.** FCM wants an OAuth2 bearer from a service
  account, which `google-auth` (already installed for Sign-In) mints. So
  `push_service.py` is a `requests.post`, shaped like `jira_service.py`, not an
  SDK. It **fails open** like `email_service` and unlike `jira_service`: nobody is
  waiting on it, and a Google outage must not 500 a follow.
- **Dispatched `after_commit`, NEVER from inside `notify()`.** `notify()` adds its
  row to the caller's open transaction, so sending there would push for
  transactions that later roll back — and **a push cannot be un-sent**. `notify()`
  appends a `PendingPush` snapshot to `Session.info["pending_pushes"]`; the
  `after_commit` listener drains it. **An `after_soft_rollback` listener clears the
  queue**, or a rolled-back event would ride out on whatever commits next.
- **The dispatcher uses its OWN session** (`_session_factory`), not the request's.
  Pruning a dead token needs a commit, and committing on the request session
  inside `after_commit` would re-enter the very listener that called it.
- **`PendingPush` is a snapshot, not the ORM row.** After commit the row's
  attributes are expired and touching one fires a lazy reload on a session
  between transactions. Resolving actor name and itinerary title inside `notify()`
  also means the dispatcher queries nothing but `device_tokens`.
- **Suppression is inherited, not reimplemented.** Because push hangs off
  `notify()`, the self/muted/blocked rules and the three `notify_*` columns govern
  it for free. **There is no fourth preference column** — the OS permission is the
  master switch.
- **Server-rendered push text does not violate the "no stored rendered text"
  rule.** The OS draws the tray entry before our code runs, so client-side
  rendering is impossible; but the payload is transient and the `notifications`
  table still stores only the structured reference.
  **`app/constants/push_i18n.py` holds the strings, copied verbatim from the
  app's `.arb` files** — reword one, reword the other in the same commit.
  The moderation branch order is load-bearing (`warn` before the hide
  fallthrough), and moderation text carries **no reason and no reporter** — the
  tray entry is visible on a lock screen.
- **Locale lives on `device_tokens`, not on `users`** — one account can be a
  phone in French and a tablet in English, and it costs no new user column.
  Normalised on the way in (`fr-CA` → `fr`, junk → `en`), never 422.
- **The actor falls back to `@username`, not to "Someone".** `push_i18n`'s
  localised "Someone" is only for rows with no actor at all.
- **`device_tokens.token` is UNIQUE globally, not `(user_id, token)`.** FCM
  reassigns a token to whichever account is signed in on that install, so
  registering is an upsert that **MOVES** the row. Otherwise two people sharing a
  phone leave the first still receiving the second's notifications.
- **Sign-out must `DELETE /devices/{token}`, before the repository call that
  discards the access token.** A token that outlives the session delivers the
  previous user's notifications — including moderation notices — to whoever signs
  in next. The registered token lives in memory, so after a restart it used to be
  unknown and sign-out unregistered nothing: on launch `attachPushListeners` now
  re-adopts the registration when the OS already granted permission (never
  prompting) and a session exists, and `unregisterForPush` falls back to
  `getToken()`. Re-sending on launch also keeps `last_seen_at` fresh for
  `DEVICE_TOKEN_RETENTION_DAYS`, and makes `onTokenRefresh` work after a restart.
- **Dead tokens are pruned on `UNREGISTERED`, and on `INVALID_ARGUMENT` only when
  the error names the token** (a `message.token` field violation, or "registration
  token" in the message). FCM answers `INVALID_ARGUMENT` for a malformed
  *payload* too, and pruning on the bare code would have unregistered every
  device of every recipient over a bug of ours. A 500, a 503 or a 401 from a
  misconfigured key is transient and must never cost a working device its
  registration — unrecoverable without a reinstall. `_post`
  returns `sent` / `dead` / `failed` / `unreachable`; on `unreachable` the whole
  notification is **abandoned**, because this runs inline in the user's request
  and that bounds the delay at **one** timeout rather than one per device.
- `validate_credentials` runs at **startup** and **logs, never raises**.
  `json.loads(..., strict=False)` tolerates raw newlines in an env-pasted
  `private_key`.
- Payload: `notification{title, body?}`, `data` (values stringified, `None`s
  dropped, `actor_id` null on moderation rows), `android.priority=high`,
  `apns.payload.aps.sound=default`. **Badge count deliberately not set.**
- **Web push is deliberately excluded** — `DEVICE_PLATFORMS = ("ios", "android")`.
  It needs a service worker and a VAPID key this build does not ship.

---

## Delivery: foreground polling

Both notifiers are keep-alive and would otherwise `build()` once per launch — a
hot restart was the only way to see a new row.

- **`NotificationPoller`** (`presentation/widgets/notification_poller.dart`,
  mounted in `main.dart`'s `MaterialApp.builder`) polls
  `GET /notifications/unread-count` every **60 s**, and immediately on launch, on
  resume, on reconnect, and on login. The interval only bounds the worst case;
  the edges are what the user actually sees. On web the same
  `didChangeAppLifecycleState` hook is driven by the browser's
  `visibilitychange`, so tab blur/focus needs no separate path and the poller
  does **not** early-return on `kIsWeb`.
- **The gate is foregrounded + online + a settled `hasSessionProvider`** —
  `authNotifierProvider` would miss every session restored by splash, and an
  invalidated `FutureProvider` keeps serving its previous value while it reloads,
  so `isLoading` has to be refused separately or the frame after logout still
  polls.
- **The feed has a loud read and a quiet one — `refresh()` and
  `silentRefresh()`.** Nobody asked for the quiet one, so it **may not show a
  spinner and may not write `AsyncError`**: a failed `silentRefresh` keeps the
  loaded feed, exactly as a failed `poll` keeps the last good badge. `refresh()`
  only swaps in the skeleton when `!state.hasValue`, so pull-to-refresh keeps the
  list under the user's finger.
- **The badge has only `poll()`** — no forced variant. The three user actions that
  change it (`markAllRead`, `clearAll`, a committed delete) invalidate the
  provider outright, and a feed load hands its badge over via `setBadge`.
  `poll()`'s first call lands while `build()` is still in flight, so it awaits
  `future` rather than racing a second request.
- **`NotificationBadge.arrivedSince`** is the single place the `latest_at`
  comparison is written, used by both the cue and the screen. It returns false
  without a baseline, which is what stops every cold launch sounding like an
  arrival.
- **`silentRefresh()` refuses to run while a delete is queued.** Reloading inside
  the undo window puts the dismissed row back under the user's finger, and
  flushing the queue first would destroy the undo they were just offered.
- **Both screens refetch on open, before acting on what they loaded.** On the
  notification feed the order is load-bearing: `markAllRead` on a *cached* feed
  marks a row the user has never been shown read on the server — badge cleared,
  cue played, row never surfaced anywhere again. `_pullInArrivals` is
  `silentRefresh()` **then** `markAllRead()`, and `markAllRead`'s null-value
  early return keeps a failed load from clearing the badge anyway.
- **The refetch is unconditional.** `GET /notifications` carries the rows *and*
  the badge and goes through `ETagMiddleware`, so the conditional GET answers 304
  with an empty body when nothing changed. Gating it on the badge would skip when
  the badge is merely stale, and skip forever after a read on another device drove
  `unread` to 0.
- **`EditorialDivider(loading:)` is the on-open refetch's only visible sign.** The
  reload deliberately leaves the previous rows on screen, and a `RefreshIndicator`
  cannot fill in because it only draws for a real drag. Its 2 px box is fixed with
  the idle hairline top-aligned inside, so toggling never nudges the content. The
  screens raise it with `setState` from a **post-frame callback**, since
  `didChangeDependencies` runs inside the build pipeline.
- **`RefreshableCenter`** is how an empty or errored list stays pullable — a
  `RefreshIndicator` wrapped around the populated list sits behind the `isEmpty`
  early return, stranding the two states where the user most wants to ask again.

### The `dispose()` problem

**Both refs outlive their owner here, and Riverpod 3 throws for it.**

- The **widget `ref`** is backed by `BuildContext`, so `dispose()` must use a
  notifier captured while still mounted — seeded in `didChangeDependencies` (a
  teardown can beat the first build) and kept current by a
  `ref.watch(…notifier)` in `build`, because an invalidation swaps the instance
  and `dispose` must reach the live one. **Never `ref.read` from `dispose`.**
- The **notifier's own `ref`** is separate but just as fragile: every `state =`
  or `ref.invalidate` that follows an `await` needs an `if (!ref.mounted) return`
  guard, because logout invalidates the provider mid-flight and a disposed `Ref`
  throws rather than no-opping.
- The client-side delete is **deferred, not optimistic-with-rollback**:
  `dismiss` takes the row out of state and queues a `Timer`; only `_commit`
  sends. Undo is therefore real, where a server-first delete could only be
  "undone" by re-creating a row the API has no endpoint for. `flushPending()`
  runs from the screen's `dispose`, and **`_commit` never rethrows** — it runs
  from a timer, usually after the screen is gone, so the row reappearing is the
  failure signal.
- Regression test:
  `test/widgets/notifications_screen_teardown_test.dart`.

## Data model

`notifications` — `user_id` FK CASCADE (**deliberately not `index=True`** —
`ix_notifications_user_created` leads with it, so a standalone index would be a
redundant prefix; the old one was dropped in `a681984a1a04`), `type` CHECK (8),
`subtype`, `actor_id` FK SET NULL indexed, `entity_type` CHECK, `entity_id` (no
FK), `read_at` indexed.

`device_tokens` — `token` **UNIQUE**, `platform` CHECK ∈ `{ios, android}`,
`locale`, `last_seen_at`. **No device name, model or OS version** — none of it
would change what we send and all of it is a fingerprint.

Full columns:
[reference/data-model.md](../reference/data-model.md#notifications).
Migrations: `8cd9a4fe3396`, `cc4e95613bad` (viewer_added), `dfb62a1759d8`
(device tokens), `393a6b3179ce` (merge).

## API surface

| Method | Path | Auth | Request | Response |
|---|---|---|---|---|
| GET | `/notifications` | Bearer | `limit` 1–100, `offset` ≥0 | `NotificationsResponse{notifications, unread_count, latest_at}` |
| GET | `/notifications/unread-count` | Bearer | — | `UnreadCountResponse{unread_count, latest_at}` |
| POST | `/notifications/read` | Bearer | `MarkReadRequest{ids?}` (≤200; omit to mark all) | 204 |
| DELETE | `/notifications` | Bearer | — | 204, idempotent |
| DELETE | `/notifications/{id}` | Bearer | — | 204, **never 404** |
| POST | `/devices` | Bearer | `DeviceRegisterRequest{token, platform, locale="en"}` | 204 |
| DELETE | `/devices/{token}` | Bearer | — | 204, **never 404** |

`NotificationItem` = `{id, type, subtype, created_at, read, actor_id,
actor_username, actor_display_name, actor_avatar_url, entity_type, entity_id,
entity_title}`.

## Config

| Var | Default | Notes |
|---|---|---|
| `NOTIFICATION_RETENTION_DAYS` | 90 | read rows |
| `NOTIFICATION_MAX_AGE_DAYS` | 365 | hard cap; **startup raises if below the above** |
| `FCM_PROJECT_ID` | unset | **both required or push is off** |
| `FCM_SERVICE_ACCOUNT_JSON` | unset | the whole JSON, **not a path** — Railway has no filesystem for a key file. A real secret. |
| `FCM_TIMEOUT_SECONDS` | 5.0 | tighter than the other integrations' 10 s, because this runs inline |
| `DEVICE_TOKEN_RETENTION_DAYS` | 180 | an uninstall never tells us |

Client setup needs `flutterfire configure` to have written
`firebase_options.dart` + `google-services.json` + `GoogleService-Info.plist`
(the Android build fails loudly without the JSON, deliberately), and iOS needs an
APNs `.p8` uploaded to Firebase. Attach Firebase to the **existing** Google Cloud
project that holds the Sign-In OAuth clients. FCM carries no per-message charge.

## Flutter surface

- **Screens** — `NotificationsScreen` (`/notifications`),
  `NotificationSettingsScreen` (`/settings/notifications`).
- **Providers** (`features/notifications/providers/notification_provider.dart`):
  | Provider | Type | Holds |
  |---|---|---|
  | `notificationRepositoryProvider` | `Provider` | the repository |
  | `notificationsProvider` | `AsyncNotifierProvider` | the feed (**keep-alive**) |
  | `notificationBadgeProvider` | `AsyncNotifierProvider` | count + `latestAt` (**keep-alive**) |
- **`core/push/`** — `push_gateway.dart` (`PushGateway`, in
  `MaterialApp.router`'s builder beside `NotificationPoller`; owns the router and
  locale) and `push_service.dart` (the FCM plumbing). **Every entry point is
  `kIsWeb`-guarded**, and `initFirebase()` swallows a missing
  `google-services.json` so the app still launches without push.
- **The permission prompt is asked on `/notifications` and nowhere else.** iOS
  allows exactly one per install and a denial is only reversible in Settings, so
  it lands when the user has just shown they want notifications — not at launch,
  in front of an app they have not seen.
- **A cold start's tap is routed by the splash screen.** `attachPushListeners`
  keeps `getInitialMessage()`'s answer as a future; splash awaits
  `takeInitialPushRoute()` after its brand flash, then goes home and pushes the
  route over it, so Back still lands somewhere. The old post-frame drain lost
  every such tap: the platform reply arrives after the first frame, and splash's
  own `go('/profile/me')` overrode it anyway. This is the most common real-world
  path and the easiest to lose.
- **Tap routing reuses `notificationRoute()`** (`app_notification.dart`), a free
  function precisely because a push arrives as a bare `data` map with no
  `AppNotification`. A tray tap and a feed tap must never disagree.
- **Foreground messages are deliberately unhandled** — Android suppresses the
  tray entry while the app is open, and the poller's badge plus
  `Sfx.newNotification` already announce the arrival.
- **UNDO captures the notifier before the snackbar shows.** Dismissing the only
  row swaps the feed for the empty view; reading `ref` from the unmounted feed in
  the undo callback threw, and UNDO silently did nothing
  (`test/widgets/notification_undo_last_row_test.dart`).
- **`NotificationType.fromString` degrades unknown values** to a generic
  renderable row. Opening the screen clears the badge but **does not** flip the
  local rows — erasing the unread tint in the frame the user arrived to read it
  defeats the point.
- Admin badges come from `admin_service.nav_counts`; operators also keep their
  `OPERATOR_EMAIL` mail.

## Known gaps / TODOs

- **Push is code-complete but not fully provisioned.** The Android API key's
  `(package, SHA-1)` restriction silently blocks token registration, and the APNs
  `.p8` is outstanding. The backend is safe unconfigured. See
  [backlog.md](../backlog.md).
- **Web push is unbuilt** — needs a service worker and a VAPID key.
- `test_notifications.py` and `test_push.py` both run.

## Related

- [follows.md](follows.md) · [ratings.md](ratings.md) · [saved-itineraries.md](saved-itineraries.md) · [collaborative-editing.md](collaborative-editing.md) · [visibility-and-access.md](visibility-and-access.md) — the triggers
- [admin-and-appeals.md](admin-and-appeals.md) — `moderation_action`, and the sweep that purges
- [blocking.md](blocking.md) — one of the three suppression rules
- [accounts-and-profiles.md](accounts-and-profiles.md) — the three `notify_*` columns
- [authentication.md](authentication.md) — sign-out must delete the device token
- [etag-concurrency.md](etag-concurrency.md) — why the unconditional refetch is cheap
- [reference/data-model.md](../reference/data-model.md#notifications)
