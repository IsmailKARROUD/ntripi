# Data model — all tables

Every table in the schema, extracted from `social_api/app/models/` via SQLAlchemy
metadata. **30 tables.** Each row links to the feature doc that owns it.

Conventions that hold everywhere:

- **UUID primary keys**, server default `gen_random_uuid()`. Flutter models carry
  them as `String`.
- **`created_at` / `updated_at`** are `TIMESTAMPTZ`, server default `now()`.
- **Every FK column carries an explicit index** unless it is a `SET NULL`
  admin/audit column with no hot read. PostgreSQL indexes the *referenced* key,
  never the referencing column — see [constraints.md](../constraints.md#database).
- **`rank` columns are `TEXT COLLATE "C"`** — lexicographic fractional-index keys,
  never numbers. See [tracks-and-stops.md](../features/tracks-and-stops.md).
- **Some schema objects exist only in migrations, not in the ORM models.** They
  are listed in [Migration-only objects](#migration-only-objects) and are
  invisible to the test suite — see the warning there.

## Table index

| Table | Owner doc | Purpose |
|---|---|---|
| `users` | [accounts-and-profiles.md](../features/accounts-and-profiles.md) | the account, profile, counters, preferences, moderation state |
| `follows` | [follows.md](../features/follows.md) | directed follow edge with pending/accepted status |
| `user_blocks` | [blocking.md](../features/blocking.md) | one-way block row, consulted in both directions |
| `refresh_tokens` | [authentication.md](../features/authentication.md) | rotating refresh-token family |
| `email_tokens` | [passwords-and-email.md](../features/passwords-and-email.md) | password-reset and email-verification tokens |
| `password_history` | [passwords-and-email.md](../features/passwords-and-email.md) | previous hashes, for reuse rejection |
| `security_audit_log` | [passwords-and-email.md](../features/passwords-and-email.md) | security-event trail |
| `itineraries` | [itineraries.md](../features/itineraries.md) | the trip: title, cost, visibility, soft-delete state |
| `tracks` | [tracks-and-stops.md](../features/tracks-and-stops.md) | a vertical column of parallel stop alternatives |
| `stops` | [tracks-and-stops.md](../features/tracks-and-stops.md) | a place within a track |
| `annotations` | [annotations.md](../features/annotations.md) | stop-level note |
| `itinerary_annotations` | [annotations.md](../features/annotations.md) | trip-wide note |
| `transit_segments` | [transit-segments.md](../features/transit-segments.md) | travel between two adjacent stops |
| `transport_legs` | [transit-segments.md](../features/transit-segments.md) | one mode-hop inside a segment |
| `itinerary_ratings` | [ratings.md](../features/ratings.md) | one user's multi-dimensional rating |
| `saved_itineraries` | [saved-itineraries.md](../features/saved-itineraries.md) | bookmark |
| `itinerary_allowed_users` | [visibility-and-access.md](../features/visibility-and-access.md) | `restricted` visibility allowlist |
| `itinerary_editors` | [collaborative-editing.md](../features/collaborative-editing.md) | edit grant |
| `itinerary_edit_locks` | [collaborative-editing.md](../features/collaborative-editing.md) | the single active edit claim |
| `content_reports` | [content-reports.md](../features/content-reports.md) | polymorphic user report |
| `legal_escalations` | [content-reports.md](../features/content-reports.md) | CSAM / legal lane |
| `moderation_log` | [admin-and-appeals.md](../features/admin-and-appeals.md) | operator + automated action audit |
| `appeals` | [admin-and-appeals.md](../features/admin-and-appeals.md) | user appeal against an action |
| `image_moderation_logs` | [image-moderation.md](../features/image-moderation.md) | Rekognition verdict + CSAM evidence |
| `text_moderation_cache` | [text-moderation.md](../features/text-moderation.md) | verdict cache, keyed by text+model+policy |
| `text_moderation_decisions` | [text-moderation.md](../features/text-moderation.md) | audit trail *and* moderator queue |
| `notifications` | [notifications.md](../features/notifications.md) | in-app feed row (structured reference) |
| `device_tokens` | [notifications.md](../features/notifications.md) | FCM registration per install |
| `bug_reports` | [bug-reports.md](../features/bug-reports.md) | in-app bug ticket + screenshot key |
| `waitlist` | [web-and-platform.md](../features/web-and-platform.md) | pre-launch signup |

---

## Identity and social graph

### `users`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `username` | VARCHAR(30) | NOT NULL, indexed — display form, preserves case |
| `username_lower` | VARCHAR(30) | NOT NULL, **UNIQUE** — the only lookup key |
| `email` | VARCHAR(255) | NOT NULL, UNIQUE — always stored lowercased |
| `password_hash` | VARCHAR(255) | nullable — null on a Google-only account |
| `google_sub` | VARCHAR(255) | UNIQUE, nullable — Google's stable subject id |
| `email_verified` | BOOLEAN | NOT NULL, default `false` |
| `display_name` | VARCHAR(50) | nullable — free Unicode, falls back to `@username` |
| `bio` | TEXT | nullable |
| `avatar_url`, `cover_image_url` | TEXT | nullable |
| `passport_countries` | JSON | nullable — ISO-3166 alpha-2 list |
| `resident_country` | VARCHAR(2) | nullable |
| `languages` | JSON | nullable |
| `is_private` | BOOLEAN | NOT NULL — **new accounts are private** |
| `followers_count`, `following_count` | INTEGER | NOT NULL — denormalised, written only by atomic SQL |
| `is_active` | BOOLEAN | NOT NULL — `false` = banned/deactivated; 403s every authed request |
| `is_admin` | BOOLEAN | NOT NULL, default `false` — **set by SQL only; no promotion UI** |
| `notify_ratings`, `notify_saves`, `notify_follow_accepted` | BOOLEAN | NOT NULL, default `true` — the three mutable notification types |
| `tos_accepted_at` | TIMESTAMPTZ | nullable |
| `tos_accepted_version` | VARCHAR(16) | nullable — the version string verbatim, never backfilled |
| `date_of_birth` | DATE | nullable — **never backfilled**; owner-visible only |
| `dob_source` | VARCHAR(16) | nullable — which source supplied the date |
| `moderation_status` | VARCHAR(20) | NOT NULL, default `approved` |

- CHECK `ck_user_moderation_status`: `moderation_status IN ('approved','pending','flagged','hidden','rejected')`
- UNIQUE indexes on `username_lower`, `email`, `google_sub`; plain index on `username`
- No outgoing FKs.

### `follows`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `follower_id` | UUID | NOT NULL, indexed, FK → `users.id` **CASCADE** |
| `following_id` | UUID | NOT NULL, indexed, FK → `users.id` **CASCADE** |
| `status` | **ENUM `followstatus`** | NOT NULL — `pending` or `accepted`. A native PostgreSQL enum type (`SAEnum(FollowStatus, name="followstatus")`, `models/follow.py:88`) — **the only one in the schema**; every other enumerated column is a VARCHAR + CHECK |

- CHECK `ck_no_self_follow`: `follower_id != following_id`
- UNIQUE `uq_follower_following (follower_id, following_id)`
- There is no `rejected` status — rejecting **deletes** the row so the requester
  can retry. See [follows.md](../features/follows.md).

### `user_blocks`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `blocker_user_id` | UUID | NOT NULL, indexed, FK → `users.id` **CASCADE** |
| `blocked_user_id` | UUID | NOT NULL, indexed, FK → `users.id` **CASCADE** |

- CHECK `ck_no_self_block`; UNIQUE `uq_user_block`
- **Both FKs CASCADE on purpose** — a block is a preference, not evidence.

---

## Sessions and credentials

### `refresh_tokens`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `user_id` | UUID | NOT NULL, indexed, FK → `users.id` CASCADE |
| `token_hash` | VARCHAR(64) | NOT NULL, **UNIQUE** — SHA-256; the raw token is never stored |
| `family_id` | UUID | NOT NULL, indexed — rotation lineage; replay revokes the whole family |
| `issued_at`, `expires_at` | TIMESTAMPTZ | |
| `revoked_at` | TIMESTAMPTZ | nullable |
| `rotated_to` | UUID | nullable — the successor token |
| `user_agent` | VARCHAR(255) | nullable — captured for a *future* "active sessions" UI (unbuilt) |

### `email_tokens`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `user_id` | UUID | NOT NULL, indexed, FK → `users.id` CASCADE |
| `token_hash` | VARCHAR(64) | NOT NULL, UNIQUE (indexed) |
| `purpose` | VARCHAR(20) | NOT NULL |
| `expires_at`, `used_at` | TIMESTAMPTZ | `used_at` non-null = spent |

### `password_history`

`id` PK · `user_id` FK → `users.id` CASCADE (indexed) · `password_hash` VARCHAR(255) · `created_at`.

### `security_audit_log`

`id` PK · `user_id` FK → `users.id` CASCADE (indexed) · `event_type` VARCHAR(64) ·
`ip_address` VARCHAR(64) · `user_agent` VARCHAR(255) · `created_at`.

---

## Itinerary core

### `itineraries`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `user_id` | UUID | NOT NULL, indexed, FK → `users.id` CASCADE — the owner |
| `title` | VARCHAR(200) | NOT NULL |
| `description` | TEXT | nullable |
| `cover_image_url` | TEXT | nullable |
| `total_duration_min` | INTEGER | NOT NULL, default `0` — denormalised |
| `total_cost` | NUMERIC(10,2) | NOT NULL, default `0.00` — denormalised |
| `currency` | VARCHAR(3) | NOT NULL, default `'EUR'` |
| `rating_avg` | NUMERIC(3,2) | nullable — recomputed by SQL `AVG()`, never in Python |
| `rating_count` | INTEGER | NOT NULL, default `0` |
| `visibility` | VARCHAR(20) | NOT NULL, default **`'only_me'`** |
| `recommended_periods` | JSON | nullable |
| `recommended_weekdays` | JSON | nullable |
| `recommended_period_note` | TEXT | nullable |
| `moderation_status` | VARCHAR(20) | NOT NULL, default `approved` |
| `hidden_at` | TIMESTAMPTZ | nullable — moderator-hidden → owner-only |
| `deleted_at` | TIMESTAMPTZ | nullable — soft delete → invisible to **everyone**, owner included |
| `updated_at` | TIMESTAMPTZ | **this column IS the concurrency ETag** |

- CHECK `ck_itinerary_moderation_status`
- `visibility` is not a DB enum or CHECK — it is enforced in the schema layer and
  by `can_view_itinerary`. See [OPEN QUESTIONS](#open-questions).

### `tracks`

`id` PK · `itinerary_id` FK → `itineraries.id` CASCADE (indexed) · `rank` TEXT NOT NULL ·
`created_at` · `updated_at`.

- UNIQUE `uq_track_rank (itinerary_id, rank)` — the constraint the `!`-prefixed
  temp ranks in `_two_phase_renumber` exist to dodge.
- A track exists only while it holds ≥1 stop; app-level lifecycle, not DB cascade.

### `stops`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `itinerary_id` | UUID | NOT NULL, indexed, FK → `itineraries.id` CASCADE |
| `track_id` | UUID | NOT NULL, indexed, FK → `tracks.id` CASCADE |
| `rank` | TEXT | NOT NULL — fractional index within the track |
| `place_name` | VARCHAR(200) | nullable |
| `place_address` | TEXT | nullable |
| `lat`, `lng` | NUMERIC(9,6) | nullable |
| `map_url` | VARCHAR(500) | nullable — host-allowlisted Google Maps link |
| `place_type` | VARCHAR(50) | nullable — one of 11 camelCase values |
| `duration_min` | INTEGER | nullable |
| `cost` | NUMERIC(10,2) | NOT NULL, default `0.00` |
| `is_free` | BOOLEAN | NOT NULL, default `false` — distinct from `cost = 0` |
| `notes` | TEXT | nullable |

- UNIQUE `uq_stop_rank (track_id, rank)`
- **There is no `type`, `position`, or `parallel_position` column.** Stop role is
  derived client-side from track order.

### `annotations` (stop-level)

`id` PK · `stop_id` FK → `stops.id` CASCADE (indexed) · `type` VARCHAR(20) NOT NULL ·
`content` TEXT NOT NULL · `created_at` · `updated_at`.

- CHECK `ck_annotation_type`: `type IN ('advice','caution','avoid','info')`

### `itinerary_annotations` (trip-wide)

`id` PK · `itinerary_id` FK → `itineraries.id` CASCADE (indexed) · `type` VARCHAR(20) ·
`content` TEXT · `created_at` · `updated_at`. Same four types.

### `transit_segments`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `itinerary_id` | UUID | NOT NULL, indexed, FK → `itineraries.id` CASCADE |
| `from_stop_id` | UUID | NOT NULL, FK → `stops.id` CASCADE (**not** separately indexed) |
| `to_stop_id` | UUID | NOT NULL, indexed, FK → `stops.id` CASCADE |
| `total_duration_min` | INTEGER | NOT NULL, default `0` |
| `total_cost` | NUMERIC(10,2) | NOT NULL, default `0.00` |

- CHECK `ck_segment_different_stops`; UNIQUE `uq_segment_stops (from_stop_id, to_stop_id)`

### `transport_legs`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `segment_id` | UUID | NOT NULL, indexed, FK → `transit_segments.id` CASCADE |
| `position` | SMALLINT | NOT NULL — legs *do* use an integer position; stops do not |
| `mode` | VARCHAR(20) | NOT NULL |
| `line` | VARCHAR(30) | nullable |
| `direction` | TEXT | nullable |
| `duration_min` | INTEGER | nullable |
| `cost` | NUMERIC(10,2) | NOT NULL, default `0.00` |
| `is_free` | BOOLEAN | NOT NULL, default `false` |
| `notes` | TEXT | nullable |
| `note_type` | VARCHAR(10) | nullable — same four annotation types |

- CHECK `ck_leg_mode`: `walk, bus, tram, metro, train, taxi, uber, bike, ferry, car, airplane`
- CHECK `ck_leg_note_type`; UNIQUE `uq_leg_position (segment_id, position)`

### `itinerary_ratings`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `itinerary_id` | UUID | NOT NULL, indexed, FK → `itineraries.id` CASCADE |
| `user_id` | UUID | nullable, FK → `users.id` **SET NULL** — a deleted account's rating survives anonymised (GDPR) |
| `stars` | SMALLINT | NOT NULL, 1–5 |
| `safety_stars`, `experience_stars`, `accessibility_stars`, `family_friendly_stars`, `crowdedness_stars` | SMALLINT | nullable, 1–5 each; NULL = not rated |
| `note` | TEXT | nullable |
| `moderation_status` | VARCHAR(20) | NOT NULL, default `approved` — per-rating, so an abusive review cannot take the trip down |

- 7 CHECK constraints: one per star column plus the moderation status
- UNIQUE `uq_itinerary_rating (itinerary_id, user_id)` — one rating per user per trip
- Exposed as `*_score` in `RatingWithUser`, not `*_stars`.

### `saved_itineraries`

`itinerary_id` + `user_id` **composite PK**, both FK CASCADE · `saved_at`.
Extra index `ix_saved_itineraries_user_id` — the trailing PK column cannot use the
PK index for `WHERE user_id = ?`.

### `itinerary_allowed_users`

`itinerary_id` + `user_id` **composite PK**, both FK CASCADE · `created_at`.
Extra index `ix_itinerary_allowed_users_user_id`, same reason.

### `itinerary_editors`

`itinerary_id` + `user_id` **composite PK**, both FK CASCADE · `granted_by` FK →
`users.id` **SET NULL** (audit only) · `created_at`.
Index `ix_itinerary_editors_user (user_id)` — this table *is* queried by its
trailing column ("itineraries I can edit"), which the allowlist is not.

### `itinerary_edit_locks`

| Column | Type | Notes |
|---|---|---|
| `itinerary_id` | UUID | **PK** — "at most one holder" is a database invariant |
| `user_id` | UUID | NOT NULL, indexed, FK → `users.id` CASCADE |
| `token_hash` | VARCHAR(64) | NOT NULL — SHA-256 of the claim token; rotated on every takeover |
| `acquired_at`, `last_heartbeat_at` | TIMESTAMPTZ | NOT NULL |

- Index `ix_itinerary_edit_locks_heartbeat (last_heartbeat_at)`
- **No `expires_at` column** — staleness is derived at read time, so raising the
  TTL takes effect on claims that already exist.

---

## Moderation and safety

### `content_reports`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `target_type` | VARCHAR(16) | NOT NULL — `itinerary`, `rating`, `user` |
| `target_id` | UUID | indexed, **no FK** — evidence must survive a hard delete |
| `reporter_user_id` | UUID | indexed, FK → `users.id` SET NULL |
| `reason` | VARCHAR(32) | NOT NULL |
| `notes` | TEXT | nullable — **deliberately not text-moderated** |
| `reporter_ip_hash` | VARCHAR(64) | indexed — HMAC, for anonymous rate limiting |
| `created_at` | TIMESTAMPTZ | indexed |
| `resolved_at` | TIMESTAMPTZ | nullable |
| `resolution` | VARCHAR(32) | NOT NULL, default `pending` |

- CHECK `ck_report_reason`: `csam, sexual_content, violence_threat, hate_speech, harassment, other, spam`
- CHECK `ck_report_resolution`: `pending, dismissed, content_removed, content_hidden, user_warned, user_banned, auto_hidden`
- Legacy wire values (`nsfw`, `violence`, `copyright`) are normalised before insert.

### `legal_escalations`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `target_type` | VARCHAR(16) | NOT NULL — `itinerary`, `rating`, `user` |
| `target_id` | UUID | indexed, no FK |
| `source` | VARCHAR(16) | NOT NULL — `report`, `score`, `hash_match` |
| `report_id` | UUID | FK → `content_reports.id` SET NULL |
| `decision_id` | UUID | FK → `text_moderation_decisions.id` SET NULL |
| `closed_at`, `closed_by`, `closure_note` | | closing demands a written note |

### `moderation_log`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `admin_user_id` | UUID | indexed, FK → `users.id` SET NULL — **NULL = automated action** |
| `target_type` | VARCHAR(16) | `itinerary`, `user`, `rating` |
| `target_id` | UUID | indexed, no FK |
| `action` | VARCHAR(32) | NOT NULL |
| `reason` | TEXT | NOT NULL |
| `content_snapshot` | JSON | nullable — **always NULL on automated rows** (no raw text/PII) |
| `created_at` | TIMESTAMPTZ | indexed |

Actions (17 total):
- **Operator** — `dismiss, hide, unhide, undelete, delete, warn, ban, unban, appeal_restore, appeal_uphold, appeal_reduce`
- **System** — `auto_reject, auto_hide_reports, auto_hide_sla, recheck, appeal_filed, legal_escalate`
- `HIDE_FAMILY = (hide, auto_hide_reports, auto_hide_sla, auto_reject)` — the
  appealable set.
- `rejected_csam` rows in `image_moderation_logs` are exempt from the 90-day purge.

### `appeals`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `user_id` | UUID | NOT NULL, indexed, FK → `users.id` CASCADE |
| `moderation_log_id` | UUID | FK → `moderation_log.id` SET NULL |
| `target_type` | VARCHAR(16) | `itinerary`, `user`, `rating` |
| `target_id` | UUID | indexed |
| `status` | VARCHAR(16) | NOT NULL, default `pending` — `pending, upheld, restored, reduced` |
| `user_reason` | TEXT | NOT NULL — **deliberately not text-moderated** |
| `admin_response` | TEXT | nullable |

### `image_moderation_logs`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `image_hash` | VARCHAR(64) | NOT NULL — SHA-256; on a CSAM takedown this is the **only surviving evidence** |
| `target_kind` | VARCHAR(32) | `itinerary_cover`, `avatar`, `user_cover` |
| `target_itinerary_id` | UUID | indexed, FK → `itineraries.id` SET NULL |
| `uploader_user_id` | UUID | indexed, FK → `users.id` SET NULL |
| `action` | VARCHAR(32) | `approved, flagged, rejected, error_allowed, rejected_csam` |
| `labels` | JSON | NOT NULL — classifier labels + confidences |
| `reviewed_at` | TIMESTAMPTZ | nullable |

### `text_moderation_cache`

`cache_key` VARCHAR(64) **PK** — hash of text + model + `POLICY_VERSION` ·
`outcome` VARCHAR(16) · `scores` JSON · `provider` · `model` · `created_at` ·
`expires_at` (indexed).

- CHECK outcome: `approve, review, reject, hide_escalate`
- **Holds no raw text and no user reference.**

### `text_moderation_decisions`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `content_hash` | VARCHAR(64) | NOT NULL, indexed |
| `target_type` | VARCHAR(24) | `itinerary`, `rating`, `user` |
| `target_id` | UUID | indexed |
| `author_user_id` | UUID | indexed, FK → `users.id` SET NULL |
| `outcome` | VARCHAR(16) | `approve, review, reject, hide_escalate, pending` |
| `scores` | JSON | NOT NULL |
| `provider`, `model` | | nullable |
| `policy_version` | VARCHAR(8) | NOT NULL |
| `source` | VARCHAR(16) | `write` or `recheck` |
| `queue_label` | VARCHAR(16) | nullable |
| `reviewed_at` | TIMESTAMPTZ | **NULL = still queued** — this table is the moderator queue |

Retention purges reviewed rows only.

---

## Notifications

### `notifications`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `user_id` | UUID | NOT NULL, FK → `users.id` CASCADE — the recipient |
| `type` | VARCHAR(32) | NOT NULL |
| `subtype` | VARCHAR(40) | nullable — carries the action name for `moderation_action` |
| `actor_id` | UUID | indexed, FK → `users.id` SET NULL — **NULL for `moderation_action`** |
| `entity_type` | VARCHAR(20) | nullable — `itinerary, user, follow, rating` |
| `entity_id` | UUID | nullable |
| `read_at` | TIMESTAMPTZ | indexed, nullable |

- 8 types: `follow_request, new_follower, follow_accepted, itinerary_rated, itinerary_saved, moderation_action, itinerary_editor_added, itinerary_viewer_added`
- 3 mutable (switchable): `follow_accepted, itinerary_rated, itinerary_saved` →
  the three `notify_*` columns on `users`
- Index `ix_notifications_user_created (user_id, created_at)` — the only query the
  list endpoint runs
- **No rendered text column.** A row is a structured reference; the sentence is
  built client-side.

### `device_tokens`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `user_id` | UUID | NOT NULL, FK → `users.id` CASCADE |
| `token` | VARCHAR | NOT NULL, **UNIQUE globally — not per user** |
| `platform` | VARCHAR(10) | NOT NULL — `ios` or `android` only |
| `locale` | VARCHAR(10) | NOT NULL — per-device, normalised on the way in |
| `last_seen_at` | TIMESTAMPTZ | NOT NULL — drives retention pruning |

The global UNIQUE is load-bearing: FCM reassigns a token to whichever account is
signed in on that install, so registering **moves** the row. Per-user uniqueness
would leave two people sharing a phone receiving each other's notifications.

---

## Support and growth

### `bug_reports`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `user_id` | UUID | FK → `users.id` SET NULL — nullable, reports are auth-optional |
| `message` | TEXT | NOT NULL — **deliberately not text-moderated** |
| `category` | VARCHAR(16) | nullable — `crash, visual, data, slow, other` |
| `screenshot_key` | VARCHAR(255) | nullable — **storage key, not a URL** |
| `app_version`, `platform`, `os_version`, `device_model`, `route`, `locale`, `theme_mode` | | diagnostics |
| `status` | VARCHAR(16) | NOT NULL, default `open` — `open` or `closed` only |
| `resolution_note` | TEXT | nullable — carries what a wontfix/fixed split would |
| `jira_issue_key` | VARCHAR(32) | nullable — **its presence IS the duplicate guard** |
| `closed_at`, `closed_by_admin_id` | | FK SET NULL |

- CHECK on `platform` (`ios, android, web, macos, windows, linux`), `category`, `status`
- Index `ix_bug_reports_status_created (status, created_at)`
- Only **closed** reports are ever purged.

### `waitlist`

`id` PK · `email` VARCHAR(255) UNIQUE nullable · `whatsapp` VARCHAR(50) nullable ·
`platform` VARCHAR(10) NOT NULL · `created_at`. One contact field is required at
the schema layer, not by a CHECK — see `waitlist_contact_required`.

---

## Migration-only objects

These exist in PostgreSQL but **not** in `__table_args__`, so they are absent
from the ORM metadata. The test suite builds its schema from that metadata on
SQLite (`test/conftest.py`), which means **nothing below is exercised by any
test.** Migration `12b6e3451c36`'s own docstring records what this cost once: a
CHECK constraint that lived only in a migration let every auto-hide of an
itinerary raise `CheckViolation` → 500 in production for months while the suite
stayed green.

| Object | Table | Defined in | Purpose |
|---|---|---|---|
| `COLLATE "C"` on `rank` | `tracks`, `stops` | `d5e6f7a8b9c0:46,68` (`ALTER TABLE … TYPE TEXT COLLATE "C"`) | byte-wise sort, identical to Python string comparison. The default locale-aware collation would order upper/lowercase differently from the ordering service |
| `idx_tracks_itinerary (itinerary_id, rank)` | `tracks` | `d5e6f7a8b9c0:43` | ordered track fetch |
| `idx_stops_track (track_id, rank)` | `stops` | `d5e6f7a8b9c0:65` | ordered stop fetch |
| `ix_itineraries_feed_recent (created_at DESC, id DESC)` **WHERE `visibility='public'`** | `itineraries` | `98fa3c7b7229:26` | the Recent feed sort |
| `ix_itineraries_feed_top (rating_avg DESC, rating_count DESC, created_at DESC, id DESC)` **WHERE `visibility='public'`** | `itineraries` | `98fa3c7b7229:32` | the Top feed sort |

Both feed indexes are **partial** (`postgresql_where`), so they cover only public
itineraries — which is all the discovery feed reads.

`a681984a1a04` is the reference implementation for adding an index to a populated
table: `CREATE INDEX CONCURRENTLY` inside `op.get_context().autocommit_block()`,
guarded on the dialect being PostgreSQL. See
[constraints.md](../constraints.md#database).

---

## OPEN QUESTIONS

- **`itineraries.visibility` has no CHECK constraint** while every other
  enumerated column in the schema does (`moderation_status`, `follows.status`,
  report reasons, leg modes, notification types). The four values are enforced by
  the Pydantic `_VISIBILITY` pattern and by `can_view_itinerary`'s fallthrough
  (an unknown value denies everyone but the owner). Whether the missing
  constraint is deliberate — it predates the CHECK convention, added in
  `c3d2e1f0a9b8` on 2026-03-15 — or an oversight is not determinable from the
  code.
- **`transit_segments.from_stop_id` has no dedicated index** while `to_stop_id`
  does. It is the leading column of `uq_segment_stops`, so `WHERE from_stop_id = ?`
  can use that index and `to_stop_id` cannot — which explains the asymmetry, but
  no comment states it.
- **`waitlist.email` is nullable and UNIQUE.** PostgreSQL permits many NULLs under
  a UNIQUE constraint, so multiple WhatsApp-only signups are possible while
  email-only signups are deduplicated. Whether that asymmetry is intended is not
  stated anywhere.
- **`security_audit_log` is written but never read.** Three `event_type`
  values are ever stored (`"password_change"`, `"password_change_failed"`,
  and — since 2026-09-28 — `"unverified_password_dropped_on_google_link"`, all in
  `auth_service.py`), and no endpoint, admin lane or query in `app/` reads the
  table. Write-only for direct-SQL support triage, or an unfinished
  feature, is not recorded.
- **`refresh_tokens.rotated_to` is written and never read**
  (`refresh_token_service.py:109`); its docstring calls it informational.
  `user_agent` is likewise captured for a "list active sessions" UI that does not
  exist.
- **`waitlist.platform` is written and read nowhere in `app/`** — no admin lane,
  no export, no query.
- **`MODERATION_LOG_SYSTEM_ACTIONS` declares `"recheck"`**
  (`models/moderation_log.py:57`) and the CHECK permits it, but nothing writes
  it — `_hide_after_recheck` writes `auto_reject` (`sweep_service.py:259`).
  Whether it is dead vocabulary or a planned row type is not stated.
