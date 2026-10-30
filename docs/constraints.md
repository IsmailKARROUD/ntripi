# Project-wide constraints

Rules that cut across features. **A new feature must not violate any of these.**
Each rule states what it is, why it exists, and where it is enforced.

`CLAUDE.md` at the repo root is the agent-facing rules file and says much of this
more tersely. This document is the human-readable version, verified against the
code, with links to the feature that exercises each rule.

---

## Portability

| Rule | Why | Where |
|---|---|---|
| Everything configurable is an env var | the app must run on any host with PostgreSQL and HTTP | `app/config.py`, `--dart-define` |
| A **single Dockerfile at the repo root**; Railway's Root Directory stays empty | one image serves the API and the Flutter web build | `Dockerfile` |
| **No platform-specific features** — standard PostgreSQL + HTTP only | no managed-service lock-in | — |
| **All storage goes through the abstraction.** Calling code uses `storage().save()` / `.delete()` only | swapping filesystem ↔ R2 is a config change | `app/storage/base.py` → [image-pipeline.md](features/image-pipeline.md) |
| **Backend and frontend share no code** — HTTP/JSON only | they deploy and version independently | — |
| Never reference `DATABASE_PUBLIC_URL` from the backend | use `${{Postgres.DATABASE_URL}}` — the public URL bills egress | Railway config |
| **Postgres runs in the same Railway region as the API service** (EU West) | a region is set per service, so moving the API never moves the database. A request waits on its database round trips one at a time, 8–20 per save; with Postgres in a US region each cost ~120 ms, and saves took 4–6 s until 2026-10-20 | Railway service settings → [decisions.md](decisions.md) |

---

## Config via env

### Startup validators that **raise**

Nine misconfigurations refuse to boot rather than degrade silently:

| Validator | Refuses | Why |
|---|---|---|
| `SECRET_KEY` `Field(min_length=32)` | a key under 32 chars | a weak or placeholder signing key must never reach traffic. `openssl rand -hex 32` |
| `_validate_text_moderation` | an unknown `TEXT_MODERATION_PROVIDER`; `openai` with no `OPENAI_API_KEY`; an unparseable `REPORT_HIDE_THRESHOLDS`, or one naming a category that is not in `constants/report_reasons.py` | a silent downgrade to the wordlist is worse than not booting; a typo'd category silently disabled auto-hide for the real one |
| `_validate_image_moderation` | an unknown `MODERATION_PROVIDER`; a `MODERATION_GOOGLE_*_LIKELIHOOD` that is not `POSSIBLE`, `LIKELY` or `VERY_LIKELY`; a reject level below the flag level | a provider name nothing can run would scan nothing, and a reject level under the flag level rejects images it never flags. A missing provider credential is not refused — it emails the operator instead ([image-moderation.md](features/image-moderation.md)) |
| `_validate_sweep_deadline` | with `SWEEP_IN_PROCESS`, `MODERATION_SLA_HOURS × 60 + SWEEP_INTERVAL_MINUTES > 24 × 60` | a report can wait the SLA plus one whole interval before a run sees it — past 24h the deadline the SLA exists for is breached |
| `_validate_notification_retention` | `NOTIFICATION_MAX_AGE_DAYS < NOTIFICATION_RETENTION_DAYS` | it would silently shorten the read window |
| `_validate_edit_lock_windows` | `TTL <= IDLE`; `IDLE < 2 × HEARTBEAT`; `HEARTBEAT < 5` | a claim that became takeable before it read as inactive would be stolen from someone the UI still showed as editing |
| `_validate_translation_detect_langs` | a `TRANSLATION_DETECT_LANGS` that is neither `all` nor a list of two-letter codes | a typo would otherwise surface on the first save that needs a language |
| `_validate_translation` | an unknown or repeated name in `TRANSLATION_PROVIDERS`; `openai` with no `OPENAI_API_KEY`; `azure` with no `AZURE_TRANSLATOR_KEY`; a `TRANSLATION_SUPPORTED_LANGS` code missing from `constants/translation_languages.py`; a `TRANSLATION_PRETRANSLATE_LANGS` code that is not supported; a non-positive timeout; an hourly limit under 1 or a negative budget (`Field` bounds) | the same stance as text moderation: a setup that would quietly translate nothing must not boot |
| `_validate_app_links` | an `IOS_APP_IDS` entry that is not `TEAMID.bundle.id`; an `ANDROID_CERT_SHA256` entry that is not 32 hex bytes; `ANDROID_APP_PACKAGE` without fingerprints or the reverse; a malformed package; a non-numeric `IOS_APP_STORE_ID`; a non-https store URL | a bad id or fingerprint makes the OS reject the association with no error anywhere — every shared link just keeps opening in the browser |

Two more refuse at first use rather than at import: **`STORAGE_BACKEND=r2` with
any `R2_*` var missing raises**, and an unknown `STORAGE_BACKEND` raises — and
`storage()` is called eagerly in the lifespan, so both surface on boot.

### The "unset = invisible" pattern

Six subsystems return **404** or render nothing when unconfigured, rather than
returning 401/403 — the feature is invisible, not merely locked:

| Unset | Effect |
|---|---|
| `ADMIN_BASIC_USERNAME` / `_PASSWORD` | every `/admin` route 404s |
| `SWEEP_TOKEN` | `POST /internal/moderation-sweep` 404s |
| any of the four `JIRA_*` | the "Create Jira issue" button is not rendered |
| `FCM_PROJECT_ID` / `FCM_SERVICE_ACCOUNT_JSON` | push is off; nothing sent, nothing raised |
| `TRANSLATION_PROVIDERS` | `POST /translations` 404s; `GET /translations/config` answers `enabled: false`, so no client offers the button |
| `IOS_APP_IDS` / `ANDROID_APP_PACKAGE` + `ANDROID_CERT_SHA256` | `/.well-known/apple-app-site-association` / `assetlinks.json` 404, so no phone hands a shared link to the app. Unset `APP_STORE_URL` / `PLAY_STORE_URL` point the share pages' download buttons at the waitlist |

