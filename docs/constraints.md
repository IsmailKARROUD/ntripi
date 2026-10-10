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

---

## Config via env

### Startup validators that **raise**

Seven misconfigurations refuse to boot rather than degrade silently:

| Validator | Refuses | Why |
|---|---|---|
| `SECRET_KEY` `Field(min_length=32)` | a key under 32 chars | a weak or placeholder signing key must never reach traffic. `openssl rand -hex 32` |
| `_validate_text_moderation` | an unknown `TEXT_MODERATION_PROVIDER`; `openai` with no `OPENAI_API_KEY`; an unparseable `REPORT_HIDE_THRESHOLDS`, or one naming a category that is not in `constants/report_reasons.py` | a silent downgrade to the wordlist is worse than not booting; a typo'd category silently disabled auto-hide for the real one |
| `_validate_sweep_deadline` | with `SWEEP_IN_PROCESS`, `MODERATION_SLA_HOURS × 60 + SWEEP_INTERVAL_MINUTES > 24 × 60` | a report can wait the SLA plus one whole interval before a run sees it — past 24h the deadline the SLA exists for is breached |
| `_validate_notification_retention` | `NOTIFICATION_MAX_AGE_DAYS < NOTIFICATION_RETENTION_DAYS` | it would silently shorten the read window |
| `_validate_edit_lock_windows` | `TTL <= IDLE`; `IDLE < 2 × HEARTBEAT`; `HEARTBEAT < 5` | a claim that became takeable before it read as inactive would be stolen from someone the UI still showed as editing |
| `_validate_translation_detect_langs` | a `TRANSLATION_DETECT_LANGS` that is neither `all` nor a list of two-letter codes | a typo would otherwise surface on the first save that needs a language |
| `_validate_translation` | an unknown or repeated name in `TRANSLATION_PROVIDERS`; `openai` with no `OPENAI_API_KEY`; `azure` with no `AZURE_TRANSLATOR_KEY`; a `TRANSLATION_SUPPORTED_LANGS` code missing from `constants/translation_languages.py`; a `TRANSLATION_PRETRANSLATE_LANGS` code that is not supported; a non-positive timeout; an hourly limit under 1 or a negative budget (`Field` bounds) | the same stance as text moderation: a setup that would quietly translate nothing must not boot |

Two more refuse at first use rather than at import: **`STORAGE_BACKEND=r2` with
any `R2_*` var missing raises**, and an unknown `STORAGE_BACKEND` raises — and
`storage()` is called eagerly in the lifespan, so both surface on boot.

### The "unset = invisible" pattern

Five subsystems return **404** or render nothing when unconfigured, rather than
returning 401/403 — the feature is invisible, not merely locked:

| Unset | Effect |
|---|---|
| `ADMIN_BASIC_USERNAME` / `_PASSWORD` | every `/admin` route 404s |
| `SWEEP_TOKEN` | `POST /internal/moderation-sweep` 404s |
| any of the four `JIRA_*` | the "Create Jira issue" button is not rendered |
| `FCM_PROJECT_ID` / `FCM_SERVICE_ACCOUNT_JSON` | push is off; nothing sent, nothing raised |
| `TRANSLATION_PROVIDERS` | `POST /translations` 404s; `GET /translations/config` answers `enabled: false`, so no client offers the button |

### `OPERATOR_EMAIL` is the one to actually set

Unset, **four alert paths guard on it and silently skip** — `report_service`,
`moderation_service`, `bug_report_service`, `text_moderation_service` — so the
queues fill with nobody told.

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
  text and the model name and nothing else.
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
  `test_privacy_names_every_translation_engine`.
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

---

## API contract stability

