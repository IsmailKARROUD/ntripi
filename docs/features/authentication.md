# Authentication and sessions

**Status:** shipped
**Tables:** `users`, `refresh_tokens`
**Config:** `SECRET_KEY`, `ALGORITHM`, `ACCESS_TOKEN_EXPIRE_MINUTES`, `REFRESH_TOKEN_EXPIRE_DAYS`

## Purpose

Email/password registration and login, short-lived JWT access tokens paired with
rotating refresh tokens, and the dependencies that gate every authenticated
request. Google Sign-In is a separate entry point into the same session model —
see [google-sign-in.md](google-sign-in.md).

## Rules

### Tokens

- **JWT HS256**, signed with `SECRET_KEY`. Claims are `{sub, exp, iat}` **and
  nothing else** — in particular **no `scope`**, and that absence is what the
  admin session (`admin.py:160`) and the appeal token
  (`appeal_token.py:57`) check against to make sure an API token cannot be used
  as one of theirs.
- **Access tokens are short** — `ACCESS_TOKEN_EXPIRE_MINUTES=15`. The refresh
  token is what keeps the session alive, so a leaked access token has a narrow
  window.
- **Refresh tokens rotate on every use** (RFC 6749 best practice).
  `REFRESH_TOKEN_EXPIRE_DAYS=30` of inactivity ends the session.
- **Only the SHA-256 hash is stored** (`refresh_tokens.token_hash`, UNIQUE), via
  the shared `token_util` helpers that every opaque-token service uses.
- **Replay revokes the whole family.** Each token carries a `family_id`; using a
  token that is already `revoked_at` revokes every token in that lineage
  (`refresh_token_service.py:244`) — the standard response to a stolen refresh
  token. Rotation marks `revoked_at` + `rotated_to` atomically with issuing the
  successor.
- **`revoke()` no-ops on an unknown or already-revoked token**
  (`refresh_token_service.py:274`) — it must not become a validity oracle.
- `POST /auth/logout` **always answers 204**, whatever the token was.

### Login

- **Timing-safe.** `_DUMMY_HASH` (`auth_service.py:42`) means bcrypt is called
  even when the identifier is unknown or the account is Google-only, so response
  time cannot reveal whether an account exists.
- The identifier is lowercased and matched against `email` **OR**
  `username_lower` — never `username`.
- **Direct bcrypt, no passlib.** Passwords are NFKC-normalised on both hash and
  verify (`services/auth.py:48,66`), and anything over 72 bytes returns `False`
  rather than raising (bcrypt 5.x behaviour).
- Failure is always 401 `login_invalid`; a deactivated account is 403
  `account_deactivated`.

### Registration

Order is load-bearing (`auth.py:87`–`111`), and each step exists to avoid paying
for the next:

1. `tos_accepted` false → **400 `tos_required`**.
2. Age check → **400 `underage`**. Both of these run **before** the paid
   moderation call.
3. `moderate_or_422` on username + display_name, **in one dict so it is one
   provider call**, and **before** `create_user` — which commits, so a rejection
   found afterwards could not undo the account.
4. `create_user`, which **re-checks the age** as defence in depth
   (`auth_service.py:122`).

- **Username policy** (`validators/username.py`): pattern
  `^[a-zA-Z][a-zA-Z0-9_.]{2,28}[a-zA-Z0-9]$` — must start with a letter, end
  alphanumeric, 4–30 chars. No consecutive `.` or `_`. A **68-entry reserved
  list** is rejected.
- **`username_lower` is the uniqueness key and the only lookup key.** Never query
  `User.username == …`.
- Email is lowercased before storage and comparison, and non-Latin emails are
  rejected.
- **New accounts are private** (`users.is_private` defaults `True`).
- `tos_accepted_version` is stamped with the **server's** `TOS_VERSION`, verbatim.

### The dependencies

