# Bug reports (shake to report) and Jira hand-off

**Status:** shipped (Jira **off unless configured**)
**Tables:** `bug_reports`
**Config:** `BUG_REPORT_RATE_LIMIT`, `BUG_REPORT_RETENTION_DAYS`, `OPERATOR_EMAIL`, `JIRA_*`

## Purpose

Shaking the phone captures the screen, lets the user draw on it, and files a
support ticket. An operator works the queue at `/admin/bugs` and can hand a
ticket to Jira with one click.

**Deliberately not part of the moderation stack**: `content_reports` is evidence
about content someone else published, with hide thresholds and escalation paths;
`bug_reports` is a ticket about our own app, reviewed and then purged once closed
and stale.

## Rules

### Intake

- **`POST /bug-reports` is one multipart request** carrying the fields and the
  screenshot. Two requests would orphan the object in R2 whenever the second
  failed.
- **Auth-optional** — someone stuck on the login or suspended screen is exactly
  who needs to report.
- **`_clean` drops an unexpected diagnostics value rather than 422ing**
  (`bug_reports.py:48`): losing a report because a device string was odd is the
  wrong trade. The column CHECKs are the real guard.
- **`message` is not text-moderated** — same rule as report notes and appeal
  reasons.
- Rate-limited **5/hour**, lower than the report limit because each one carries an
  upload.

### The screenshot

- **Uses `process_screenshot_image`, not the cover/avatar processors** — those
  cover-crop (destroying a portrait capture) and reject anything under 600 px. It
  preserves aspect, downscales to a 1600 px long side, and relaxes the minimum to
  200 px via `_decode_and_validate(min_dimension=…)`.
- **No Rekognition scan** — it is never served to another user, so a hard reject
  could only drop a real bug report because our own UI tripped a classifier.
  **`process_and_store` still strips EXIF.**
- Key is `bug_reports/{report.id}.jpg`, `cache_bust=False`.
- **An `ImageProcessingError` keeps the report** and logs a warning.
- **`screenshot_key` stores the storage key, not a URL**: the retention purge
  needs it, and it keeps bug screenshots outside
  `admin_service.parse_storage_key`, whose whole job is refusing to guess.

### Retention is a privacy duty

Not housekeeping — **a screenshot can contain a third party's data.**
`bug_report_service.purge_expired`:

- runs from `sweep_service`;
- **only ever touches `closed` reports** — nobody has read an open one yet;
- **deletes the object *before* the row**, so a storage failure keeps the row and
  the next sweep retries rather than orphaning a screenshot;
- uses `asyncio.run()` for the delete, safe because the sweep only runs on a
  worker thread.

### Status vocabulary

`open` | `closed` only. **There is deliberately no wontfix/fixed split** — the
`resolution_note` carries that, and a wider vocabulary would need an admin UI
nobody asked for (`models/bug_report.py:41`).

Closing a bug report writes **no `moderation_log` row** — it is not an action
against a user.

### The Flutter plumbing

- **Two packages, one custom sheet.** `shake` (accelerometer, pulls
  `sensors_plus`) and `feedback` (screenshot + draw layer). The compose UI is ours
  via `feedbackBuilder` — `bug_report_sheet.dart`, mirroring
  `report_content_sheet.dart`.
