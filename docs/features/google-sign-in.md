# Google Sign-In

**Status:** shipped (off unless a client id is configured)
**Tables:** `users.google_sub`, `users.email_verified`
**Config:** `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_ANDROID_CLIENT_ID`

## Purpose

One endpoint, `POST /auth/google`, that does three different things depending on
what the ID token turns out to mean: sign in an existing Google account, link
Google to an existing email/password account, or create a brand-new account. It is
also **the only path that sets `email_verified`** for most users, which is what
gates the nine `require_verified_email` endpoints.

## Rules

### Token verification

- `verify_oauth2_token(audience=None)` first, then **manual checks**
  (`services/auth.py:136`):
  - `aud` must be in `settings.google_client_ids`;
  - `iss` must be `accounts.google.com` or `https://accounts.google.com`.
- Any failure → **401 `google_token_invalid`**, with no detail leaked about which
  check failed.
- **All three client ids empty ⇒ every token fails** `invalid_audience`, so
  Google sign-in is silently off. That is the "unset = invisible" pattern used
  throughout.
- Android tokens carry the **web** client id as `aud` (via `serverClientId`); the
  Android id is listed for completeness.

### The three branches

**1 — Existing Google account** (`auth_service.py:214`): matched on `google_sub`.
Flips `email_verified = True` if Google says the address is verified. 403
`account_deactivated` if banned.

**2 — Link to an existing account** (`auth_service.py:233`): matched on email,
**and only if Google reports `email_verified`** — otherwise anyone could claim
an address they do not control. A **verified** account keeps `password_hash`,
producing a dual-method account that can then delete itself with either
credential. **An unverified one loses its password and every session**
(`unverified_password_dropped_on_google_link` in `security_audit_log`):
registration needs no verification, so the password may belong to someone who
squatted the owner's address first, and linking used to hand that person the
account the moment the owner signed in. The owner can set a new password through
forgot-password. See [decisions.md](../decisions.md).

**3 — New account** (`auth_service.py:257`):
- Requires `tos_accepted` → **400 `tos_required`** otherwise.
- **Date of birth**: the People API result **wins over** the client-posted date
  (`auth_service.py:270`), and `dob_source` records which stood behind the
  account (`"google"` or `"self"`). No date at all → 400 `dob_required`; under
  16 → 400 `underage`.
- Username is synthesised by `generate_username_from`
  (`validators/username.py:74`).
- **A moderation reject on the Google display name drops the name instead of
  failing signup** (`auth_service.py:308`) and resets the status to `approved`.
  The name is Google's, not something the user typed, so a 422 would lock a real
  person out with no recourse — and nothing offensive was persisted.

### Fields only branch 3 may read

**`tos_accepted`, `date_of_birth` and `google_access_token` are read only on the
create-a-new-account branch.** Sign-in and linking must never consult them, or
every returning Google user would be re-prompted forever.

### Consent-on-demand

The client's move is: post the token; on **400 `tos_required`**, show the consent
sheet and **re-post the same ID token** with `tos_accepted: true`. Google ID
tokens live about an hour and verification is stateless, so re-posting is free.
Asking before the picker would re-prompt every returning Google user at every
sign-in.

### The People API birthday read

- Google **ID tokens carry no birthdate claim**. Getting one needs the People
  API, the `user.birthday.read` **sensitive scope**, and an *access* token rather
  than the ID token.
- **`google_people.fetch_birthdate` verifies `resourceName == "people/{sub}"`**
  (`google_people.py:586`). This is load-bearing: the access token is a separate
  credential, so without the check a caller could pair their own ID token with an
  access token minted for a different Google account and inherit that account's
  birthday.
- `ACCOUNT` source beats `PROFILE`. An entry **without a `year` is unusable** — a
  `{month, day}` cannot answer an age question.
- **It never raises.** Every failure returns `None` and the caller falls through
  to asking the user.
- **The scope is requested only after the server answers `tos_required`** — that
  400 is the only signal the token means signup rather than sign-in.
- **The client's own People API read is a prefill hint only.** The server re-reads
  it and its answer is what gets stored.

## Data model

`users.google_sub` — VARCHAR(255), UNIQUE, nullable, indexed. `users.password_hash`
nullable. `users.dob_source` VARCHAR(16). Migration `0a2c5b2f918e` added
`google_sub` and made `password_hash` nullable; `2ddec1197cc9` added
`date_of_birth` / `dob_source`.

## API surface

| Method | Path | Auth | Rate | Request | Response | Errors |
|---|---|---|---|---|---|---|
| POST | `/auth/google` | none | 10/min | `GoogleAuthRequest` | `TokenPair` | 401 `google_token_invalid`, 403 `account_deactivated`, 400 `tos_required` / `dob_required` / `underage`, 409 (uncoded) email already registered |

`GoogleAuthRequest` = `{id_token, tos_accepted=false, date_of_birth=null,
google_access_token=null}`. **`tos_accepted` defaults `false`** — never `true`,
anywhere.

Two further endpoints consume a Google token for re-authentication rather than
sign-in: `DELETE /users/me` (account deletion) answers 401
`google_account_mismatch` or 401 `google_reauth_required`. See
[accounts-and-profiles.md](accounts-and-profiles.md).

## Flutter surface

- `core/auth/google_signin_service.dart` — the plugin wrapper.
- `core/auth/google_web_button.dart` with `_stub` / `_web` conditional imports —
  the web flow needs Google's own rendered button.
- `core/auth/google_people_client.dart` — the client-side prefill read.
- `core/ui/google_g_logo.dart` — the mark.
- **`GOOGLE_WEB_CLIENT_ID` is regex-injected into the SPA's
  `<meta name="google-signin-client_id">` at serve time** by `_SPAStaticFiles`
  (`main.py:62`) and cached in memory — the web plugin reads its client id from
  that tag, and the value cannot be baked in at build time.
- Login leads with the Google button; email sign-up is secondary.

## Known gaps / TODOs

- **The Google-sourced birthday half is blocked on OAuth verification** for the
  `user.birthday.read` sensitive scope: a 100-test-user cap and an "unverified
  app" warning until it clears. The consent-sheet fallback means everything else
  ships without waiting. See [backlog.md](../backlog.md).
- `google_reauth_required` has **no client-side localization**: the Google
  delete path always sends a token, so the app cannot reach it.
  `google_account_mismatch` is localized (`apiErrorGoogleAccountMismatch`) and
  shown by name on the delete screen — see
  [reference/error-codes.md](../reference/error-codes.md#unmapped-codes).
- Branch 2's "email already registered, use your password" answers 409 with the
  generic `code="auth_error"`.
- `require_verified_email`'s error message says verification happens **only** by
  signing in with Google, which is no longer true — see OPEN QUESTIONS in
  [passwords-and-email.md](passwords-and-email.md).

## Related

- [authentication.md](authentication.md) — the session model this feeds
- [legal-and-age-gate.md](legal-and-age-gate.md) — `tos_accepted` and the DOB rules
- [accounts-and-profiles.md](accounts-and-profiles.md) — dual-method deletion
- [text-moderation.md](text-moderation.md) — why a reject drops the name
- [passwords-and-email.md](passwords-and-email.md) — the other verification path
- [web-and-platform.md](web-and-platform.md) — the SPA meta-tag injection
- [reference/error-codes.md](../reference/error-codes.md#google-sign-in)
