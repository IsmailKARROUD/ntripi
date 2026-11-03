# Account deletion — in the app, and without it

**Status:** shipped
**Tables:** `users` (deleted; `erasure_requested_at`, `erasure_request_lang`), `signup_blocks`, `email_tokens` (purpose `account_delete`)
**Config:** `ACCOUNT_DELETION_RATE_LIMIT` (default `5/hour`), `OPERATOR_EMAIL`, `PRIVACY_CONTACT_EMAIL`; a sweep driver (`SWEEP_IN_PROCESS` or the scheduler) for deferred erasures

## Purpose

GDPR erasure of an account, by two routes that end in one function:

- **In the app** — `DELETE /users/me`, after re-authenticating with a password
  or a fresh Google ID token.
- **Without the app** — `/delete-account`, a public web page. Google Play's
  Data safety form needs a URL where someone who no longer has the app can get
  their account deleted, and this is it: **`https://ntripi.app/delete-account`**.
  It is also the only erasure route a suspended account has, since the app's
  answers 403 to every request from one.

## Rules

### One erase function

**`account_service.erase_account(db, user)` is the only code that deletes a
User row** (`account_service.py:68`). Its callers do their own proof of who is
asking — re-authentication in the app, an emailed single-use link on the web,
and the sweep finishing an erasure that had to wait — and then hand over. Order
is load-bearing:

1. **Lock the user row** (`SELECT … FOR UPDATE`, re-read). Two erasures of one
   account — the web link and the sweep, or two devices — would otherwise both
   decrement the counters; the second waits, finds the row gone and returns
   `False`, changing nothing.
2. **Decrement other users' follow counters before the cascade**, by bulk
   `UPDATE`, clamped at 0 with the same `case()` as `bump_follow_counters` — the
   one documented exception to "`bump_follow_counters` is the only way to touch
   the counters".
3. **Null `ItineraryRating.user_id` explicitly** — belt and braces over the
   `ON DELETE SET NULL`. The score and the review text stay (Terms §9.2,
   Privacy §10, since 3.3 / 2.6).
4. **Collect the image keys, block a suspended account's address, delete the
   row, commit.** The cascade removes itineraries, stops, annotations, allowlist
   and editor rows, locks, follows, blocks, notifications, device tokens, saves,
   appeals, refresh and email tokens, password history, the security audit log,
   the cached translations of every owned itinerary and the hourly translation
   counter.
5. **Erase the images, after the commit, best-effort** (`_erasable_image_keys`):
   the avatar, the profile cover and every owned itinerary's cover — **except**
   while the account is under an open legal escalation (nothing is erased), and
   except the cover of any itinerary that was taken down (`deleted_at` /
   `hidden_at`, `hidden` / `rejected`) or is escalated in its own right. A
   storage failure is logged, never raised.

Storage deletes go through `storage.factory.delete_from_sync` (`asyncio.run`),
not `anyio.from_thread.run`: the in-process sweep runs in `asyncio.to_thread`
(`main.py:182`), which is not an anyio worker thread, and `from_thread.run`
raises there — every deferred erasure would have kept every image. Callers are
sync code on a worker thread; never call it from an `async def`.

**Rows that survive with a NULL user, because they are evidence:**
`content_reports.reporter_user_id`, `moderation_log.admin_user_id`,
`image_moderation_logs.uploader_user_id`,
`text_moderation_decisions.author_user_id`, `bug_reports.user_id` and
`.closed_by_admin_id`, `legal_escalations.closed_by`, `notifications.actor_id`,
`itinerary_editors.granted_by`, and `itinerary_ratings.user_id`. **Rows that
survive untouched**: `moderation_log` rows about the account or its content —
an operator row keeps its `content_snapshot` (an account's email, username,
display name and avatar URL; a trip's title and description; a review's text)
— `content_reports` about its content and `legal_escalations`. Nothing purges
them (Privacy §10 says so since 2.6).

### The web flow

```
GET  /delete-account                  the form, and what deletion keeps
POST /web/delete-account-request      → the same page for every address
                                        (background: lookup, token, email)
GET  /delete-account/confirm?token=   what the link will delete; never deletes
POST /web/delete-account              consume → defer, or erase
```

- **The request route takes no database session at all** (`web.py:562`). It
  schedules `account_service.send_deletion_link` as a `BackgroundTasks` job and
  renders one "check your email" page, so neither the content nor the time of
  the answer can depend on whether the address has an account — the property
  `/auth/forgot-password` does not have (it looks up and sends inside the
  request). `test_the_request_route_takes_no_database_session` pins it
  structurally. The job opens its own session (`_session_factory`, the
  `translation_service.pretranslate_title` precedent; conftest points it at the
  test database for every test).
- **Suspended accounts get a link too** — the owner's choice: GDPR erasure does
  not end with a ban, and this is their only route.