### `OPERATOR_EMAIL` is the one to actually set

Unset, **four alert paths guard on it and skip the email** — `report_service`,
`moderation_service` (the image flag email), `bug_report_service`, and
`operator_alerts` (text and image moderation outages) — so the queues fill with
nobody told.

### Mailboxes

Google Workspace on the root MX; Resend sends from the `send.ntripi.app`
subdomain, so sending and receiving never collide.

| Address | Role |
|---|---|
| `ops@` | `OPERATOR_EMAIL` — the one to set |
| `abuse@` | published in-app **and on the store listing**; must match |
| `privacy@` | hardcoded in all six `app/constants/legal/*.py` as the GDPR controller contact |
| `support@`, `contact@` | the Flutter `kSupportContactEmail` / `kGeneralContactEmail` defaults — **change both sides together** |
| `noreply@` | the `EMAIL_FROM` sender; **must stay a real routed address** — users reply to password resets |

### Production settings that must not change

`DEBUG=False` (disables `/docs` and `/redoc`) · `ALLOWED_HOSTS=ntripi.app,*.ntripi.app`
(apex and wildcard listed **separately** — Starlette's wildcard does not match the
apex) · `ALLOWED_ORIGINS=https://ntripi.app` · `STORAGE_BACKEND=r2` with
`R2_PUBLIC_URL` on a **proxied custom domain**, never `pub-*.r2.dev`.

### `.env.example` is 14 settings behind

`Settings` declares **69** fields; `.env.example` documents **55**. Missing:
`ALLOWED_HOSTS`, `REFRESH_TOKEN_EXPIRE_DAYS`, `FEED_TOP_MIN_RATINGS`,
`PWNED_CHECK_ENABLED`, `SUPPORT_CONTACT_EMAIL`, `PRIVACY_CONTACT_EMAIL`,
`GENERAL_CONTACT_EMAIL`, `BUG_REPORT_RATE_LIMIT`, `BUG_REPORT_RETENTION_DAYS`,
`NOTIFICATION_RETENTION_DAYS`, `NOTIFICATION_MAX_AGE_DAYS`,
`EDIT_LOCK_HEARTBEAT_SECONDS`, `EDIT_LOCK_IDLE_SECONDS`, `EDIT_LOCK_TTL_SECONDS`.

**Three of those have startup validators that raise**, so an operator has no
discoverable way to learn the constraints. Logged in
[backlog.md](backlog.md).

---

## Authentication

| Rule | Why |
|---|---|
| **`username_lower` is the only lookup key.** Never `User.username == …` | case-insensitive uniqueness |
| **Email is always lowercased** before storage and comparison | ditto |
| **Direct bcrypt, never `passlib`** | Python 3.13+ compatibility |
| **Timing-safe login** — always call `verify_password`, even for an unknown user | response time must not reveal whether an account exists (`_DUMMY_HASH`) |
| **Access token claims are `{sub, exp, iat}` only — no `scope`** | that *absence* is what the admin session and the appeal token check against |
| **A missing `Authorization` header is 403, not 401** | the Flutter `AuthInterceptor` only logs out on a *codeless* 401 |
| **Never store tokens in Riverpod state** — `flutter_secure_storage` only | and `ref.invalidate()` every user-specific provider on logout |
| **Sign-out must `DELETE /devices/{token}` before discarding the access token** | otherwise the next user on that phone inherits these notifications |

→ [authentication.md](features/authentication.md) ·
[google-sign-in.md](features/google-sign-in.md) ·
[passwords-and-email.md](features/passwords-and-email.md)

---

## Access control

**There is one access ladder, never two.**

- **`can_view_itinerary()` is the single source of truth** for reads.
- **`can_edit_itinerary()` delegates to it first**, which is what makes edit
  rights *re-derived* rather than stored: a block, a visibility change, a
  moderator hide, a banned owner or a soft delete revokes editing the moment it
  revokes viewing — no rows to clean up, no sweep.
- **Never create new access-control logic.** Reuse those two.
- `public_listing_criteria()` is the query-level twin and must stay in lock-step;
  its caller **must `join(User)`**, and it does **not** cover the visibility
  ladder.
- A blocked, banned or deleted profile all **404 identically**, so the blocked
  user is never told.
- **Translation follows the same ladder and stops short of takedowns.** A
  reader only ever has translated what `can_view_itinerary` (and, for a review,
  `can_view_rating`) lets them read, and content under a takedown is never
  translated, even for its author. Missing, forbidden and taken down all
  answer `not_found`.

→ [visibility-and-access.md](features/visibility-and-access.md) ·
[collaborative-editing.md](features/collaborative-editing.md) ·
[blocking.md](features/blocking.md)

---

## Concurrency

- **`itineraries.updated_at` IS the concurrency ETag.**
- **Every itinerary-content mutation requires `If-Match`**; missing → 428,
  mismatch → 412.
- **Any moderation write from outside the owner's own request MUST go through
  `admin_service.set_preserving_etag` / `moderation_actions.set_status`** — moving
  `updated_at` 412s the author's open editor over a change they cannot see. 13
  call sites.
- **A heartbeat or a takeover must never touch `updated_at`** — every open client
  would 412 once a minute.
- **Nor may granting or revoking edit rights, or the allowlist** — they change
  what some viewer's GET shows, not the trip; the GET's body-hash validator
  already refreshes a cached copy, and moving the stamp only made the owner
  reload (since 2026-10-22).
- **The lock check sits above the `If-Match` check.** After a takeover the ETag has
  usually moved too, and 412 would send the user to reload into a screen they
  still cannot save from.
- **409 `edit_lock_lost` and 423 `itinerary_locked` must never be collapsed** —
  one says protect unsaved input, the other says offer to wait.
- **Compare `If-Match` as an instant (`_concurrency_token`), never as a string** —
  Dart and Python spell the same `updated_at` differently one time in a thousand.
