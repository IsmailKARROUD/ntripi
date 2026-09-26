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

The backend Rekognition scan is the actual authority, so this is a cost and UX
gap, not a safety one. → [features/image-moderation.md](features/image-moderation.md)

### in-progress — push notifications are code-complete but not provisioned

Two external blockers:

- The Android API key's `(package, SHA-1)` restriction **silently blocks token
  registration** — no error, no token.
- The APNs `.p8` has not been uploaded to Firebase.

The backend is safe unconfigured: with `FCM_PROJECT_ID` or
`FCM_SERVICE_ACCOUNT_JSON` unset, nothing is sent and nothing raises, and the
60-second poll behaves exactly as before. → [features/notifications.md](features/notifications.md)

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

## Localization

### planned — `de`, `es` and `zh` are each missing the same 36 keys

All 36 are collaborative-editing / edit-lock strings. **`fr` and `ar` are
complete.** Measured by diffing the `.arb` files (955 keys in `en`, `fr`, `ar`;
919 in `de`, `es`, `zh`):

```
apiErrorEditLockLost, apiErrorEditLockRequired, apiErrorEditorCannotView,
apiErrorEditorExists, apiErrorEditorIsOwner, apiErrorEditorNotFound,
apiErrorItineraryLocked, editLockAvailableIn, editLockAvailableNow,
editLockCopied, editLockCopyText, editLockLostMessage,
editLockLostMessageUnknown, editLockLostTitle, editLockMoveHere,
editLockMoveHereMessage, editLockOwnerCanReclaim, editLockReclaim,
editLockReclaimed, editLockSomeoneEditing, editLockSomeoneEditingIdle,
editLockTakeOver, editLockYouElsewhere, editorsAdd,
editorsChangeVisibilityMessage, editorsEmpty, editorsGrantViewConfirm,
editorsGrantViewMessage, editorsGrantViewTitle, editorsOpenVisibility,
editorsRemoveMessage, editorsRemoveTitle, editorsRemoved, editorsSearchHint,
editorsSubtitle, editorsTitle
```

A German, Spanish or Chinese user sharing a trip sees the English string for every
editor and lock message. → [features/collaborative-editing.md](features/collaborative-editing.md)

### planned — `errorUnderage` and `errorDobRequired` are translated and never used

Both keys exist in all six `.arb` files. A grep for either identifier outside
`lib/l10n/` returns **nothing**, and neither `underage` nor `dob_required` has a
case in `localizedApiError`. So the two failures on the **signup path** fall
through to the server's English `detail` in every locale.

This is the cheapest fix in the backlog: two switch cases. →
[reference/error-codes.md](reference/error-codes.md#unmapped-codes)

### idea — 12 more error codes have no client localization

`appeal_already_decided`, `appeal_reason_required`, `appeal_reason_too_long`,
`bug_report_empty`, `cannot_save_own_itinerary`, `display_name_invalid`,
`google_account_mismatch`, `google_reauth_required`, `not_found`,
`reauth_required`, `unauthorized`, `username_invalid`.

`unauthorized` and `not_found` are raised only by `/internal/moderation-sweep`,
which has no app client, so they need no mapping. →
[reference/error-codes.md](reference/error-codes.md)

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

### idea — `moderate_or_422`'s documented precondition is not held

Its docstring says the caller "must not have added rows to the session", but
`require_edit_access` writes the lock heartbeat before the endpoint body runs, so a
rejected PATCH commits that write. Harmless in effect; the contract is wrong as
written. → [features/text-moderation.md](features/text-moderation.md)

---

## Dead and unread code

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
| `security_audit_log` | holds exactly two `event_type` values; **no endpoint, admin lane or query in `app/` reads the table** |
| `refresh_tokens.rotated_to` | written at rotation, documented "informational" |
| `refresh_tokens.user_agent` | captured for a **"list active sessions" UI** its docstring anticipates, which does not exist |
| `waitlist.platform` | written, read nowhere — no admin lane, no export |
| `Storage.exists()` | on the ABC, implemented by both backends, **no caller anywhere** |
| `ResetPasswordRequest` (`schemas/auth.py:141`) | defined, referenced by no router or test |
| `MODERATION_LOG_SYSTEM_ACTIONS`'s `"recheck"` | permitted by the CHECK; nothing writes it |

### planned — the web password-reset path skips the shared validator

`web.py:198` validates inline (mismatch / under 8 chars / needs a digit) instead
of calling `validate_password_strength`, so **the 72-byte NFKC bcrypt cap is not
enforced there** while it is on every other password path. →
[features/passwords-and-email.md](features/passwords-and-email.md)

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

### idea — `POST /waitlist/join` has no rate limit

Every other public POST does. Its body schema is also the only one defined inline
in a router rather than in `schemas/`.

### idea — Redis-backed rate limiting, gated on horizontal scaling

The in-memory store is documented as single-instance-only in **four** places
(`limiter.py:12`, `main.py:219`, `social_api/README.md:535`, `CLAUDE.md:87`), plus
the text-moderation cache (`text_moderation_service.py:80`). Nothing records the
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

## Roadmap

### idea — the three features named in the root README

`README.md:283`, the only explicit roadmap line in the repository:

> Upcoming: posts feature, real-time feed, native app store distribution.

- **Posts** — no schema, no endpoint, no screen. Entirely unstarted.
- **Real-time feed** — the current feed is a paginated poll. Would need a push
  channel; FCM exists but is scoped to notifications.
- **Store distribution** — the app is pre-launch; every download button opens the
  waitlist, and the help CTA points at `/#get-the-app` precisely because a
  hardcoded store URL would ship dead.

### idea — web push

`models/device_token.py:34` — *"Web push needs a service worker and a VAPID key
that this build does not ship, so it is deliberately not accepted."*
`DEVICE_PLATFORMS = ("ios", "android")`. The same note appears at
`core/push/push_service.dart:10`. Web is poll-only by design.

### idea — `/help/whats-new` holds one release entry

`RELEASES` has a single entry, so the page is thin. Note the trap: `releases()`
falls back **whole**, not per entry, so an entry added only to `en.py` silently
leaves the other five languages showing an outdated What's New **with no test to
catch it**. → [features/help-centre.md](features/help-centre.md)

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
| `CLAUDE.md` | the middleware table omits `LanguageCookieMiddleware`, so it shows six runtime layers where there are seven |
| `dependencies.py:110` | `require_verified_email`'s message says verification happens "only by signing in with Google", but `/auth/register` emails a link and `/verify-email` sets the flag |

`docs/` supersedes the schema and endpoint sections of both backend READMEs. →
[README.md](README.md)
