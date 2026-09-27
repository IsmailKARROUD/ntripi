# Ntripi documentation

**This folder is the single source of truth for what this project does.**

`CLAUDE.md` at the repo root is the *rules* file — terse, agent-facing,
prescriptive. This folder is the *reference* — what exists, how it behaves, why it
was built that way, and what is still missing.

Ntripi is a full-stack social app for sharing travel itineraries, live at
<https://ntripi.app>. Backend: FastAPI + PostgreSQL (`social_api/`). Frontend:
Flutter for iOS, Android and web (`social_flutter/`).

---

## How to use this folder

### Read before building

1. **[constraints.md](constraints.md)** — project-wide rules any new feature must
   not violate. Read this first; the rules are cross-cutting, and a feature that
   breaks one is wrong before it is written.
2. **The relevant [features/](features/) doc**, and the **Related** links at its
   foot — that is where you find what your change would conflict with.
3. **[decisions.md](decisions.md)** if you are about to reverse something. The
   reasoning is usually recorded, including the alternatives already rejected.

### Update after building

A change is **not finished** until the docs match it:

- The relevant **`features/<feature>.md`** reflects the new behaviour — Rules,
  Data model, API surface, Flutter surface, Known gaps.
- A new capability gets **its own `features/<name>.md`**, linked from this index
  and from the **Related** section of every doc it touches.
- Any architectural decision is **appended to [decisions.md](decisions.md)** as a
  new dated entry. **Append only** — never edit or delete an existing entry; a
  reversed decision gets a new entry that supersedes the old one and links to it.
- Anything deferred goes in **[backlog.md](backlog.md)**, marked
  *idea* / *planned* / *in-progress*.
- A new table or column goes in
  **[reference/data-model.md](reference/data-model.md)**; a new error code in
  **[reference/error-codes.md](reference/error-codes.md)**.
- A cross-cutting rule goes in **[constraints.md](constraints.md)**.

This is the same standard the help centre is held to: **documentation describing
last month's behaviour is worse than none, because the reader follows it.**

### Conventions in these files

- **Only what the code actually does** is documented. Anything undeterminable from
  the code sits under an **OPEN QUESTIONS** heading at the foot of the file it
  belongs to, rather than being guessed at.
- Non-obvious claims carry a `file.py:line` citation.
- **Status labels are evidence-based.** "shipped (off by default)" means a config
  flag gates it off — which is true of most of the moderation and integration
  stack.
- A refactor, an index or a migration with no user-visible surface needs no doc
  change. The test is whether a reader could notice.

---

## Index

### Cross-cutting

| Document | What it is |
|---|---|
| [constraints.md](constraints.md) | Project-wide rules: portability, config-via-env, auth, access control, concurrency, moderation, GDPR, ToS/store compliance, security middleware, database, API contract stability, shared helpers, frontend — plus a **Known deviations** section where the code breaks its own rules |
| [decisions.md](decisions.md) | Append-only dated log of architectural decisions, with Context / Decision / Consequences / Alternatives rejected |
| [backlog.md](backlog.md) | Unbuilt work found in comments, skipped tests, un-vendored assets and unticked checklists, marked idea / planned / in-progress |

### Reference

| Document | What it is |
|---|---|
| [reference/data-model.md](reference/data-model.md) | All **30 tables**: columns, keys, FK on-delete behaviour, indexes, plus the **migration-only objects** the test suite cannot see |
| [reference/error-codes.md](reference/error-codes.md) | All **63 error codes**: HTTP status, raise site, and whether the client localizes it |

### Features

#### Identity and access

| Document | What it covers |
|---|---|
| [authentication.md](features/authentication.md) | Register, login, JWT HS256, rotating refresh tokens, logout, timing-safe login, the auth dependencies |
| [google-sign-in.md](features/google-sign-in.md) | `/auth/google`, ID-token verification, the three branches, account linking, the People API birthday read |
| [passwords-and-email.md](features/passwords-and-email.md) | Reset, in-app change, HIBP, password history, security audit log, email verification |
| [accounts-and-profiles.md](features/accounts-and-profiles.md) | Profile CRUD, avatar and cover, travel identity, visited locations, privacy toggle, GDPR deletion |
| [legal-and-age-gate.md](features/legal-and-age-gate.md) | ToS / Privacy / Guidelines in six languages, acceptance on both signup paths, the re-acceptance gate, the 16+ gate |

#### Social graph

| Document | What it covers |
|---|---|
| [follows.md](features/follows.md) | Hybrid public/private model, follow requests, atomic counters |
| [blocking.md](features/blocking.md) | `user_blocks`, two-way visibility cuts, 404-as-deleted |

#### Itineraries

