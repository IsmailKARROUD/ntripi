# Passwords and email verification

**Status:** shipped
**Tables:** `email_tokens`, `password_history`, `security_audit_log`
**Config:** `EMAIL_BACKEND`, `RESEND_API_KEY`, `EMAIL_FROM`, `PWNED_CHECK_ENABLED`, `SHARE_BASE_URL`

## Purpose

Three related flows: forgotten-password reset by emailed link, in-app password
change for accounts that have a password, and email verification. All three mint
single-use opaque tokens; none of them ever stores a raw token.

## Rules

### Tokens

- **Only the SHA-256 hash is stored** (`email_tokens.token_hash`, UNIQUE), via
  the shared `token_util` helpers (`hash_token` / `as_aware_utc` /
  `new_raw_token`) that every opaque-token service in the project uses.
- **Single-use** (`used_at`), **purpose-scoped** (`password_reset`,
  `email_verify`, and since 2026-11-03 `account_delete` — the
  [account-deletion.md](account-deletion.md) link), and expiry-checked. Presenting
  a reset token to the verify route is reported as an *unknown token*, not a
  wrong-purpose error.
- **`peek` validates without spending** (`email_token_service.peek`): the
  deletion link's confirm page reads it on GET, because mail scanners open every
  link in an email; only the page's POST calls `consume`.
- TTLs: **password reset 30 minutes**, **email verification 24 hours**,
  **account deletion 1 hour**.

### Forgotten password

- **`POST /auth/forgot-password` always answers 200** with
  `"If an account exists…"` — enumeration-safe. It is a silent no-op for a
  Google-only account (no password to reset) and for an inactive one
  (`auth_service.py:388`).
- Completing a reset **revokes every refresh token** for that user
  (`auth_service.py:423`) and records the new hash in `password_history`.
- **A reset or an in-app change retires every other outstanding reset link**
  (`email_token_service.retire_unused`). Each forgot-password request mints its
  own; until 2026-09-28 one left in an old email could reset the password again
  for the rest of its 30 minutes.
- Rate-limited **3/hour**.

### In-app change

`POST /auth/change-password` runs in this order (`auth_service.py:520`):

1. Verify the current password → **403**, deliberately not 401
   (`auth_service.py:523`): a 401 would trip the Flutter `AuthInterceptor` into a
   login redirect.
2. Reject reuse of any of the last **5** hashes (`_PASSWORD_HISTORY_KEEP`).
3. Reject a password found in the **Have I Been Pwned** breach corpus.
4. `revoke_all_for_user` — every *other* session dies.
5. Write a `security_audit_log` row.
6. Commit, then send a best-effort notification email.

The current device is **reissued a fresh `TokenPair`** in the response, so
changing your password does not sign you out of the device you did it on.

- **HIBP uses the k-anonymity range API and fails open** — only a 5-character
  hash prefix leaves the app, and a HIBP outage never blocks a change
  (`services/pwned_service.py`). `PWNED_CHECK_ENABLED=False` disables it for
  offline dev and tests.
- Rate-limited **5/hour**.

### Email verification

- `POST /auth/resend-verification` is a no-op if already verified
  (`auth_service.py:555`); rate-limited 3/hour.
- `GET /verify-email?token=` consumes the token, sets `email_verified = True`
  (`auth_service.py:589`), and renders `email_verified.html` or
  `token_invalid.html` — **always HTTP 200**, so a bad link is a page, not an
  error.

### Email delivery

- `email_service.py:662` switches on `EMAIL_BACKEND`: `"resend"` POSTs the Resend
  HTTP API; **anything else logs to the console** (the dev default, no provider
  needed).
- **All failures are logged and swallowed.** A mail outage must never fail a
  user's write. This is the opposite of the Jira hand-off, which fails closed —
  see [bug-reports.md](bug-reports.md).
- Every emailed link is built from `SHARE_BASE_URL`.
- **One builder for every email's HTML: `email_service.branded_email_html`**
  (heading, paragraph, one button, the link printed beneath it). It moved there
  from `auth_service._email_html`, which six modules had imported privately, and
  takes `lang=`: Arabic reads right to left, and the line under the button is
  translated (`email_button_fallback`). **It escapes the link**, because a raw
  `&lang=` is the entity `&lang;` to some mail clients, which breaks the URL;
  `heading` and `body` are HTML, escaped by their callers. English output is
  unchanged byte for byte (`test_account_deletion_web.py::TestEmailBuilder`),
  and the existing emails still pass no language — only the account-deletion
  emails are translated so far. Its button radius is a typed 14, held to the app's token by
  `test_radius_scale.py`.
