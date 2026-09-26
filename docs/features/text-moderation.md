# Text moderation

**Status:** shipped (**disabled by default**)
**Tables:** `text_moderation_cache`, `text_moderation_decisions`
**Config:** `TEXT_MODERATION_PROVIDER`, `OPENAI_API_KEY`, `TEXT_MODERATION_MODEL`, `TEXT_MODERATION_TIMEOUT_SECONDS`, `TEXT_MODERATION_CACHE_TTL_DAYS`, `TEXT_MODERATION_LOG_RETENTION_DAYS`

## Purpose

Scans user-written prose before the write commits, and rejects, flags or queues
it according to **Ntripi's own policy** rather than a provider's verdict.
Provider-agnostic by construction: swapping providers is a config change, never a
code edit.

## Rules

### Policy is ours

- **`app/services/moderation_policy.py` holds the 13 categories with Ntripi's own
  `(review, reject)` thresholds.** The provider's boolean `flagged` verdict is
  **deliberately ignored**.
- **`POLICY_VERSION` is part of the cache key**, so bumping it invalidates every
  cached verdict. **Bump it whenever you touch a threshold** — otherwise stale
  verdicts survive.

### Providers

`app/services/text_moderation_providers.py`. Chain is **`openai → local →
pending`**:

| Value | Behaviour |
|---|---|
| `openai` | OpenAI Moderation API; falls back to `local` on failure |
| `local` | `alt-profanity-check`, self-contained, no network |
| `disabled` | no scanning at all — **the default**, and what dev and tests use |

- **Startup fails if `openai` is selected without `OPENAI_API_KEY`** — a silent
  downgrade to the wordlist is worse than not booting (`config.py:286`).
- **The OpenAI request body carries the text and the model name and nothing
  else** — no user id, email, or content id, ever.
- The operator is emailed when the chain degrades (fallback, or all-down),
  throttled to one per hour per level.

### Blocking calls are correct here

Every text write path is a **sync `def`** endpoint, which FastAPI runs in a
threadpool, so a blocking `requests.post` with a timeout never touches the event
loop. **Do NOT convert these endpoints to `async def`** — that would put the sync
SQLAlchemy session on the loop, which is the actual hazard.

### Call it from the endpoint body

**`moderate_or_422` must be called from the endpoint BODY, never as a
`Depends`.** Dependencies resolve before the body, so a `Depends` would spend a
paid moderation call before `require_etag` could return its 412.

### Coverage

**Every stored user string except the moderator-facing ones:**

itinerary title/description · stop name/address/notes · both annotation tables ·
transport-leg line/direction/notes · rating notes · profile display_name/bio ·
the `username` + `display_name` chosen at registration.

**Deliberately NOT moderated:** `content_reports.notes`, `appeals.user_reason`,
`bug_reports.message`, and admin action reasons. A 422 there would block someone
reporting hate speech who quotes it — a safety regression, not an improvement.

### Content state

Lives on `itineraries.moderation_status` (shared with the image tier),
`itinerary_ratings.moderation_status`, and `users.moderation_status`.

**Stop, annotation and transport-leg text rolls up to its parent itinerary** —
hiding is itinerary-level, so a per-fragment status would have no read path.

### Escalate-only

**Automated writes only ever RAISE severity** (`apply_moderation_status`), in the
order `approved < pending < flagged < hidden < rejected`: a clean caption edit
must not clear an unresolved image flag. **Moderator and appeal paths assign
directly** to lower it.

**An author's rewrite of a profile or a review goes through
`apply_author_edit_status`** (`text_moderation_service.py`). A rewrite that was
rescanned whole *replaces* an automated flag — the text that earned it is gone.
It only escalates in two cases: the record is under a **takedown** (`hidden` /
`rejected` — only a moderator or an appeal lifts one; with the provider disabled
nothing was scanned at all), or the rewrite was **partial** (a profile edit that
left a stored `display_name` or `bio` unsent, so that text was never re-judged).
A review's note is rescanned whole on every upsert, so only the takedown case
applies there. Before 2026-09-26 both paths assigned the verdict outright, which
let any author edit un-hide their own taken-down profile or review.

**Any moderation write to an itinerary from outside the owner's own request MUST
go through `admin_service.set_preserving_etag` / `moderation_actions.set_status`**
— `updated_at` IS the concurrency ETag, and moving it 412s the author's open
editor over a change they cannot see. Thirteen call sites.

### Account creation scans before it writes

`create_user` commits, so a rejection found afterwards could not undo the
account — `moderate_or_422` runs first, with `author=None`.

`POST /auth/google` scans the Google profile name but **never rejects it**: the
name is Google's, not something the user typed, so a 422 would lock a real person
out with no recourse. A reject there drops the name and stores `approved`.

### Escalation

**A `hide_escalate` verdict must open a `legal_escalations` row, on every path.**
Callers pass `ctx.escalate` to `moderation_actions.escalate_if_flagged` after
their flush — the caller is the only party holding the row to point at. The one
exception is a *rejected* minors verdict, escalated from `_finalize` against the
**author**: nothing was stored, so there is no content row.