- **Pydantic field-definition order IS JSON key order IS part of the API
  contract.** Never merge Response classes into a shared base if it reorders keys
  — base-class fields serialize first. This is why the two annotation Response
  classes stay separate, why `ItineraryDetail` declares `hidden`, the
  recommended-period fields and `can_edit` inline and last, and why
  `ItinerarySummary` gains no `can_edit`.
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
| `services/user_service.py` | `get_active_user_or_404` / `..._by_username_or_404` — **the only** fetch-or-404; `get_follow` / `is_accepted_follower` — **never write an inline Follow query**; `bump_follow_counters` — **the only** way to touch the counters; `public_profile_text` |
| `services/token_util.py` | `hash_token` / `as_aware_utc` / `new_raw_token` — every opaque-token service |
| `services/image_service.py` | `process_and_store` — all image uploads |
| `services/share_service.py` | `build_share_url`, `build_profile_share_url`, `absolute_storage_url`, `absolutize_stored_url` |
| `services/ordering.py` | `key_between`, `n_keys_between` |
| `services/itinerary_access.py` | `can_view_itinerary`, `can_edit_itinerary`, `public_listing_criteria`, `visible_rating_criteria`, `recalculate_rating` |
| `services/translation_service.py` | `REGISTRY` — the one list of translatable fields; `sync_translations` — **every write of translatable text calls it** before the commit; `purge_orphans` — **every delete below the itinerary calls it** after the flush; `source_hash` |
| `app/middleware/__init__.py` | `STATIC_PREFIXES` |
| `routers/itineraries.py` (router-private, keep them so) | `_etag_json_response`, `_require_viewable`, `_two_phase_renumber`, `_require_stops_in_itinerary`, the annotation CRUD helpers |
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
| **`*.fromString` degrades unknown values** — `ModerationStatus` → `approved`, `NotificationType` → a generic row, `EditLockState` → `active` | a newer backend must never crash a deployed client |
| **Never use the `--web-renderer` flag** | removed in Flutter 3.29 |
| **Never run `dart format`** | the repo predates Dart 3.7 tall style; it reflows whole files |
| **Every "view more" is `ExpandableText`** (`shared/widgets/expandable_text.dart`) — never re-inline a `TextPainter` overflow check, and never place one under `IntrinsicHeight` | a check that measures with less than `Text` renders with — no inherited style, no text scaler — says "fits" while the text is ellipsised, and the rest is unreachable; the two private copies it replaced had done exactly that. Its `LayoutBuilder` throws on an intrinsic query |

### Surfaces and chrome

- **Everything paints `nt.surface`** — full-screen routes, modal sheets, dialogs.
  `bottomSheetTheme.modalBackgroundColor` and `dialogTheme.backgroundColor` both
  say so, so **passing a `backgroundColor` is what breaks the rule.**
- **`nt.sand` is a warm accent fill, never a background** — its job is to make one
  element stand out *against* the surface.
- **Chrome comes from `shared/widgets/editorial_widgets.dart`, never re-inlined**:
  `EditorialTopBar`, `EditorialDivider`, `SectionLabel`, `SectionCard`,
  `FieldDivider`, `EditorialRow`, `RefreshableCenter`, `AvatarInitials`,
  `OwnerAttributionRow`. Six private clones had already drifted apart before they
  were extracted.
- **Never call `.toUpperCase()` on a `SectionLabel`** — it uppercases internally.
- **A sheet leads with a title and uses `showDragHandle: true`** — a 48 px tap
  target and a `Semantics` label a hand-rolled 36×4 box does not have.
- **Geometry scale**: card radius 18 · card margin 16 · label inset 22 · input
  radius 14 · icon-pill radius 9.
- **Colors come from `context.nt` only.** `app_theme.dart` is the single source of
  truth and there is **not one `Color` literal outside it** (`Colors.transparent`
  excepted) — keep it that way. `nt.danger` is the destructive color, not
  `nt.ratingRed` and not `colorScheme.error`. Note **`Theme.of(context).dividerColor`
  is NOT `nt.border`** — the theme sets `dividerTheme.color` but never
  `dividerColor`, so that getter falls through to M3's `outlineVariant` grey.
- **A sheet that fails must say so inline.** `ScaffoldMessenger` snackbars render
  behind the modal barrier and are never seen.

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
  the keyboard counted as visible. A dialog with a field must be able to shrink:
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

---

## OPEN QUESTIONS

- **Is the in-memory rate limiter's single-instance assumption still safe?** The
  same assumption is recorded in four places (`limiter.py:12`, `main.py:219`,
  `social_api/README.md:535`, `CLAUDE.md:87`) plus the text-moderation cache
  (`text_moderation_service.py:80`). Nothing records a threshold at which Redis
  becomes required, or who would notice.
- **Should the four client-less backend endpoints be retired?**
  `GET /itineraries/{id}/segments`, the three `/legs` writes, and
  `GET /users/by-username/{username}` have no consumer, and two places document
  them as "for future API consumers" — but there is no public API programme.