- **An endpoint-set ETag is suffixed with the body hash by `ETagMiddleware`**; only
  the part before `;` is the concurrency token.
- **Every client surface that saves itinerary content claims the edit lock
  first** — the owner included, and the stop page included.
- **Edit mode is this device holding the claim, wherever it was taken.** A claim
  taken from the stop page is the trip's edit mode, and the trip page follows it.
  No surface claims "just for one edit" and hands the claim back afterwards — it
  ends from the trip page's exit, sign-out, or the detach grace once no screen is
  left on it.
- **The claim is never handed back under a running save.** Every write carrying
  it goes through `ItineraryDetailNotifier._write` — the only place the token can
  be read — and ✓/Back wait on `writesSettled()`. Released first, the write is
  refused after the screen that would show its error has gone.
- **A token-bearing `DELETE /lock` ends only the claim it names** — the owner's
  included. The client hands journalled claims back late, after a relaunch; an
  ownership match alone would end the claim the owner has since taken on another
  device.
- **One user action is one guarded write.** A write that moves `updated_at`
  leaves every `If-Match` read before it stale, so the client must learn the new
  stamp before its next write — from the answer, which since 2026-10-21 is the
  whole trip for every trip edit, never from a reload after it. The itinerary
  form's save sent its cover through `POST`/`DELETE /image`, which sit outside
  the guard and answer with no stamp, then the fields with the old `If-Match`,
  and the PATCH was refused until 2026-10-21; it is now one request
  ([itineraries.md](features/itineraries.md)).

→ [etag-concurrency.md](features/etag-concurrency.md)

---

## Moderation

| Rule | Why |
|---|---|
| **Call `moderate_or_422` from the endpoint BODY, never as a `Depends`** | dependencies resolve first, so a `Depends` spends a paid call before `require_etag` can 412 |
| **Do not convert text write endpoints to `async def`** | sync SQLAlchemy on the event loop is the real hazard; the threadpool already keeps blocking provider calls off it |
| **Bump `POLICY_VERSION` whenever you touch a threshold** | it is part of the cache key; stale verdicts would survive |
| **Automated writes only ever RAISE severity** (`approved < pending < flagged < hidden < rejected`) | a clean caption edit must not clear an unresolved image flag. Moderator and appeal paths assign directly to lower it |
| **Send nothing but the text to a provider** | no user id, email, or content id, ever |
| **Send Cloud Vision nothing but the image, the feature and `parent`** | the same rule for images: no user id, email, storage key or URL |
| **Read an absent SafeSearch category as `UNKNOWN`, and an `UNKNOWN` `adult` or `violence` as a failed scan** | proto3 JSON omits an enum left at zero, and Google's zero is `UNKNOWN`; reading it as unlikely would approve an image nobody classified |
| **Never map Cloud Vision's likelihoods onto percentages** | the audit row would claim a confidence Google never gave |
| **Scan account text BEFORE `create_user`** | it commits, so a later 422 could not undo the account |
| **Never let a verdict reject a Google-supplied profile name** | drop the name instead — the user cannot edit what Google sent |
| **Always call `escalate_if_flagged` after consuming `ctx.escalate`** | hiding without the `legal_escalations` row keeps a CSAM signal out of `/admin/legal` |
| **Never moderate report notes, appeal reasons, bug-report messages, or admin action reasons** | a 422 there would block someone reporting hate speech who quotes it — a safety regression |
| **The client filter warns, never blocks** — and is never applied to titles or place names | European place names false-positive (Bitche, Condom, Sexbierum, Wank) |
| **Never purge, downgrade or touch a `rejected_csam` row** | the object is deleted in the same action, so the row and its hash are the only evidence |
| **Hash the object before deleting it in `csam_takedown`** | the order is the evidence |
| **Never email the uploader or surface a CSAM-specific message** | it tells someone whose upload matched a law-enforcement corpus exactly what was detected |
| **Never point `R2_PUBLIC_URL` at `pub-*.r2.dev` in production** | it bypasses the Cloudflare zone and silently disables CSAM scanning entirely |

**One of the two sweep drivers is required** (`SWEEP_IN_PROCESS=True` or an
external scheduler) **or SLA auto-hide and post-outage re-checks never run.**

→ [text-moderation.md](features/text-moderation.md) ·
[image-moderation.md](features/image-moderation.md) ·
[content-reports.md](features/content-reports.md) ·
[admin-and-appeals.md](features/admin-and-appeals.md)

---

## Privacy and GDPR

- **Data minimisation in provider payloads** — the OpenAI request body carries the
  text and the model name and nothing else; the Cloud Vision request carries the
  image, the SafeSearch feature and `parent` (the EU location) and nothing else.
- **A translation engine receives the texts, the target language and what it
  needs to process them — never a user id, an email, a content id or a field
  name.** OpenAI gets the texts under opaque keys (`t0`, `t1`, …) with
  `store: false`; Azure gets a bare array. Translation logs carry sizes and
  outcomes only, never text.
- **`text_moderation_cache` holds no raw text and no user reference.**
- **Automated `moderation_log` rows carry `content_snapshot=None`** and no raw
  text, email or display name. Operator rows keep their snapshot.
- **`privacy@ntripi.app` is the GDPR controller contact**, hardcoded in all six
  legal modules.
- **Every third party that receives user data is named in Privacy §5, in all six
  languages, before it receives any.** An undisclosed processor is a GDPR breach
  and a store-label mismatch, so a new one ships behind its config flag until
  the policy that names it is deployed — translation's engines are pinned by
  `test_privacy_names_every_translation_engine`, and every `MODERATION_PROVIDER`
  value by `test_privacy_names_every_image_moderation_provider`.
- **Account deletion is a hard delete** with a documented set of `SET NULL`
  evidence columns, and it erases the account's stored images too — except while
  the account is under an open legal escalation, and except taken-down or
  escalated itinerary covers — see
  [accounts-and-profiles.md](features/accounts-and-profiles.md).