- **A single-use `email_tokens` row**, purpose `account_delete`
  (`email_token_service.PURPOSE_ACCOUNT_DELETE`), valid
  **`ACCOUNT_DELETE_LINK_TTL` = 1 hour** — between the reset link's 30 minutes
  and verification's 24 hours. Only the SHA-256 is stored (`token_util`).
- **The link never erases, and its page never spends it.** Mail scanners open
  every link in an email, so `GET /delete-account/confirm` reads the token with
  `email_token_service.peek` and shows a form; only its button (a POST) consumes
  and erases. Two GETs, then the owner's POST, works.
- **The mailbox owner wins**, as everywhere else: registration verifies no
  address, so an account squatting someone's address can be erased by the
  address's owner.
- **Every page and both emails are in the language the request was made in**
  (`resolve_lang`); the forms post to `?lang=`, the link carries `&lang=`, and
  the deferred completion email uses `users.erasure_request_lang`. The copy is
  `i18n.TRANSLATIONS` (`delete_*`, `deleted_*`, `email_button_fallback`), all
  six languages.
- **What deletion keeps is not repeated on the page** — `GET /delete-account`
  renders the help block `your-data-and-privacy#what-deletion-keeps` (one text,
  six languages), so the page and the help centre cannot disagree.
- **The link is escaped in the email** (`branded_email_html`): it carries
  `&lang=`, and to some mail clients a raw `&lang` is the entity `&lang;`, which
  turns the URL into `…〈=en` and breaks the link.
- **Rate-limited per IP**: the request POST by `ACCOUNT_DELETION_RATE_LIMIT`
  (`5/hour`, the appeal-request limit — each request can email a stranger's
  address), the erase POST at `10/hour`. A person can reach these, retrying while
  the email is slow or from a shared address, so a limited request gets a page
  in the reader's language with `Retry-After`
  (`web.deletion_rate_limited_page`), not slowapi's raw JSON.

### Deferral under an open legal escalation

- **`account_service.erasure_blocked(db, user)`**: an open `legal_escalations`
  row on the account, on a trip it owns or on a review it wrote. One `EXISTS`,
  explicitly correlated (`correlate_except`) — left to auto-correlation the
  inner `EXISTS` put `users` in its own `FROM`, true for anyone's escalated trip.
  `test_someone_elses_escalated_trip_holds_nothing` pins it.
