# Backlog

Ideas and unbuilt work found referenced in the code, comments, tests, specs and
plan files. Each item carries its **status**, its evidence, and why it is not
built.

- **idea** — referenced somewhere, no commitment
- **planned** — a decision has been made, or an insertion point is already marked
- **in-progress** — code exists but is inert or incomplete

The codebase has only **two literal `TODO` markers**. Nearly every `TODO` grep
hit is the Spanish word *todo* in the `es` locale and help/legal modules, so the
real backlog was recovered from prose comments, skipped tests, un-vendored
assets and unticked operator checklists.

---

## Test coverage

### idea — migration-only schema objects cannot be tested

The suite builds its schema from ORM metadata on SQLite, so `COLLATE "C"` on both
rank columns and both partial feed indexes are never exercised. Migration
`12b6e3451c36` records what this cost once. Either declare them in
`__table_args__` or add a PostgreSQL-backed test lane. →
[reference/data-model.md](reference/data-model.md#migration-only-objects)

---

## Half-built features

### planned — Apple Sign-In is a live button that says "Coming soon"

`features/auth/presentation/login_screen.dart:318`:

```dart
if (isApplePlatform()) ...[
  … onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.comingSoon)))
```

`comingSoon` (`app_en.arb:512`) has **no other use site in the app**. The
historical parallel is exact: `f44d75d` (2026-05-18) added the same placeholder
for Google, and Google shipped a month later (`eb63f28`). Apple never did.

App Store review expects Sign in with Apple where a third-party social login is
offered, so this is on the release path. → [features/authentication.md](features/authentication.md)

### in-progress — the client NSFW pre-check is inert on both platforms

Neither model file is vendored, by design — they are large binaries — so the tier
is a no-op everywhere.

- **Mobile** — `core/moderation/nsfw_precheck_io.dart:8`: *"The model file
  (assets/models/nsfw_mobilenet.tflite, ~3 MB) is NOT vendored in the repo; see
  assets/models/README.md for how to source it. Until it's dropped in, this tier
  is a no-op."* The required contract is documented: input `[1,224,224,3]` float32
  RGB `/255`, output `[1,5]` softmax over `drawings, hentai, neutral, porn, sexy`.
- **Web** — `social_flutter/web/nsfw/README.md`: TensorFlow.js and NSFWJS weights
  are not committed; `load()` fails gracefully. Everything must stay same-origin —
  *"Do **not** switch `nsfw_glue.js` back to a CDN URL."*

The backend image scan is the actual authority, so this is a cost and UX
gap, not a safety one. → [features/image-moderation.md](features/image-moderation.md)

### in-progress — push notifications are code-complete but not provisioned

Two external blockers:

- The Android API key's `(package, SHA-1)` restriction **silently blocks token
  registration** — no error, no token.
- The APNs `.p8` has not been uploaded to Firebase.

The backend is safe unconfigured: with `FCM_PROJECT_ID` or
`FCM_SERVICE_ACCOUNT_JSON` unset, nothing is sent and nothing raises, and the
60-second poll behaves exactly as before. → [features/notifications.md](features/notifications.md)

### in-progress — translation is code-complete but switched off

Every layer ships dark (2026-10-07): `POST /translations` 404s and the app draws
no button until `TRANSLATION_PROVIDERS` is set. Switching it on is operator
work, in this order: run `scripts/backfill_source_lang.py` (dry run first) in
the Railway container; create the Azure Translator F0 resource and set
`AZURE_TRANSLATOR_KEY` / `_REGION`; add an OpenAI budget alert; deploy Privacy
2.3 and the help article **before** enabling (an undisclosed processor is a
GDPR breach); set `TRANSLATION_PROVIDERS=openai,azure`; smoke-test in `fr` and
`ar`; then update the App Store privacy label and Play Data safety for
Microsoft. Not yet done: a manual end-to-end run against real keys.
→ [features/translations.md](features/translations.md#operations)

### planned — the Google birthday half of the age gate is blocked externally

`user.birthday.read` is a **sensitive scope** requiring Google verification
review: a 100-test-user cap and an "unverified app" warning until it clears. The
consent-sheet fallback is what let everything else ship.

Two unticked store-compliance tasks ride along: **App Store privacy nutrition
label** and **Play Data safety** both need the date of birth declared. →
[features/legal-and-age-gate.md](features/legal-and-age-gate.md)

### planned — auto-generated per-itinerary OG preview images

The repo's **one real code-adjacent TODO**, `app/static/README.md:15`:

> TODO (Jira Ticket 3): Replace with dynamic per-itinerary preview images
> generated from the itinerary's cover image + title overlay.

The insertion point is already marked in `share_service.py:170`: *"1.
User-uploaded cover image (Phase 1 — this release). 2. Auto-generated map image
(Phase 2 — future) … Phase 2 map-image fallback goes here."* →
[features/sharing.md](features/sharing.md)

### idea — "Phase 2b: whole-track reorder"

Referenced by name in `move_stop_to_track_sheet.dart:20`, which clears segments
now specifically so a future Phase 2b restoring track adjacency cannot resurrect a
stale one. Sibling phases are labelled in `reorder_parallels_sheet.dart:11`
(Phase 2a) and `move_stop_to_track_sheet.dart:4,9` (Phase 2c). →
[features/tracks-and-stops.md](features/tracks-and-stops.md)

---

## Error-contract cleanup

### idea — 11 `AuthError` sites share one error code

All carry the default `code="auth_error"` (`auth_service.py` lines 212, 247, 417,
421, 518, 526, 529, 534, 583, 587). The client localizes by code, so these are
indistinguishable: "Google account has no email", "email already registered, use
your password", "reset link invalid", "verification link invalid", "no password
set", "current password incorrect", "can't reuse a recent password", "password
appeared in a breach".

**The last four all surface on the change-password screen and need different
UI.** → [features/authentication.md](features/authentication.md)

### idea — reachable `HTTPException` raises with no code

`follows.py:125` (409 already following / pending) · `itineraries.py:250` (400
stop not in itinerary) · `:491,502,547,559` (422 bad rank anchors) ·
`:1526–1578` (422 reorder validation, six distinct messages) · `:2172` (409
duplicate leg position) · `users.py:446,499` and `itineraries.py:2261` (400
`ImageProcessingError`, **user-facing and untranslated**).

### idea — `reject_follow_request` leaks what `accept` hides

`follows.py:338` answers **403 `cannot_reject_request`** where
`accept_follow_request` answers **404 `follow_request_not_found`** for the
identical condition — and the accept path carries an explicit comment saying 404
exists "to avoid leaking the existence of other users' requests". →
[features/follows.md](features/follows.md)

### idea — `POST /reports` answers `itinerary_not_found` for every target type

`reports.py:82`, including a `rating` or `user` target. Either deliberate
uniformity or a copy-paste; nothing records which.

---

## Unenforced invariants

### planned — a model docstring asserts a rule nothing checks

`models/transit_segment.py:5` — *"A TransitSegment lives strictly between two
adjacent stops (`from_stop.position + 1 == to_stop.position`)"*. The `position`
column was removed by `d5e6f7a8b9c0`, and `_require_stops_in_itinerary` checks
only itinerary membership. **Adjacency is enforced nowhere.** Either the comment
is stale or a check is missing. (Its sibling — `models/transport_leg.py:20`,
"deleting the last leg deletes the segment" — is enforced by `delete_leg` since
2026-09-26.) → [features/transit-segments.md](features/transit-segments.md)

### idea — `Stop.outgoing_segment` is one-to-one in the ORM, one-to-many in the data

`models/stop.py` declares `outgoing_segment` / `incoming_segment` with
`uselist=False` and the comment "at most one per stop", but the only constraint is
`UNIQUE(from_stop_id, to_stop_id)`. A stop before a track of parallel
alternatives legitimately has one segment into **each** of them, and the client
already treats it that way (`stop_detail_screen.dart` filters a list). Its one
reader was the public share page, which rendered one arbitrary segment per stop;
since 2026-10-19 that page shows a teaser and loads no stops, so **nothing reads
the relationship now** — the mismatch is latent and bites the next reader, who
should take `uselist=True` (and a decision on how a branch reads) rather than the
first row. Deletion is unaffected — the DB `ON DELETE CASCADE` removes the rest.
→ [features/transit-segments.md](features/transit-segments.md)

### idea — `moderate_or_422`'s documented precondition is not held

Its docstring says the caller "must not have added rows to the session", but
`require_edit_access` writes the lock heartbeat before the endpoint body runs, so a
rejected PATCH commits that write. Harmless in effect; the contract is wrong as
written. → [features/text-moderation.md](features/text-moderation.md)

### idea — the profile's image cache calls can fail a write that landed

`MyProfileNotifier`'s avatar and cover uploads seed the image cache with the new
bytes (`_refreshImageCache`: evict, then `putFile`) after the upload landed, and
its deletes clear the cache (`_evictImageCache`) before the delete is sent —
both straight through `CachedNetworkImage`/`NtripiImageCacheManager`. A cache
that throws turns a landed upload into an error the edit form reports, and
stops a delete before it is sent. Itinerary covers already go through the
best-effort `ImageCacheEviction` (2026-10-25); the profile's calls could do the
same, with the seed best-effort too. → [features/accounts-and-profiles.md](features/accounts-and-profiles.md)

### idea — the reloads the app starts with `ref.invalidate` can still blank a screen

A `refresh()` keeps content on screen through any failure but a refusal
(`ReloadKeepsContent`, 2026-10-25), and the guard test holds every one of them.
The reloads the app starts after a write whose answer cannot carry the result
go through `ref.invalidate` instead, outside both: the feed after a block or
unblock and my Following list after a follow (`profile_screen.dart`),
someone's Followers list and trips after an unfollow and their Following list
after a removal (`follow_actions.dart`), and the blocked users list after a
block or unblock (`ugc_actions.dart`, `blocked_users_screen.dart`). Riverpod keeps the
old value on screen while such a rebuild runs, but a failed one replaces it
with the error view. They target screens that are usually closed at that
moment; giving each provider a `refresh()` and calling it would close the gap.
→ [constraints.md](constraints.md)

---

## Policy calls left by the 2026-09-28 sweep

Found while debugging and verified in the code, but each is a decision rather
than a bug, so none was changed.

### idea — an anonymous IP counts again once its hash is scrubbed

`scrub_expired_ip_hashes` nulls hashes past the rate window, after which
`has_pending_report_by_ip` no longer sees the earlier report, and
`count_distinct_reporters` counts every hash-less row as one reporter "apiece" —
deliberately, so an attacker cannot age out evidence. The side effect: one IP can
reach a threshold by reporting once a day (`harassment:2` in two days). →
[features/content-reports.md](features/content-reports.md)

### idea — reviews by banned users stay visible and counted

The ratings page joins `User` but never checks `is_active`, and
`recalculate_rating` counts the stars. A banned owner's itineraries are hidden;
a banned rater's review is not. Hiding it also means recounting every itinerary
they rated at ban time. → [features/ratings.md](features/ratings.md)

### idea — a replaced itinerary cover keeps its URL

Itinerary covers use `cache_bust=False` by design (documented in CLAUDE.md), so
a replacement reuses `itineraries/{id}.jpg` and URL-keyed image caches
(CachedNetworkImage, the browser) keep the old picture until they expire. R2's
`max-age=3600` bounds only the CDN. → [features/image-pipeline.md](features/image-pipeline.md)

### idea — password reset skips the reuse and breach checks

`change_password` refuses a recently used or breached password; the email reset
path does not. And `forgot_password` does a write, a commit and a mail call only
when the account exists, so its latency leaks existence despite the
enumeration-safe body (`/web/appeal-request` has the same shape). →
[features/passwords-and-email.md](features/passwords-and-email.md)

### idea — smaller loose ends

- `create_appeal` does not check that the action is still in force; the feed
  hides lifted actions, but the endpoint accepts them.
- `jira_service._summary` collapses the whole message, not the first line its
  docstring promises.
- Deleting a transport leg has no confirmation or undo (`leg_form_dialog.dart`).
- A leg's thoughts, shown to readers since 2026-10-08, have no report target
  of their own — `ReportTarget` has no leg kind, so a viewer reports the stop
  or the trip. → [features/transit-segments.md](features/transit-segments.md)
- The client drops a leg's `note_type` on every segment save: no control writes
  it and `LegEditor.legToMap` omits it. Give it a control or retire the column.
  → [features/transit-segments.md](features/transit-segments.md)
- A request that reaches Railway directly, bypassing Cloudflare, can forge
  `CF-Connecting-IP` as easily as `X-Forwarded-For` — closing that is edge
  configuration (restrict the origin to Cloudflare), not app code. →
  [features/web-and-platform.md](features/web-and-platform.md)

---

## Dead and unread code

### planned — retire `POST`/`DELETE /itineraries/{id}/image`

Since 2026-10-21 the app changes an itinerary's cover only through the form
routes (`POST /itineraries/form`, `PATCH /itineraries/{id}/form`), which check it
with the fields under the edit lock and `If-Match`. The pair stays, unchanged,
because builds already installed upload through it — and a build that still does
keeps the 412 described in [decisions.md](decisions.md). Remove both routes,
their `OWNER_ONLY` rows in `test_edit_guard_coverage.py` and their tests once no
build in testing calls them; the request-timing log at `SLOW_REQUEST_LOG_MS=0`
shows whether anything still does. Do not "fix" their 412 with
`set_preserving_etag` in the meantime — that was the rejected alternative.
→ [features/image-pipeline.md](features/image-pipeline.md)

### idea — delete `segment_form_screen.dart`

The entire file body (line 12 onward) is wrapped in a `/* */` block, with
`//--TODO: In the future we could consider deleting this from because no need of
it.` above it. **The only commented-out code block in all of `lib/`.** Left
behind by `7025987` (2026-05-05, *"bypass the concept of segement"*). Its two
apparent references are prose mentions in comments. →
[features/transit-segments.md](features/transit-segments.md)

### idea — a decorative message button with no action

`features/profile/presentation/widgets/follow_action_row.dart:39` — *"Decorative
message button placeholder — not yet wired to a route."* A 46×46 mail-icon
`Container` with no `onTap` ships to users. Either wire direct messaging or remove
the affordance. → [features/accounts-and-profiles.md](features/accounts-and-profiles.md)

### idea — four backend endpoints have no client

`GET /itineraries/{id}/segments` (Flutter reads segments from the detail payload)
and the three `/legs` writes (the segment PATCH does a full replace). Documented
as "for future API consumers" in `api_endpoints.dart:199` and
`social_api/README.md:328`, but there is no public API programme. Also
`GET /users/by-username/{username}`, a functional duplicate of
`GET /users/{identifier}`.

### idea — written-and-never-read columns and helpers

| Thing | Note |
|---|---|
| `security_audit_log` | holds three `event_type` values; **no endpoint, admin lane or query in `app/` reads the table** |
| `refresh_tokens.rotated_to` | written at rotation, documented "informational" |
| `refresh_tokens.user_agent` | captured for a **"list active sessions" UI** its docstring anticipates, which does not exist |
| `waitlist.platform` | written, read nowhere — no admin lane, no export |
| `Storage.exists()` | on the ABC, implemented by both backends, **no caller anywhere** |
| `ResetPasswordRequest` (`schemas/auth.py:141`) | defined, referenced by no router or test |
| `MODERATION_LOG_SYSTEM_ACTIONS`'s `"recheck"` | permitted by the CHECK; nothing writes it |

---

## Operations and compliance

### planned — `media_pipeline_spec.md` §5: eight unticked operator steps

R2 bucket + token · proxied custom domain · enable CSAM Scanning · Railway vars ·
run `scripts/migrate_to_r2.py` · verify and detach the Railway volume · fill in
the runbook counsel block · **optional: register with NCMEC as an ESP**.

The spec's header still reads *"implemented in code; awaiting the operator steps
in §5."* It also carries a one-way-door warning: rollback only restores files
never deleted from the volume.

### planned — `csam_response_runbook.md` needs counsel sign-off

**§6 is a six-row decision table with an unticked `Signed off ☐` column** —
reproduced in [decisions.md](decisions.md). Line 23: *"Get counsel to review §6
before going live — the stances there are engineering defaults, not legal
advice."* §5's counsel contact block is an empty fill-in form, and **§7's six
readiness boxes are all unticked**, including *"Calendar reminder for a quarterly
dry run"*. → [features/content-reports.md](features/content-reports.md)

### planned — legal translations need counsel review

Three documents × six languages. English is authoritative and every other
language carries a prevailing-language clause, which bounds the exposure in the
meantime. → [features/legal-and-age-gate.md](features/legal-and-age-gate.md)

### planned — a hardcoded Google Maps Embed key in the Dockerfile

`Dockerfile:15` — `--dart-define=GOOGLE_MAPS_EMBED_API_KEY=AIzaSy…`, against the
project's own "never hardcode secrets or environment values" rule. An Embed key
necessarily ships to the client and this one is referrer-restricted, so exposure
is not the issue; it is a **committed, un-rotatable build constant**.
`API_BASE_URL` and `SHARE_BASE_URL` are hardcoded there too, which is what stops
one image serving a staging environment. → [constraints.md](constraints.md#known-deviations)

### planned — `.env.example` is 14 settings behind

69 declared, 55 documented. **Three of the missing ones are validator-backed**
(`EDIT_LOCK_*`), so an operator has no discoverable way to learn constraints that
will refuse to boot. Full list in
[constraints.md](constraints.md#envexample-is-14-settings-behind).

### planned — the ratings clause says "score only", but deletion keeps the review text

The ToS and Privacy §10 promise a deleted account's ratings are kept as "score
only"; `delete_my_account` nulls `user_id` and leaves the `note` (and its cached
translations). Either the deletion clears the note or both documents change. →
[features/legal-and-age-gate.md](features/legal-and-age-gate.md#open-questions)

### idea — `POST /waitlist/join` has no rate limit

Every other public POST does. Its body schema is also the only one defined inline
in a router rather than in `schemas/`.

### idea — transitive dependencies resolve fresh on every build

`requirements.txt` pins only top-level packages and the Dockerfile runs a plain
`pip install -r`, so every Railway build installs the newest versions the
dependencies allow. FastAPI 0.135.1 asks only for `starlette>=0.46.0`: on
2026-10-07 the image resolved **Starlette 1.7.0** while the dev venv tested
0.52.1, and 27 other transitive packages differed (cryptography 46 → 50,
websockets 16 → 17, …). The suite happened to pass against that resolution
(1898 passed), but nothing keeps the next build's set equal to the tested one. A
constraints file generated from the tested venv and installed with `-c` would
make the image reproducible. → [web-and-platform.md](features/web-and-platform.md)

### idea — Redis-backed rate limiting, gated on horizontal scaling

The in-memory store is documented as single-instance-only in **four** places
(`limiter.py:12`, `main.py:219`, `social_api/README.md:535`, `CLAUDE.md:87`), plus
the operator-alert throttle (`operator_alerts.py:30`). Nothing records the
threshold at which it becomes necessary.

### idea — reporter reputation weighting

`report_service.py:41` names the feature, says "when it arrives", and
pre-designates the insertion point: *"it belongs in `_effective_threshold`, which
is the only place that decides how many reporters are 'enough' — nothing else
needs to change."* → [features/content-reports.md](features/content-reports.md)

### idea — admin provisioning UI

`models/user.py:80` — *"Set manually via SQL — there is no API or UI to promote a
user (single-operator model)."* Needed when a second operator exists.

### idea — outbound email authentication

The `temporal-wondering-walrus` plan (which shipped as `428088c`, 2026-08-30,
wiring the four `@ntripi.app` mailboxes into the app) also flagged **incomplete
SPF / DKIM / DMARC** on the sending domain. Whether that half shipped is not
visible from the repository — it is DNS state. → [constraints.md](constraints.md#mailboxes)

---

## Translation

Deferred when "See translation" shipped (2026-10-07). →
[features/translations.md](features/translations.md)

### idea — DeepL as a third engine

`translation_providers.py` takes a new engine as one class plus a
`_FACTORIES` entry and a name in `TRANSLATION_PROVIDER_NAMES`. Azure already
covers the fallback role at no cost, so there was nothing to gain yet.

### idea — a translation language other than the app's

The target is always the app language, on both sides. A reader who wants the
app in English but trips in Spanish has no way to say so. Translations are
already wrapped in a `Directionality` by their own language, so the client
would render one correctly.

### idea — stop names

Excluded because nothing records whether the author typed a name or the form
imported it from Nominatim or a Google Maps link — translating an imported
place name breaks the match with signs and maps. Needs a provenance column on
`stops` first.

### idea — leg notes for viewers

`transport_legs.notes` is translatable on the server, but only
`leg_form_dialog.dart` ever shows leg notes. Showing them to viewers comes
first; the client half of translating them follows, and `TransportLeg` gains
its `sourceLang` then.

### idea — the surfaces that still show originals

Saved, profile and shared-with-me lists (the feed alone carries
`title_translation`); the profile bio (not in the registry); the public
`/share/*` page (signed-out visitors get nothing, by decision).

### idea — originals laid out by their own language

An Arabic review in an English app renders left to right. Only translations
are wrapped by their language; originals take the app's direction. The
detected `source_lang` is already on every row.

### idea — a "translate" button in `/admin`

Moderators read reports in languages they may not speak. It would need its own
budget line, since it is not a reader's quota.

### idea — expiry for cached translations

Rows live as long as their source text. A TTL would let a better model replace
old answers; nothing needs it yet.

### idea — Microsoft attribution

Microsoft *recommends* a "Translated by Microsoft" line on Azure output; it is
not required. The client does not know which engine answered a field (the
`provider` key is parsed but not shown).

### idea — three-letter spoken-language codes

Profile `languages` allow 2–3 letter codes; lingua returns ISO 639-1. A reader
who listed a three-letter code never matches, so the feed shows them the
translated title.

### idea — Simplified and Traditional Chinese

lingua reports `zh` without telling them apart, and `zh` is the one Chinese
target (`zh-Hans` at Azure). A reader of the Simplified app gets no toggle on
Traditional text detected as `zh`.

---

## Follows

### idea — a "Follows you" label on profiles

`UserPublicProfile.follows_you` (2026-10-18) exists so the ⋯ menu offers
**Remove follower** only when it applies. The same flag could label a profile
"Follows you", as most social apps do — nothing renders it yet. →
[features/follows.md](features/follows.md)

### idea — the follow lists refresh only when pulled

Accepting a request takes it off the requests section but does not add the
person to ALL FOLLOWERS until a pull-to-refresh, and following someone from
their profile does not refresh their Followers list or the trips shown on their
profile. The row actions sync every cache they touch (`follow_actions.dart`);
these two older paths were left as they were. →
[features/follows.md](features/follows.md)

### idea — the Decline ✕ pill has no accessible label

`_ActionPill` became a `Semantics` button on 2026-10-18 and the new row pills
announce whom they act on, but the Decline pill on a request row is icon-only:
a screen reader hears "button" and not whose request it declines. Needs a
`declineRequestSemantics(username)` key in the six `.arb` files. →
[features/follows.md](features/follows.md)

---

## Roadmap

### idea — the three features named in the root README

`README.md:283`, the only explicit roadmap line in the repository:

> Upcoming: posts feature, real-time feed, native app store distribution.

- **Posts** — no schema, no endpoint, no screen. Entirely unstarted.
- **Real-time feed** — the current feed is a paginated poll. Would need a push
  channel; FCM exists but is scoped to notifications.
- **Store distribution** — the app is pre-launch; every download button opens the
  waitlist, and the help CTA points at `/#get-the-app` precisely because a
  hardcoded store URL would ship dead. The share pages' buttons already follow
  `APP_STORE_URL` / `PLAY_STORE_URL` (2026-10-18); the homepage's do not yet —
  see below.

### planned — the homepage's store buttons follow the store URLs at launch

The share pages send their download buttons to `APP_STORE_URL` / `PLAY_STORE_URL`
once set, but `home.html`'s three download buttons still open the waitlist, and
its `#get-the-app` hash handler — what the help CTA and the share pages' nav
button land on — opens the waitlist too. On launch day those should read the same
settings, or the share pages and the homepage disagree about whether the app can
be installed. → [features/app-links.md](features/app-links.md)

### idea — open the shared trip after installing (deferred deep linking)

Installing the app from a share page does not open the shared trip on first
launch. Android can carry it through the Play Store URL's `referrer` and the Play
Install Referrer API; iOS has no equivalent without a third-party attribution
service or the clipboard, both of which bring privacy questions of their own.
Until then the share page, once a store is live, tells a phone visitor to tap
the link again after installing — the same link then opens the app. →
[features/app-links.md](features/app-links.md)

### planned — image keys nobody can guess (share teaser, step 2)

Covers and avatars are stored at keys derived from published ids
(`itineraries/<trip id>.jpg`, `avatars/<user id>.jpg`, `covers/<user id>.jpg`) on
the public image domain, so a private trip's share link leads straight to its
cover and an avatar URL gives away the profile cover. Approved 2026-10-19: a
random part in every key, a re-key script for the existing objects, and
`parse_storage_key` accepting both forms. → [features/sharing.md](features/sharing.md)

### planned — public trips and profiles findable by search and answer engines (share teaser, step 3)

Approved 2026-10-19: `sitemap.xml` lists every live public trip and public
profile; `robots.txt` refuses the six AI training crawlers (GPTBot, ClaudeBot,
CCBot, Bytespider, Google-Extended, Applebot-Extended) while search engines and
answer bots stay welcome, enforced by Cloudflare's AI Crawl Control; and the
app, the help centre and the Privacy Policy say that "public" means findable.
→ [features/sharing.md](features/sharing.md)

### idea — open more of the teaser if search engines will not index it

A trip with no description is a title, a photo and a rating. Once the sitemap
ships, Search Console shows whether such pages are "crawled — not indexed"; if
so, the next layer to open is a template change. Opening is reversible; what a
crawler has read is not. → [features/sharing.md](features/sharing.md)

### idea — language in the share URL, so Cloudflare can cache share pages

The share pages' chrome language comes from a cookie or `Accept-Language`, and
Cloudflare varies its cache on `Accept-Encoding` only, so caching them at the
edge would serve one visitor's language to everyone. Reading the language from
`?lang=` alone — as the help centre's machine surfaces do — would make the URL
the whole cache key. → [features/sharing.md](features/sharing.md)

### idea — site-wide dark mode

No page on ntripi.app honours `prefers-color-scheme`. The share pages copy the
app's light tokens only, so a visitor in dark mode goes from a white page to a
dark app on sign-in. A dark set belongs in every template at once, not the share
pages alone. → [features/web-and-platform.md](features/web-and-platform.md)

### planned — turn on the iPhone "Open in Ntripi" (operator rollout)

Built on 2026-10-26 and off until configured: add `open.ntripi.app` as a Railway
custom domain with a proxied Cloudflare CNAME (the Bot Fight skip rule must cover
its `/.well-known`), check Apple's CDN serves its AASA
(`app-site-association.cdn-apple.com/a/v1/open.ntripi.app`), ship a build with the
second `applinks:` entry, then set `APP_OPEN_HOST=open.ntripi.app`. →
[features/app-links.md](features/app-links.md#opening-the-app-from-the-page)

### idea — claim `www.ntripi.app` too

Only the apex is claimed. Every link the app builds uses `SHARE_BASE_URL`
(`https://ntripi.app`), so this matters only for links people type or rewrite;
claiming it means serving both association files on `www` without a redirect. →
[features/app-links.md](features/app-links.md)

### idea — web push

`models/device_token.py:34` — *"Web push needs a service worker and a VAPID key
that this build does not ship, so it is deliberately not accepted."*
`DEVICE_PLATFORMS = ("ios", "android")`. The same note appears at
`core/push/push_service.dart:10`. Web is poll-only by design.

### idea — a web tab closed while editing still holds the trip

On the web the edit-claim journal lives in the tab's `sessionStorage`
(2026-10-15) — the one storage that survives a reload without being shared by
other tabs — so a *closed* tab takes its entry with it, and its claim reads as
"you, on another device" in the next tab until **Continue here**. The Web Locks
API could tell a closed tab from a live one: each tab holds a named lock for its
lifetime, the journal moves to `localStorage`, and an entry whose tab no longer
holds its lock is a leftover. →
[features/collaborative-editing.md](features/collaborative-editing.md)

### idea — `/help/whats-new` is thin

`RELEASES` holds two entries (`0.3.0`, `0.4.0`). The trap that came with it —
`releases()` falls back **whole**, so an entry added only to `en.py` left the
other five languages an outdated What's New — is closed:
`test_every_language_lists_every_release` fails the suite for it.
→ [features/help-centre.md](features/help-centre.md)

### idea — housekeeping

An abandoned `.CLAUDE.md.swp` (16 KB, untracked, dated 2026-04-23) sits in the
repo root. `storage/filesystem.py:7` still calls itself "Phase 1 implementation"
although R2 superseded it on 2026-05-02, and `app/static/README.md` claims the
default OG PNG is "not committed to version control" although it is on disk and
tracked.

---

## Documentation drift

Recorded because a reader who trusts these will be wrong. None is a code change.

| Document | Stale claim |
|---|---|
| `README.md` | 24-hour JWT (really 15 min + refresh); `ACCESS_TOKEN_EXPIRE_MINUTES=1440` (default 15); "auto-logout on **any** 401" (really codeless-401 only); ratings list omits crowdedness; `features/users/` (really `profile/`); a 4-row Flutter test table against 62 backend test files; `is_private` "default false" (the model default is `True`); `GET /` described as returning `{"status":"ok"}` (that is `/health`) |
| `social_api/README.md` | documents **11 of 30** tables; the endpoint tables omit ~60 endpoints; still documents the dropped `itineraries.safety_rating`; `Storage backend (filesystem or s3-compatible)` predates the R2 decision |
| `social_flutter/README.md` | still presents transit segments as a current feature after `7025987` bypassed the concept; names no unbuilt work at all |
| `dependencies.py:110` | `require_verified_email`'s message says verification happens "only by signing in with Google", but `/auth/register` emails a link and `/verify-email` sets the flag |

`docs/` supersedes the schema and endpoint sections of both backend READMEs. →
[README.md](README.md)

---

## Performance

### planned — saves still take 1–1.5 s; the bar is under one second

After Postgres moved to the API's region (2026-10-20,
[decisions.md](decisions.md)), the owner timed five actions on the phone, from
tapping Save to seeing the result: create a trip 1.3 s, add a stop 1.0 s, edit
the description 1.1 s, add a trip note 1.5 s, rate a trip 1.51 s. A local replay
at a 2 ms database delay puts server time at 0.07–0.17 s per action, plus about
0.1 s of network per request, so 0.6–1.1 s per action is unaccounted for. The
owner set the bar at under one second per action, timed the same way.

Next step: set `SLOW_REQUEST_LOG_MS=0` on Railway, do each action twice, read
the `slow request:` lines, then put the threshold back. The candidates those
lines will rank:

- **The OpenAI moderation call on every text save** —
  `TEXT_MODERATION_PROVIDER=openai` in production. Even a refused request to
  `api.openai.com` takes about 0.2 s from Belgium, and a real check adds the
  model's time. Moderation runs before the write by design (a reject is a 422 and
  nothing is stored), so taking it off the request would be a policy reversal,
  not tuning.
- ~~**The reload after every save**~~ — **done 2026-10-21.** The log showed it
  after every stop, note and rating save: 43–68 ms of server time plus a round
  trip, and a full-screen rebuild of the trip view. Every trip edit now answers
  with the whole trip (`?return=itinerary`) and a rating with the trip's
  aggregate, which the app adopts; nothing follows a save
  ([decisions.md](decisions.md)). To check after a deploy: with
  `SLOW_REQUEST_LOG_MS=0`, no `GET /itineraries/{itinerary_id}` line follows a
  save's line.
- **First requests after a restart** — the language detector loads a model the
  first time it meets a language, and imports and pool connections warm up.
- ~~**Rating only** — the push to the trip's owner is sent inline, before the
  response~~ — **done 2026-10-22**, for every push, not only the rating's: the
  request queues it after commit and one background worker sends it, so no
  write waits on FCM ([decisions.md](decisions.md)). To check after a deploy:
  with `SLOW_REQUEST_LOG_MS=0`, a rating of someone else's trip shows no
  `ext=fcm.googleapis.com`, and the owner's phone still gets the push.
- ~~**The waits after other writes**~~ — **done 2026-10-22.** Creating a trip
  downloaded it, a grant or revoke reloaded the owner's trip, a follow or block
  re-read `/users/me`, accepting the terms re-read it too, an appeal re-read the
  Account status list, a rating on the Ratings page re-read the page, and stop
  and header saves re-downloaded the Itineraries tab's lists. Each now answers
  with what the screen shows next and the app adopts it
  ([decisions.md](decisions.md)). To check after a deploy, with
  `SLOW_REQUEST_LOG_MS=0`: no GET of a trip after its create, of
  `/itineraries/me` or `/shared-with-me` after a save, of `/users/me` after a
  follow write or accepting the terms, of `/appeals/violations` after an
  appeal, or of `…/ratings` after a rating from that page.
- ~~**A new connection for most requests**~~ — **done 2026-10-25.** Dio's
  adapter closed an unused connection after 3 s, so nearly every save, every
  lock heartbeat and every notification poll paid a TCP and TLS handshake:
  90–125 ms to the first byte from Belgium, against 40–60 ms on a connection
  already open. The app now keeps it for two minutes and starts over after
  leaving the app or changing network ([decisions.md](decisions.md)). The
  server's timing line cannot show it, because it starts after the handshake.
  To check on a phone: DevTools' Network tab shows two saves a minute apart on
  the same local port.
- **The phone** — the closing animation of the form or dialog. (The trip
  screen no longer redraws behind a reload.)

→ [features/web-and-platform.md](features/web-and-platform.md)

### idea — delta answers merged in the app

**Tracked in Jira.** A save could answer with only what it changed — the stop,
the note, the totals — for the app to merge into its copy of the trip, instead
of the whole trip it answers with since 2026-10-21. It was rejected for now: it
needs about a dozen merge paths in the app, each free to drift from what the
server holds, where adopting the whole trip has one. Worth revisiting only if a
trip's full answer grows large enough to cost noticeable time on a phone
connection. The opt-in leaves room for it: a `?return=` value of its own, which
servers without it refuse with a 422 rather than answering a shape the client
cannot read. → [features/itineraries.md](features/itineraries.md),
[decisions.md](decisions.md)
