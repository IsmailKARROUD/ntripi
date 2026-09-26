# API error codes

Every machine-readable error code the backend raises. **63 codes.**

## How the mechanism works

`ApiError` (`social_api/app/errors.py:17`) is an `HTTPException` carrying an
extra stable `code`, plus an optional `extra` dict merged into the JSON body.
A response looks like:

```json
{ "detail": "You do not have permission to modify this itinerary.", "code": "itinerary_not_owner" }
```

`detail` is kept byte-identical to the pre-`code` `HTTPException` messages so web
templates and older tests are unaffected — `code` is purely additive. A plain
`HTTPException` with no code still emits `{"detail": ...}` unchanged.

Two service layers raise their own exception types that routers convert to
`ApiError`, each with its own `http_status` field:
`AuthError` (`services/auth_service.py:45`) and `AppealError`
(`services/appeal_service.py:52`, default status **400**).

**Client resolution order** (`lib/core/api/api_client.dart:313`,
`extractErrorMessage`):

1. Typed edit-lock / stale exceptions, caught before any HTTP branch.
2. Dio transport errors → "no internet".
3. `code == 'text_moderation_rejected'` → `moderationRejectionMessage()`, which
   turns the `categories` in `extra` into plain language.
4. `localizedApiError(code, l10n)` (`lib/core/api/api_error_codes.dart`) — a
   localized string for **49 of the 63 codes**.
5. Fall back to the server's `detail` string — **English, untranslated**.
6. Fall back to a generic message.