- **The client's HTTP cache is per account.** Keys are `<JWT sub>:<url>`
  (`core/api/cache_key.dart`) and sign-out cleans the store; every keep-alive
  user-scoped provider is in `auth_provider.dart`'s reset list, run on sign-in
  and sign-out. A new user-scoped provider that is not added there leaks one
  account's data to the next person on the device.
- **A translation is derived data and dies with its source.** An edit drops
  the translations of the text it replaced (`sync_translations`), a delete
  below the itinerary purges them (`purge_orphans`), and deleting a trip or an
  account cascades through `content_translations.itinerary_id`. The table
  holds no user reference and never stores the source text — only its hash.
- **A non-public trip's share page and preview card carry no title, cover photo
  or owner.** The card reaches everyone in the chat the link is pasted into,
  mostly people who cannot open the trip; the router passes `share_private.html`
  nothing about the trip, so it cannot leak — see
  [sharing.md](features/sharing.md#visibility-on-a-public-page).
- **A share page sends a reader signed in on the web straight into the web app,
  from one localStorage entry and nothing more.** `ntripi_web_session_until`
  (the web app's `web_session_hint.dart`; the server's
  `app_links.WEB_SESSION_HINT_KEY`) holds the session's end — never a token or
  an account, since every script on the origin can read it — and moves only in
  `saveTokens` / `clearAllTokens`. The page reads it in `<head>` and leaves with
  `location.replace`, never `assign`. Change the key on both sides together.
- **`APP_OPEN_HOST` serves the association files and nothing else**; every other
  path there redirects to `SHARE_BASE_URL` (`middleware/open_host.py`). A second
  copy of the site would hold its own localStorage, where the share pages could
  not see the reader's session.
- **A reader without an account reaches the teaser and nothing else.** A public
  trip's share page shows its title, cover, rating and description; a profile's,
  its display name, @username and avatar — the same to a person, a chat crawler
  and a search engine, card included. Everything else needs an account, on the
  web as in the app (`kPublicRoutes` is the sign-in screens alone).
  `test_public_surface.py` classifies every route reachable without sign-in and
  seeds a marker into every non-teaser field — see
  [web-and-platform.md](features/web-and-platform.md#the-public-surface).
- **A rating survives its author anonymised** (`user_id` SET NULL) so the trip
  keeps its score.
- **Bug-report screenshot retention is a privacy duty, not housekeeping** — a
  screenshot can contain a third party's data. Only **closed** reports are purged,
  and the object is deleted before the row.
- **Unread notifications are never purged inside the read-retention window** — an
  unread notice is the recipient's only record that something happened to them.
- **`date_of_birth` is owner-visible only** and is never backfilled — inventing
  one fakes the evidence the gate exists to produce.
- **Never put the bug reporter's email in the Jira payload**, and never log
  `JIRA_API_TOKEN`.
- **Never name a reporter, a reason, or a report count in push text** — the tray
  entry is visible on a lock screen.

---

## ToS and store compliance

- **The 16+ age gate is enforced on all three write paths**, and the arithmetic
  lives only in `age_service.py`.
- **`tos_accepted` must never default `True` anywhere** — an account created
  without an explicit acceptance is the App Store 1.2 / Play UGC violation this was
  built to close.
- **`POST /auth/accept-tos` stamps the server's `TOS_VERSION`**, never a
  client-supplied one.
- **`ABUSE_CONTACT_EMAIL` must match the in-app address AND the store listing.**
- **A legal document must ship as plain text**, never HTML — one string serves the
  web page and the in-app sheet without a renderer package.
- **Adding a language to the app's locales requires adding it to `i18n.py`
  `SUPPORTED`**, or the app's `?lang=` silently serves English.
- Outstanding: **App Store privacy nutrition label and Play Data safety both need
  the DOB declared**, and the six-language legal translations need counsel review.

→ [legal-and-age-gate.md](features/legal-and-age-gate.md)

---

## Security middleware

The stack, its LIFO ordering, and the reason each layer sits where it does are in
[web-and-platform.md](features/web-and-platform.md#the-middleware-stack). The
non-negotiables:

- **`ProxyHeadersMiddleware` outermost** — without it, rate limiting throttles
  every user from the same Railway proxy IP.
- **Never key a per-IP limit on X-Forwarded-For alone** — behind Cloudflare its
  leftmost entry is caller-chosen. `ClientIPHeaderMiddleware` sets the client
  from `CLIENT_IP_HEADER` (`cf-connecting-ip`), just inside ProxyHeaders.
- **Never set `ALLOWED_HOSTS` to `*`** in production.
- **Never use `allow_origin_regex=".*"`, `allow_methods=["*"]` or
  `allow_headers=["*"]`** in CORS — explicit lists only.
- **Keep `X-Edit-Lock` in CORS `allow_headers`** or the browser preflight fails
  before an itinerary mutation is sent.
- **Never expose `/docs` or `/redoc` in production** — `DEBUG=False` handles it;
  do not override `docs_url`/`redoc_url` unconditionally.
- **Re-raise `asyncio.CancelledError`, `KeyboardInterrupt` and `SystemExit`** in
  exception handlers — intercepting them breaks Starlette's lifespan.
- **Import `limiter` from `app/limiter.py`, never from `app/main.py`** — circular
  import.
- **Never run the container as root** — keep `USER appuser`.
- **Never put request timing in a response header** (`Server-Timing` or any
  other) — a query count or a duration tells any caller whether an account or a
  trip exists, undoing the timing-safe login and the identical 404 pages.
  `RequestTimingMiddleware` logs instead, with the route template, never the
  path.
- **Register a new static mount in `app/middleware/__init__.py`'s
  `STATIC_PREFIXES`**, not in each middleware, and test paths with
  `is_static_path` — a bare `startswith` matched `/appeal` as `/app`.

---

## Database

| Rule | Why |
|---|---|
| **Every FK column needs an explicit index** | PostgreSQL indexes the *referenced* key, never the referencing column: without it the join seq-scans, and a DELETE on the parent locks the child table and scans it whole — which is what a CASCADE to `users.id` does on every account deletion |
| **A trailing composite-PK column is not covered either** | `saved_itineraries` and `itinerary_allowed_users` are keyed `(itinerary_id, user_id)`, so `WHERE user_id = ?` cannot use the PK index. `ix_itinerary_editors_user` is the precedent |
| **Never compute a denormalised counter in Python** | read-then-write loses concurrent updates under READ COMMITTED; the increment belongs in the `UPDATE` |
| **Never compute rating averages in Python** — use SQL `AVG()` | same |
| **A limit is enforced in the same statement that counts** — `INSERT … ON CONFLICT DO UPDATE … WHERE total + n <= limit RETURNING` (`translation_usage`) | a check-then-increment lets two concurrent requests both pass a cap they jointly exceed |
| **`rank` columns must be `TEXT COLLATE "C"`** | locale-aware collation orders upper/lowercase differently from the ordering service |
| **Clamp with `case()`, not `GREATEST()`** | the suite runs on SQLite, which has no `GREATEST` |
| Pool `pool_size=10`, `max_overflow=20`, `pool_pre_ping=True`; statement timeout **30 s** | Alembic uses its own `NullPool` engine and is unaffected |

**The eight remaining unindexed FKs are all `SET NULL` admin/audit columns with no
hot read and no cascade scan — deliberately left alone.**

### Alembic

- **Never hand-write a revision ID.** Generate with
  `venv/bin/alembic revision -m "…"`. Hand-written placeholders silently collide,
  fork the chain and crash Railway on `alembic upgrade head` — which is exactly
  what happened three times with `a1b2c3d4e5f6` and twice with `42f3ed3997b2`
  before this rule existed.
- **Always verify a single head before committing** — `venv/bin/alembic heads`.
- **Never keep two files with the same revision ID.**
- **`down_revision` must point at the current single head** — read it, do not
  guess from filenames.
- **Adding an index to a populated table needs `CREATE INDEX CONCURRENTLY`** —
  migrations run at deploy. Wrap it in
  `with op.get_context().autocommit_block():` with
  `postgresql_concurrently=True`, guard on the dialect being PostgreSQL, and keep
  a plain branch otherwise. The trade-off is forfeiting the migration's atomicity:
  a failed concurrent build leaves an `INVALID` index to drop by hand.
  `a681984a1a04` is the reference implementation.

### The test-schema divergence

**The suite builds its schema from ORM metadata on SQLite**
(`test/conftest.py`), so **anything that exists only in a migration is untested**.
That set is enumerated in
[reference/data-model.md](reference/data-model.md#migration-only-objects) and
includes `COLLATE "C"` on both rank columns and both partial feed indexes.
Migration `12b6e3451c36`'s docstring records what this cost once: a CHECK
constraint that lived only in a migration let every auto-hide of an itinerary
raise `CheckViolation` → 500 in production for months while the suite stayed
green. **Declare constraints in `__table_args__`, not only in the migration.**

**SQLite also keeps time in whole seconds.** `func.now()` renders there as
`CURRENT_TIMESTAMP`, so `itineraries.updated_at` — `server_default` and
`onupdate` both — does not move between two writes in the same second, and a
stale `If-Match` that production answers with 412 passes in the suite. That is
how the 412 the itinerary form hit on every cover change stayed invisible to
it. A test about the ETag moving backdates the row first (`_backdate` in
`test_itinerary_form.py`).

---

## API contract stability

- **Pydantic field-definition order IS JSON key order IS part of the API
  contract.** Never merge Response classes into a shared base if it reorders keys
  — base-class fields serialize first. This is why the two annotation Response
  classes stay separate, why `ItineraryDetail` declares `hidden`, the
  recommended-period fields and `can_edit` inline and last, and why
  `ItinerarySummary` gains no `can_edit`.
- **A new answer shape is opt-in per request.** Asked nothing, every write
  answers byte for byte as it always has — status, schema, key order, ETag
  header — so builds already installed keep working; the new answer comes only
  with `?return=…`, from the one factory `return_requested`
  (`app/dependencies.py`), which 422s any value it does not know:
  `itinerary` on every trip edit and both creates, `aggregate|ratings_page` on
  `DELETE /ratings/me`, `ratings_page` on `POST /ratings`, `counts` on
  unfollow, remove follower and block, `violations` on `POST /appeals`
  ([itineraries.md](features/itineraries.md),
  [follows.md](features/follows.md)). `test_trip_edit_answers.py` pins both
  halves on every `EDIT_GUARDED` route and both creates. Keys added to an
  existing answer are appended after it, never inserted — the rating POST's
  aggregate and page ride on subclasses of `RatingResponse`, follow and accept
  append `counts` through `FollowWriteResponse`, so the shapes other routes
  share are untouched.
- **Constrained string fields stay `pattern=` regexes, not `Literal`** —
  switching changes the 422 body. (`_VISIBILITY` is the one existing exception.)
- **Keep `detail` strings stable** — web templates and tests read them.
- **Raise `ApiError`, not a bare `HTTPException`**, when a client might branch on
  the reason; put machine-readable context in `extra`, never in `detail`.
- **Shape errors are 422; policy refusals are 400.** The client renders a field
  error for one and a message for the other.
- **A new error code needs a `localizedApiError` case and an `apiError*` key in
  all six `.arb` files in the same change**, or it lands in the
  [unmapped list](reference/error-codes.md#unmapped-codes) and shows English to
  everyone.
- **Never skip `If-Match` on a mutation endpoint.**
- **Never send or return `position` / `parallel_position` for stops**, and never
  add a `type`, `position` or `parallel_position` column to `stops`.
- **Classify every new mutating itinerary endpoint in
  `test_edit_guard_coverage.py`** — the test fails until you do, deliberately.
  And never add a READ route to any of its sets: `classified - live` is asserted
  empty.

---

## Shared helpers (DRY)

**Before writing a query or response block in a router, check here first. If a
block appears a second time anywhere, extract it instead of copying.**

| Helper | Owns |
|---|---|
| `services/user_service.py` | `get_active_user_or_404` / `..._by_username_or_404` — **the only** fetch-or-404; `get_follow` / `is_accepted_follower` — **never write an inline Follow query**; `bump_follow_counters` — **the only** way to touch the counters; `delete_follow` — **the only** way to delete a follow row (decrements from the row's status as it was deleted, never as loaded); `follow_counts` — **the only** source of a follow write's `counts` (read after the commit; `them` null where the profile would 404); `public_profile_text` |
| `app/dependencies.py` | `return_requested(*representations)` — **the one** `?return=` opt-in factory; `wants_counts` |
| `routers/follows.py` | `counts_answer` — the `?return=counts` answer, which the block route (`users.py`) shares |
| `services/token_util.py` | `hash_token` / `as_aware_utc` / `new_raw_token` — every opaque-token service |
| `services/image_service.py` | `process_and_store` — all image uploads |
| `services/google_service_account.py` | **the one** home of a Google service-account key read from an env var: `parse` (`strict=False`, and why), `validate` (the startup check — logs, never raises), `access_token` (the token cache, keyed by variable and scope, one lock per key). FCM push and Cloud Vision each hold their own key through it |
| `services/moderation_service.py` | `label_text` — **the one** rendering of a stored image-scan label (a level for Cloud Vision, a percentage for Rekognition): the flag email, and both admin pages through the `scan_label` filter |
| `services/operator_alerts.py` | `notify_operator` — **the one** throttled operator alert: at most one email per key per hour (in memory), its WARNING line, the `OPERATOR_EMAIL` guard, mail errors swallowed. Text moderation's degradation notices and image moderation's outage alerts; an async caller builds the body first and sends with `asyncio.to_thread`. A per-event email (a flag, a report) is not an alert and is never throttled |
| `services/share_service.py` | `build_share_url`, `build_profile_share_url`, `absolute_storage_url`, `absolutize_stored_url`, `default_preview_image_url` |
| `services/app_links.py` | `cta_context` / `store_links` — every share page's call to action; `apple_app_site_association`, `asset_links`; `APP_LINK_PATHS` |
| `services/ordering.py` | `key_between`, `n_keys_between` |
| `services/itinerary_access.py` | `can_view_itinerary`, `can_edit_itinerary`, `public_listing_criteria`, `visible_rating_criteria`, `recalculate_rating` |
| `services/translation_service.py` | `REGISTRY` — the one list of translatable fields; `sync_translations` — **every write of translatable text calls it** before the commit; `purge_orphans` — **every delete below the itinerary calls it** after the flush; `source_hash` |
| `app/middleware/__init__.py` | `STATIC_PREFIXES` |
| `routers/itineraries.py` (router-private, keep them so) | `_etag_json_response`, `_require_viewable`, `_viewer_detail` — **the one builder of the trip a GET shows**, which every trip edit's and create's answer reuses — `_trip_edit_answer`, `wants_itinerary`, `_ratings_page` — **the one builder of the ratings page**, for the GET and both rating writes — `_two_phase_renumber`, `_require_stops_in_itinerary`, the annotation CRUD helpers |
| `schemas/itinerary.py` | `_NOTE_TYPE_PATTERN`, `_PLACE_TYPE_PATTERN`, `_VISIBILITY`, `_AnnotationCreateBase` / `_AnnotationUpdateBase` |

---

## Frontend

| Rule | Why |
|---|---|
| **Riverpod only** — no other state management library | one model |
| **No build_runner / json_serializable / freezed.** Manual `fromJson`/`toJson` | keeps the build simple |
| **OSM via `flutter_map` only — never the Google Maps SDK** | licensing and portability |
| **Never `ListView` inside `Column`** — use `CustomScrollView` + slivers | unbounded height |
| **Three async states always**: loading, error, data (and empty) | |
| **Never touch `ref` in `State.dispose()`** | `ref` resolves through `BuildContext`, already deactivated by then. Capture the notifier in a field, seeded in `didChangeDependencies` and refreshed by a `ref.watch(…notifier)` in `build` |
| **Guard `state =` / `ref.invalidate` after an `await` with `if (!ref.mounted) return`** | logout disposes the provider mid-flight and a disposed `Ref` throws |
| **Never let a background read write `AsyncLoading` or `AsyncError`** | nobody asked for it; blanking a correct badge over one dead request is worse than a stale value |
| **A reload never blanks content already on screen.** Every `refresh()` goes through `ReloadKeepsContent.reloadKeepingContent` (`core/providers/reload_keeps_content.dart`), the only place a notifier writes `AsyncLoading` or `AsyncError`: with nothing on screen, the loader then the answer or the error; with content on screen it stays mounted, an answer replaces it in place (unless a write landed while the reload was in flight — that newer state stands), a refusal (`refusesContent`: 401/403/404/410) replaces it with the error view, and any other failure leaves it and is reported by the screen that started the reload (`reportReloads`, a SnackBar). Reloads are never answered from the HTTP cache's stale copy; first loads are. Whatever a pull does before its reload — clearing covers through `ImageCacheEviction` — is best-effort and cannot stop it. `test/reload_keeps_content_guard_test.dart` holds it, screens included: a `.refresh()` in `presentation/` is reported (`reportReloads`) or dropped on purpose (`unawaited`) | Riverpod 3 carries the previous value into both states, and `AsyncValue.when()` still draws them as the loader and the error view: every pull-to-refresh unmounted the content and closed each "view more", a failed one replaced a good copy with the error view, and on phones the cache's stale copy hid the failure altogether (2026-10-25) |
| **A write answers with what the screen shows next, and the app never re-downloads after its own write.** Every trip save sends `?return=itinerary` and goes through `ItineraryDetailNotifier._save`, which adopts the answered trip and replaces its row in the Itineraries tab; a create's trip opens from `tripSeedsProvider`; follow writes adopt the counts they answer with (`adoptMyCounts`, `adoptTheirFollowState`), accepting the terms the profile, an appeal the violations list, a rating the aggregate — and the ratings page when it is loaded. An answer that replaces a whole GET body is also written as that GET's cached entry (`cacheAsGet`). **The named exceptions**: content an answer cannot carry (someone's trips or followers after an unfollow or removal, the feed after a block or unblock, a new row in a list); pull-to-refresh and Retry; sign-in, sign-out and token exchanges; invalidating data no open screen shows | the reload after every save was a second request the form waited on, and its loading state rebuilt the whole trip view behind the full-screen loader (production, 2026-10-20); the audit of 2026-10-22 found the same wait after creates, editor grants, follows, blocks, accepting the terms, appeals and ratings |
| **Every request to the API travels on `apiConnectionPool`.** Only `createDioClient` and `createBareDio` build a Dio for `kApiBaseUrl`. `kApiConnectionIdleTimeout` (120 s) stays below Cloudflare's 400 s keep-alive. The pool is retired when the app is hidden and when the network changes, by setting the old client's `idleTimeout` to zero, never by `close()` | one pool is what lets a request reuse the connection the one before it opened, where Dio's own adapter dropped it after 3 s; at 400 s both ends close an idle connection at the same moment and a request sent then fails; dart:io never checks a pooled connection before reusing it, so one kept through a sleep or a network switch fails the next save; `close()` also cancels a request still connecting. `api_connection_pool_test.dart` fails on a third API client and on a retire that closes |
| **`*.fromString` degrades unknown values** — `ModerationStatus` → `approved`, `NotificationType` → a generic row, `EditLockState` → `active` | a newer backend must never crash a deployed client |
| **Never use the `--web-renderer` flag** | removed in Flutter 3.29 |
| **Never run `dart format`** | the repo predates Dart 3.7 tall style; it reflows whole files |
| **Every "view more" is `ExpandableText`** (`shared/widgets/expandable_text.dart`) — never re-inline a `TextPainter` overflow check, and never place one under `IntrinsicHeight` | a check that measures with less than `Text` renders with — no inherited style, no text scaler — says "fits" while the text is ellipsised, and the rest is unreachable; the two private copies it replaced had done exactly that. Its `LayoutBuilder` throws on an intrinsic query |
| **A screen opened from outside the app is never alone, and always has a way out.** A notification tap enters through `GoRouter.pushOverHome` / `openFromOutside` (`core/router/navigation_ext.dart`), never `go()`; so does a shared link, through `appLinkOnEnter` and `landHome` (`core/router/app_links.dart`), parked rather than dropped while splash is up or nobody is signed in; every screen `notificationRoute` can open leaves through `popOr`, in every state | `go()` left the tapped screen alone on its navigator — a back arrow that did nothing, an Android back that closed the app — and destroyed the screen the user had left. `tap_routing_test.dart` and `notification_destinations_exit_test.dart` hold the two halves, and the second fails until a new destination has a case |
| **On the web every screen is a URL the app can start on, and the app never starts on an editing form.** The address bar shows the screen on top (`GoRouter.optionURLReflectsImperativeAPIs`, `main.dart`); a reload or a pasted address on a form that saves under an edit claim lands on what it edits (`editingRouteLaunchRedirect`), and a trip or profile URL opened signed out is parked through the sign-in (`signInRedirect`). `test/core/router/landing_routes_test.dart` classifies every route as one or the other | the bar used to show the screen beneath the pushes — `#/profile/me` over a shared profile — so a reload or a copied URL lost the screen; showing the screen on top made forms reachable on a fresh start, where they hold no claim and their Save could only fail (2026-10-26) |
| **Share a link only through `shareLink` / `ShareService`**, never share_plus directly | the phone builds' share popup carries a Copy link row only through the `ntripi/share` channel; share_plus alone has no way to add it |

### Surfaces and chrome

- **Everything paints `nt.surface`** — full-screen routes, modal sheets, dialogs.
  `bottomSheetTheme.modalBackgroundColor` and `dialogTheme.backgroundColor` both
  say so, so **passing a `backgroundColor` is what breaks the rule.**
- **`nt.sand` is a warm accent fill, never a background** — its job is to make one
  element stand out *against* the surface.
- **Chrome comes from `shared/widgets/editorial_widgets.dart`, never re-inlined**:
  `EditorialTopBar`, `EditorialDivider`, `SectionLabel`, `SectionCard`,
  `FieldDivider`, `EditorialRow`, `RefreshableCenter`, `AvatarInitials`,
  `OwnerAttributionRow`, `SheetErrorRow`, `SheetActionBar`. Six private clones
  had already drifted apart before they were extracted.
- **A sheet's buttons never scroll with its content.** They sit in a
  `SheetActionBar` pinned below the scroll view — `KeyboardSafeSheetBody(actions:)`
  on a modal sheet, under its own list in the bug reporter — which carries a top
  hairline, the bottom safe area and the sheet's error (`error:`), above the
  buttons. As the body's last child they sat under the keyboard while a field
  was in use and below the fold once the body outgrew its cap, and the bug
  reporter — whose sheet the `feedback` package opens shorter than its form —
  opened with Send out of sight on every phone (2026-10-29).
  `test/keyboard_avoidance_guard_test.dart` fails on a `KeyboardSafeSheetBody`
  without `actions:`.
- **Never call `.toUpperCase()` on a `SectionLabel`** — it uppercases internally.
- **A sheet leads with a title and uses `showDragHandle: true`** — a 48 px tap
  target and a `Semantics` label a hand-rolled 36×4 box does not have.
- **Every corner is a token of the radius scale, one per job** — `NtripiRadius`
  (`core/ui/app_radii.dart`): card 18 · field 14 · button 14 · tile 12 · icon 10
  · toggle 12 · inset 8 · pill 999 · modal 28 · checkbox 4. Never a number in
  `Radius.circular` / `BorderRadius.circular`; a sheet's or a dialog's corners
  come from the theme only, never a `shape:` per call; every
  `OutlineInputBorder` names its radius. The web pages mirror the scale as
  `var(--radius-*)` in `social_api/app/templates/_radius_tokens.html`, which
  every layout includes. Held by `test/radius_scale_guard_test.dart` and
  `social_api/test/test_radius_scale.py` — the second also fails when the two
  scales disagree. Before the scale, 247 corners were typed as 18 different
  numbers, and boxes doing the same job drifted apart: the trip page's
  edit-mode info boxes kept a 4 copied from a field that had moved to 14.
- **Spacing**: card margin 16 · label inset 22.
- **Colors come from `context.nt` only.** `app_theme.dart` is the single source of
  truth and there is **not one `Color` literal outside it** (`Colors.transparent`
  excepted) — keep it that way. `nt.danger` is the destructive color, not
  `nt.ratingRed` and not `colorScheme.error`. Note **`Theme.of(context).dividerColor`
  is NOT `nt.border`** — the theme sets `dividerTheme.color` but never
  `dividerColor`, so that getter falls through to M3's `outlineVariant` grey.
- **A sheet that fails must say so inline.** `ScaffoldMessenger` snackbars render
  behind the modal barrier and are never seen. A sheet with buttons hands its
  `SheetErrorRow` message to its `SheetActionBar`, so it shows above them
  wherever the body is scrolled.

### Keyboard

One contract, in `shared/widgets/keyboard_avoidance.dart`, held by
`test/keyboard_avoidance_guard_test.dart`.

- **Whoever lifts content above the keyboard removes the inset from what it
  passes down.** Scaffold does; the bottom-nav shell and `AboveKeyboard` do too.
  The shell rebuilds its tabs' MediaQuery from a context *above* its Scaffold, so
  it must strip the inset itself — until 2026-10-01 it did not, and every tab
  lifted twice.
- **Screens keep the default `resizeToAvoidBottomInset`.** `false` only for a
  page that must not reflow — the map picker (a live map relayouting every
  keyboard frame froze the device) and the cover crop overlay — each allowlisted
  with its reason. On the root navigator `false` means no keyboard avoidance at
  all.
- **A sheet with a field lifts its body with `KeyboardSafeSheetBody`**: the inset
  outside the scroll view, the cap on the content, shown with
  `isScrollControlled` + `useSafeArea`. Inset padding *inside* a scroll view is
  cancelled once a height cap stops the sheet growing, and the field stays under
  the keyboard counted as visible. Its buttons go in `actions:` — a
  `SheetActionBar` pinned below the scroll view, inside the cap, above the
  keyboard. A dialog with a field must be able to shrink:
  `scrollable: true`, or a `Flexible` list that absorbs the space.
- **A field and the text that belongs to it are revealed as one unit** with
  `RevealTogether` (already inside `ModerationHint`) — never a `scrollPadding`
  number. It stands aside for a group taller than the viewport, so a long note
  keeps its caret.
- **An overlay outside every Scaffold reads the inset from the full-window
  overlay's context** (`field_help`'s popover): under the shell, the anchor's own
  context reads 0.

### Destructive actions

Three tiers, and **never an inline `showDialog`**:

1. undo snackbar — `showUndoableActionSnackbar()`
2. confirm dialog — `confirmDestructiveAction()`
3. type-to-confirm — `confirmTypedDestructiveAction()`

---

## Known deviations

Places where the code does not follow its own rules. Recorded as fact, not
excused.

| Deviation | Detail |
|---|---|
| **A Google Maps Embed API key is hardcoded** | `Dockerfile:15` — `--dart-define=GOOGLE_MAPS_EMBED_API_KEY=AIzaSy…`, against "never hardcode secrets or environment values". An Embed key necessarily ships to the client and this one is referrer-restricted, so exposure is not the issue; it is a committed, un-rotatable build constant. `API_BASE_URL` and `SHARE_BASE_URL` are hardcoded there too |
| **`_VISIBILITY` is a `Literal`, not a `pattern=`** | `schemas/itinerary.py:31`, against the constrained-string rule. It is also the reason `itineraries.visibility` has no DB CHECK |
| **Eleven `AuthError` sites share `code="auth_error"`** | including four that surface on one screen needing different UI |
| **`CLAUDE.md`'s middleware table omits `LanguageCookieMiddleware`** | the real runtime stack has seven layers, not six |
| **`.env.example` is 14 settings behind**, three of them validator-backed | see above |
| **A model docstring asserts an invariant nothing enforces** | segment stop-adjacency — see [transit-segments.md](features/transit-segments.md). ("Deleting the last leg deletes the segment" is enforced since 2026-09-26) |
| **`POST`/`DELETE /itineraries/{id}/image` write the itinerary outside the guard** | no edit lock, no `If-Match`, and they move `updated_at` when the cover changes the row — against "every itinerary-content mutation requires `If-Match`". Kept unchanged for installed builds; the app uses the form routes instead, and the pair is to be retired ([backlog.md](backlog.md)) |

---

## OPEN QUESTIONS

- **Is the in-memory rate limiter's single-instance assumption still safe?** The
  same assumption is recorded in four places (`limiter.py:12`, `main.py:219`,
  `social_api/README.md:535`, `CLAUDE.md:87`) plus the operator-alert throttle
  (`operator_alerts.py:30`). Nothing records a threshold at which Redis
  becomes required, or who would notice.
- **Should the four client-less backend endpoints be retired?**
  `GET /itineraries/{id}/segments`, the three `/legs` writes, and
  `GET /users/by-username/{username}` have no consumer, and two places document
  them as "for future API consumers" — but there is no public API programme.