Six call sites: register, `PATCH /users/me`, `_moderate_itinerary_text`, rating
submit, the Google signup path, and the reject path in
`text_moderation_service.py:266`.

### The two tables

- **`text_moderation_cache` holds no raw text and no user reference.** Keyed by
  `hash(text + model + POLICY_VERSION)`.
- **`text_moderation_decisions` is the audit trail *and* the moderator queue** —
  `reviewed_at IS NULL` means queued. **Retention purges reviewed rows only.**

### The client filter

`lib/core/moderation/text_precheck.dart` **warns, never blocks**: any failure
returns "clean", the submit control stays enabled, and text is **never mutated or
cleared**.

**Applied to free prose only — never to titles or place names.** European place
names false-positive on wordlists (Bitche, Condom, Sexbierum, Wank); flagging a
real destination teaches users to ignore the warning. The backend still moderates
titles, where a context-aware classifier can tell the difference.

This replaced the `safe_text` package on 2026-07-30 (`e56c9be`) — see
[decisions.md](../decisions.md).

### What the author is told

**`pending` and `flagged` are internal and are NOT surfaced to the author.**
Only `hidden` is, with a reason and a one-tap appeal.
`ModerationStatus.fromString` degrades unknown values to `approved` — a newer
backend must never crash a deployed client.

## Data model

`text_moderation_cache` — `cache_key` VARCHAR(64) **PK**, `outcome`, `scores`
JSON, `provider`, `model`, `expires_at` indexed.
CHECK outcome ∈ `approve, review, reject, hide_escalate`.

`text_moderation_decisions` — `content_hash` indexed, `target_type`, `target_id`,
`author_user_id` FK SET NULL, `outcome` (the four above **plus `pending`**),
`scores`, `provider`, `model`, `policy_version`, `source` (`write` | `recheck`),
`queue_label`, **`reviewed_at`**.

Full columns:
[reference/data-model.md](../reference/data-model.md#text_moderation_cache).
Migration: `4bdacee286ac`; `d3db17c28b44` added the rating/user statuses.

## API surface

No endpoints of its own. It is a step in the body of four router sites plus
`auth_service.login_or_register_google` and `sweep_service._recheck_pending`.

It surfaces as **422 `text_moderation_rejected`** with a `categories` list in
`extra`, which the client turns into plain language via
`moderationRejectionMessage()` — never the raw classifier id. Two admin lanes
read the queue: `GET /admin/text-flags` and
`POST /admin/text-flags/{decision_id}/action`.

## Config

| Var | Default | Notes |
|---|---|---|
| `TEXT_MODERATION_PROVIDER` | `disabled` | `openai` / `local` / `disabled`; an unknown value **raises at startup** |
| `OPENAI_API_KEY` | unset | **required if provider is `openai`, or startup fails** |
| `TEXT_MODERATION_MODEL` | `omni-moderation-latest` | part of the cache key |
| `TEXT_MODERATION_TIMEOUT_SECONDS` | `5.0` | |
| `TEXT_MODERATION_CACHE_TTL_DAYS` | `30` | |
| `TEXT_MODERATION_LOG_RETENTION_DAYS` | `90` | reviewed rows only |

## Known gaps / TODOs

- **The decision-row cache is single-instance**, like the rate limiter
  (`text_moderation_service.py:80`). Horizontal scaling needs a shared store.
- `test_text_moderation_{config,endpoints,policy,service}.py` all run.

## Related

- [image-moderation.md](image-moderation.md) — shares `moderation_status`
- [content-reports.md](content-reports.md) — `legal_escalations`, thresholds
- [admin-and-appeals.md](admin-and-appeals.md) — the queue, the sweep, `set_preserving_etag`
- [etag-concurrency.md](etag-concurrency.md) — why moderation writes preserve `updated_at`
- [itineraries.md](itineraries.md) · [ratings.md](ratings.md) · [annotations.md](annotations.md) · [tracks-and-stops.md](tracks-and-stops.md) · [transit-segments.md](transit-segments.md) — the scanned fields
- [authentication.md](authentication.md) · [google-sign-in.md](google-sign-in.md) — the signup scans
- [accounts-and-profiles.md](accounts-and-profiles.md) — display_name and bio

## OPEN QUESTIONS

- **`moderate_or_422`'s stated precondition is violated by every guarded
  endpoint.** Its docstring (`text_moderation_service.py:224`) says *"Whatever
  the caller does next must not have added rows to the session: the reject path
  commits."* But `require_edit_access` runs `edit_lock_service.touch(lock)`
  (`dependencies.py:250`) **before** the body, so a rejected PATCH commits that
  heartbeat write. Harmless in effect, but the contract as written is not held.
  Whether the guard should defer the touch or the docstring should be narrowed is
  not recorded.
- **A CSAM-category reject at registration opens no legal escalation.**
  `text_moderation_service.py:259` requires `ctx.author is not None`, and
  `/auth/register` passes `author=None`. So a `sexual/minors` hit on a username or
  display name at signup writes a decision row but produces **no
  `legal_escalations` row and no `/admin/legal` entry**. Arguably correct (no
  account exists to escalate against — and the same reasoning makes the *rejected
  minors* case escalate against the author elsewhere), but the asymmetry is not
  explained in the code.