Step 5 is why the "Client" column below matters: a code with no client mapping
shows English to every user regardless of app language. See
[Unmapped codes](#unmapped-codes).

---

## Codes by area

`—` in the Client column means no `localizedApiError` case: the server's English
`detail` is shown.

### Authentication and session

| Code | Status | Raised at | Client |
|---|---|---|---|
| `not_authenticated` | 403 | `dependencies.py:90` | localized |
| `account_deactivated` | 403 | `dependencies.py:68`, `auth_service.py:91,225,242` | localized |
| `login_invalid` | 401 | `auth_service.py:84` | localized |
| `invalid_grant` | 401 | `auth.py:258` | localized |
| `email_unverified` | 403 | `dependencies.py:122` | localized |
| `incorrect_password` | 401 | `users.py:243` | localized |
| `reauth_required` | 401 | `users.py:281` | — |
| `unauthorized` | 401 | `internal.py:66` | — |
| `not_found` | 404 | `internal.py:52` | — |

`not_authenticated` is **403, not 401** — a missing `Authorization` header is
distinguished from an invalid one, and the Flutter `AuthInterceptor` only
refreshes or logs out on *codeless* 401s.

### Google Sign-In

| Code | Status | Raised at | Client |
|---|---|---|---|
| `google_token_invalid` | 401 | `auth.py:201` (×2) | localized |
| `google_account_mismatch` | 401 | `users.py:259` | — |
| `google_reauth_required` | 401 | `users.py:274` | — |

### Registration, ToS and age gate

| Code | Status | Raised at | Client |
|---|---|---|---|
| `username_taken` | 409 | `auth_service.py:150` | localized |
| `email_taken` | 409 | `auth_service.py:160` | localized |
| `username_invalid` | 422 | `auth_service.py:133` | — |
| `display_name_invalid` | 422 | `auth_service.py:141` | — |
| `tos_required` | 400 | `auth.py:90`, `auth_service.py:116,262` | localized |
| `underage` | 400 | `auth.py:435`, `auth_service.py:126,286` | — |
| `dob_required` | 400 | `auth.py:426`, `auth_service.py:280` | — |

**Shape errors are 422; policy refusals are 400.** A future or >120-year date
fails the Pydantic validator (422); a real date under 16 answers 400 `underage`
from the router. The client is meant to render a field error for one and a
message for the other — see [legal-and-age-gate.md](../features/legal-and-age-gate.md)
for the gap here.

### Follows

| Code | Status | Raised at | Client |
|---|---|---|---|
| `cannot_follow_self` | 400 | `follows.py:103` | localized |
| `not_following` | 404 | `follows.py:192` | localized |
| `follow_request_not_found` | 404 | `follows.py:272` (×4 — accept ×2, reject ×2: missing, or no longer pending) | localized |
| `follow_request_already_accepted` | 400 | `follows.py:286` | localized |
| `cannot_reject_request` | 403 | `follows.py:341` | localized |
| `account_private` | 403 | `follows.py:55` | localized |
| `user_not_found` | 404 | `follows.py:113` (×6) | localized |

### Blocking

| Code | Status | Raised at | Client |
|---|---|---|---|
| `cannot_block_self` | 400 | `users.py:625` | localized |

A blocked or banned profile answers **404 with the same body as a deleted one**,
so the blocked user is never told. There is no dedicated code for it.

### Itineraries and access

| Code | Status | Raised at | Client |
|---|---|---|---|
| `itinerary_not_found` | 404 | `dependencies.py:177` (×4) | localized |
| `itinerary_not_owner` | 403 | `dependencies.py:239` (×6) | localized |
| `itinerary_access_denied` | 403 | `itineraries.py:177` | localized |
| `allowlist_restricted_only` | 400 | `itineraries.py:920` | localized |
| `allowlist_user_exists` | 409 | `itineraries.py:934` | localized |
| `allowlist_user_not_found` | 404 | `itineraries.py:1006` | localized |
| `cannot_save_own_itinerary` | 400 | `itineraries.py:1889` | — |

`itinerary_not_owner` is deliberately the same code and wording whether the
caller was never granted edit rights or was granted them and lost view access.

### Concurrency (ETag / If-Match)

| Code | Status | Raised at | Client |
|---|---|---|---|
| `if_match_required` | **428** | `dependencies.py:189` | localized |
| `itinerary_stale` | **412** | `dependencies.py:201` (×3) | typed exception |

`itinerary_stale` becomes `ItineraryStaleException` in the repository before it
reaches `extractErrorMessage`. See
[etag-concurrency.md](../features/etag-concurrency.md).

### Edit lock and editors

| Code | Status | Raised at | Client |
|---|---|---|---|
| `itinerary_locked` | **423** | `edit_lock_service.py:87` | typed exception |
| `edit_lock_required` | **428** | `edit_lock_service.py:109` | typed exception |
| `edit_lock_lost` | **409** | `edit_lock_service.py:98` | typed exception |
| `editor_cannot_view` | 409 | `itineraries.py:1082` | localized |
| `editor_exists` | 409 | `itineraries.py:1069` | localized |
| `editor_is_owner` | 400 | `itineraries.py:1064` | localized |
| `editor_not_found` | 404 | `itineraries.py:1157` | localized |

**423 and 409 must never be collapsed.** 423 `itinerary_locked` means "you asked
to claim and cannot" — answerable by waiting or taking over. 409
`edit_lock_lost` means "you believed you held it and do not" — protect the
unsaved input. `editor_cannot_view` carries `{visibility, can_fix_with_allowlist}`
in `extra`: it is a question, not an error.

### Stops, tracks, segments, legs

| Code | Status | Raised at | Client |
|---|---|---|---|
| `stop_not_found` | 404 | `itineraries.py:1471` (×3) | localized |
| `track_not_found` | 404 | `itineraries.py:400` | localized |
| `rank_collision` | 409 | `itineraries.py:1362` | localized |
| `segment_not_found` | 404 | `itineraries.py:583` | localized |
| `segment_already_exists` | 409 | `itineraries.py:2047` (×2) | localized |
| `leg_not_found` | 404 | `itineraries.py:594` | localized |

### Annotations and ratings

| Code | Status | Raised at | Client |
|---|---|---|---|
| `annotation_not_found` | 404 | `itineraries.py:256` | localized |
| `rating_not_found` | 404 | `itineraries.py:1842` (×2) | localized |

### Moderation

| Code | Status | Raised at | Client |
|---|---|---|---|
| `image_moderation_rejected` | **422** | `itineraries.py:2266` (×3) | localized |
| `text_moderation_rejected` | **422** | `text_moderation_service.py:237` | special: `moderationRejectionMessage()` |

`text_moderation_rejected` ships a `categories` list in `extra`. The client maps
each raw classifier id (`sexual/minors`, `illicit/violent`, …) to a plain-language
phrase and falls back to a generic message for unknown ids, rather than leaking
an internal identifier. **No compose form clears its field on this error.**

### Reports

| Code | Status | Raised at | Client |
|---|---|---|---|
| `report_own_content` | 400 | `reports.py:90` | localized |
| `report_rate_limited` | **429** | `reports.py:97` | localized |

### Appeals

All raised via `AppealError` in `services/appeal_service.py`.

| Code | Status | Raised at | Client |
|---|---|---|---|
| `appeal_reason_required` | 422 | `appeal_service.py:128` | — |
| `appeal_reason_too_long` | 422 | `appeal_service.py:133` | — |
| `appeal_target_not_found` | 404 | `appeal_service.py:140` | localized |
| `appeal_already_pending` | 409 | `appeal_service.py:155` | localized |
| `appeal_cooldown` | **429** | `appeal_service.py:163` | localized |
| `appeal_already_decided` | 409 | `appeal_service.py:327` | — |

### Bug reports and waitlist

| Code | Status | Raised at | Client |
|---|---|---|---|
| `bug_report_empty` | 422 | `bug_reports.py:87` | — |
| `waitlist_contact_required` | 422 | `waitlist.py:49` | localized |

---

## Unmapped codes

These **14** have no `localizedApiError` case, so the server's English `detail`
is shown to every user in every language:

`appeal_already_decided` · `appeal_reason_required` · `appeal_reason_too_long` ·
`bug_report_empty` · `cannot_save_own_itinerary` · `display_name_invalid` ·
`dob_required` · `google_account_mismatch` · `google_reauth_required` ·
`not_found` · `reauth_required` · `unauthorized` · `underage` ·
`username_invalid`

Two of them are worse than the rest: **`underage` and `dob_required` sit on the
signup path**, and the l10n keys `errorUnderage` / `errorDobRequired` are already
written and translated in all six `.arb` files — they are simply never read. A
grep for either identifier outside `lib/l10n/` returns nothing. Logged in
[backlog.md](../backlog.md).

`unauthorized` and `not_found` are raised only by `/internal/moderation-sweep`,
which has no app client, so they need no mapping.

---

## Rules for adding a code

- Raise `ApiError`, never a bare `HTTPException`, when a client might branch on
  the reason.
- **Shape errors are 422; policy refusals are 400.** The client renders a field
  error for one and a message for the other.
- Keep `detail` stable — web templates and tests read it.
- Add the case to `lib/core/api/api_error_codes.dart` **and** an `apiError*` key
  to all six `.arb` files in the same change, or the code lands in the unmapped
  list above. Note `de`, `es` and `zh` are already missing 36 keys — see
  [backlog.md](../backlog.md).
- Put machine-readable context in `extra`, never in `detail`.
- Add the row to this file.

---

## OPEN QUESTIONS

- **`user_not_found` (404) vs `appeal_target_not_found` (404) vs `not_found`
  (404)** all mean "the thing is not there" at different call sites, and
  `isGoneError()` on the client keys off the HTTP status rather than the code.
  Whether three codes for one condition is deliberate — each does carry a
  different `detail` — or accumulated is not determinable from the code.
- **`reauth_required` and `google_reauth_required` are both 401 on the
  account-deletion path** (`users.py:274,281`). Since the Flutter
  `AuthInterceptor` passes *coded* 401s through to the caller rather than logging
  out, both reach the screen — but nothing in `lib/` references either string, so
  which one the delete-account screen is meant to distinguish is not visible in
  the code.
