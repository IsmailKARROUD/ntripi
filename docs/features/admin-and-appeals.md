# Admin dashboard, appeals and the sweep

**Status:** shipped (**404s entirely unless configured**)
**Tables:** `moderation_log`, `appeals`
**Config:** `ADMIN_BASIC_USERNAME`, `ADMIN_BASIC_PASSWORD`, `ADMIN_SESSION_EXPIRE_MINUTES`, `MODERATION_SLA_HOURS`, `SWEEP_TOKEN`, `SWEEP_IN_PROCESS`, `SWEEP_INTERVAL_MINUTES`

## Purpose

A server-rendered Jinja2 dashboard at `/admin` where an operator works the
moderation queues, a user-facing appeal path for every reversible action, and a
periodic sweep that enforces the review SLA and re-checks content that was let
through during an outage.

## Rules

### Access

- **Two layers.** HTTP Basic is a coarse gate in front of a per-admin session
  login; the session cookie carries `scope="admin"`, which an API access token
  can never have (its claims are `{sub, exp, iat}` only).
- **Both Basic credentials unset ⇒ every `/admin` route returns 404** — the panel
  is *invisible*, not merely locked. The router is also
  `include_in_schema=False`.
- **`users.is_admin` is set manually via SQL.** There is no API or UI to promote
  a user — a single-operator model (`models/user.py:80`).
- **`_LANES` is an allowlist** (`admin.py:832`) for the `next` parameter, which
  arrives in a form post and would otherwise be an open redirect off an
  authenticated admin session.
- `nav_counts` is injected in `_page` **only when `"admin"` is in the context**,
  so the login page does not pay for six `COUNT`s.
- **Only queues are badged.** Hidden / Removed / Suspended / Log are outcomes and
  would light permanently.

### Soft state

- `hidden_at` → owner-only. `deleted_at` → invisible to **everyone**.
- **An admin "delete" is a soft delete**; the *owner's* `DELETE /itineraries/{id}`
  is a hard delete. Two different operations behind one word.
- **`itinerary_detail` deliberately bypasses `can_view_itinerary`**
  (`admin_service.py:1022`) — hidden, removed and `only_me` content is exactly
  what a moderator must read. It returns `None` for a purged row, rendering a 404
  shell page. `public_page_live` mirrors the share gate exactly.
- **`_last_takedown_at` is a correlated subquery over `moderation_log`**
  (`admin_service.py:549`) because ratings and profiles have **no `hidden_at`**,
  so the log is the only record of *when*. Ordering by `updated_at` would be
  wrong — an author editing a hidden review would move it.
- `hidden_itineraries` excludes `deleted_at IS NOT NULL` so lanes do not
  double-count, and `overview_counts` mirrors each lane's predicate exactly.

### The moderation log

17 actions, in two groups:

- **Operator** — `dismiss, hide, unhide, undelete, delete, warn, ban, unban,
  appeal_restore, appeal_uphold, appeal_reduce`
- **System** (`admin_user_id IS NULL`) — `auto_reject, auto_hide_reports,
  auto_hide_sla, recheck, appeal_filed, legal_escalate`

`HIDE_FAMILY = (hide, auto_hide_reports, auto_hide_sla, auto_reject)` is shared
by the log template (which actions it offers to reverse), `_last_takedown_at`,
and the appeal logic — so the UI and the appeal rules cannot disagree about what
is reversible.

**Automated rows carry `content_snapshot=None`** and no raw text, email or
display name. Operator rows keep their snapshot.

**Never write an itinerary's moderation state from outside the owner's request
without `set_preserving_etag`** — 13 call sites go through it.

### Appeals

- **`hide` and every automated action are appealable.** `APPEALABLE_ACTIONS` is
  `delete, warn, ban, hide, auto_hide_reports, auto_hide_sla, auto_reject`: an
  auto-hide is provisional and nobody has judged it, so a one-tap appeal is the
  only thing between a false positive and a silenced user.
- **Filing an appeal writes its own `appeal_filed` log row** — proof the contest
  path was available and used.
- **One pending appeal per item.** An **upheld** appeal locks it for
  `REAPPEAL_COOLDOWN = 30 days`, measured from `updated_at` (the decision time).
- `_owns_target` (`appeal_service.py:83`) is the IDOR guard. A soft-deleted
  itinerary still carries `user_id`, so a removed trip stays appealable.
- **`_action_still_active`**: `ban` → `not user.is_active`; `delete` →
  `deleted_at IS NOT NULL`; `HIDE_FAMILY` → a per-target-type check; **`warn` →
  always true**, because a warning is a permanent record and stays contestable.
- **Three decisions:**
  | Decision | Effect |
  |---|---|
  | `restore` | clears `deleted_at` + `hidden_at`, sets `approved` via `set_preserving_etag`; un-bans if the original was a ban; clears the classifier queue |
  | `uphold` | status only; starts the 30-day cooldown |
  | `reduce` | a ban becomes a warning; a `delete` becomes a hide; **already in `HIDE_FAMILY` → honestly says the same as uphold** ("nothing to reduce it to") |
