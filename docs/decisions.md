# Decision log

Append-only. Oldest first, newest last. **Never edit or delete an entry** — a
reversed decision gets a new entry at the bottom that supersedes the old one and
links to it.

Dates come from git history (438 commits, 2026-03-12 → 2026-09-02) and from the
date each Alembic revision was **first added**, which dates the schema decision
behind it. Where no commit anchors a decision it is marked **undated** rather
than guessed at. Two gaps in the history — 2026-05-26 → 2026-06-11 and
2026-08-18 → 2026-08-29 — are why interpolation is refused.

---

### 2026-03-12 — Monorepo with a strictly separated backend and frontend

**Context.** One person building a FastAPI backend and a Flutter app for three
platforms.
**Decision.** One repository, `social_api/` and `social_flutter/`, sharing **no
code** — HTTP/JSON only. UUID primary keys everywhere, carried as `String` in
Dart.
**Consequences.** The two halves version and deploy independently; every contract
change has to travel over the wire, which is what makes the API shape matter so
much later. UUIDs cost index size but remove any need for id-guessing defences.
**Alternatives rejected.** Two repositories (coordination overhead for one
person); a shared codegen layer (would reintroduce coupling and require
build_runner, rejected separately).

---

### 2026-03-13 — Accounts are private by default

**Context.** A social app whose content is people's travel plans.
**Decision.** `users.is_private` defaults `True`. New itineraries default
`only_me`.
**Consequences.** Every new account starts invisible, so growth depends on
deliberate sharing. The private→public flip needs a bulk auto-accept path, which
now lives in `update_me`.
**Alternatives rejected.** Public by default with an opt-out (the usual choice,
and the wrong one when the content is somebody's itinerary and home city).

---

### 2026-03-15 — Four-level visibility replaces the `is_public` boolean

**Context.** `is_public` could not express "my followers" or "these five people".
**Decision.** `visibility` ∈ `public | followers | restricted | only_me`, with
`itinerary_allowed_users` backing `restricted`. One function,
`can_view_itinerary()`, owns the ladder.
**Consequences.** Every read path in the project calls that one function, and the
edit ladder later delegates to it rather than duplicating it — the single most
load-bearing structural decision in the codebase. The column shipped without a DB
CHECK, which is still true.
**Alternatives rejected.** A boolean plus a separate share table (cannot express
`followers`); per-stop visibility (no read path would have been cheap enough).
Migration `c3d2e1f0a9b8`.

---

### 2026-04-19 — GDPR deletion keeps ratings by anonymising them

**Context.** A hard account delete would erase ratings other people rely on to
judge a trip.
**Decision.** `itinerary_ratings.user_id` is `ON DELETE SET NULL`. The account and
its own content are hard-deleted; a documented set of evidence columns keep their
rows with a NULL user.
**Consequences.** A trip keeps its score after a reviewer leaves. `rating_count`
stays honest. The deletion path has to decrement other users' counters *before*
the cascade, and nulls `user_id` explicitly as belt-and-braces.
**Alternatives rejected.** Cascading ratings away (would silently re-score every
trip a departing user had rated); soft-deleting accounts (a GDPR erasure request
is not satisfied by a flag).

---

### 2026-04-22 — Community ratings replace the owner-declared `safety_rating`

**Context.** `itineraries.safety_rating` was set by the trip's author.
**Decision.** Drop the column. Introduce `itinerary_ratings` with a required
overall score and five optional dimensions (safety, experience, accessibility,
family-friendly, and later crowdedness), one row per user per trip.
**Consequences.** The number means something. Averages must be computed in SQL,
the aggregate has to exclude moderated reviews, and each rating needs its own
`moderation_status` so an abusive review cannot take down the trip.
**Alternatives rejected.** Keeping both (two numbers called "safety" on one
screen); a single overall score only (loses the dimension that travellers
actually ask about). Migrations `07035928fd6c`, `a1b2c3d4e5f6`, `b7c8d9e0f1a2`.

---

### 2026-04-23 — `CLAUDE.md` as the conventions file, and a portability rule set

**Context.** Most of the code is written with an AI assistant, and conventions
were being re-derived every session.
**Decision.** One root `CLAUDE.md` holding architectural rules and a "What NOT To
Do" list, plus five portability rules: env-var config, a single root Dockerfile,
no platform-specific features, storage behind an abstraction, and no shared
backend/frontend code.
**Consequences.** The rules held — there is not one `Color` literal outside
`app_theme.dart`, and the storage abstraction made the R2 migration a config
change. The file also grew to 1,011 lines with no navigation, which is why
`docs/` now exists beside it.
**Alternatives rejected.** Per-directory convention files (an agent reads the root
first); documenting nothing and relying on code review (there is one reviewer).

---

### 2026-04-27 — Conservative username policy with `username_lower` as the key

**Context.** Case-insensitive uniqueness, and handles that appear in share URLs.
**Decision.** `username_lower` is UNIQUE and **the only lookup key**; `username`
keeps display casing. Pattern `^[a-zA-Z][a-zA-Z0-9_.]{2,28}[a-zA-Z0-9]$`, no
consecutive `.`/`_`, a 68-entry reserved list. A separate free-Unicode
`display_name`.
**Consequences.** `User.username == …` is a bug anywhere it appears. Usernames
became immutable, because `build_profile_share_url` depends on it.
**Alternatives rejected.** `LOWER(username)` functional index (easy to forget at
a call site); allowing Unicode usernames (homoglyph impersonation in a share URL).
Migration `d4e5f6a7b8c9`.

---

### 2026-05-02 — Filesystem storage → Cloudflare R2

**Context.** Railway's filesystem is ephemeral; images vanished on redeploy
without a mounted volume.
**Decision.** Add an R2 backend behind the existing `Storage` ABC. Keep filesystem
as the local-dev and rollback path.
**Consequences.** Because the abstraction already existed, this was a config
change plus one class. R2 later became a **compliance dependency**: Cloudflare's
CSAM scanning only sees images served through the zone, so `STORAGE_BACKEND=r2`
with any `R2_*` var missing now raises at startup, and an `r2.dev`
`R2_PUBLIC_URL` logs a warning. Filesystem `public_url` returns a relative path,
which is why `absolute_storage_url` exists.
**Alternatives rejected.** A Railway persistent volume (works, but keeps images
off the CDN and out of the CSAM scan); presigned direct-to-R2 uploads — rejected
in writing at `media_pipeline_spec.md:70`, because the server would never see the
bytes it is supposed to scan and strip EXIF from.

---

### 2026-05-04 — Place types become 11 purpose-based categories; `destination` → `arrival`

**Context.** The original place taxonomy described venue kinds rather than what a
traveller goes there to do.
**Decision.** 11 camelCase values in `stops.place_type`: `eatDrink, sleep, pray,
learnSee, buy, playWatch, nature, travel, healBathe, entertainment, sight`. The
final stop role is renamed `arrival`.
**Consequences.** `PlaceType.fromString()` must handle legacy values and return
null for unknowns — it is the only permitted way to read the field. `travel` was
later renamed `transport` (2026-07-04, `c78a28a2e02f`). The column still has no DB
CHECK; the Pydantic regex is the only gate.
**Alternatives rejected.** A venue-type taxonomy (users do not think in venue
types); a free-text tag (unfilterable).

---

### 2026-05-05 — Stop role is derived from position, not stored

**Context.** Users were being asked to label a stop as origin / waypoint /
arrival, which is information the list order already carries.
**Decision.** Drop `stops.type`. Derive the role client-side in
`Itinerary._parseTracks()`: one track → all `origin`; two or more → first
`origin`, last `arrival`, rest `waypoint`.
**Consequences.** Reordering can never produce an inconsistent labelling, because
there is nothing to keep in sync. `Stop.fromJson` sets a placeholder and the real
role is assigned after deserialisation. The model file says "Never add it back".
It also broke the share page — `794725c` (2026-05-20) fixed a 500 from a leftover
`stop.type` access, which a live `test_share.py` would have caught.
**Alternatives rejected.** Keeping the column and recomputing on write (two
sources of truth); a DB trigger (same problem, further from the reader).
Migration `f1e2d3c4b5a6`.

---

### 2026-05-07 — Fractional indexing with first-class tracks

**Context.** Integer stop positions meant a mid-list insert rewrote every row
above it — 25 UPDATEs in a 50-stop trip — and those writes raced with concurrent
edits. Parallel alternatives ("Hotel A or Hotel B") had no representation at all.
**Decision.** `tracks` becomes a real table. `tracks.rank` and `stops.rank` are
lexicographic base-62 strings, `TEXT COLLATE "C"`. `services/ordering.py` owns
`key_between` / `n_keys_between`. A track exists only while it holds ≥1 stop,
enforced in application code.
**Consequences.** An insert or a move writes **one** row. `COLLATE "C"` is
required so SQL order matches Python order. `_two_phase_renumber` with `!`-prefixed
temporary ranks exists to dodge the UNIQUE constraints during a full rewrite, and
`add_stop` needs a 3-attempt retry on rank collision. Out-of-order anchors answer
**412**, not 422 — they mean the client's list is stale. The clean-slate migration
wiped stops, segments and annotations. **The same commit skipped six test files
with `"rewriting after fractional-indexing refactor"`, and they are still
skipped** — see [backlog.md](backlog.md).
**Alternatives rejected.** Integer positions with gaps (still rewrites on
exhaustion, and the gap size is a guess); a linked list (no `ORDER BY`); a
`parallel_position` column, which had shipped the day before (2026-05-06,
`c5d6e7f8a9b0`) and was replaced by tracks a day later. Migration
`d5e6f7a8b9c0`.

---

### 2026-05-12 — The cache ETag is split from the concurrency ETag

**Context.** `If-Match` on itinerary mutations already used `updated_at` as an
ETag. Bandwidth on repeated GETs was the separate problem.
**Decision.** Add `ETagMiddleware`, which hashes any JSON GET body to a 16-char
opaque token and answers 304 on `If-None-Match`. **It leaves an endpoint-set
`ETag` alone**, so `GET /itineraries/{id}` keeps emitting the ISO concurrency
token and the 304 round-trip still works against it.
**Consequences.** Two mechanisms share a header name and a normalisation function
but not a value format. `_normalize_etag` has to absorb Cloudflare's `W/` weak
prefix and Dart's `Z` vs Python's `+00:00`. Later designs are shaped by it: the
edit-lock GET carries absolute timestamps and **no** remaining-seconds field
specifically so its body is byte-stable and the 304 fires on every poll.
**Alternatives rejected.** Reusing `updated_at` for caching too (wrong for every
endpoint that is not one itinerary); `Last-Modified` (second resolution is too
coarse). Commits `71078a2`, `3968f71`, `eea9554`.

---

### 2026-05-14 — Alembic migration rules, after five revision-ID collisions

**Context.** The placeholder revision id `a1b2c3d4e5f6` had been hand-written for
**three different migrations** and `42f3ed3997b2` for two. Each collision forked
the chain and crashed the deploy, producing eight separate head-fixing commits
between 2026-04-27 and 2026-05-14.
**Decision.** Never hand-write a revision id — generate it. Always verify a single
head with `alembic heads` before committing. Never keep two files with the same
id. `down_revision` must be read from `alembic heads`, not guessed from filenames.
Written into `CLAUDE.md`.
**Consequences.** No collision since. Later additions: adding an index to a
populated table needs `CREATE INDEX CONCURRENTLY` inside an
`autocommit_block()`, guarded on the dialect — which forfeits the migration's
atomicity in exchange for not holding a write lock through a deploy.
**Alternatives rejected.** A CI check on head count (would have worked; nobody had
CI); sequential integer revisions (Alembic's own docs advise against it for
branching). Commit `e360f99`.

---

### 2026-05-19 — `StatefulShellRoute` replaces the hand-rolled `_AppShell`

**Context.** Switching tabs rebuilt each tab's widget tree, losing scroll position
and refetching.
**Decision.** `StatefulShellRoute.indexedStack` with five branches — `/search`,
`/profile/me`, `/itineraries`, `/saved`, `/feed`.
**Consequences.** Each branch's tree stays alive, so keep-alive providers render
their previous data on a second visit — which is why several screens now refetch
explicitly on open. `/profile/:userId` must be declared *after* the shell so
`/profile/me` wins.
**Alternatives rejected.** An `IndexedStack` inside one route (loses per-branch
navigation); `AutomaticKeepAliveClientMixin` per screen (per-widget, not
per-branch). Commit `4d869bd`.

---

### 2026-06-12 — Short access tokens plus rotating refresh tokens

**Context.** A 24-hour JWT was the whole session. A leak meant a day of access,
and there was no revocation.
**Decision.** `ACCESS_TOKEN_EXPIRE_MINUTES=15`; a rotating refresh token with a
`family_id`, 30-day inactivity expiry, stored only as a SHA-256 hash. **Replaying
a revoked token revokes the whole family.** `revoke()` no-ops on an unknown token
so it cannot become a validity oracle. The client refreshes transparently.
**Consequences.** Every write path can now be invalidated — password change and
reset both call `revoke_all_for_user`. The access token deliberately carries no
`scope` claim, and that *absence* is what the admin session and the appeal token
check against. `rotated_to` and `user_agent` are captured and still unread.
**Alternatives rejected.** Long-lived JWTs with a denylist (needs the same table
plus a check on every request); server-side sessions (gives up statelessness for
a mobile client). Migration `340e256514b7`.

---

### 2026-06-20 — Google Sign-In, and email verification effectively via Google

**Context.** Verifying email addresses needed an email provider and a flow;
high-value actions needed *some* verification signal.
**Decision.** `POST /auth/google` with manual `aud` and `iss` checks after
`verify_oauth2_token`. Three branches: sign in, link to an existing email account
(**only if Google reports the address verified**), create new.
`require_verified_email` gates nine write endpoints.
**Consequences.** Dual-method accounts exist and can delete themselves with
either credential. All three client ids empty means Google sign-in is silently
off. The server later became the only place that knows whether a token means
signup or sign-in, which forced consent-on-demand. `/auth/register` does email a
verification link, so `require_verified_email`'s "only via Google" message is now
stale.
**Alternatives rejected.** Email-only verification (a provider dependency on the
critical signup path); trusting the Google token's `aud` without checking it
(accepts tokens minted for any app). Migration `0a2c5b2f918e`.

---

### 2026-07-27 — Image moderation as a two-tier, fail-open pipeline

**Context.** User-uploaded cover images and avatars are served publicly.
**Decision.** AWS Rekognition `DetectModerationLabels` inside
`process_and_store`, **after** Pillow processing and **before** storage. Hard
reject (≥80) → 422 and nothing stored; soft flag (≥50) → stored, logged,
operator emailed; **AWS error → stored as `pending` (fail-open)**. A client-side
pre-check is a UX/cost optimisation only.
**Consequences.** An AWS outage cannot block every upload; the `pending` status is
what the sweep's post-outage re-check looks for — though the re-check only
re-scans *text*, so a fail-open image is never looked at again. Off by default, so
a missing credential degrades to "stored unscanned". The client pre-check is still
inert on both platforms because neither model file is vendored.
**Alternatives rejected.** Fail-closed (an AWS outage becomes an app outage);
scanning before Pillow (EXIF and resizing would change the bytes that were
scanned); client-side only (trivially bypassed). Migration `b858424a1092`.

---

### 2026-07-28 — Moderation is soft state, and moderator writes preserve the ETag

**Context.** Hiding or removing content had to be reversible and appealable, and
`updated_at` was already the concurrency ETag.
**Decision.** `hidden_at` (owner-only) and `deleted_at` (invisible to everyone,
owner included) as soft state on `itineraries`. **`admin_service.set_preserving_etag`
is the only way to write an itinerary's moderation state from outside the owner's
request.**
**Consequences.** 13 call sites go through it. Without it a moderator action would
412 the author's open editor over a change they cannot see. An admin "delete" is a
soft delete while the *owner's* `DELETE /itineraries/{id}` is a hard delete — two
operations behind one word. Ratings and profiles have no `hidden_at`, so
`moderation_log` is the only record of *when*, which is why `_last_takedown_at` is
a correlated subquery.
**Alternatives rejected.** Hard deletion (destroys evidence and makes appeals
impossible); a separate moderation table (the visibility check would need a join
on every read). Migration `e190f1dcbf2c`.

---

### 2026-07-30 — Text moderation with our own policy, not the provider's verdict

**Context.** Provider APIs return a boolean `flagged` plus per-category scores.
The boolean encodes someone else's thresholds.
**Decision.** `moderation_policy.py` holds 13 categories with Ntripi's own
`(review, reject)` thresholds; **the provider's `flagged` is ignored**.
`POLICY_VERSION` is part of the cache key. Provider chain `openai → local →
pending`, selected by config. `moderate_or_422` is called from the endpoint
**body**, never as a `Depends`. `text_moderation_cache` stores no raw text and no
user reference; `text_moderation_decisions` is both the audit trail and the
moderator queue.
**Consequences.** Swapping providers is a config change. Bumping a threshold
requires bumping `POLICY_VERSION` or stale verdicts survive. Four text fields are
**deliberately not** moderated — report notes, appeal reasons, bug-report
messages, admin action reasons — because a 422 there would block someone reporting
hate speech who quotes it. Stop, annotation and leg text rolls up to the parent
itinerary, because hiding is itinerary-level.
**Alternatives rejected.** Using the provider's boolean (a threshold change on
their side silently changes our policy); a `Depends` (spends a paid call before
the 412); per-fragment moderation status (no read path). Migration
`4bdacee286ac`, one commit with six migrations (`8365e10`).

