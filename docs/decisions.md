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