- **`noreply@` must stay a real routed address** — users reply to password
  resets.

## Data model

`email_tokens` — `user_id` CASCADE, `token_hash` UNIQUE, `purpose` VARCHAR(20),
`expires_at`, `used_at`. Migration `58de08fcefdf`.

`password_history` — `user_id` CASCADE, `password_hash`, `created_at`. Only the
last 5 matter.

`security_audit_log` — `user_id` CASCADE, `event_type` VARCHAR(64) (free-form),
`ip_address`, `user_agent`. Both from `1b3aeb06f54f`.

Full columns:
[reference/data-model.md](../reference/data-model.md#email_tokens).

## API surface

| Method | Path | Auth | Rate | Request | Response |
|---|---|---|---|---|---|
| POST | `/auth/forgot-password` | none | 3/h | `ForgotPasswordRequest` | **200 always** |
| POST | `/auth/change-password` | Bearer | 5/h | `ChangePasswordRequest{current_password, new_password}` | `TokenPair` |
| POST | `/auth/resend-verification` | Bearer | 3/h | — | 200 |
| GET | `/reset-password?token=` | none | — | — | HTML form |
| POST | `/web/reset-password` | none | — | form: `token, password, password_confirm` | HTML, **always 200** |
| GET | `/verify-email?token=` | none | — | — | HTML, **always 200** |

Change-password errors all arrive as 403/400 with the generic
`code="auth_error"` — see Known gaps.

## Flutter surface

- **Screens** — `ForgotPasswordScreen` (`/forgot-password`),
  `ChangePasswordScreen` (`/settings/change-password`).
- The change-password entry point lives in the profile edit **Security** section
  and is **gated on `has_password`** — a Google-only account has nothing to
  change.
- Reset and verification both complete **in the browser**, not in the app: the
  emailed link opens a server-rendered page.
- No dedicated providers; both flows call `AuthRepository` directly.

## Known gaps / TODOs

- **The web reset path skips the breached-password (HIBP) and reuse checks**
  that `change_password` runs (`auth_service.py:533`). It does enforce the shared
  `validate_password_strength` policy since 2026-09-26 — before that it
  validated inline, so a password over bcrypt's 72-byte cap reached `hashpw`,
  which bcrypt 5 answers with a `ValueError` (a 500 page), and Arabic-Indic
  digits satisfied the digit rule.
- **`ResetPasswordRequest` (`schemas/auth.py:141`) is defined and never
  referenced** by any router or test.
- **Eight distinct change-password failures share one error code.** "No password
  set", "current password incorrect", "can't reuse a recent password" and
  "password appeared in a breach" all arrive as `auth_error`, and all four
  surface on the same screen needing different UI.
- **`security_audit_log` is write-only.** It holds three `event_type` values
  (the two password-change events and the Google-link password drop) and **nothing in `app/` reads the table** — no endpoint, no admin lane,
  no query.
- `PWNED_CHECK_ENABLED` is absent from `.env.example`.

## Related

- [authentication.md](authentication.md) — sessions, and why 403 not 401
- [google-sign-in.md](google-sign-in.md) — the other verification path
- [accounts-and-profiles.md](accounts-and-profiles.md) — `has_password` / `has_google`
- [admin-and-appeals.md](admin-and-appeals.md) — the public appeal form shares this email plumbing
- [account-deletion.md](account-deletion.md) — the `account_delete` link and the translated deletion emails
- [web-and-platform.md](web-and-platform.md) — the server-rendered pages
- [reference/data-model.md](../reference/data-model.md)

## OPEN QUESTIONS

- **`require_verified_email`'s docstring and user-facing message say verification
  happens only by signing in with Google** (`dependencies.py:110`: *"Please
  verify your email by signing in with Google to do this."*). But
  `/auth/register` emails a verification link (`auth.py:144`) and
  `GET /verify-email` sets `email_verified = True`. Either the message is stale
  or the email path is not meant to count. Which is intended is not recorded.
- **Is the web reset path's weaker validation deliberate?** It predates
  `validate_password_strength` being centralised, and nothing says whether the
  divergence was noticed.