---

### 2026-07-30 — Blocking cuts visibility in both directions

**Context.** A one-sided block would let the blocked user keep reading someone who
asked to be left alone.
**Decision.** `is_blocked_either_way` is the predicate, consulted inside
`can_view_itinerary` and as a SQL `NOT IN` in `public_listing_criteria`. **A
blocked profile 404s identically to a deleted one.** Blocking severs follows both
ways; unblocking does not restore them. Both FKs CASCADE, because a block is a
preference, not evidence.
**Consequences.** Twelve surfaces consult it. Search and the follow lists filter
**in the query**, not after, or `limit`/`offset` would silently shrink pages. You
can block someone who has already blocked you, which needs a bare `db.get` rather
than the blocked-aware helper.
**Alternatives rejected.** One-directional blocking (the failure above); a
distinct 403 for blocked (tells the blocked user the account exists). Migration
`9dcbd2b7d34c`.

---

### 2026-07-30 — The client text filter is a hand-written list; `safe_text` is removed

**Context.** Lifted from the commit body of `e56c9be`, which is the fullest
written rationale in the repository:

> `ModerationHint` built `safe_text`'s ~21,700-entry trie synchronously on the UI
> isolate the first time any compose screen opened. Its Aho-Corasick preprocessing
> dequeues with `List.removeAt(0)` — O(n) per node, so **O(n²)** over the
> ~150k-node trie: **2,889 ms on a desktop JIT, tens of seconds on a phone**. That
> is the "Ntripi isn't responding" dialog users hit while editing an annotation…
> Search was never implicated (0.05 ms/call), so the per-keystroke debounce was not
> the problem.
>
> Precision was the second reason to drop it, not just cost. Those lists are
> scraped, not curated: *beach, queue, fish, after, el, ce, eg* and the bare pronoun
> *i* are all in them, so **roughly a third of ordinary travel prose flagged**. No
> minimum-length cutoff fixes that — *beach* is five letters — and a hint that fires
> on "Beautiful beach" teaches people to ignore every hint.

**Decision.** A short hand-written list we own: pure Dart, no assets, no plugin,
no isolate, hash-set lookups over leet-normalised tokens. **Whole-token matching**,
so Scunthorpe and Cockermouth are structurally safe. Stretched spellings (`fuuck`)
collapse onto the list, **but only for tokens that actually stutter, or squeezing
would put *Niger* onto a slur**. Slurs with common innocent readings in the app's
own six languages are **omitted on purpose** (`spic, chink, pedo, negro, con,
cono`) — the backend classifier reads context and catches those.
**Consequences.** `looksOffensive` keeps its signature, so the six call sites are
untouched; `warmUpTextPrecheck` is gone. **The never-block contract is
unchanged**: any failure still reads as clean, the submit control stays enabled,
and text is never mutated. 42 new tests, 26 of them benign prose across all six
languages plus the documented place-name traps — **they exercise the real list for
the first time**, because the old implementation always degraded to "clean" under
`flutter test` when its assets could not load. The filter is never applied to
titles or place names.
**Alternatives rejected.** Keeping `safe_text` with a background isolate (does not
fix the ~⅓ false-positive rate); a minimum token length (*beach* is five letters);
blocking submission on a client verdict (the backend is the authority).

---

### 2026-08-03 — CSAM detection at the Cloudflare edge, serve-time, with a stated accepted risk

**Context.** Known-CSAM hash matching needs a corpus no application can hold.
**Decision.** Cloudflare's CSAM Scanning Tool, enabled by a dashboard toggle with
**no app config**, scanning at **serve time** on R2 behind a proxied custom
domain. The app's whole job is the response: `admin_service.csam_takedown`, driven
from `/admin/legal`.
**Consequences.** The order inside the takedown is the evidence — **hash the
object before deleting it**, then clear the URL, deactivate the account, write one
operator `ban` row, escalate against the *user*, commit, and only then delete the
object. `rejected_csam` rows are exempt from the 90-day purge and must never be
touched. `parse_storage_key` refuses anything it does not recognise, because
guessing could suspend an unrelated account. The uploader is never emailed. A
`pub-*.r2.dev` `R2_PUBLIC_URL` silently disables the entire layer.
**Accepted risk, stated in writing** (`media_pipeline_spec.md:23`): *"because
detection is serve-time and the digest is daily, a matched image will have been
stored and possibly served before you learn of it. Upload-time hash matching
(PhotoDNA) is the only thing that prevents that, and it was consciously traded
away for operational simplicity."*
**Alternatives rejected.** PhotoDNA at upload time — *"needs a Microsoft
application and NCMEC ESP paperwork that a solo operator cannot sustain"*;
detection of *new, unknown* CSAM — out of scope, *"services that attempt it exist
and need their own legal review"*; automated reporting to authorities, rejected in
the model file itself: *"the requirement is that this category cannot be silently
closed, not that the app files reports on its own."* Migration `7f6e757d452c`.

#### The six stances awaiting counsel sign-off

Reproduced from `csam_response_runbook.md` §6 **with the sign-off column intact**
— all six are still unticked.

| Decision | Stance | Rationale | Signed off |
|---|---|---|---|
| Detection timing | **Serve-time only** (Cloudflare); no upload-time hash matching | PhotoDNA needs a Microsoft application and NCMEC ESP paperwork a solo operator cannot sustain. **Accepted risk: matched content is stored and may be served before detection.** | ☐ |
| Notification latency | **Daily digest accepted** | Cloudflare's cadence; not configurable. The filing clock starts at the notice, not the upload. | ☐ |
| Uploader notification | **None** — no email, no distinct error | A notice confirms what was detected to the person who uploaded it | ☐ |
| Reporting to authorities | **Manual only** | Neither Ntripi nor Cloudflare files automatically; the requirement is that these cannot be silently closed | ☐ |
| Account suspension | **Immediate, on the operator's takedown** | A hash match does not guess; reversible via the standard unban if ever disputed | ☐ |
| Evidence retention | **Indefinite** for `rejected_csam` rows | Preservation duties; the object is deleted, so nothing else survives | ☐ |

---

### 2026-08-06 — Notifications are structured references, never rendered text

**Context.** Six locales, and display names that moderation may later hide.
**Decision.** A row is `(type, subtype, actor_id, entity_type, entity_id)`; the
sentence is built client-side from `AppLocalizations`. **`notification_service.notify`
is the only writer**, and it does `db.add()` and nothing else — no commit, no
flush — so a notification lands in the same transaction as the event that caused
it.
**Consequences.** Its three suppression rules (self, muted, blocked) hold only
because there is one door. Preferences are three booleans on `users` checked at
**write** time, so a muted type writes no row at all. Adding a type alters the
`type` CHECK regardless, which is why a separate preferences table would buy
nothing. `moderation_action` carries the action in `subtype` and **no actor** —
naming the reporter would out them.
**Alternatives rejected.** Storing the rendered sentence (wrong in five of six
locales, freezes a name moderation may hide, needs a backfill to reword); a
preferences table; committing inside `notify()` (would take the caller's write
with it). Migration `8cd9a4fe3396`.

---

### 2026-08-08 — A 16+ age gate, with the arithmetic in one place

**Context.** The ToS had asserted a minimum age for a release before anything
asked for one.
**Decision.** `users.date_of_birth` + `dob_source`, enforced on all three write
paths. `age_service.py` is the single source of truth — `MINIMUM_AGE = 16`,
`MAX_PLAUSIBLE_AGE = 120`. **Shape errors are 422; policy refusals are 400
`underage`.** The check runs **before** `moderate_or_422`.
**Consequences.** 16 clears GDPR Art. 8 in every member state, so no
parental-consent path is ever needed — but it does not imply contract capacity,
which is why the ToS keeps a separate age-of-majority clause. The comparison is a
tuple compare, which is what makes a 29 February birth turn 16 on 1 March, and
`DateOfBirthField.isOldEnough` mirrors it. `date_of_birth` is nullable and **never
backfilled**; existing accounts declare at the re-acceptance gate, and an existing
date is never overwritten.
**Alternatives rejected.** A checkbox ("I am over 16") — not evidence; storing a
derived age (goes stale daily); backfilling a plausible date (fakes the evidence
the gate exists to produce); 13+ (would need a parental-consent path in most of
the EU). Migration `2ddec1197cc9`.

---

### 2026-08-08 — Google supplies the birthday when it can; the consent sheet is the fallback

**Context.** Google ID tokens carry **no birthdate claim**.
**Decision.** Read it from the People API with the `user.birthday.read` sensitive
scope and an access token, **requested only after the server answers
`tos_required`** — that 400 is the only signal the token means signup rather than
sign-in. `dob_source` records which source stood behind the account. The consent
sheet is the guaranteed fallback.
**Consequences.** `fetch_birthdate` must verify `resourceName == "people/{sub}"`,
because the access token is a separate credential and without the check a caller
could pair their own ID token with an access token minted for a different Google
account. A birthday with no `year` is unusable. The lookup never raises. **This
half is blocked on OAuth verification** — a 100-test-user cap until it clears — and
the sheet fallback is what lets everything else ship.
**Alternatives rejected.** Prompting before the Google picker (re-prompts every
returning user at every sign-in); trusting the client's People API read (it is a
prefill hint; the server re-reads).

---

### 2026-08-13 — Editors, and an edit lock identified by a rotating token