- `appeal.updated_at` is set **explicitly**, because SQLite has no `onupdate`
  semantics for a no-op UPDATE.
- **The log reason is `admin_response or appeal.user_reason`** — the user's own
  words are the reason of record.
- **`user_reason` is deliberately not text-moderated.**
- **A banned user cannot reach `/appeals/*`** — `is_active=False` 403s every
  authenticated request. The **public token form** is their only path: a JWT with
  `scope="appeal"` and a **30-day TTL that equals the re-appeal cooldown**.
  `/web/appeal-request` is enumeration-safe: it always renders the same page, and
  mints a link only if the address exists and has an appealable action.

### The sweep

`app/services/sweep_service.py`. **Idempotent by construction**;
`pg_try_advisory_lock(8215309471002117)` makes concurrent runs impossible
(skipped on SQLite).

**One of two drivers is required, or SLA auto-hide and post-outage re-checks
never run:**

- `SWEEP_IN_PROCESS=True` — an `asyncio` timer in the app process, interval
  `max(60, SWEEP_INTERVAL_MINUTES × 60)`. No token, no scheduler. The
  single-instance default.
- An external scheduler POSTing `/internal/moderation-sweep` hourly — keeps a
  wall-clock schedule across deploys, which restart the in-process timer.

**Both at once is safe** — the advisory lock makes the duplicate a no-op. The
loop re-raises `CancelledError`; swallowing it would break Starlette's lifespan.

**Three jobs:**

1. **SLA enforcement** — pending reports older than `MODERATION_SLA_HOURS`,
   oldest first, batch 200. Target gone → close as `auto_hidden`; otherwise
   `auto_hide(action="auto_hide_sla")`.
2. **Post-outage re-check** — `moderation_status == 'pending'` rows across
   itinerary title/description, rating notes and user display_name/bio, batch 100
   across all three. A verdict → `auto_reject`; still pending → leave it;
   `approved`/`flagged` → **assigned, not escalate-only**, because `pending`
   means there was never a verdict to escalate from.
3. **Housekeeping** — expired `text_moderation_cache`; **reviewed**
   `text_moderation_decisions` past retention (**unreviewed rows are the queue
   and are never purged**); expired bug reports; notifications; idle device
   tokens; dead edit locks.

Emails are collected during the transaction and sent **after** the commit, each
wrapped. **The re-check does not touch images** — a fail-open image scan sets
`pending`, and only the *text* fields get re-scanned.

`SWEEP_TOKEN` unset ⇒ the endpoint **404s**, and `secrets.compare_digest` runs
**unconditionally** — including for a missing or short header — so response time
reveals nothing.

## Data model

`moderation_log` — `admin_user_id` FK SET NULL (**NULL = automated**),
`target_type`, `target_id` indexed (no FK), `action` CHECK (17 values), `reason`
NOT NULL, `content_snapshot` JSON, `created_at` indexed.

`appeals` — `user_id` FK **CASCADE** (appeals are not evidence),
`moderation_log_id` FK SET NULL, `target_type` CHECK, `target_id` **NOT NULL with
no FK** (denormalised so the one-pending and cooldown rules survive
`moderation_log_id` being nulled), `status` CHECK ∈ `{pending, upheld, restored,
reduced}`, `user_reason` NOT NULL, `admin_response`, `updated_at` (**drives the
cooldown**).