| Dependency | Behaviour |
|---|---|
| `get_current_user` | **403 `not_authenticated`** if no `Authorization` header; 401 if the token is invalid, expired, or names an unknown user; **403 `account_deactivated`** if `is_active == False` |
| `get_current_user_optional` | `None` when no header — but a **present-but-invalid** token still 401s, so a stale app token cannot silently downgrade a request to anonymous |
| `require_verified_email` | `get_current_user` plus **403 `email_unverified`** |
| `require_edit_access` | see [collaborative-editing.md](collaborative-editing.md#the-guard) |

**403, not 401, for a missing header** is deliberate: the Flutter
`AuthInterceptor` only refreshes or logs out on a *codeless* 401, so a coded 401
reaches the calling screen instead of bouncing the user to the login page.

`require_verified_email` guards exactly **nine** endpoints — creating an
itinerary, a stop, either kind of annotation, a rating, a segment, a leg, an
itinerary image, and following someone. Reading and editing never require it.

## Data model

`users` — `password_hash` is **nullable** (a Google-only account has none);
`google_sub` is UNIQUE and nullable. Non-column properties: `has_password`,
`has_google`, `tos_current`, `name_for_display`, `handle`.

`refresh_tokens` — `token_hash` UNIQUE, `family_id` indexed, `revoked_at`,
`rotated_to` (**written, never read** — forensics only), `user_agent` (captured
for a "list active sessions" UI that does not exist).

Full columns:
[reference/data-model.md](../reference/data-model.md#users). Migration:
`340e256514b7` added refresh tokens; `d4e5f6a7b8c9` added `username_lower` and
`display_name`.

## API surface

| Method | Path | Auth | Rate | Request | Response | Errors |
|---|---|---|---|---|---|---|
| POST | `/auth/register` | none | 5/h | `RegisterRequest` | `TokenPair` 201 | 400 `tos_required`, 400 `underage`, 422 `username_invalid` / `display_name_invalid` / `text_moderation_rejected`, 409 `username_taken` / `email_taken`, 429 |
| POST | `/auth/login` | none | 10/min | `LoginRequest{identifier, password}` | `TokenPair` | 401 `login_invalid`, 403 `account_deactivated` |
| POST | `/auth/refresh` | none | 60/min | `RefreshRequest{refresh_token}` | `TokenPair` | 401 `invalid_grant` |
| POST | `/auth/logout` | none | — | `RefreshRequest` | **204 always** | — |

`RegisterRequest` = `{username (4–30), email (EmailStr, ASCII only),
password (8–128), display_name? (≤50), tos_accepted (bool), date_of_birth}`.

`TokenPair` = `{access_token, refresh_token, token_type: "bearer", user_id,
username, refresh_expires_at}`.

## Flutter surface

- **Screens** — `LoginScreen` (`/login`), `RegisterScreen` (`/register`),
  `SplashScreen` (`/splash`), `SuspendedScreen` (`/suspended`),
  `AcceptTermsScreen` (no route — mounted by `TosGate`).
- **Providers** (`features/auth/providers/auth_provider.dart`):
  | Provider | Type | Holds |
  |---|---|---|
  | `authRepositoryProvider` | `Provider` | `AuthRepository` |
  | `authNotifierProvider` | `NotifierProvider` | the just-signed-in user |
  | `hasSessionProvider` | `FutureProvider` | **"is somebody signed in?"** |
- **`hasSessionProvider`, not `authNotifierProvider`, is the signed-in signal
  outside the router.** Splash restores a session without calling
  `setAuthenticated`, so the notifier is null for exactly the returning users a
  gate exists for. An invalidated `FutureProvider` also keeps serving its previous
  value while reloading, so `isLoading` has to be refused separately.
- **`TokenManager`** (`core/auth/token_manager.dart`, `tokenManagerProvider`) owns
  the access/refresh pair; storage is `flutter_secure_storage` only
  (`core/storage/secure_storage.dart`) — **never Riverpod state**.
- **`AuthInterceptor`** (`core/api/api_client.dart`) refreshes transparently
  before expiry and, on a **codeless** 401, refreshes once and retries. A
  **coded** 401 is passed through to the caller. **The retry's own answer is what
  the caller sees**: until 2026-09-28 any failure of the retried request (412,
  409, 422, 5xx, a timeout) bounced the user to `/login` and reported the original
  401. Only a fresh token still being refused (a codeless 401 on the retry) means
  the session is gone. A multipart body is cloned before the retry — Dio refuses to
  finalize the same `FormData` twice, which failed every upload that crossed a
  token expiry.
- **The interceptor stamps the account (JWT `sub`) on every request** for the
  HTTP cache key (`core/api/cache_key.dart`) — from the expired token too, so
  offline still finds that account's entries. See
  [accounts-and-profiles.md](accounts-and-profiles.md).
- **One reset list for sign-in and sign-out.** `_userScopedProviders` in
  `auth_provider.dart` names every keep-alive user-specific provider (feed,
  follow requests and lists, blocked users, profiles, itinerary detail, ratings,
  editors, allowlist, edit locks, …); `setAuthenticated` and `logout` both
  invalidate it. Sign-out also releases this device's edit claims and
  `DELETE /devices/{token}` **before** discarding the access token (see
  [notifications.md](notifications.md)), then cleans the HTTP cache store.
- **`hasSessionProvider` follows `sessionEnded`**, bumped by `clearAllTokens()`
  whoever calls it — the interceptor's forced paths (a rejected refresh, a
  suspension) have no ref, and the provider used to keep answering "signed in".
- Login leads with Google/Apple; email sign-up is a secondary button.

## Known gaps / TODOs

- **11 `AuthError` raise sites share the default `code="auth_error"`**
  (`auth_service.py` lines 212, 247, 417, 421, 518, 526, 529, 534, 583, 587). The
  client localizes by `code`, so "no password set", "current password incorrect",
  "can't reuse a recent password" and "password appeared in a breach" are
  indistinguishable — and all four surface on the change-password screen, where
  they need different UI.
- **Apple Sign-In is a live button that shows a "Coming soon" snackbar**
  (`login_screen.dart:318`) — the only use of the `comingSoon` l10n key.
- `refresh_tokens.user_agent` and `rotated_to` are written and never read.
- `ACCESS_TOKEN_EXPIRE_MINUTES` and `REFRESH_TOKEN_EXPIRE_DAYS` are absent from
  `.env.example`; the root `README.md` still documents a 24-hour JWT and
  `ACCESS_TOKEN_EXPIRE_MINUTES=1440`.

## Related

- [google-sign-in.md](google-sign-in.md) — the other entry point
- [passwords-and-email.md](passwords-and-email.md) — reset, change, verification
- [accounts-and-profiles.md](accounts-and-profiles.md) — the profile and deletion
- [legal-and-age-gate.md](legal-and-age-gate.md) — the two gates before moderation
- [text-moderation.md](text-moderation.md) — why the scan precedes `create_user`
- [admin-and-appeals.md](admin-and-appeals.md) — `is_active` and suspension
- [reference/error-codes.md](../reference/error-codes.md#authentication-and-session)
- [reference/data-model.md](../reference/data-model.md)

## OPEN QUESTIONS

- **`ResetPasswordRequest` (`schemas/auth.py:141`) is defined and never used.**
  No router or test references it. Whether a JSON `POST /auth/reset-password` was
  planned, or the schema is a leftover, is not recorded — see
  [passwords-and-email.md](passwords-and-email.md) for the consequence.