**Context.** An itinerary needed more than one author, and two people writing at
once had nothing stopping them.
**Decision.** `itinerary_editors` mirrors the allowlist. **`can_edit_itinerary()`
delegates to `can_view_itinerary()` first**, so edit rights are re-derived, not
stored. `itinerary_edit_locks.itinerary_id` is the **PRIMARY KEY**, so "at most
one holder" is a database invariant. **The claim is identified by a rotating
opaque token, never by `user_id`** — every takeover mints a fresh one, and that
rotation is the entire mechanism behind "the displaced device cannot save". One
guard, `require_edit_access`, re-checks permission + lock + `If-Match` on all 17
mutating endpoints, and `test_edit_guard_coverage.py` proves the coverage
structurally.
**Consequences.** A block, a visibility change, a moderator hide, a banned owner
or a soft delete revokes editing the moment it revokes viewing — no rows to clean
up, no sweep. **The lock check sits above the `If-Match` check**, because after a
takeover the ETag has usually moved too and 412 would send the user to reload into
a screen they still cannot save from. 409 and 423 must never be collapsed. There
is no `expires_at` column, so raising the TTL affects existing claims. A heartbeat
must never touch `updated_at`. A new mutating endpoint fails the suite until
somebody classifies it.
**Alternatives rejected.** Identifying the claim by `user_id` (cannot tell a
displaced device from the same person on a new one); checking only at acquire time
(the whole point is the re-check); a second access ladder for editing (edit rights
would outlive view rights); letting editors grant edit rights (the grant is the
owner's trust decision and does not carry the power to delegate it). Migrations
`192d73531acf`, `393a6b3179ce`.

---

### 2026-08-13 — FCM push as a latency improvement, dispatched after commit

**Context.** A 60-second poll was the only delivery channel; a hot restart was the
only way to see a new row.
**Decision.** FCM HTTP v1 with **zero new backend dependencies** — `google-auth`
(already installed for Sign-In) mints the bearer, so `push_service.py` is a
`requests.post`. **Dispatched from an `after_commit` listener, never from inside
`notify()`**: `notify()` appends a frozen `PendingPush` snapshot to
`Session.info`, and an `after_soft_rollback` listener clears the queue. The
dispatcher uses its **own** session. It **fails open**.
**Consequences.** **Push is never load-bearing** — `NotificationPoller` stays,
and stays unconditional, because gating it on push would inherit push's failure
modes. Suppression is inherited from `notify()`, so there is no fourth preference
column: the OS permission is the master switch. `device_tokens.token` is UNIQUE
**globally, not per user**, because FCM reassigns a token across accounts — so
registering moves the row. Sign-out must delete the token before discarding the
access token. Dead tokens are pruned only on `UNREGISTERED` / `INVALID_ARGUMENT`.
Locale lives on the device, not the user. Web push is deliberately excluded.
**Alternatives rejected.** Sending inside `notify()` (would push for transactions
that roll back — and a push cannot be un-sent); the Firebase Admin SDK (a new
dependency for one HTTP call); committing on the request session inside
`after_commit` (re-enters the listener that called it); holding an ORM row in the
snapshot (expired attributes lazy-load on a session between transactions).
Migration `dfb62a1759d8`.

---

### 2026-08-15 — The Edit Itinerary screen reopens to editors, minus the owner-only controls

**Context.** Two days after editors shipped, `1d3cf4a` had restricted the whole
"Edit Itinerary" screen to the owner. That also refused the title, currency and
recommended period, which an editor may already change.
**Decision.** Reverses `1d3cf4a` the same day. **The screen opens on `mayEdit`;
each owner-only control inside gates on `isOwner`** and is hidden rather than
offered and left to 403. An editor's branch of the danger zone is
`EditorAccessRow` — removing themselves, the way out that *is* theirs.
**Consequences.** `visibility` must be **absent** from the PATCH body for a
non-owner, because the server refuses the key's presence, so an explicit null 403s
exactly as a real value does. `_CannotEditNotice` fires **only on evidence** — a
still-loading profile falls through to the form, or a cold deep link would lock the
owner out of their own trip. Regression test:
`test/widgets/itinerary_edit_form_access_test.dart`.
**Alternatives rejected.** Keeping the screen owner-only (refuses three fields an
editor may change); showing owner-only controls and letting them 403 (teaches the
user the app is broken). Commits `1d3cf4a` then `4ccbf4d`, `0db613a`.

---

### 2026-08-16 — `shared-with-me` as a durable surface, reusing the feed schema

**Context.** The grant notification could not be the only way back to a shared
trip: a `restricted` itinerary is in no feed and no search, and notifications are
purged at 90 days read / 365 hard.
**Decision.** `GET /itineraries/shared-with-me`, reusing `ItineraryFeedItem` and
`_to_feed_item`. **`ItinerarySummary` gains no `can_edit`** — that would churn the
JSON key order of `/me`, `/saved` and `/feed` for a flag only this list needs.
**Consequences.** It is the only query that reads `itinerary_editors` by its
trailing column, which is what `ix_itinerary_editors_user` was created for. Two
filters: `public_listing_criteria` in SQL, then `can_edit_itinerary` **per row**,
because the SQL half does not cover the visibility ladder. Mine and Shared are
disjoint by construction. On the client `sharedWithMeProvider` stays a **separate**
provider, so a dead `shared-with-me` cannot blank the Mine segment, and the scope
selector lives **inside** the list so a failure cannot strand the user on a scope
they cannot leave. A row's **provenance**, not an id comparison, gates the
owner-only chrome.
**Alternatives rejected.** Adding `can_edit` to `ItinerarySummary` (reorders three
existing payloads); a new schema (summary + owner is exactly
`ItineraryFeedItem`); one merged provider (one dead endpoint blanks both
segments). Commit `62608f2`.

---

### 2026-08-30 — Follow counters become atomic SQL; hot-path FKs get indexes

**Context.** `bump_follow_counters` read the count into a Python int and wrote it
back. Under READ COMMITTED two people following one account in the same moment
both read N and both write N+1, and **the count drifts low forever**. Separately,
several FK columns had no index — including the trailing halves of two composite
primary keys.
**Decision.** The arithmetic moves **into the `UPDATE` statement**, clamped with a
`case()` expression, `synchronize_session=False`, then `db.expire()` on the
attribute. `bump_follow_counters` becomes **the only** way to touch either
counter. Index the hot-path FKs with `CREATE INDEX CONCURRENTLY` in an
`autocommit_block()`, and drop the redundant `ix_notifications_user_id` (a prefix
of `ix_notifications_user_created`).
**Consequences.** `GREATEST` cannot be used — the suite runs on SQLite. The one
permitted exception is `delete_my_account`'s bulk UPDATEs.
`ix_saved_itineraries_user_id` and `ix_itinerary_allowed_users_user_id` exist
because a trailing composite-PK column cannot serve `WHERE user_id = ?`. The eight
remaining unindexed FKs are all `SET NULL` audit columns with no hot read and are
deliberately left alone. `a681984a1a04` is now the reference implementation for
concurrent index creation, at the cost of the migration's atomicity.
**Alternatives rejected.** `SELECT … FOR UPDATE` then write (serialises every
follow); a periodic recount job (the count is wrong in the meantime, and this is a
profile's headline number); a plain `CREATE INDEX` (holds a write lock through the
deploy). Commit `2e8e5c6`, migration `a681984a1a04`.

---

### undated — Single-operator admin model

**Context.** One person operates the service.
**Decision.** `users.is_admin` is set **manually via SQL**. There is no API or UI
to promote a user. `/admin` sits behind HTTP Basic *and* a per-admin session whose
cookie carries `scope="admin"`, and **404s entirely when the Basic credentials are
unset**.
**Consequences.** No privilege-escalation surface exists, because there is no
grant path. Adding a second operator means a SQL statement and, at that point,
probably a provisioning UI. The 404-when-unconfigured pattern was reused for the
sweep endpoint, the Jira button and push.
**Alternatives rejected.** A role table (nothing to model yet); 403 instead of 404
when unconfigured (advertises that a dashboard exists). Undated because the
`is_admin` column and the dashboard arrived in different commits and the
single-operator reasoning appears only as a code comment.

---

### undated — No automated reporting to authorities

**Context.** CSAM and other legal escalations.
**Decision.** Stated in `models/legal_escalation.py:13`: *"Deliberately NOT
implemented here: automated reporting to authorities. The requirement is that this
category cannot be silently closed, not that the app files reports on its own."*
**Consequences.** `legal_escalations` gets its own `/admin/legal` lane, the routine
dismiss action refuses escalated reports, and closing one demands a written note.
The CyberTipline filing (24h from a Cloudflare notice), removal and preservation
are all manual and documented in
`../social_api/docs/csam_response_runbook.md`.
**Alternatives rejected.** Automated filing (a false positive filed with law
enforcement is not reversible, and an ESP registration carries duties a solo
operator cannot sustain). Undated — the stance predates the file that records it.

---

### 2026-09-26 — An author's edit can no longer lift a takedown

**Context.** `PATCH /users/me` and the rating upsert *assigned* the text-moderation
verdict to `moderation_status` rather than escalating it, on the reasoning that
rewritten profile or review text is new content (recorded in
[text-moderation.md](features/text-moderation.md) and
[accounts-and-profiles.md](features/accounts-and-profiles.md) as the deliberate
exception to escalate-only). Two holes followed. With the default
`TEXT_MODERATION_PROVIDER=disabled` the verdict is always `approved` and nothing
is scanned, so any edit un-hid a profile or review a moderator or a report
threshold had taken down. And the profile scan covers only the submitted fields,
so renaming alone brought back a still-offensive bio.
**Decision.** Both paths now call `apply_author_edit_status`
(`text_moderation_service.py`). A rewrite that was rescanned whole still
*replaces* an automated flag. It only escalates when the record is under a
takedown (`hidden` / `rejected`) or when the rewrite was partial (a stored
`display_name` or `bio` left out of the request).
**Consequences.** A takedown is lifted only by a moderator or an appeal — the path
the help centre already describes. An author who cleans up a *flagged* (not
hidden) review or full profile still clears the flag. A partial profile edit on a
flagged profile leaves it flagged until a moderator reviews it.
**Alternatives rejected.** Escalate-only for every author edit (a cleaned-up
flagged bio would stay flagged forever); rescanning the stored-but-unsent field on
every profile edit (spends a paid provider call on text nobody changed, and could
422 a rename over an old bio judged under an older policy).

---

### 2026-09-26 — The rating aggregate does not move the itinerary's ETag

**Context.** `rating_count` / `rating_avg` live on the `itineraries` row, and
`updated_at` has `onupdate=now()` and *is* the `If-Match` concurrency token.
`recalculate_rating` assigned the two columns directly, so every stranger's
rating — and every moderator hide or restore of a review — bumped `updated_at`
and 412'd the owner's open editor with "itinerary modified, please reload" over a
change they could not see.
**Decision.** `recalculate_rating` writes through
`admin_service.set_preserving_etag`, the same helper moderation writes use.
Imported lazily, because `admin_service` imports `itinerary_access`.
**Consequences.** The detail GET's cache validator is that same `updated_at`, so
a viewer holding a *cached* detail can see a stale average until the next content
edit or a pull-to-refresh (which uses `CachePolicy.refresh` and skips the
conditional GET). The rater's own post-submit refresh is forced, so they always
see their rating counted, and the ratings page carries a body-hash ETag and is
always fresh. Moderation writes have accepted the identical trade-off since they
started preserving the ETag.
**Alternatives rejected.** Keeping the bump (the owner's editor keeps 412ing on
every rating); a separate cache validator on the detail GET (changes the header
the Flutter client and the test helpers echo back as `If-Match`); moving the
aggregates to their own table (a migration and a join on every feed read, for a
number that tolerates being a minute stale).

---

### 2026-09-28 — The detail GET's cache validator carries a body hash

Supersedes the *Consequences* and the rejected "separate cache validator" of
[2026-09-26 — The rating aggregate does not move the itinerary's ETag](#2026-09-26--the-rating-aggregate-does-not-move-the-itinerarys-etag).

**Context.** `GET /itineraries/{id}` set `ETag = updated_at`, and `ETagMiddleware`
answered `If-None-Match` with 304 against it. The rating aggregate, moderator
hides and the owner's hidden state all change the body without moving
`updated_at` (by design, so the owner's editor does not 412), so every device
that had the detail cached kept the old average and the old hidden flag until
somebody edited the content. The earlier entry accepted this as "a minute stale";
in practice it was stale until the next content edit, indefinitely. The Flutter
client builds `If-Match` from the body's `updated_at` (`itinerary.dart`), not from
the header, so the header was never the client's concurrency token.
**Decision.** When an endpoint sets its own ETag, the middleware emits
`"<endpoint token>;<sha256[:16] of body>"` and compares `If-None-Match` against
that composite. `require_etag` reads only the part before `;`
(`_concurrency_token`), so a consumer that echoes the GET header as `If-Match` —
the test helpers do — keeps working.
**Consequences.** A 304 now means the body really is unchanged, and the detail
keeps its bandwidth saving. Tests that asserted the GET header survives a
moderation action compare the concurrency half (`conftest.concurrency_part`)
instead.
**Alternatives rejected.** Never 304-ing the detail (correct, but ships the
largest payload in the app on every open); bumping `updated_at` on ratings and
hides (412s the owner — the reason the earlier entry exists).

---

### 2026-09-28 — If-Match is compared as an instant, not a string

**Context.** `_normalize_etag` collapsed quotes, `W/` and `Z` ↔ `+00:00`, then
byte-compared. Dart's `toIso8601String()` drops the sub-millisecond digits when
they are zero (`.123Z`) where Python writes `.123000+00:00`, so about one save in
a thousand produced an itinerary the app could never save again — a reload
returns the same `updated_at`.
**Decision.** `require_etag` parses both sides with `datetime.fromisoformat` and
compares instants, falling back to the normalised string for anything that is not
a datetime. The middleware keeps its string compare (its values are hashes).
**Alternatives rejected.** Normalising the fractional digits by string surgery
(one more format edge each time a client changes its serializer).

---

### 2026-09-28 — The client IP comes from CF-Connecting-IP

**Context.** `ProxyHeadersMiddleware(trusted_hosts="*")` makes uvicorn 0.41 take
the **leftmost** `X-Forwarded-For` entry. Cloudflare appends to a client-supplied
header rather than replacing it, so any caller could name its own IP and walk
past every per-IP rate limit (login, register, forgot-password, reports,
appeals).
**Decision.** `ClientIPHeaderMiddleware`, just inside ProxyHeaders, sets
`request.client` from `CLIENT_IP_HEADER` (default `cf-connecting-ip`), which
Cloudflare overwrites. Absent or unparseable, the X-Forwarded-For answer stands
(local dev, a non-Cloudflare deploy). ProxyHeaders stays for `X-Forwarded-Proto`.
**Consequences.** Behind the proxied zone the key every limit uses is the real
client. A request that reaches Railway directly, bypassing Cloudflare, can still
forge either header — closing that is edge configuration, not app code.
**Alternatives rejected.** A trusted-proxy CIDR list for uvicorn (standards-based,
but a wrong or stale list puts every user behind one IP and one rate-limit
bucket, and the Railway ranges are not published as a contract).

---

### 2026-09-28 — Linking Google to an unverified password account drops the password

**Context.** Registration needs no email verification, so anyone could register a
password on someone else's address. When the real owner later signed in with
Google, step 2 of `google_sign_in` linked the account and marked it verified,
keeping the squatter's password and sessions — a pre-account takeover.
**Decision.** Linking onto an account whose email was never verified clears
`password_hash`, revokes every refresh token and records
`unverified_password_dropped_on_google_link`. A verified account keeps both
methods, as before.
**Consequences.** A legitimate user who registered with a password but never
verified, then signs in with Google, loses the password and their other
sessions; forgot-password (now deliverable, the email being verified) sets a new
one.
**Alternatives rejected.** Refusing to link (strands the real owner behind an
account they cannot prove is theirs); keeping the password but demanding it on
first Google sign-in (the squatter knows it; the owner does not).

---

### 2026-09-28 — The HTTP cache is partitioned by account

**Context.** The Hive-backed Dio cache (7-day `maxStale`) keyed entries by URL
alone, and was never cleaned. `/users/me`, `/itineraries/me` and
`/notifications` are the same URL for everybody, and the interceptor's offline
branch always falls back to the cache, so the next person to sign in on a device
was served the previous account's profile (email, date of birth), private trips
and notifications. Sign-out also reset only seven of the ~20 keep-alive
user-scoped providers, and a session ending on the interceptor's forced path
(expiry, suspension) reset none.
**Decision.** Cache keys are `<JWT sub>:<url key>` (`core/api/cache_key.dart`),
the account stamped by AuthInterceptor on every request — from the expired token
too, so offline still finds the account's own entries. Sign-out also
`clean()`s the store. One list of user-scoped providers is reset on sign-in and
on sign-out, and `hasSessionProvider` re-reads storage whenever tokens are wiped
(`sessionEnded`).
**Alternatives rejected.** Cleaning the store only on sign-out (misses the forced
paths); cleaning on every sign-in (throws away the offline warm cache when the
same person signs back in after an expiry).

---

### 2026-09-28 — Hiding or restoring content settles every pending report on it

**Context.** `auto_hide` resolved only the report that tipped the threshold, and
un-hide, restore and a granted appeal resolved none. The rest stayed `pending`,
so ~20h later the SLA sweep hid content a moderator or an appeal had just
restored.
**Decision.** Any takedown resolves every pending report on the target
(`auto_hidden` for the system, `content_hidden` / `content_removed` for an
operator); a reversal resolves the rest as `dismissed`. A target under an open
legal escalation keeps its reports — they close from the Legal lane, with a note.
**Consequences.** A report filed after a restore is new evidence and still acts.

---

### 2026-09-28 — Account deletion erases the account's images, except evidence

**Context.** `DELETE /users/me` cascaded the rows but left every stored image
(avatar, profile cover, itinerary covers) publicly reachable at its stable URL.
**Decision.** After the commit, best-effort, the avatar, the profile cover and
the cover of every owned itinerary are deleted from storage — except while the
account is under an open legal escalation (nothing is deleted), and except the
cover of any itinerary that was taken down or is escalated in its own right.
**Alternatives rejected.** Deleting everything (destroys what the CSAM runbook
requires preserved); leaving the objects (the "permanent deletion" the privacy
policy describes would not be true).

---

### 2026-10-01 — The shell consumes the keyboard inset; nothing below it compensates

**Context.** The bottom-nav shell rebuilt its tabs' MediaQuery with
`MediaQuery.removePadding(context: context, …)` from its own build context —
above its Scaffold — which put back the keyboard inset that Scaffold had just
consumed (f871566, 2026-05-11). Every tab saw the keyboard twice and lifted a
second time, so e3404d2 set `resizeToAvoidBottomInset: false` on 18 screens and
c86c105 wrote the comment "inner screens use false … without double-counting".
When 3a822fb moved the itinerary routes to the root navigator, those screens
kept `false` and lost keyboard avoidance entirely: the stop form's notes, the
description editor and the annotation editor were typed blind. Sheets failed
the same way: rate, report and leg padded by the inset *inside* their scroll
view under a 0.7 height cap, which cancels it.
**Decision.** One contract, in `shared/widgets/keyboard_avoidance.dart`, held by
`test/keyboard_avoidance_guard_test.dart`. Whoever lifts content above the
keyboard removes the inset from what it passes down (the shell now calls
`.removeViewInsets`). Screens keep the default `resizeToAvoidBottomInset` — only
the map picker and the crop overlay may not, each with a stated reason. Sheets
lift through `KeyboardSafeSheetBody` / `AboveKeyboard`. A field and the text that
belongs to it are revealed as one unit by `RevealTogether`, a render object that
widens the field's own `showOnScreen` request in transit — the move the
framework's pinned headers make — and stands aside when the group is taller
than the viewport, so a long note keeps its caret.
**Consequences.** All 19 compensating flags are gone. A screen pushed on both
navigators (the markdown editor: the description from detail, the bio from the
profile tab) is right on both. A sheet opened from a tab no longer pads for a
keyboard the shell has already accounted for.
**Alternatives rejected.** A `scrollPadding` number per field (tuned for one
screen, explains nothing, drifts). Flipping flags per screen (cannot serve a
screen pushed on two navigators). A global focus listener calling
`Scrollable.ensureVisible` (races EditableText's own reveal — the last request
wins). A keyboard package (a new dependency, and the shell would still leak).

---

### 2026-10-07 — Production runs Python 3.14, the development interpreter

**Context.** The runtime image was `python:3.11-slim` while the development venv
ran 3.14, so the suite never ran on the interpreter that shipped. Translating
user content needs source-language detection with `lingua-language-detector`:
its current release (2.2.0) requires Python ≥3.12, and the last release that
supports 3.11 (2.1.1) has no 3.14 wheel — no single version served both. A 3.14
image could not install `alt-profanity-check==1.6.1` either: it pins
scikit-learn 1.6.1, which has no cp314 wheel, which is also why the moderation
fallback had never been installed in the dev venv at all.
**Decision.** The runtime stage moves to `python:3.14-slim`, and
`alt-profanity-check` to 1.9.1 (it pins scikit-learn 1.9.1, which ships cp314
wheels).
**Consequences.** Every requirement and every transitive dependency resolves to a
prebuilt manylinux x86_64 wheel for cp314 — nothing compiles at build time. The
local moderation classifier now actually runs in development; before, every
fallback attempt there raised and fell through to `pending`. The suite passes
both on the dev venv and on a venv holding exactly what the image resolves
(1898 passed, 4 skipped). Transitive dependencies are still unpinned — see
[backlog.md](backlog.md#idea--transitive-dependencies-resolve-fresh-on-every-build).
**Alternatives rejected.** Staying on 3.11 with another detector (py3langid,
fast-langdetect — weaker than lingua's high-accuracy mode on short titles).
Pinning lingua 2.1.1 (no 3.14 wheel, so the dev venv could not install it).
`python:3.13-slim` (works, but keeps development and production on different
interpreters, the gap that hid this in the first place).

---

### 2026-10-07 — Source language is detected at save time; translations cascade from their itinerary

**Context.** Translating user content needs two things before any provider is
called: knowing which language a text is in (to decide whether a reader is
offered "See translation" without asking anyone), and a cache whose rows can
never outlive the text they were made from — a translation of a deleted review
is a copy of deleted personal data. Six tables hold translatable prose, so the
cache key has to be polymorphic, and a polymorphic key cannot carry a foreign
key. Meanwhile a stop delete removes its annotations and its segments' legs
through database cascades the application never sees.
**Decision.** Language is detected locally with `lingua-language-detector`
(all 75 languages, high-accuracy mode, minimum relative distance 0.1) on every
write and stored as `source_lang`; an undetected text stays NULL. Translations
live in `content_translations`, keyed by `(content_type, content_id, field,
target_lang, source_hash)` — the source text itself is never stored. Every row
also carries `itinerary_id` as a real FK with `ON DELETE CASCADE`, because every
translatable row belongs to exactly one itinerary. An edit calls
`sync_translations`, which deletes the translations whose hash its new text no
longer matches; a delete below the itinerary calls
`purge_orphans(db, itinerary_id)`, which deletes whatever lost its content row.
**Consequences.** Deleting a trip or an account removes its translations in the
database, so no future delete path can forget them. The seven delete paths below
the itinerary make one call each and never need to know what cascaded. Stale
translations are unreachable even before they are deleted, because lookups match
the current hash. Detection costs about 66 MB of resident memory with every
language loaded (measured on macOS against a 14-language sample) and a few
milliseconds per save. On short trip titles about one confident answer in forty
is wrong and a quarter are left undetected, which errs toward offering the
button.
**Alternatives rejected.** Explicit per-type deletes on every path (a stop
delete would have to enumerate what the database cascaded, and the next new
delete path would forget). Detecting through the translation provider on first
request (every reader would pay a request just to learn whether to show a
button). A minimum relative distance of 0.0 (about one wrong answer in ten on
short titles). A detection list limited to the six app languages (other
languages get forced onto a neighbour, and a wrong match hides the button).

---

### 2026-10-07 — User content is translated on the server: OpenAI first, Azure as fallback

**Context.** Readers need trips and reviews in their own language on iOS,
Android and web. A translation of a public trip is read by many people, so
whatever produces it should do so once, the same way for everyone, and be
cheap. User text can also carry instructions aimed at whatever model reads it.
**Decision.** Translation runs on the backend behind a `Translator` protocol
(`services/translation_providers.py`), with engines and their order chosen by
`TRANSLATION_PROVIDERS`. The primary engine is a small OpenAI model
(`TRANSLATION_MODEL`, default `gpt-6-luna` — OpenAI's model for cost-sensitive,
high-volume work at the time) called through the Responses API with a strict
JSON schema built from the batch, `store: false`, and the texts under opaque
keys; the fallback is Azure AI Translator v3 on its free tier. Every output must
pass `translation_validation` — and, with text moderation on, the moderation
policy — before it counts; a field that fails moves to the next engine, and a
field every engine fails is answered as unavailable and never cached.
**Consequences.** Swapping or adding an engine (DeepL) is a class and a config
value. A model coaxed by a hidden instruction into producing something else
fails the checks and falls through to Azure, which does not follow
instructions. Output moderation fails closed: during a classifier outage
nothing new is translated, and readers keep the original. `OPENAI_API_KEY` is
shared with moderation, and both now call OpenAI through
`services/openai_http.py`.
**Alternatives rejected.** On-device translation (ML Kit) — unavailable on
Flutter web and different output per device. On-device language models — the
same, plus their size. DeepL, for now — Azure already covers the fallback role, and the
interface makes DeepL one class and a config value whenever it is wanted.
Translating everything automatically on write — most of it would never be read
in most languages. Trusting the model's output unchecked — it is served to
every later reader from the cache.

---

### 2026-10-07 — Translation cost is capped in Postgres; public titles are translated ahead of time

**Context.** Every translation that misses the cache is a paid call, and a
reader or a script could ask for thousands. The feed shows many titles at once,
and translating each card on demand would cost a request per card.
**Decision.** Two caps, both counted by one atomic conditional upsert
(`INSERT … ON CONFLICT DO UPDATE … WHERE total + n <= limit RETURNING`): fields
per reader per clock hour, counting only cache misses, and characters per
engine per UTC day. A refused reservation counts nothing; an engine past its
budget, or reporting its own quota spent, is skipped until midnight UTC; with
every engine spent the reader keeps the original. Public trip titles are
translated into `TRANSLATION_PRETRANSLATE_LANGS` by a FastAPI background task
when the title first becomes readable to strangers — a public trip created, a
trip published, a public title changed — and the feed carries the cached
translation for `?lang=`.
**Consequences.** Spend is bounded per reader and per day without Redis, and the
counters survive restarts and would hold across instances. Drafts default to
`only_me`, so editing one never spends a translation. A background task is lost
if the process restarts mid-flight; the reader's tap is the fallback. The feed
does one extra query per page.
**Alternatives rejected.** Counting in slowapi's in-memory store (lost on every
deploy, wrong across instances, and it cannot tell a cache hit from a miss).
Check-then-increment in Python (two concurrent requests both pass a cap they
jointly exceed). Pre-translating on every save (collaborative editing saves
often, and most of those trips are private drafts). Pre-translating every
field (most descriptions are never read in most languages). `Accept-Language`
for the feed (the client caches by URL, so a language change would serve the
previous language's titles).

---

### 2026-10-07 — One "See translation" per content group; the feed decides by spoken languages

**Context.** A trip header is up to four translatable fields plus any number of
one-line note chips with no room for a link of their own; a toggle per field
would litter the screen and spend a request per tap. The feed shows many titles
at once. And a reader's app language is not the only language they read.
**Decision.** One toggle per content group — a trip's header with its trip-wide
notes, a stop with its notes and annotations, one review — backed by a
keep-alive `contentTranslationProvider` family keyed by the group's anchor and
the target language. The target is always the app language. The client keeps
only final answers (translated, same language, empty), each with the text it was
made from: an edited text falls back to its original, and a transient failure —
unavailable, rate limited, a failed request — is asked again on the next tap. A
404 or 400 from the POST re-reads the config, which removes the button. Feed
titles never cost a request: a title in one of the reader's profile `languages`
shows as written with a toggle; any other shows translated with a lit marker.
**Consequences.** One tap is one request for a whole section of a page, and a
failure never sticks. Unsetting `TRANSLATION_PROVIDERS` takes every button away
within one request. Both providers are reset on sign-in and sign-out, so one
account's translations never reach the next. A feed card's flip lives in the
card and resets when the card is rebuilt.
**Alternatives rejected.** A toggle per field (a request per field, and chips
have no room). Translating everything into the app language automatically (it
pays for text nobody asked to read in translation, and replaces the author's
words by default). A separate translation-language setting (a second language
control before anyone asked for one — backlog). Keeping failures in the client
state (a dropped connection would hide the button until sign-out).

---

### 2026-10-07 — Privacy 2.3 discloses translation in §4 and §5; the ToS stays at 3.1

**Context.** Translation sends user text to OpenAI and, as fallback, Microsoft.
Privacy §5 is the list of every processor and §4 already describes what the
moderation calls carry. ToS §12 names categories of third-party services and
defers to the Privacy Policy for the list. Only `TOS_VERSION` is recorded per
user, so a ToS change sends everyone through the re-acceptance gate.
**Decision.** Privacy 2.3, in all six languages: §4 becomes "Automated content
moderation and translation" and says what a translation request carries, what
each engine keeps (OpenAI: not used for training, kept up to 30 days for abuse
monitoring; Microsoft: no-trace), that translations pass the same moderation
check, and that taken-down content is never sent; §5 adds Microsoft (Azure AI
Translator) and widens OpenAI to moderation and translation; §10 says when a
translation is deleted. The ToS is untouched.
**Consequences.** Section numbers stay put — §5 and §11 are cited by number
inside the bodies. ToS §12's category list now misses translation, as it
already missed push notifications, until a ToS change that needs a version bump
anyway. `test_privacy_names_every_translation_engine` fails any language that
drops Microsoft.
**Alternatives rejected.** A new "Translation" section with every later
section renumbered (six languages of cross-references to keep in step). Bumping
`TOS_VERSION` to add one word to §12 (every user re-accepts a document whose
list defers to the Privacy Policy anyway).

---

### 2026-10-08 — Editing from the stop page enters the trip's edit mode

**Context.** The stop page had no edit mode. Its pencil and long-presses ran
through `_withClaim`, which took the edit claim for one edit and handed it back,
so a stop could be edited while the trip itself sat in read mode, and a trip
someone else held answered with a snackbar that named them and offered no way
forward. Meanwhile the trip page's edit mode was already, in all but name, this
device holding the claim: `_editMode` is seeded from `holdsClaim`, entering
acquires it, leaving releases it.
**Decision.** Edit mode is the claim, wherever it was taken. The stop page keeps
its pencil and long-presses for owners and editors; using one from read mode
acquires the claim and **keeps** it (`_inEditMode`), exactly as a read-mode
long-press on the trip page does. The trip page follows a claim taken while it
was covered (`ref.listen` on the acquire edge). A refused claim opens a pop-up
naming the holder in the banner's words (`editLockCopy`), offering the takeover
the banner would — owner always, own other device always, an editor once the
server says `takeable` — or, when it may not, `ConfirmDialog.inform` with when it
will be. Taking over opens nothing; the user taps Edit after. The stop page
attaches to the claim like the trip page, and a claim that lands after every
screen has gone starts the detach grace.
**Consequences.** The user returns from a stop to a trip still in edit mode and
leaves it with ✓. Takeover can now start from two places under one rule, and the
pop-up is its confirmation. The stop page inherits the read-mode-only rule for
translation. A new `ok` string (all six languages): the existing `dismiss` reads
"discard" or "ignore" in four of them, wrong beside an editing session.
**Alternatives rejected.** Hiding the pencil unless the trip was already in edit
mode (the first proposal — in read mode the only visible way to edit a stop
would have been back on the trip page). A message-only pop-up sending the user back to the trip page's banner to
take over (three screens for one decision). Keeping claim-per-edit (editing
outside edit mode is what this fixes). A separate edit-mode provider (a second
source of truth beside the claim, free to disagree with it).

---

### 2026-10-08 — Transport-leg thoughts are shown to readers and translated by the toggle already on screen

**Context.** A leg's notes — "Thoughts" in the leg form — were stored,
moderated and, since 0.4.0, translatable on the server, but no reader screen
showed them: both transit views rendered mode, line, time and cost only.
Showing them meant folding long text, and "view more" already existed twice as
private copies (`stop_card.dart`, `ratings_page_screen.dart`) whose overflow
check was a bare `TextPainter` — no inherited style (the theme's DM Sans), no
text scaler, no bold text — so under large accessibility text a note rendered
ellipsised with no link to the rest of it.
**Decision.** Thoughts show under each leg on both surfaces — the trip page's
read-mode transit card and the stop page's Transit section — through one
widget, `LegThoughts`, folded to two lines by a new shared `ExpandableText`
whose check measures with everything `Text` renders with. They are plain text,
never markdown. Translation adds no toggle: the trip's "See translation" covers
every leg's thoughts on the trip page, and a stop's covers its inbound and
outbound legs. `TranslatableText` now returns one tree shape while translation
is offered, so a swap leaves an unfolded thought unfolded. Both private copies
of "view more" now use `ExpandableText`.
**Consequences.** The trip's toggle can be offered when only a leg's thoughts
are in another language, and a tap then changes text further down the page
rather than under the toggle; a trip's tap also spends more of the reader's
200-fields-an-hour allowance. Stop-card and review notes gained the measurement
fix and a button role on the link. The editable transit card still shows no
thoughts — the leg's form holds them. Authors who wrote thoughts before today
never saw them published; the field's help text always described them as
advice for the reader, and they reach only those who can already read the trip.
**Alternatives rejected.** A "See translation" inside each transit card (one
more control per card; one tap for the whole trip matches how trip-wide notes
already work). Showing the thoughts on the stop page only (the trip page is
where a reader plans the journey). Rendering them as markdown (the form is a
plain field, so a typed `#` would become a heading). A third private copy of
"view more" (the extract-on-second-occurrence rule, and the two copies were
already measuring wrong).

---

### 2026-10-10 — Leaving edit mode waits for the saves that carry the claim; leg thoughts show while editing

**Context.** ✓ (and Back) left edit mode at once and released the edit claim.
A leg save still on its way carried that claim: when the release reached the
server first, the save was refused — and the editable card that showed its
spinner, and would have shown its error, had already been swapped for the
read-mode one, so the change was lost without a word. Separately, the
2026-10-08 entry kept a leg's thoughts out of the editable transit card, so
they vanished the moment the author started editing, which read as a bug.
**Decision.** Every write that carries the claim goes through
`ItineraryDetailNotifier._write`, which hands it the token — readable nowhere
else — and counts it until it and its refresh are done. ✓ and Back go through
`_requestExitEditMode`: with nothing running it leaves at once; otherwise the
page goes under `SavingOverlay` with a message, takes no new edit, and leaves
once every write has landed. A write that failed keeps edit mode and the claim,
under that write's own error and then one line saying why the page is still
editing — the only word on it when the save came from the stop page, which has
no screen left to report on. The editable transit card shows each leg's
thoughts as written; a tap on them opens the leg, only the link unfolds them.
This supersedes the 2026-10-08 entry's "the editable transit card still shows
no thoughts".
**Consequences.** The guard covers every write that carries the claim on the
trip page — leg saves, adding or removing a transport, deleting a note, the
best-time-to-visit save, reorders — and any future one, which cannot reach the
token another way. A flow that saves twice in a row (deleting orphaned
segments, then opening the stop form) can still be cut between its writes; it
is recorded as a known gap. The overlay blocks the whole page while it waits,
usually for about a second.
**Alternatives rejected.** Refusing ✓ with "try again in a moment" (it makes
the user do the waiting the app can do itself). Leaving edit mode at once and
finishing the save in the background (the read-mode card shows the old values
until the save lands, and a failure surfaces after the user has moved on).
Guarding leg saves only (every claim-carrying write had the same race). A
counter that each call site keeps (one forgotten site reopens the race; routing
the token through `_write` makes skipping it a compile error).

---

### 2026-10-15 — A claim the app could not hand back is handed back on the next look

**Context.** Reported from a test device: enter Edit mode, close the app, reopen
the same trip, and the banner said "You're editing this on another device". The
claim token lived only in `EditLockNotifier`'s memory, so it died with the app
while the claim stayed on the server. The relaunched app held no token, the
server's `is_you` was all it had to go on, a plain Edit was refused with 423, and
**Continue here** warned about "your other device" — until the row was purged,
`TTL × 24` after the last heartbeat (two hours by default). A web reload did the
same, and so did a release that failed offline.
**Decision.** `EditClaimJournal` (`features/itineraries/data/edit_claim_journal.dart`)
writes each claim down — itinerary id, token, account — from the moment it is
taken until a release is known to have landed: secure storage on a device, the
tab's `sessionStorage` on the web. Before its first look at a trip and before
every claim, `EditLockNotifier` hands back any journalled claim that is not the
one it holds live, and forgets it on 204, 403 or 404; a transient failure keeps
it for the next look. Sign-out hands back every entry of the account and empties
the journal. On the server, a token-bearing `DELETE /lock` now ends only the
claim that token names, the owner's included; a token-less one from the owner
still force-releases. This supersedes the 2026-08-13 entry's memory-only token.
**Consequences.** A journalled token is only ever sent to `DELETE /lock` — never
adopted for a save or a heartbeat — and a stale one is a no-op server-side, so
nothing can resurrect a session; the rotation that ejects a displaced device is
untouched. Reopening a trip the app was closed editing lands in read mode with no
banner, and Edit claims without a takeover. The server change also closes a race
that predates the journal: an owner's ✓ on a device just displaced, before its
next heartbeat noticed, ended the claim that had displaced it. Deploy the backend
first — a new client against the old server would reopen that race on every late
release. A web tab closed while editing still leaves its claim behind (its
`sessionStorage` goes with it); recorded as a known gap.
**Alternatives rejected.** Resuming edit mode on relaunch (re-holds a lock the
user walked away from, blocking collaborators — and the app restarts at home
anyway). A device id stored on the claim (a migration, a header and a response
field, and on the web it still needs a per-tab identity, to answer what one
DELETE settles). Releasing on `paused`/`detached` (neither is delivered on a
swipe-kill, and releasing on every backgrounding would hand the trip away during
a copy-paste). Journalling in `localStorage` on the web (a second tab would hand
back the first tab's live claim). Rewording the banner alone (honest, but the
stale claim, the 423 and the takeover dialog would all stay).

---

### 2026-10-18 — Removing a follower: silent, idempotent, accepted-only

**Context.** A follow could end only from the follower's side (Unfollow) or with
a block, which also cuts visibility both ways — a heavier tool than "this person
should stop seeing what I share with followers". Nothing on the server let the
followed account end someone's follow, and `UserPublicProfile` carried only the
viewer→target direction, so a profile could not tell whether its owner follows
*you*.
**Decision.** `DELETE /users/me/followers/{user_id}` ends `user_id`'s **accepted**
follow of the caller, keyed by user id because neither the list item nor the
profile carries a follow id. It is **idempotent** — nothing to remove answers
204 — and **silent**: no notification, no push. A pending request is left
alone. `UserPublicProfile.follows_you` (appended last) lets the profile's ⋯ menu
offer **Remove follower** only when it applies; the own Followers list gets a
**Remove** pill per row and, asked for in the same change, the own Following
list a **Following** pill that unfollows. `user_service.delete_follow` becomes
the only way to delete a follow row — unfollow, remove, decline and the block
sever — deleting with `RETURNING status` and decrementing only when *this* call
removed a row that was accepted *when it went*; `only_if=` makes decline's
delete conditional on `pending`. `edit_lock_service.release_claims_lost_by`
drops the claims a person holds on an owner's trips once they can no longer
edit them, after a follower removal and after a block (both directions). The
client refetches the owner's profile for the counts rather than subtracting one,
and `FollowListNotifier.removeLocally` steps the paging offset back by one.
**Consequences.** Access to followers-only trips — and editing them — ends the
moment the row goes, with nothing to clean up but a stranded claim, which is
released in the same transaction. On a public account the removed follower can
follow again at once; the confirm dialog says so and points at Block. Three
latent races close: a block racing an unfollow decremented twice (the sever used
ORM `db.delete()`); a request accepted between a cancel's read and its delete
went without its decrement; and an accept landing between Decline's status
check and its delete was deleted anyway. A blocked editor's claim no longer
stands until the TTL. The unfollow dialog's message, which the Following pill
now shows too, was corrected in all six languages: it promised the trips would
leave "your feed", which is public-only and never depended on a follow.
**Alternatives rejected.** A 404 `not_a_follower` (a stale list row would show
an error for a state the user asked for, and a new code needs strings in six
languages for nothing actionable). Keying by follow id (the client has none to
send; adding one would change `FollowerListItem`'s contract). Letting Remove
delete a pending request (a stale Remove would decline a request the owner has
not seen — Decline exists for that). Telling the removed follower (a decline
and a block are silent for the same reason). Labelling the menu item
"Unfollow", as first asked — that word already means the other direction on
the Following button. Swipe-to-remove (it fights the TabBarView's own
horizontal swipe, and is undiscoverable). A local `followersCount - 1` (counts
twice when the row was already stale). Leaving the stranded claim to the TTL
(CLAUDE.md: never leave a revoked editor's claim standing).

---

### 2026-10-18 — A notification tap never opens a screen with nothing beneath it

**Context.** A tray tap while the app was in the background navigated with
`go()`, which replaces the whole stack. Six of the eight types open a
root-level route, so the tapped screen became the only page on the root
navigator: the profile's back arrow (`maybePop`) did nothing, the AppBar
screens drew no back button, Android's back closed the app, and the screen the
user had left was destroyed, unsaved text included. The cold start meant to
avoid this — splash's `go('/profile/me')`, then a `push` one frame later —
raced the redirect: `push()` builds on the stack as it stands at the call,
`go()` lands only after the redirect's async secure-storage reads, and
splash's loader keeps frames coming, so the push could fire first and stack
the tap on the splash page. The destinations' own exits had gaps too: the
profile's and the trip's error states had no way back, and the profile's
"account unavailable" page hid Go back exactly when there was nothing to pop —
the state a notification about a since-deleted account produces.
**Decision.** Two primitives in `core/router/navigation_ext.dart`, beside
`popOr`. `GoRouter.pushOverHome` opens a route with `/profile/me` beneath it as
**one** navigation — `routeInformationProvider.push` with an explicit base from
`configuration.findMatch` — and the cold start uses it. `GoRouter.openFromOutside`
is the warm tap: a root-level destination is pushed over the screen the user
left, so Back returns there and their input survives; a destination inside the
tab shell opens over home. `openTappedRoute` (`push_gateway.dart`) gates it: a
tap while splash still owns the first navigation is handed to splash
(`deferTapToSplash`), and one on a signed-out screen (`kPublicRoutes`, hoisted
out of the redirect so the two cannot disagree) is dropped. On the way out,
every screen `notificationRoute` can open leaves through `popOr` in every
state, to the page that would have been underneath: the profile hero gains
`onBack`, its error state and the unavailable page a Go back, the trip's error
state a Go back outside edit mode, the ratings and Account status AppBars an
explicit `BackButton`, and `EditorialTopBar` an `onBack`.
`tap_routing_test.dart` runs every notification type through both paths — the
cold one on the real `SplashScreen`, pumped at 60 Hz — and pins each
destination to the root or the Profile tab;
`notification_destinations_exit_test.dart` pumps each destination alone and
fails until a new one has a case.
**Consequences.** Back from a tapped screen returns to where the user was, or
to home after a cold start, on both platforms, and an unsaved stop note
survives a tap of every type but two: Follow requests and Account status still
close whatever sat above the tabs, as `go()` did. A warm tap in the instant
after splash took its parked route is lost to home. A tap after the session
died in the background pushes the redirect's `/login` over the screen rather
than replacing it; signing in resets the stack. The cold-start race shows only
when frames outrun the redirect, which `pumpAndSettle`'s 100 ms steps never
do — hence the 60 Hz pump.
**Alternatives rejected.** Swapping `go` for `push` alone (pushing
`/follow-requests` over a root-level page appends a second shell — the
duplicate-key assertion `app_router.dart` already records). Always opening over
home, Android's synthetic back stack (one rule, but it keeps destroying the
screen the user left). Moving the two shell routes to the root (takes the
bottom bar off both screens, a change nobody asked for). Waiting for `go()` to
land and then pushing (a delegate listener never fires when `go` targets the
current configuration, so from home the push would never come). A home
fallback inside `EditorialTopBar`'s default arrow (on a screen alone it would
bypass a `PopScope`'s unsaved-changes guard).

---

### 2026-10-18 — Shared links open the app, and say plainly when they can't

**Context.** With TestFlight and Play internal testing live, a shared link
(`/share/i/{id}`, `/share/u/{username}`) still always opened the server-rendered
page, even on a phone with the app: nothing native claimed the domain. The pages'
**Open in app** pointed at `ntripi://…`, a scheme the app never registered, and
their store buttons were `href="#"`. Three more gaps lay on the same path. The
private page for a followers or specific-people trip put its title, `@owner` and
cover photo on the page and into the chat preview, while the help centre
promised such a link shows none of that. A malformed id answered a browser with
FastAPI's raw JSON 422, and a dead profile link said "This itinerary is not
available". In the app, a trip someone may not open, or one that was deleted,
showed an error with a Retry that could never succeed.
**Decision.** iOS Universal Links and Android App Links for **share links only**,
through Flutter's own deep linking — no plugin. The server serves
`/.well-known/apple-app-site-association` and `assetlinks.json` from settings
(404 until set; `_validate_app_links` refuses malformed ids and fingerprints).
The manifest claims `https://ntripi.app/share/i/` and `/share/u/` with
`autoVerify`, the entitlements `applinks:ntripi.app`; a guard test holds them to
the release `SHARE_BASE_URL` and to `appLinkLocation`. A link never lands as it
arrives: a cold start is parked by the redirect and opened over home by splash;
a link while running opens over the current screen (`openFromOutside`); one that
arrives during splash or while signed out is parked, and the next landing opens
it (`landHome`, called by splash and every sign-in path). Android moves to
`launchMode="singleTask"`. A link that cannot be opened gets exactly two answers
— **no access** (the API's single 403) and **not available** (404, or a link
`appLinkLocation` cannot read) — neither saying why and neither with a Retry. On
the web every share page offers the app first (Android's `intent://` **Open in
app**, the store buttons with the waitlist as their fallback, the iOS Smart App
Banner once the app is live) and **Continue on web** second. The private page
keeps saying the trip is private but names nothing about it, enforced by the
router passing the template no trip; the owner chose this over both
alternatives below.
**Consequences.** Links open the app on store-signed builds once the association
files are live; the files must be deployed before a build is installed, since
devices fetch them at install. Launch day is a variable change for every share
page's download buttons, though not yet the homepage's. A link tapped while
signed out survives the sign-in, where a tray tap is dropped. A cut-short link
can never open the create-trip form (`/share/i/new`). Previews already cached in
chats keep a private trip's old card. iOS has no in-page **Open in app**: a
same-domain link never opens an app. `singleTask` means one instance: a system
picker left open may close when the app is relaunched from its icon.
**Alternatives rejected.** The `app_links` plugin (needs Flutter's deep linking
off; the engine already handles both lifecycles, UIScene included). Repairing
the `ntripi://` scheme (hijackable by any app, and an error dialog in Safari
without the app). Claiming `/*` (would capture emailed reset, verification and
appeal links, which are web forms). Letting go_router land the link as it
arrives (skips splash on a cold start, destroys the stack on a warm one).
Redirecting mobile visitors without the app to a store (the page must stay
readable; the app is offered, never forced). For the private page, the owner
weighed two other options: revealing nothing at all, identical to a missing trip
(the link would look dead even to someone who can open it in the app), and
keeping the details (the title and cover reached everyone in the chat, against
the help centre's promise). Keeping `singleTop` (a link from Gmail started a second copy of the
app in the caller's task).

### 2026-10-19 — Share pages become a teaser; the full trip needs an account

**Context.** A signed-out visitor who opened a shared link got a server-rendered
page with the whole trip on it — stops, transport, costs, notes, reviews, the
owner — in a design of its own (forest green on the trip page, indigo on the
other four), so their first sight of Ntripi did not look like Ntripi. Search
engines and AI bots read the same page. The owner wanted visitors to sign up or
install first, and asked that a reader without an account reach the teaser and
nothing else, demonstrably. Before launch every store button leads to the
waitlist, so "install first" could not be the way in yet.
**Decision.** Every share page shows a teaser, the same to a person, a chat-card
crawler and a search engine: a public trip's title, cover, rating and
description; a profile's display name, @username and avatar (private accounts
the same, `noindex`). The chat card says what the page says. The routes pass the
templates those fields and never the row. The way in is **See the full trip** /
**See the full profile** into the web app, which parks the link through sign-in
or sign-up — a line above the sign-in forms says what is waiting — and, once a
phone's store is live, that store comes first with "tap the link again once
installed"; a desktop keeps the web first. All five pages share one layout in the
app's own tokens, light only. `/share/*` is rate-limited per IP (120/minute,
HTML 429), `/openapi.json` is off in production, and `test_public_surface.py`
classifies every route reachable without sign-in and fails on any non-teaser
field seeded into a response. This supersedes the 2026-10-18 entry's rejected
alternative "the page must stay readable; the app is offered, never forced".
**Consequences.** The help article `share-a-trip-link` and What's New were
rewritten in all six languages; the Terms are untouched (their sentence — a
public trip's link works without an account and may be crawled — stays true,
and a change would bump `TOS_VERSION` and gate every user). A trip without a
description is thin for a search engine. The anonymous report dialog stays on
the teaser — the title, cover and description can still be what someone needs
to report, and the EU DSA expects a notice mechanism open to non-users. The
audit found image keys derived from published ids (a private trip's cover sits
at `itineraries/<id>.jpg`), approved as step 2; the sitemap and the crawler
policy follow as step 3. Nothing reads `Stop.outgoing_segment` now.
**Alternatives rejected.** A hard wall naming nothing about the trip (the link
would look dead, and before launch the only way in is a sign-up form), skipping
the page straight to the web app's sign-in (the visitor sees nothing of what
they were sent), and keeping the full page restyled (the owner wanted the
content behind an account). For search: the full trip in the HTML hidden by CSS
under paywall markup (a cosmetic gate, readable in view-source), and the full
trip to a verified Googlebot only (on the cloaking line, and answer bots would
retell it without the click). The trip's stop names as an outline on the
teaser, and the owner, duration, cost and stop count on it — the owner chose
the four fields. Bio, counts and a trip list on the profile teaser.

### 2026-10-19 — A phone is offered only its own store; the app's first language walks the device's list

**Context.** Every share page offered both store badges on every device, and the
homepage hero did the same; the page script only moved a live store first. It
also missed iPads: since iPadOS 13 their Safari reports a Mac, and the app ships
for iPad. The owner asked that an Android phone see only Google Play and an
iPhone only the App Store, in the device's language. The page already followed
the device's language list (`resolve_lang`), but the web app behind **See the
full trip** read only the list's first entry, so a phone set to Portuguese then
French got a French page and then an English sign-in screen.
**Decision.** `platform_head` (`_app_links.html`) decides the platform once, in
`<head>` before the body is parsed, onto `<html data-platform>` — `android`,
`ios` (an iPad: `Macintosh` plus touch points), or nothing — and one CSS rule
hides the other store's `[data-store]` button. Every share page gets it through
`app_links_head`, the homepage calls it itself, and `app_links_script` reads its
answer instead of the User-Agent. A laptop, an unknown device and a browser
without JavaScript get both, and both stay in the HTML. `test_app_links.py` pins
the templates that render store buttons and checks each page's `<head>`. In the
app, `firstSupportedLocale` walks the device's whole list, as `resolve_lang`
walks `Accept-Language`.
**Consequences.** Googlebot renders as an Android phone, so its rendered page
shows Google Play only; the HTML keeps both. An Android tablet in desktop mode
reports a Linux desktop and gets both, the safe default. The waitlist still
records the platform of the button pressed.
**Alternatives rejected.** Choosing on the server from the User-Agent: the HTML
would vary by User-Agent, an iPad cannot be told apart there, and the page's
other platform choices already live in its script. Hiding the other badge from
the end-of-body script: a phone would see both badges flash first.

### 2026-10-20 — Postgres moved to the API's region

**Context.** Saves took 3.6–5.7 s for the owner in Belgium: create a trip 3.63 s,
add a stop 5.65 s, edit the description 4 s, add a trip note 5 s, rate 4.41 s.
The network was not the cause: a page that runs no query answered in ~0.11 s
through Cloudflare's Brussels edge, while the same share page with one
primary-key lookup answered in ~0.59 s, so one query cost ~0.48 s. A local
replay — the real backend against Postgres behind a proxy that adds a fixed
round-trip delay — reproduced that single-query cost at 120 ms per round trip,
and at that delay reproduced the owner's save timings; at 2 ms the same flows
took 0.07–0.17 s of server time. Each request makes 8–20 database round trips
one after another (its statements plus the pool's ping, BEGIN and COMMIT), and
the app sends a save and then a full reload in sequence. The owner found the
Postgres service had been created in a US region while the API ran in EU West;
a region is set per service, so moving the API had never moved the database.
**Decision.** Postgres runs in the API's region, EU West (Amsterdam), moved on
2026-10-20. The rule is in constraints.md (Portability) and CLAUDE.md (Hosting),
with a check that needs no sign-in: `/share/i/not-a-uuid` (refused before any
query) and `/share/i/<random uuid>` (one query) answer in the same time when the
two services share a region.
**Consequences.** Timed the same way, saves dropped to 1.0–1.5 s, and the
share-page check shows no gap. What remains is not database distance: the
OpenAI moderation call on every text save, whose replies come from across the
Atlantic; first requests after a restart; the client's reload after each save
and its animations; and, on a rating, the inline push. The owner set the bar at
under one second per action — tracked in backlog.md and measured with the
request-timing log in the next entry. The privacy policy already disclosed US
processing (section 13), so the old location was a speed problem, not a
compliance one.
**Alternatives rejected.** Moving the API to the database's region instead:
a save would cross the Atlantic once rather than 8–20 times, but every request
from a user in Europe would pay that crossing, and the database would stay in
the US. Cutting round trips in code first: no code change could have closed a
gap that size, and it is now optional work measured against the one-second bar.

### 2026-10-20 — Request timing is a log line, never a response header

**Context.** Postgres sat in another region for weeks and nothing said so:
Railway shows WARNING lines only and the app never configures logging, so no
request duration was ever recorded. With saves at 1.0–1.5 s against a
one-second bar, the next fixes need to know where each request's time goes —
the database, OpenAI, Firebase, or the app itself.
**Decision.** `RequestTimingMiddleware` (`app/middleware/request_timing.py`),
innermost in the stack, times every request except `/health` and the static
mounts. One slower than `SLOW_REQUEST_LOG_MS` (default 1000; `0` logs every
request) logs one WARNING line: method, route template, status, total, database
time and query count, outbound HTTP time per host, and the remainder. Database
time comes from class-level `Engine` cursor-execute listeners; outbound time
from wrapping `requests.Session.send` and botocore's `URLLib3Session.send`, the
two seams every integration already passes through, with a redirect timed once.
The record rides a `ContextVar`, which anyio copies into the worker thread of a
sync endpoint, and the clock stops at the last body chunk, so a background task
is not counted.
**Consequences.** A slow request now leaves a trace in Railway's logs, split
between Postgres, each outside service, and the app. Logging the route template,
never the path, keeps ids and usernames out of the log. An HTTP client library
outside `requests` and botocore stays invisible until it gets a hook. COMMIT,
ROLLBACK and the pool's ping are not cursor executes, so `db` slightly
undercounts round trips. `test_request_timing.py` pins the line, the template
rule, the exclusions, the redirect counted once and the config bound.
**Alternatives rejected.** A `Server-Timing` response header, which browsers
show in DevTools: a query count or a duration in the response tells any caller
whether an account or a trip exists, undoing the timing-safe login and the
identical 404 pages. Tagging each outbound call site by hand (OpenAI, Azure,
FCM, Google, Resend, HIBP, Jira, R2, Rekognition): ten places to remember, and a
new integration would stay invisible until someone did. OpenTelemetry: a
collector and new dependencies for one log line.

### 2026-10-21 — The itinerary form saves its fields and its cover in one request

**Context.** The Edit itinerary form saved in two requests: the cover first
(`POST` or `DELETE /itineraries/{id}/image`), then `PATCH /itineraries/{id}`
with the `If-Match` the form had read before either. The cover endpoints are
`OWNER_ONLY` — no lock, no `If-Match` — and a cover write that changed the row
(a first cover, a removal, a scan that flagged or errored) moved `updated_at`,
so the PATCH behind it answered 412. The production log of 2026-10-20 showed
`POST /itineraries/{itinerary_id}/image 200` followed by
`PATCH /itineraries/{itinerary_id} status=412`, twice: the cover saved, the
other fields did not, and every retry failed the same way until the trip was
reloaded. Replacing a cover after a clean scan rewrites the same URL, changes
nothing and never failed, which is why it went unseen. Creating a trip with a
cover took two requests as well.
**Decision.** One request carries the form's fields and its cover change,
checked once by `require_edit_access`. `PATCH /itineraries/{id}/form` —
multipart: `fields` as JSON validated with `ItineraryUpdate`, an optional
`image`, an optional `remove_cover` — serves every save of the Edit itinerary
form, editors included; `POST /itineraries/form` (`ItineraryCreate` and a
required `image`) creates a trip with its cover. The paths name what they
serve, the form's save, beside the JSON pair, which stays as it was for the
description editor, the period picker, the visibility screen and creates
without a cover. On the edit route: guard → field validation → the owner-only
parts and a verified email → text scan → the cover processed, scanned and
stored → verdicts, cover and fields applied → `sync_translations` → one commit,
with a removed cover's object deleted after it. Both routes are sync `def`:
FastAPI parses the multipart body before calling them, and they reach the async
image pipeline through `anyio.from_thread.run`. The app's save is one notifier
call through `_write`, and the answer's stamp is adopted in place.
**Consequences.** On this path the cover changes under the edit lock and
`If-Match`, like the fields beside it, and a save is one request in the timing
log. Each moderation reject commits the session for its audit row, so the
itinerary is not touched until both checks pass — and a text verdict commits
with a refused cover: harmless for `approve`, a moderator-queue entry for text
never saved on `review`, and on `hide_escalate` an escalation against the
author, as for a rejected minors verdict. On create, the cover's audit row
cannot name the trip before its row exists (a real foreign key, and a reject
commits it), so `moderation_service.attach_itinerary` links it after the flush.
A refused cover at create now creates nothing and keeps the form open; the
trip used to be created without it. The cover object is still written to its
stable key before the commit — per-upload keys (share teaser, step 2) would end
that. `POST`/`DELETE /image` stay unchanged until no build in testing calls
them, and the app no longer has code for them. The suite's SQLite stamps
`updated_at` in whole seconds, which hid this kind of 412 from it; the tests
about the ETag moving now backdate the row.
**Alternatives rejected.** Writing the cover endpoints through
`admin_service.set_preserving_etag`: the cover would leave the version check and
the edit lock, so the owner's two devices could overwrite each other's cover,
and a save would still take two requests. Keeping two requests and re-reading
the ETag between them: a second round trip on every save, with the cover still
changed outside the lock. One route taking JSON or multipart by content type:
the JSON PATCH had to stay exactly as installed builds call it.

### 2026-10-21 — A trip save answers with the whole trip, and the app never reloads after it

**Context.** With Postgres in the API's region, the owner still timed 1.0–1.5 s
per action on a Play internal-testing (release) build, against a bar of one
second. The request-timing log (`SLOW_REQUEST_LOG_MS=0`, 2026-10-20) showed
every stop, note and rating save followed by a forced
`GET /itineraries/{itinerary_id}` that the form waited on before closing: a stop
save took 129–487 ms of server time plus a 55–57 ms reload, a note save
391–885 ms plus 43–68 ms, a rating 71–83 ms plus 55–58 ms — each reload a second
round trip in sequence. During it `ItineraryDetailNotifier.refresh()` set
`AsyncLoading`, which Riverpod 3.4.2 turns into a reloading state, and the trip
screen's `itineraryAsync.when(...)` rendered that as the full-screen
`NTripiRouteLoader` (`skipLoadingOnReload` defaults to false): the whole trip
view was rebuilt from scratch after every save. `applyReorder` already received
the full trip from `POST /reorder`, ignored it, and downloaded the trip again.
**Decision.** The owner's: a save's answer carries the whole updated trip —
exactly the body `GET /itineraries/{id}` would give that caller at that moment —
and the app replaces its copy with it, merging nothing. It is opt-in per
request, as the query parameter `?return=itinerary`: every `EDIT_GUARDED` route
(18 since the form route of the same day) then answers
`ItineraryEditResponse {itinerary, created_id}` with the concurrency ETag;
asked nothing, each answers exactly as before. The trip is read back after the
route's last commit and built by `_viewer_detail` — the helper the GET now uses
too, which sets the caller's `can_edit` — and wrapped by `_trip_edit_answer`;
the reorder's inline copy of the GET went the same way. `created_id` names what
a create made, and deletes answer 200. A rating's answer carries the trip's
aggregate: `POST /ratings` appends `rating_avg` and `rating_count` (a subclass
of `RatingResponse`, so `GET /ratings/me` is unchanged) and
`DELETE /ratings/me?return=aggregate` answers them. In the app every trip edit
sends the parameter and `_adopt` sets the answered trip as the state; a rating
adopts the aggregate into a trip already loaded. `refresh()` stays for
pull-to-refresh, Retry and an editor who removed themselves; its blanking is a
separate fix.
**Consequences.** A save is one request: a stop with two queued notes is three
requests and no GET, and no save puts the trip view behind the loader. A write
counted by `_write` ends when its answer is adopted, so ✓ waits for the save
alone. The reload had also refreshed the HTTP cache's copy of the trip — what
the app shows when it starts offline — so the answered trip is written there
instead (`cacheAsGet`), under the account's key and with no validator; the next
online open downloads it once rather than answering 304. After a rating the
offline copy keeps the old average until the next download. The answer's
`itinerary` is null only when the save itself took the caller's view away
(moderation hiding an editor's text on the spot); the app then makes the one GET
whose 403 says so. **Deploy the backend first**: the app asks for the trip and
does not fall back to the old answers. `test_trip_edit_answers.py` compares
every route's answer, for the owner and an editor, with a GET made right after,
and fails on a new trip edit until it has a case. The help centre is unchanged:
nothing a reader sees changes but the speed.
**Alternatives rejected.** Answering with only what changed and merging it in
the app: about a dozen merge paths, each free to drift from the server — kept as
an idea, tracked in Jira ([backlog.md](backlog.md#idea--delta-answers-merged-in-the-app)).
Closing the form first and reloading afterwards: still a full download after
every save. A request header for the opt-in: it would need an entry in CORS's
explicit `allow_headers` list, where a query parameter needs nothing. Leaving
the offline copy as of the last download (the owner chose to keep it current):
a trip edited at home and opened offline later would show without the edits.

### 2026-10-22 — A write answers with what the screen shows next; the app never re-downloads after its own write

**Context.** After `10435ce` made every trip edit answer with the whole trip,
the owner asked whether the same had been done everywhere time could be saved,
and whether "fix it in one place" held. An audit of the app's writes found five
waits after a write:
- the Itineraries tab's lists downloaded again after a save;
- an editor grant or revoke reloading the owner's trip, because it moved
  `updated_at` (next entry);
- a create downloading the trip it had just made;
- follows and blocks re-reading `/users/me` for two counters;
- FCM pushes sent inside the request (the entry after).

It found three smaller re-downloads too: accepting the terms re-read
`/users/me`, an appeal re-read the Account status list, and a rating made on
the Ratings page re-read the page. And it found duplication: sixteen save
methods repeated the same request-and-adopt lines, with `_listsChanged()`
placed by hand — so segment saves left the tab's totals stale — and
`_HeldClaim` was copied into five test files.

**Decision.** The owner's, as a project-wide rule: **a write answers with what
the screen must show next, and the app never re-downloads after its own
write.** The named exceptions:
- content an answer cannot carry — someone's trips or followers after an
  unfollow or removal, the feed after a block or unblock, a new row in the
  Following list;
- pull-to-refresh and Retry;
- sign-in, sign-out and token exchanges;
- invalidating data no open screen shows, which loads when its screen opens.

Server:
- `return_requested(*representations)` in `app/dependencies.py` is the one
  opt-in factory (`?return=…`, pattern-checked, 422 for anything else). Asked
  nothing, every route answers byte for byte as before.
- The two creates take `?return=itinerary` and answer
  `{itinerary, created_id}`, with `created_id` the new trip.
- Follow and accept always append `counts` (`FollowWriteResponse`, a subclass
  of `FollowResponse`). Unfollow, remove follower and block answer 200
  `FollowCounts` when asked with `?return=counts`, 204 otherwise.
  `user_service.follow_counts` reads both counters after the commit and
  computes nothing.
- `POST /ratings?return=ratings_page` appends the page, and
  `DELETE /ratings/me` takes `aggregate|ratings_page`. One builder,
  `_ratings_page`, serves the GET and both writes.
- `POST /appeals?return=violations` answers the Account status list.
- `POST /auth/accept-tos` already answered the profile.

App:
- Every trip save goes through `ItineraryDetailNotifier._save`, which also
  replaces the trip's row in Mine or Shared with me from the answer
  (`_syncListRows`).
- A create's trip waits in `tripSeedsProvider`, which the trip's first build
  takes, so the new trip opens with no GET.
- Follow writes adopt their counts through `adoptMyCounts` and
  `adoptTheirFollowState`.
- Accepting the terms adopts the answered profile, an appeal the answered list,
  and a rating made with the Ratings page open the answered page.
- An answer that replaces a whole GET body — the trip, the profile, the
  violations list, the ratings page — is also written into the HTTP cache as
  that GET's entry (`cacheAsGet`), as on 2026-10-21.

Three refinements came out of reading the code:
- **`counts.them` is null wherever `GET /users/{id}` would 404 for the caller**:
  an unknown or suspended account, or a block in either direction. Remove
  follower answers even when there was nothing to remove, and a count there
  would tell a blocked user that the account behind the block still exists.
- **Asked for the ratings page, `DELETE /ratings/me` checks view access before
  deleting** (403 `itinerary_access_denied`). The page is the GET's, which
  refuses, and the refusal writes nothing.
- **The answered profile is cached as `/users/me`.** Otherwise an offline start
  after accepting the terms read `tos_current: false` from the cache and
  raised the gate again.

**Consequences.**
- Segment saves now update the Itineraries tab's totals.
- Accepting a follow request now updates my followers count, which nothing
  refreshed before.
- A block made from a review or a trip now updates my counts; only a block from
  a profile refreshed them before.
- Counts and list rows are partial answers, so their offline copies stay as of
  the last download.
- **Deploy the backend first**: the app asks for the new answers and has no
  fallback.
- Server tests: `test_trip_edit_answers.py` (creates, ratings page),
  `test_follows.py` and `test_blocks.py` (counts), `test_appeals.py` (the list).
- App tests assert the absent GETs exactly: `trip_edit_adoption_test.dart`,
  `editors_notifier_test.dart`, `follow_counts_answer_test.dart`,
  `tos_gate_test.dart` and `appeal_sheet_test.dart`.
- Test support lives in `test/support/`: `HeldClaim`, `RecordingDio`, the trip
  JSON builders and `kZeroCounts`.

**Alternatives rejected.**
- A local ±1 on the counts: it counts twice from a stale row, which is why the
  profile was re-read in the first place.
- Answering the counts on the 204 routes without being asked: installed builds
  have always been sent an empty 204 there.
- Asking for the ratings page on every rating: the app asks only while it holds
  the page, and otherwise the server would build a page nobody looks at.
- Writing a new trip straight into the detail provider: reading a family member
  builds it, which is the GET, and a provider may not change another while it
  builds — hence the seeds holder.

### 2026-10-22 — Granting or revoking edit rights no longer moves `updated_at`

Supersedes the rule in
[2026-08-13 — Editors, and an edit lock identified by a rotating token](#2026-08-13--editors-and-an-edit-lock-identified-by-a-rotating-token)'s
implementation that every editor endpoint calls `_touch_itinerary`.

**Context.** `add_editor` and `remove_editor` bumped `updated_at` so that a
revoked editor's cached detail would not keep offering them a pencil:
`can_edit` rides in the detail, whose ETag was `updated_at`. Since
[2026-09-28 — The detail GET's cache validator carries a body hash](#2026-09-28--the-detail-gets-cache-validator-carries-a-body-hash),
the validator is `"<updated_at>;<body hash>"`, so a changed `can_edit` already
fails a cached copy's 304. All the bump still did was move the owner's
`If-Match`, and the app reloaded the trip after every grant or revoke to learn
the new stamp.

**Decision.** The editor endpoints leave `updated_at` alone, like the
allowlist, and the comment in each says why. The app no longer reloads after a
grant or revoke. An editor who leaves sets `can_edit` false on their own copy
(`ItineraryDetailNotifier.editRightsEnded`) and drops the trip from Shared with
me in place, through `EditorsNotifier.leave`.

**Consequences.** The owner's If-Match from before a grant or revoke still
saves (`TestTheStampStays`), and a revoked editor's conditional GET answers 200
with `can_edit: false`. Their next save is still refused by the guard, which
re-derives the right on every write, and `remove_editor` still releases their
claim.

**Alternatives rejected.** Keeping the bump and answering the grant with the
new stamp: the stamp would still move under any editor who had the trip open,
and they would get a 412 for a change to the editor list they cannot see.

### 2026-10-22 — Pushes leave the request

**Context.** Since
[2026-08-13 — FCM push as a latency improvement, dispatched after commit](#2026-08-13--fcm-push-as-a-latency-improvement-dispatched-after-commit),
the `after_commit` listener sent each push itself, on the request's thread,
between the commit and the response. Every follow, accept, rating, save or
editor grant that notified someone waited on FCM — up to one timeout when it
did not answer — and the request-timing log counted that time as the
request's. The backlog's performance list named the rating's push.

**Decision.** The listener still drains the queue after commit, and a rollback
still clears it. It now hands the batch to one module-level worker
(`ThreadPoolExecutor(max_workers=1, thread_name_prefix="push")`) through
`_submit`, which runs it in an empty `contextvars.Context`. The worker opens its
own session and sends exactly as before.

**Consequences.**
- No write waits on FCM, and `ext=fcm.googleapis.com` no longer appears in a
  request's timing line.
- One thread keeps sends in order. A stalled FCM delays the pushes queued
  behind it, never a user's write, which is why an unreachable FCM still
  abandons the rest of that notification's devices.
- Pushes still queued when the process stops are sent before it exits,
  within the platform's shutdown grace.
- Tests run the batch inline through a patched `_submit`. One test proves a
  follow answers while its push is still blocked.

**Alternatives rejected.**
- FastAPI `BackgroundTasks`: the `after_commit` listener, and the services
  that call `notify()`, hold no request to attach a task to.
- One thread per push: unbounded under a burst, and sends out of order.
- An external queue: a new dependency for something the poll already backs up.

<<<<<<< HEAD
### 2026-10-25 — A reload never blanks the content on screen

Completes the separate fix that
[2026-10-21 — A trip save answers with the whole trip, and the app never reloads after it](#2026-10-21--a-trip-save-answers-with-the-whole-trip-and-the-app-never-reloads-after-it)
left to `refresh()` ("its blanking is a separate fix").

**Context.** Pulling to refresh the trip page swapped the trip for the
full-screen loader until the new copy landed, and brought it back rebuilt with
every "view more" closed; a failed reload replaced it with the error view,
although the copy on screen had been fine a second earlier. Riverpod 3 (3.3.2
installed) routes every `state =` through `asyncTransition`, which merges the
previous value into an `AsyncLoading` or `AsyncError` (`copyWithPrevious`), and
`AsyncValue.when()` defaults to `skipLoadingOnReload: false` and
`skipError: false`: it still draws the loader and the error view, and the data
subtree is unmounted either way. Eleven `refresh()` methods wrote
`AsyncLoading` unconditionally; the two that kept the rows during the load
(follow requests, notifications) still wrote a failure over them. Reading the
code found three more of the same:
- `MyProfileNotifier.updateProfile` wrote a failed save into the profile, so a
  refused bio replaced the profile screen — the edit form and its typed text
  included — with the error view, and the form's own catch never ran;
- Account status pulled with `ref.invalidate`, which returns at once (the
  spinner ended before the list came back) and let a failed rebuild replace
  the list;
- on iOS and Android a forced reload that timed out or got a 5xx was answered
  by the HTTP cache with its stored copy, as a success — so no failure could be
  reported, and the copy could be older than the screen, because list rows,
  follow counts and the rating average are adopted from write answers in
  memory only.

**Decision.** One mechanism, `ReloadKeepsContent`
(`core/providers/reload_keeps_content.dart`): a mixin on `AsyncNotifier` whose
`reloadKeepingContent(fetch, onApply:)` is the only place a notifier writes
`AsyncLoading` or `AsyncError`.
- Nothing on screen (no value, or the error view): the loader, then the answer
  or the error — a first load and Retry, unchanged.
- Content on screen: it stays mounted. An answer replaces it in place after
  `onApply` (paging bookkeeping) — unless something else wrote the state while
  the reload was in flight, and then that newer state stands: the GET may
  predate a save, a dismissal or a removal answered meanwhile, and applying it
  would undo the user's own action on screen (on the trip page, put back an
  old `updated_at`, so the next save 412s). The owner chose this over always
  applying the answer.
- A refusal — `refusesContent`, the `kNeverServeStaleFor` statuses
  401/403/404/410 — replaces the content with the error view: a deleted,
  blocked or no-longer-shared trip must not stay on screen.
- Any other failure leaves the content and is returned as a `ReloadFailure`.
  The screen that started the reload shows it with `reportReloads`
  (`shared/widgets/reload_report.dart`: a SnackBar of `extractErrorMessage`,
  only while that screen is mounted); a reload the app starts drops it.
  `refresh()` never throws, so nothing reaches a `RefreshIndicator` as an
  error.

All thirteen `refresh()` methods use it, and `MyViolationsNotifier` gains one
for Account status's pull. `ItineraryDetailNotifier._adopt`'s GET — after a
save answered with no trip — goes through it too. `updateProfile` throws on
failure and leaves the profile. Forced reads (`forceRefreshOptions()`) no
longer fall back to the stored copy on a transient error, and the four reloads
that were not forced (my profile, a profile, the places map, Account status)
now are; first loads keep the fallback, which is what shows content offline.

**Consequences.**
- A pull keeps the scroll position and every opened "view more"; its spinner
  is the only sign of the reload. A failed pull keeps the content and shows the
  reason; a refused one shows the screen's error or unavailable view, as
  before.
- The two ratings screens draw from `.value`, which an `AsyncError` still
  carries, so their error check became `hasError` alone: an error state now
  only ever means "show the error".
- The follow lists and the notification feed stay scrollable during a pull, so
  a `loadMore` page requested before a reload landed is dropped (a generation
  counter) rather than appended to the new first page at the old offset.
- A notification-settings switch whose save fails shows a SnackBar and stays
  where it was, instead of the settings list being swapped for an error; the
  profile edit form's existing catch now runs and keeps the text.
- A timeout on the GET that follows a save answered with no trip keeps the trip
  on screen, and the save reports the error to its caller. The refusal that
  GET exists for still shows the no-access view.
- The edit-lock status read is forced as well: a failed one now returns
  nothing rather than a claim that had decayed in the cache, and `peek()`
  already treated a failure as nothing.
- Tests: `reload_keeps_content_test.dart` (every notifier held, answered, timed
  out, 5xx and 404; the in-flight write; the dropped page; `_adopt`;
  `updateProfile`), `trip_reload_keeps_content_test.dart` (the trip page with an
  open "view more" through an answered and a failed pull),
  `cache_error_test.dart` (a forced read is never answered from the cache) and
  `reload_keeps_content_guard_test.dart`, which fails on a loading or error
  write, an `AsyncValue.guard` or a `refresh()` outside the mechanism. Its one
  allowlisted class is `PlaceSearchNotifier`: a new query must not keep
  showing the previous query's results.
- The help centre is unchanged: no article describes what a screen shows
  during a reload, and the "please reload" troubleshooting entry stays true.

**Alternatives rejected.**
- `skipLoadingOnReload: true` / `skipError: true` at every `when()` call site:
  31 sites, each a place to forget, and `skipError` would also keep the content
  over a 403 or 404 — a trip deleted or taken away would stay on screen.
- A guard copied into each notifier: the two copies that existed already got
  the failure case wrong.
- Always applying the reload's answer: simpler, but with the content usable
  during a reload, the user's own write could be undone on screen.
- Keeping the cache's stale-on-error fallback for reloads: it hides every failed
  reload on a phone and can put back a copy older than the screen.
- Keeping the stored copies of partial answers current by patching cached list
  bodies: a bigger change that still would not reveal a failed reload.

### 2026-10-26 — A shared link opens where the reader already is; Copy link copies the link alone

Supersedes one consequence of
[2026-10-18 — Shared links open the app, and say plainly when they can't](#2026-10-18--shared-links-open-the-app-and-say-plainly-when-they-cant):
"iOS has no in-page **Open in app**".

**Context.** The owner reported five confusing behaviours. A share link opened in
a browser already signed in to the web app showed the teaser and its "free
account needed" gate: the server-rendered page had no way to know about the
session, whose tokens flutter_secure_storage keeps encrypted. On a phone with the
app, the page — reached by pasting the link, which no OS hands to an app — offered
the app only on Android, as a second button, and on an iPhone not at all. In the
web app, `/app/share/u/name` opened home (the app reads only the part after
`#`), and `/app/#/share/u/name` showed the profile under `#/profile/me`: go_router
never writes a pushed screen into the address bar, so a reload or a copied URL
lost every pushed trip and profile. And the share sheet's Copy copied the caption
with the link, where the owner wanted the link alone.
**Decision.**
- **Signed in on the web → straight in.** The web app keeps one plain
  localStorage entry while a session lasts, `ntripi_web_session_until` — the
  session's end, nothing else — written by `saveTokens` and removed by
  `clearAllTokens`. Each teaser page reads it in `<head>` and leaves with
  `location.replace` before the body is drawn.
- **A phone gets "Open in Ntripi".** On Android, Chrome's installed-app check
  (`getInstalledRelatedApps`, through `asset_statements` in the app and
  `/manifest.webmanifest` on the site) puts it first and drops the store badges
  when the app is installed, and hides it when it is not; an installed app also
  wins over a web session. On an iPhone it links a second host,
  `APP_OPEN_HOST` (`open.ntripi.app`), claimed beside `ntripi.app`: a tap across
  hosts is what iOS hands to an app. Without the app, Safari loads it and the
  host sends it back to the page with `?app=missing`, which says the app did not
  open. That host serves its association files and nothing else.
- **The web address bar shows the screen on top**
  (`GoRouter.optionURLReflectsImperativeAPIs`). Two rules follow: the app never
  starts on an editing form (a reload lands on what it edits), and a trip or
  profile URL opened signed out is parked through the sign-in like a shared
  link. Every route is classified one way or the other by a test. A page load of
  `/app/<path>` is redirected to `/app/#/<path>`.
- **The phone's own share popup gets a Copy link row**, through a method channel
  (`ntripi/share`): a `ChooserAction` on Android 14+, a first target before it, a
  `UIActivity` on iOS. The owner chose this over a sheet of the app's own. The
  web, whose popups take no row, gets a two-item menu — or, with no popup at
  all, the link copied at once. Sharing passes the tapped button as the popup's
  origin, which also fixes sharing on iPad.
**Consequences.**
- The app gains its first custom native code; a build without it falls back to
  share_plus without the row.
- The iPhone button waits on infrastructure: a Railway custom domain, a proxied
  CNAME, Apple's CDN serving the host's AASA, a build with the second
  `applinks:` entry, then `APP_OPEN_HOST`.
- iOS cannot tell a page that an app is installed, so an iPhone signed in on the
  web goes to the web app when a link is pasted into Safari, and readers without
  the app see the iPhone button too.
- A signed-in owner sees their own teaser only in a private window.
- A `/app/#/…` address still never opens the app; the app's Share and Copy link
  always hand out the `/share/` form, which does.
- The help article `share-a-trip-link` and What's New changed in all six
  languages.
**Alternatives rejected.**
- A server-side redirect keyed on a cookie the web app sets: the HTML would vary
  by cookie, and the app's session lives in localStorage anyway.
- Reading flutter_secure_storage's own localStorage keys from the page: a
  private format of a plugin, which a plugin update can move.
- Opening the app from script on page load: browsers refuse an intent or a
  cross-host navigation without a tap.
- A custom URL scheme: rejected on 2026-10-18 — any app can register one.
- The path URL strategy: every `/app/#/…` link already sent, in emails, help
  pages and share pages, would land on home.
- Leaving the address bar as it was: a reload and a copied URL keep losing the
  screen.
- A sheet of the app's own with Copy link and Share via…: the owner preferred
  the phone's own popup with one row added.
=======
### 2026-10-25 — Image moderation tells the operator when it cannot scan

Extends
[2026-07-27 — Image moderation as a two-tier, fail-open pipeline](#2026-07-27--image-moderation-as-a-two-tier-fail-open-pipeline):
fail-open stays, and stops being silent.

**Context.** In production every image scan failed for days and nobody knew.
The AWS account behind Rekognition had been closed, every
`DetectModerationLabels` call answered `UnrecognizedClientException`, and
`moderate_or_raise` failed open exactly as designed: a logged traceback, the
upload stored, an `error_allowed` row waiting in `/admin/flagged` as "Not
scanned". Nothing told anyone. A log line reaches only someone already reading
the logs, and a queue only someone who knows it is filling. Text moderation has
emailed the operator when its provider chain degrades since
[2026-07-30](#2026-07-30--text-moderation-with-our-own-policy-not-the-providers-verdict),
at most once an hour per level; images had nothing like it. Scanning switched
on with a credential missing was quieter still: a WARNING per upload, and every
upload stored as approved with no row at all.

**Decision.**
- `moderate_or_raise` emails the operator in two situations, each at most once
  an hour: a scan that raised (the fail-open branch), and
  `MODERATION_ENABLED=True` with a credential missing. `MODERATION_ENABLED=False`
  stays silent — a choice, not a failure. What is stored and logged is
  unchanged in both.
- The hook is where `moderate_or_raise` decides the outcome
  (`_notify_unscanned`), not in the provider client: Rekognition is about to be
  replaced, and the alert must outlive it. The provider's error code is read
  from botocore's shape by duck typing, so a new provider needs no change there.
- The hourly throttle, its WARNING line, the `OPERATOR_EMAIL` guard and the
  swallowed mail error move out of `text_moderation_service` into
  `operator_alerts.notify_operator`, which both tiers call. Text's subjects,
  bodies, levels and WARNING lines are unchanged. The check-and-claim now holds
  a lock: callers run on threadpool workers, and two could pass the check at
  once.
- The alert names the exception's class and the provider's error code, never
  the message or traceback — a provider's HTTP client can put the request URL,
  key included, in its message — and never the image, its key, the uploader or
  any content.
- Every image-tier operator email, the existing flag email included, is built
  on the event loop and sent with `asyncio.to_thread`. `moderate_or_raise` runs
  on the loop and `send_email` is a blocking `requests.post` with a 10 s
  timeout, so each flag email stalled every request on the server for as long
  as the mail provider took.

**Consequences.**
- With the dead key, the first upload emails `ops@` once and the uploads after
  it in that hour send nothing.
- The throttle is in memory, like slowapi's store, on the same single-process
  assumption. A restart or deploy re-arms it, so each deploy during an outage
  sends one more email.
- The upload that takes the hour's slot, and each flagged upload, still waits
  for its own send — at worst Resend's 10 s timeout. The loop never does, so no
  other request waits with it.
- An upload stored while scanning is unconfigured still leaves no audit row and
  never reaches `/admin/flagged`; the alert is its only trace.
- Text moderation's defensive "degradation email failed" log line is now the
  helper's, which names the key. `send_email` catches its own errors, so
  neither line has ever fired.

**Alternatives rejected.**
- Failing the upload when the scan cannot run: an outage at the provider would
  block every legitimate user. Fail-open was deliberate on 2026-07-27 and
  stays; what was missing was telling someone.
- Refusing to start when the provider is unreachable: a boot cannot know that
  without spending a paid call on every deploy, and it changes after boot —
  this key died while the app was running, which a startup check would never
  have seen. A refused boot would also take the whole app down over a degraded
  safety layer. The missing-credential case likewise keeps its documented
  storage behaviour and gains the alert, not a startup refusal.

### 2026-10-25 — Image moderation gains Google Cloud Vision; one variable picks the scanner

Extends
[2026-07-27 — Image moderation as a two-tier, fail-open pipeline](#2026-07-27--image-moderation-as-a-two-tier-fail-open-pipeline)
and
[2026-10-25 — Image moderation tells the operator when it cannot scan](#2026-10-25--image-moderation-tells-the-operator-when-it-cannot-scan).

**Context.** The AWS account behind Rekognition was closed, so every image scan
in production fails: each upload is stored as `error_allowed` and waits in
`/admin/flagged`, and since the entry above the operator is emailed about it
once an hour. A new key cannot revive a closed account, and nothing else could
scan.

**Decision.**
- Google Cloud Vision SafeSearch becomes a second image scanner beside
  Rekognition, and `MODERATION_PROVIDER` (`rekognition`, the default, or
  `google_vision`) picks which one runs. An unknown value refuses startup, like
  `TEXT_MODERATION_PROVIDER`. `MODERATION_ENABLED` stays the master switch.
  Rekognition's code, thresholds and variables are unchanged, so a deploy that
  sets nothing new behaves exactly as before.
- Each provider sits behind one seam in `moderation_service` (`_PROVIDERS`) that
  returns a verdict or raises, so `moderate_or_raise` keeps a single reject /
  flag / approve / fail-open path, and the "not configured" alert names only the
  selected provider's settings.
- Cloud Vision is one `requests.post` to `eu-vision.googleapis.com` with
  `parent=projects/{project_id}/locations/eu`, so images are stored and
  processed only in the EU. The body carries the image, the feature and
  `parent`, nothing else. The bearer is minted by google-auth from a key of its
  own, `MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON`, with the `cloud-vision` scope.
  The call and its token request get Rekognition's budget: 3 s to connect, 3 s
  to read, one attempt.
- The verdict is read on Google's levels: reject on `adult` or `violence` at
  `MODERATION_GOOGLE_REJECT_LIKELIHOOD` (`VERY_LIKELY`), flag on `adult`,
  `violence`, `racy` or `medical` at `MODERATION_GOOGLE_FLAG_LIKELIHOOD`
  (`LIKELY`), `spoof` ignored. Every answer that is not a verdict — an
  exception, a non-2xx status, a body that is not JSON, a per-image error, a
  missing annotation, an `UNKNOWN` or omitted `adult` or `violence` — goes to the
  fail-open branch and is never an approval.
- For Cloud Vision the alert's error code is Google's `error.status` plus the
  first `details[].reason` (`PERMISSION_DENIED/SERVICE_DISABLED`), read by
  `_provider_error_code` beside botocore's shape. The message is never read:
  Google's names the project and links to its console.
- `image_moderation_logs.provider` records the scanner on every scan row
  (`a989b5ce5994`; earlier scan rows backfilled `rekognition`, `rejected_csam`
  rows NULL). Google labels are stored as `{name, likelihood}`, and one
  formatter, `label_text`, renders both shapes in the flag email and on the
  admin pages.
- The service-account parsing, the PEM check and the cached token move out of
  `push_service` into `google_service_account`, keyed by variable and scope,
  with one lock per key. Push's log lines and its fail-open token handling are
  unchanged.
- Privacy 2.4 names Google Cloud Vision in §4 and §5, in all six languages,
  claiming only what Google's data-usage FAQ says; pinned by
  `test_privacy_names_every_image_moderation_provider`.

**Consequences.**
- Switching the scanner is a variable change. Production moves to Cloud Vision
  by setting the key and `MODERATION_PROVIDER=google_vision` once this is
  deployed, and Rekognition can come back the same way.
- The two providers' signals are not the same. SafeSearch has no self-harm or
  gore class of its own, and five levels are coarser than a percentage: by
  default only `VERY_LIKELY` rejects and `LIKELY` flags.
- An audit row's labels now come in two shapes, and whatever reads them must
  handle both — today that is `label_text`. Rekognition's flag email lists its
  labels as `Suggestive (60%)` instead of `Suggestive: 60.0%`, and a takedown's
  evidence row no longer renders as `csam_hash_match (0%)`.
- Rekognition's answer is now read inside the fail-open `try`, so a malformed
  one fails open instead of returning a 500.
- The Cloud Vision token is minted inside an upload about once an hour.
  google-auth still makes up to three attempts on a 5xx from the token
  endpoint, each bounded to 3 s + 3 s.
- The translated privacy texts, the 2.4 paragraphs included, still need counsel
  review; English is authoritative.

**Alternatives rejected.**
- A fallback chain across providers, as text moderation has: each image would
  reach a second processor exactly when the first was failing, the audit row's
  provider would depend on an outage, and with the AWS account closed the second
  tier would fail too. Text's chain falls back to a free local wordlist; images
  have no such tier. One variable keeps which processor saw an image a
  deliberate choice.
- The `google-cloud-vision` SDK: gRPC and a large dependency, and it bypasses
  `requests.Session.send`, so a slow scan would never show in the slow-request
  log.
- Mapping Google's levels onto percentages, to reuse the `MODERATION_*_THRESHOLD`
  pair: the audit row would claim a confidence Google never gave.
- Reusing FCM's service-account key: one key per job, so revoking either never
  stops the other.
- Sightengine: its finer gore and self-harm classes did not outweigh EU-only
  routing being available on its Enterprise plan only.
- Hive: US-only.
- OpenAI's image moderation: US.
>>>>>>> ntripiworktree