- **`BetterFeedback` must wrap `MaterialApp`, not sit inside
  `MaterialApp.builder`.** Its bottom sheet builds a bare `Navigator`; inside
  `MaterialApp` that Navigator inherits the app's `HeroController` and Flutter
  asserts ("a HeroController can not be shared by multiple Navigators"). **The
  consequence is that the sheet renders outside `MaterialApp`**, so it gets l10n
  from the delegates passed to `BetterFeedback` (the app's own are listed there)
  and its `ThemeData` from `ntripiFeedbackAppTheme` in the `feedbackBuilder`.
  **`localeOverride` is required too** — that scope otherwise resolves the
  *platform* locale and ignores the in-app language picker, and it is what drives
  `Directionality` for Arabic.
- **`ShakeToReport` stays *inside* `MaterialApp.builder`** so the handler has a
  `ScaffoldMessenger` for the confirmation snackbar; `BetterFeedback.of()` still
  finds the controller above.
- **`BetterFeedback` owning the outermost `Overlay` redefines what
  `rootOverlay: true` means app-wide.** The package hosts the entire app in one
  `OverlayEntry` with `maintainState: false`, so
  `Overlay.of(context, rootOverlay: true)` now resolves **outside** `MaterialApp`:
  an entry inserted there gets no app `Theme` and no app `Localizations`, and an
  `opaque: true` one drops the app's own entry from the element tree — unmounting
  every route, disposing them, and then throwing from `LocalHistoryEntry.remove()`
  on the dead route so the overlay can never close itself.
  **Anything wanting a full-window layer above the app wants
  `Navigator.of(context, rootNavigator: true).overlay` instead**
  (`openImageCropOverlay` in `cover_image_field.dart`; regression test
  `test/widgets/cover_crop_overlay_test.dart`). `field_help.dart` still uses
  `rootOverlay` — safe only because it is non-opaque and captures its colors from
  the caller's context.
- **The gesture is opt-out-able** (`shakeReportEnabledProvider`, secure storage,
  default on) and guarded: `minimumShakeCount: 2`, paused whenever the app is not
  `resumed`, a **3 s cooldown**, and skipped on `/splash`. **No-op on web**
  (`kIsWeb`) — the Settings ▸ Support row is the entry point there.

### Jira hand-off

- **It FAILS CLOSED — the only third-party integration that does**
  (`jira_service.py:14`). The operator is standing in front of the dashboard
  waiting for a key, so a silently dropped failure is worse than useless. A
  `JiraError` becomes a red flash carrying Jira's own message.
- **`bug_reports.jira_issue_key`'s presence IS the duplicate guard** — a
  non-empty value returns early **before** the API call, so two operators working
  the queue cannot file the same bug twice.
- **Sync `def` on purpose.** FastAPI runs it in a threadpool so the blocking
  `requests.post` never touches the loop; `async` would put the sync SQLAlchemy
  session on the loop.
- **`browse_base` normalises what the operator pasted** — adds a scheme to a bare
  hostname, and trims a leftover path **only for `*.atlassian.net`** (Cloud always
  serves REST from the site root; Server/DC may sit under a context path).
- **`_json_or_error` exists for one specific failure**: a wrong `JIRA_BASE_URL`
  returns the SPA shell at HTTP 200 with HTML, so the only symptom is an
  unparseable body.
- **A plain string is not a valid Jira `description`** — REST v3 requires ADF
  (`{"type":"doc","version":1,…}`), which `_adf` builds.
- `_summary` = `[category] first line`, clipped to 255 with an ellipsis (Jira
  rejects longer outright).

#### Reporter attribution

**The issue's Reporter is the admin who clicked**, not the service account. Jira
Cloud dropped username/email as user identifiers in the 2019 GDPR change, so
`find_account_id` resolves `admin.email` to an `accountId` via
`GET /rest/api/3/user/assignable/search?project=…` — **project-scoped**, because
"is this person on *this* board" is the actual question.

- **It matches on exact `emailAddress` only.** `query` also matches displayName,
  and a loose hit would file the ticket under a colleague's name.
- **Attribution is strictly best-effort.** A failed lookup, an unknown admin, or a
  Jira 400 naming `reporter` all **drop the field, file the ticket anyway**, and
  return a `JiraResult.warning` the dashboard shows as a yellow flash beside the
  green one. This is the one deliberate exception to the fail-closed rule, which
  still governs `create_issue` itself.
- Three Jira-side prerequisites, each of which merely degrades to that warning:
  the service account needs **Browse users and groups** (global) and **Modify
  Reporter** (project), and **Reporter must be on the create screen** for the
  issue type.

#### Privacy

**The Jira payload carries the reporter's `@username` but never their email** —
the operator inbox is one person, a Jira project is a whole team. The acting
**admin's** email is a different matter and does go to Jira, **as a
`user/assignable/search` query term only**; an operator's Jira identity is
already visible to that team, and it never reaches the ticket body.
**Never log `JIRA_API_TOKEN`.**

## Data model

`bug_reports` — `user_id` FK SET NULL (nullable, auth-optional), `message` TEXT,
`category` CHECK nullable-or-∈`{crash, visual, data, slow, other}`,
`screenshot_key`, seven diagnostics columns, `status` CHECK ∈ `{open, closed}`,
`resolution_note`, `jira_issue_key` (no constraint — keys are opaque),
`closed_at`, `closed_by_admin_id` FK SET NULL.
Index `ix_bug_reports_status_created (status, created_at)`.

Full columns:
[reference/data-model.md](../reference/data-model.md#bug_reports).
Migrations: `2b2bbad6e3c0`, `87495daa26f9` (the Jira key).

## API surface

| Method | Path | Auth | Request | Response | Errors |
|---|---|---|---|---|---|
| POST | `/bug-reports` | **optional**, 5/h | **multipart**: `message` (≤2000), `category?`, `app_version?`, `platform?`, `os_version?`, `device_model?`, `route?`, `locale?`, `theme_mode?`, `screenshot?` | `BugReportAck{ok, id}` 201 | 422 `bug_report_empty` |
| GET | `/admin/bugs` | admin | — | HTML | — |
| POST | `/admin/bugs/{id}/close` | admin | form | redirect | — |
| POST | `/admin/bugs/{id}/jira` | admin | form | redirect + flash | Jira's own message on failure |

## Config

| Var | Default | Notes |
|---|---|---|
| `BUG_REPORT_RATE_LIMIT` | `5/hour` | |
| `BUG_REPORT_RETENTION_DAYS` | `180` | **closed reports only** |
| `OPERATOR_EMAIL` | unset | **what turns the notification email on** |
| `JIRA_BASE_URL` / `_EMAIL` / `_API_TOKEN` / `_PROJECT_KEY` | unset | **all four required or the button is not rendered**; a partial config logs which are missing |
| `JIRA_ISSUE_TYPE` | `Bug` | must name a type that exists in that project |
| `JIRA_TIMEOUT_SECONDS` | `10.0` | |

`JIRA_PROJECT_KEY` is the board key (`NTRIPI`), not a numeric id. The token comes
from id.atlassian.com. The Jira Cloud REST API carries no per-call charge.

## Flutter surface

- **`bug_report_sheet.dart`** — the compose sheet, via `feedbackBuilder`.
- **`ShakeToReport`** — inside `MaterialApp.builder`.
- **`ReportBugScreen`** — route `/settings/help/report-bug`, which on web is the
  only entry point (it explains the shake gesture on mobile).
- **Providers** — `bugReportRepositoryProvider`, `packageInfoProvider`
  (`FutureProvider`), `shakeReportEnabledProvider` (`NotifierProvider`, secure
  storage).
- `diagnostics_service.dart` collects the version/platform/route fields.

## Known gaps / TODOs

- `bug_reports.theme_mode` and `locale` are written, shown in the operator email,
  the Jira description and `admin/bugs.html` — but never queried or grouped on.
  Display-only.
- `bug_report_empty` has no client-side localization.
- `test_bug_reports.py` runs.

## Related

- [image-pipeline.md](image-pipeline.md) — `process_screenshot_image`, `parse_storage_key`
- [admin-and-appeals.md](admin-and-appeals.md) — the `/admin/bugs` lane and the sweep
- [content-reports.md](content-reports.md) — the thing this is deliberately *not*
- [text-moderation.md](text-moderation.md) — why `message` is unmoderated
- [help-centre.md](help-centre.md) — the Support row that reaches this on web
- [notifications.md](notifications.md) — `PushGateway` sits beside `ShakeToReport`
- [reference/data-model.md](../reference/data-model.md#bug_reports)