| Document | What it covers |
|---|---|
| [itineraries.md](features/itineraries.md) | Itinerary CRUD, denormalised totals, currency, recommended travel period |
| [visibility-and-access.md](features/visibility-and-access.md) | The four-level ladder, the allowlist, `can_view_itinerary`, `public_listing_criteria` |
| [tracks-and-stops.md](features/tracks-and-stops.md) | Tracks, stops, fractional indexing, the two-phase renumber, place types, map URLs |
| [transit-segments.md](features/transit-segments.md) | Segments, transport legs, leg modes, the orphan warning |
| [annotations.md](features/annotations.md) | Both annotation systems — stop-level and trip-wide |
| [ratings.md](features/ratings.md) | Multi-dimensional community ratings, SQL aggregates, per-rating moderation status |
| [saved-itineraries.md](features/saved-itineraries.md) | Bookmarks and the Saved tab |
| [collaborative-editing.md](features/collaborative-editing.md) | Editors, the rotating-token edit lock, the unified write guard, `shared-with-me` |
| [etag-concurrency.md](features/etag-concurrency.md) | `If-Match` optimistic concurrency **and** `If-None-Match` cache validation — two mechanisms, one header |

#### Discovery and sharing

| Document | What it covers |
|---|---|
| [feed-and-search.md](features/feed-and-search.md) | The Discover feed (Top/Recent), user search, place search |
| [sharing.md](features/sharing.md) | Public HTML landing pages for itineraries and profiles, Open Graph previews |

#### Media and moderation

| Document | What it covers |
|---|---|
| [image-pipeline.md](features/image-pipeline.md) | Upload paths, Pillow processing, EXIF stripping, the storage abstraction, filesystem vs R2 |
| [image-moderation.md](features/image-moderation.md) | Rekognition tiers, reject / flag / fail-open, the inert client pre-check |
| [text-moderation.md](features/text-moderation.md) | Provider chain, our own policy and `POLICY_VERSION`, the cache, the moderator queue, coverage and deliberate exclusions |
| [content-reports.md](features/content-reports.md) | Polymorphic reports, distinct-reporter thresholds, legal escalations, the CSAM takedown procedure |
| [admin-and-appeals.md](features/admin-and-appeals.md) | The `/admin` dashboard and its lanes, the moderation log, appeals, the moderation sweep |

#### Delivery and support

| Document | What it covers |
|---|---|
| [notifications.md](features/notifications.md) | Eight in-app types, the poll and badge, FCM push, device tokens, retention |
| [bug-reports.md](features/bug-reports.md) | Shake-to-report, the screenshot pipeline, `/admin/bugs`, the Jira hand-off |
| [help-centre.md](features/help-centre.md) | `/help` — 26 articles rendered five ways — plus sitewide canonical, hreflang and sitemap |

#### Platform

| Document | What it covers |
|---|---|
| [web-and-platform.md](features/web-and-platform.md) | The middleware stack, rate limits, config invariants, static mounts, web i18n, the marketing homepage, the waitlist, hosting, and the Flutter app's widget wiring and route table |

---

## External specs (not in this folder)

These live beside the backend and are cited by `CLAUDE.md` by path, so they stay
where they are:

| Document | What it covers |
|---|---|
| [`social_api/docs/media_pipeline_spec.md`](../social_api/docs/media_pipeline_spec.md) | The four-layer upload safety architecture, the deterministic key patterns, the rejected presigned-upload design, the accepted serve-time-detection risk, and an eight-step operator checklist |
| [`social_api/docs/csam_response_runbook.md`](../social_api/docs/csam_response_runbook.md) | The operator takedown procedure, preservation duties, the CyberTipline filing, and a **six-row decision table awaiting counsel sign-off** |
| `social_api/docs/csam_manual_test_plan.xlsx` | Manual test plan (binary) |

---

## Older documentation, and where it is now wrong

The three READMEs predate most of the system and are **superseded by this folder**
for schema and endpoint detail. They remain useful for setup instructions.

| Document | Status |
|---|---|
| [`README.md`](../README.md) | Setup and local-run instructions are current. **Stale**: the JWT lifetime, `ACCESS_TOKEN_EXPIRE_MINUTES`, the 401 behaviour, the ratings list, the repo tree, the test table, and the `is_private` default |
| [`social_api/README.md`](../social_api/README.md) | Its **Key Design Decisions** section is good and has been folded into [decisions.md](decisions.md). **Stale**: documents 11 of 30 tables and omits roughly 60 endpoints |
| [`social_flutter/README.md`](../social_flutter/README.md) | **Stale**: still presents transit segments as a current feature |

Every drifted claim is itemised in
[backlog.md § Documentation drift](backlog.md#documentation-drift).

---

## Scale, for orientation

Measured from the code, not estimated.

| | |
|---|---|
| Backend | 251 Python files · **30 tables** · 16 routers · **147 routes** · **63 error codes** · 53 migrations |
| Frontend | 217 Dart files · 10 feature directories · **58 providers** · **36 live screens** · 5 shell branches |
| Localization | 6 languages · 956 keys, complete in all six |
| Help centre | 26 articles · 8 categories · 6 languages |
| History | 438 commits, 2026-03-12 → 2026-09-02 |

`docs/` is tracked by git and listed in `.dockerignore`, so it never enters the
production image.