Full columns:
[reference/data-model.md](../reference/data-model.md#moderation_log).
Migrations: `e190f1dcbf2c` created both; `cc74b2080cbf` allowed rating targets;
`eb9d286c54fb` added system actions and legal escalations; `e17d93969953` allowed
`undelete`; `12b6e3451c36` allowed `hidden` on the itinerary status.

## API surface

### Admin — 30 routes, all HTML, `include_in_schema=False`

| Lane | Routes |
|---|---|
| session | `GET/POST /admin/login`, `POST /admin/logout` |
| overview | `GET /admin` |
| reports | `GET /admin/reports`, `POST /admin/reports/{id}/action`, `POST /admin/reports/bulk` |
| flagged images | `GET /admin/flagged`, `POST /admin/flagged/{log_id}/action` |
| text flags | `GET /admin/text-flags`, `POST /admin/text-flags/{decision_id}/action` |
| legal | `GET /admin/legal`, `POST /admin/legal/takedown`, `POST /admin/legal/{id}/close` |
| appeals | `GET /admin/appeals`, `POST /admin/appeals/{id}/decide` |
| bugs | `GET /admin/bugs`, `POST /admin/bugs/{id}/close`, `POST /admin/bugs/{id}/jira` |
| outcomes | `GET /admin/log`, `/hidden`, `/removed`, `/suspended` |
| itinerary | `GET /admin/itineraries/{id}`, `POST …/unhide`, `…/restore`, `…/remove` |
| reversals | `POST /admin/ratings/{id}/unhide`, `POST /admin/users/{id}/unhide`, `POST /admin/users/{id}/unban` |

`bulk_resolve` only accepts `dismiss` / `delete`, silently skips non-pending
rows, and for rating or profile targets calls `hide_reported_target(commit=False)`
— the previous branch closed them as `content_removed` **without touching the
content**.

`sla_class`: `SLA_WARN=12h` → `sla-warn`, `SLA_LATE=24h` → `sla-late`, `None` →
`sla-ok` (neutral, not "freshly actioned").

### Appeals — user-facing

| Method | Path | Auth | Rate | Response |
|---|---|---|---|---|
| GET | `/appeals/violations` | Bearer | — | `ViolationsResponse{violations: [ViolationItem]}` |
| POST | `/appeals` | Bearer | 10/h | `AppealResponse` 201 |
| GET | `/appeal/{token}` | **none** | — | HTML form, or `token_invalid.html` — **always 200** |
| POST | `/web/appeal` | none | 10/h | `appeal_done.html` |
| GET | `/appeal` | none | — | `appeal_request.html` |
| POST | `/web/appeal-request` | none | 5/h | **always** `appeal_done.html` |

`ViolationItem` = `{id, action, target_type, target_id, item_title, created_at,
active, appealable, appeal_status, cooldown_until}`.
Errors: 422 `appeal_reason_required` / `appeal_reason_too_long`, 404
`appeal_target_not_found`, 409 `appeal_already_pending` / `appeal_already_decided`,
429 `appeal_cooldown`.

### Sweep

| Method | Path | Auth | Rate | Response |
|---|---|---|---|---|
| POST | `/internal/moderation-sweep` | `Bearer $SWEEP_TOKEN` | 10/min | the counters dict, or `{"skipped": "locked"}` |

Counters: `sla_hidden, sla_already_hidden, rechecked, still_pending,
recheck_hidden, cache_purged, decisions_purged, bug_reports_purged,
notifications_purged, device_tokens_purged, edit_locks_purged`.

## Config

| Var | Default | Notes |
|---|---|---|
| `ADMIN_BASIC_USERNAME` / `_PASSWORD` | unset | **both required, or `/admin` 404s** |
| `ADMIN_SESSION_EXPIRE_MINUTES` | 720 | 12 hours |
| `MODERATION_SLA_HOURS` | 20 | **validated `ge=1, le=22`** — the DSA clock starts when the report is *filed*, and 22 leaves margin for a run missed during a deploy |
| `SWEEP_TOKEN` | unset | **unset ⇒ the endpoint 404s** |
| `SWEEP_IN_PROCESS` | `False` | the in-app timer |
| `SWEEP_INTERVAL_MINUTES` | 30 | in-process only; floored at 60 s |

## Flutter surface

There is no admin client — `/admin` is server-rendered. The user-facing half:

- **`AccountStatusScreen`** — route `/settings/account-status`, the single home
  for violations and appeals. `myViolationsProvider`
  (`FutureProvider.autoDispose`).
- **`SuspendedScreen`** — route `/suspended`, for a banned account.
- A `moderation_action` notification routes here; **appeals must not get a second
  home**.
- `core/utils/appeal_link.dart` builds the public token link.

## Known gaps / TODOs

- **`csam_response_runbook.md` §6 is a decision table with an unticked "Signed
  off" column** (six stances awaiting counsel), §5 of the pipeline spec has eight
  unticked operator steps, and §7's readiness checklist is unticked — including
  *"Calendar reminder for a quarterly dry run"*. See [backlog.md](../backlog.md).
- **`MODERATION_LOG_SYSTEM_ACTIONS` declares `"recheck"` but nothing writes it** —
  `_hide_after_recheck` writes `auto_reject`.
- **No admin-provisioning UI** — `is_admin` is SQL-only, consciously, until a
  second operator exists.
- `appeal_already_decided`, `appeal_reason_required` and `appeal_reason_too_long`
  have no client localization.
- `/web/appeal-request` imports the private `auth_service._email_html`
  (`web.py:405`).
- `moderation_actions.py:119`: itineraries are deliberately not fully handled
  there — their restore must also clear `hidden_at`/`deleted_at`, so those callers
  go through `admin_service._reverse_takedown` instead. Documented asymmetry, and
  a refactor candidate.
- Tests: `test_admin_auth.py`, `test_admin_moderation.py`,
  `test_admin_text_queues.py`, `test_appeals.py`, `test_auto_hide_appeals.py`,
  `test_moderation_sweep.py`, `test_csam_takedown.py` all run.

## Related

- [content-reports.md](content-reports.md) — what fills the queues
- [text-moderation.md](text-moderation.md) · [image-moderation.md](image-moderation.md) — the other two queues
- [visibility-and-access.md](visibility-and-access.md) — what hiding does
- [etag-concurrency.md](etag-concurrency.md) — `set_preserving_etag`
- [notifications.md](notifications.md) — `moderation_action`, and why `ban_user` sends none
- [bug-reports.md](bug-reports.md) — the `/admin/bugs` lane and Jira
- [accounts-and-profiles.md](accounts-and-profiles.md) — `is_active`, `is_admin`
- [passwords-and-email.md](passwords-and-email.md) — the shared email plumbing
- `../../social_api/docs/csam_response_runbook.md`