- **The web flow defers instead of erasing** (the owner's choice): the account
  is evidence until then. `defer_erasure` stamps `erasure_requested_at` (the
  first request's time stands) and `erasure_request_lang`, through a Core
  `UPDATE` that writes `updated_at` back to itself — `/admin/suspended` reads
  `updated_at` as the suspension time — and emails the operator
  (`operator_alerts.email_operator`, per event, never throttled).
- **The requester is told nothing about why** — `delete_account_deferred.html`
  says the account will be deleted as soon as possible, that they will be
  emailed, and gives `PRIVACY_CONTACT_EMAIL`.
- **The sweep finishes it** (`account_service.erase_deferred`, the sweep's last
  job, so one of the two sweep drivers must be on — as SLA hides already
  require): accounts with a request that no escalation holds any more, oldest first,
  `DEFERRED_ERASURE_BATCH` = 50 a run. The escalation filter is in the query,
  so held accounts never starve the batch. Each erasure commits on its own; a
  failure rolls back and is retried next run. Counter `deferred_erasures`
  (appended last). Each erased address is emailed in its stored language, with a
  link to what deletion keeps.
- **`/admin/legal` lists the waiting requests** (`pending_erasures`): username,
  email, how long, and whether an escalation still holds it. Read-only — the
  sweep acts.
- **The in-app path does not defer.** `DELETE /users/me` under an escalation
  still erases the rows, keeping only the images, exactly as before — its
  answer is what installed builds parse, and the owner asked for it unchanged.
  Logged in [backlog.md](../backlog.md).

### The sign-up block

- **Erasing a suspended account blocks its address from signing up again**
  (the owner's choice), in the same transaction as the erasure.
- **Stored as a keyed hash, never the address**: `token_util.keyed_hash` (HMAC
  on `SECRET_KEY`, the report IP-hash precedent) of the lowercased address, in
  `signup_blocks`. Sign-up hashes the address it is given and looks it up; the
  table cannot be listed or reversed without the key. (The plain address does
  survive in the ban's `moderation_log` snapshot — the block does not depend on
  it.)
- **Both sign-up paths refuse it with 400 `email_unavailable`** — `/auth/register`
  after the ToS and age gates and **before `moderate_or_422`** (no paid scan for
  a refusal), `create_user` again (it commits), and the Google new-account
  branch before the People API and the name scan. Sign-in and account linking
  never consult it. The message never says why.
- **Kept until an operator lifts it** — no expiry, as a ban has none.
  `POST /admin/signup-blocks/lift`, from a form on `/admin/suspended`, hashes the
  address typed in and deletes the row (the remedy for a disputed block, or an
  address a mail provider gave to someone new).
- **Rotating `SECRET_KEY` lifts every block** — every hash changes. A rotation
  also signs everyone out, so it is rare and deliberate.
- Aliases of one mailbox (`+tag`, Gmail dots) are not recognised.

## Data model

- `users.erasure_requested_at` TIMESTAMPTZ nullable, `users.erasure_request_lang`
  VARCHAR(8) nullable — on the model only, in no schema.
- `signup_blocks` — `email_hash` VARCHAR(64) PK, `created_at`. No user
  reference.
- `email_tokens.purpose` gains `account_delete` (no CHECK, no migration).

Migration `e24b3c5c59ba` (two nullable columns and an empty table — no
`CONCURRENTLY`). Full columns: [reference/data-model.md](../reference/data-model.md#users).

## API surface

| Method | Path | Auth | Rate | Response |
|---|---|---|---|---|
| DELETE | `/users/me` | Bearer | — | 204; `DeleteAccountRequest{password?, google_id_token?}`; 401 ×4 — see [accounts-and-profiles.md](accounts-and-profiles.md#api-surface) |
| GET | `/delete-account` | none | — | HTML form + the help block |
| POST | `/web/delete-account-request` | none | `ACCOUNT_DELETION_RATE_LIMIT` | HTML, the same for every address; 429 is an HTML page |
| GET | `/delete-account/confirm?token=` | the token | — | HTML confirm page, or `token_invalid.html` |
| POST | `/web/delete-account` | the token | 10/h | HTML done / deferred page, or `token_invalid.html` |
| POST | `/admin/signup-blocks/lift` | admin | — | 303 to `/admin/suspended` |

The four public routes are `TOKEN_FORM` in `test_public_surface.py` and stay out
of `APP_LINK_PATHS` — they are web forms, like the reset and appeal links.
`/delete-account` is in the sitemap; the confirm page is not.

New error code: **`email_unavailable`** (400) — see
[reference/error-codes.md](../reference/error-codes.md#registration-tos-and-age-gate).

## Flutter surface

- The in-app path is unchanged: `DeleteAccountScreen` (`/settings/delete-account`),
  opened from the profile edit form's Security section; Tier-3
  `confirmTypedDestructiveAction()`.
- `email_unavailable` is localized (`apiErrorEmailUnavailable`, six `.arb`
  files, `localizedApiError`), so the sign-up screens show it in the reader's
  language. Installed builds older than that show the server's English
  `detail`.

## Help centre

`your-data-and-privacy#deleting` gives both routes;
`#what-deletion-keeps` (new) lists what stays and is rendered on
`/delete-account`; `sign-in-and-account-security#deleting` and `#suspended` link
the web route — all six languages, `updated` 2026-11-03. What's New 0.4.0 has
the entry. None of the eight in-app FAQ answers covers deletion.

## Known gaps / TODOs

- **The in-app path erases under an open escalation** (rows gone, images kept)
  where the web path defers. Aligning it needs a new answer from
  `DELETE /users/me` and app copy for it — [backlog.md](../backlog.md).
- **No operator erase.** Someone who lost the mailbox can only write to
  privacy@; erasing for them needs SQL — [backlog.md](../backlog.md).
- The image-delete step runs after the commit and is best-effort; an object a
  storage outage left behind is not retried.
- Tests: `test_account_service.py` (the function), `test_account_deletion_web.py`
  (the flow, the block, the deferral, the admin lanes), and the unchanged
  `test_account_deletion.py`. **The suite runs on SQLite, which has no row
  locks**, so the `FOR UPDATE` in step 1 is not exercised by it. It was checked
  by hand on PostgreSQL 14 on 2026-11-03, with the migration up, down and up:
  two links for one account at once and one link double-clicked, six rounds
  each, gave no 500 and moved the follow counter exactly once.

## Related

- [accounts-and-profiles.md](accounts-and-profiles.md) — the account, the in-app delete screen
- [legal-and-age-gate.md](legal-and-age-gate.md) — Terms 3.3 / Privacy 2.6 say what deletion keeps
- [content-reports.md](content-reports.md) — legal escalations, what defers an erasure
- [admin-and-appeals.md](admin-and-appeals.md) — the sweep's job, the Legal and Suspended lanes
- [passwords-and-email.md](passwords-and-email.md) — `email_tokens`, the translated email builder
- [ratings.md](ratings.md) — a deleted account's reviews stay, anonymised
- [help-centre.md](help-centre.md) — the block the page renders
- [web-and-platform.md](web-and-platform.md) — the public surface and the rate limit
- [reference/data-model.md](../reference/data-model.md) · [reference/error-codes.md](../reference/error-codes.md)

## OPEN QUESTIONS

- **How long may a deferral last, and what must the requester be told once a
  month has passed?** GDPR Art. 12(3)–(4) set a month (extendable) for an answer
  and want reasons for not acting; a legal hold may restrict what can be said.
  The page and the emails say only that the deletion will happen. For counsel.
- **Backups.** Railway's database backups keep an erased account for as long as
  a backup is kept; nothing in this repository says how long that is.
