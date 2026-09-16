# Accounts and profiles

**Status:** shipped
**Tables:** `users`
**Config:** `STORAGE_PUBLIC_URL_PREFIX`, `R2_PUBLIC_URL` (for the image-URL validator)

## Purpose

The user's own account: profile fields, avatar and cover image, travel identity
(passport countries, residence, languages), the visited-locations map, privacy
toggle, notification preferences, and GDPR account deletion.

## Rules

### Identity

- **`username_lower` is the lookup key.** Never query `User.username == …`. It
  is UNIQUE; `username` itself is indexed but not unique and preserves the
  display casing.
- **Email is always lowercased** before storage and comparison.
- **Display name is free Unicode, ≤50 chars, and falls back to `@{username}`**
  via the `name_for_display` property.
- **Username cannot be edited.** It is deliberately absent from
  `UserUpdateRequest`, because `share_service.py:145` builds profile share URLs
  from the handle and depends on handles being immutable.

### `public_profile_text` — the leak guard

`user_service.py:725` returns `(None, None)` for display name and bio when the
subject's `moderation_status` is `hidden` or `rejected` **and** the viewer is not
the subject. **Eleven surfaces route through it**: user search, public profile,
blocks list, follow lists, follow requests, feed owner attribution, the editors
list, notification resolution, push actor names, the lock-holder view, the
ratings page, and the share profile page.

`GET /users/search` builds its results **by hand rather than with
`from_attributes`** (`users.py:401`) for exactly this reason — an ORM-to-schema
mapping would bypass the guard.

### Privacy toggle

- **`is_private` defaults `True`** — new accounts are private.
- **Flipping private → public auto-accepts every pending follow request**
  (`users.py:137,168`), bumps both counters, and emits one `follow_accepted`
  notification each.

### Images

- **Storage keys are deterministic**: `avatars/{user_id}.jpg` and
  `covers/{user_id}.jpg`. Because the key is stable, both use
  **`cache_bust=True`**, which appends `?v=<ms>` so a replaced image is not
  served from cache. Itinerary covers use `cache_bust=False` — they never carried
  a `?v=`.
- **`validators/image_url.py` is what forces uploads through the scan pipeline.**
  `PATCH /users/me` accepts `avatar_url` / `cover_image_url` only as `null` or a
  URL beginning with `STORAGE_PUBLIC_URL_PREFIX` or `R2_PUBLIC_URL`. Without it,
  a user could point their avatar at an arbitrary external image and skip
  moderation entirely — which is the bypass `d7f48e8` closed.
- Avatar is a square crop; the cover is a wide crop.

### Text moderation

`PATCH /users/me` scans `display_name` + `bio` in one call, and the resulting
status is **assigned, not escalate-only** (`users.py:146`) — so cleaning up a
flagged bio clears the flag. That is the deliberate exception to the
automated-writes-only-raise-severity rule, because this *is* the author's own
request.

### Account deletion (GDPR)

`DELETE /users/me` order is load-bearing (`users.py:208`):

1. **Re-authenticate.** The branch is chosen by **what the client sent**, not by
   account precedence (`users.py:237`):
   | Sent | Checked against | Failure |
   |---|---|---|
   | `password` + account has one | bcrypt | 401 `incorrect_password` |
   | `google_id_token` + account has `google_sub` | Google, then `sub` match | 401 `google_token_invalid` / 401 `google_account_mismatch` |
   | neither | account type decides | 401 `incorrect_password` / `google_reauth_required` / `reauth_required` |
   A dual-method account can therefore delete itself with **either** credential.
2. **Decrement other users' counters before the cascade**, via bulk `UPDATE`
   (`users.py:286`). This is the one documented exception to
   "`bump_follow_counters` is the only way to touch the counters".
3. **Null `ItineraryRating.user_id` explicitly** (`users.py:318`) — belt and
   braces over the `ON DELETE SET NULL`.
4. `db.delete(user)`; the cascade removes itineraries, stops, annotations,
   allowlist and editor rows, locks, follows, blocks, notifications, device
   tokens, saves, appeals, refresh and email tokens, password history, and the
   security audit log.

**Rows that survive with a NULL user, because they are evidence:**
`content_reports.reporter_user_id`, `moderation_log.admin_user_id`,
`image_moderation_logs.uploader_user_id`,
`text_moderation_decisions.author_user_id`, `bug_reports.user_id` and
`.closed_by_admin_id`, `legal_escalations.closed_by`, `notifications.actor_id`,
`itinerary_editors.granted_by`, and `itinerary_ratings.user_id`.

## Data model

`users` — 29 columns. Non-column properties: `has_password`, `has_google`,
`tos_current`, `name_for_display`, `handle`. Full list:
[reference/data-model.md](../reference/data-model.md#users).

`date_of_birth` is on **`UserPrivateProfile` only** — never on `UserBase` or
`UserPublicProfile`.

Migrations: `d4e5f6a7b8c9` (username_lower + display_name), `95a44d78f959`
(travel identity), `460d73edaf3d` (cover image), `9dcbd2b7d34c` (ToS version),
`2ddec1197cc9` (date of birth).

## API surface

| Method | Path | Auth | Request | Response | Errors |
|---|---|---|---|---|---|
| GET | `/users/me` | Bearer | — | `UserPrivateProfile` | — |
| PATCH | `/users/me` | Bearer | `UserUpdateRequest` | `UserPrivateProfile` | 422 `text_moderation_rejected`, 422 on an external image URL |
| DELETE | `/users/me` | Bearer | `DeleteAccountRequest{password?, google_id_token?}` | 204 | 401 ×4 (see above) |
| GET | `/users/{identifier}` | Bearer | UUID **or** username | `UserPublicProfile` + `is_following`, `follow_is_pending` | 404 `user_not_found` |
| GET | `/users/by-username/{username}` | Bearer | — | `UserPublicProfile` | 404 `user_not_found` |
| GET | `/users/{user_id}/locations` | Bearer | — | `VisitedLocationsResponse` | 404 `user_not_found` |
| POST | `/users/me/avatar` | Bearer, 10/min | multipart `file` | `UserImageResponse{avatar_url}` | 400 (uncoded), 422 `image_moderation_rejected` |
| DELETE | `/users/me/avatar` | Bearer | — | 204 | — |
| POST | `/users/me/cover-image` | Bearer, 10/min | multipart `file` | `UserImageResponse{cover_image_url}` | same as avatar |
| DELETE | `/users/me/cover-image` | Bearer | — | 204 | — |

`UserUpdateRequest` = `{display_name? (≤50), bio? (≤500), avatar_url?,
cover_image_url?, is_private?, passport_countries? (≤5 × 2-letter),
resident_country?, languages? (≤60), notify_ratings?, notify_saves?,
notify_follow_accepted?}`.

`UserPrivateProfile` adds `email, email_verified, has_password, has_google,
is_active, updated_at, moderation_status, notify_*, tos_current, date_of_birth`
over the public shape.

`VisitedLocationsResponse` = `{locations: [{lat, lng, place_name, place_type,
itinerary_id, stop_id}]}` — derived from the user's stops, filtered by
`can_view_itinerary`.

## Flutter surface

- **Screens** — `ProfileScreen` (`/profile/me` in shell branch 2, and
  `/profile/:userId` at root, plus `/search/profile/:userId` nested),
  `DeleteAccountScreen` (`/settings/delete-account`), `CountryPickerScreen`
  (pushed imperatively from `profile_edit_form.dart`),
  `FullscreenLocationsMapScreen` (pushed from `ProfileScreen`),
  `AccountStatusScreen` (`/settings/account-status`), `ChangePasswordScreen`.
- **Providers** (`features/profile/providers/`):
  | Provider | Type | Holds |
  |---|---|---|
  | `profileRepositoryProvider` | `Provider` | `ProfileRepository` |
  | `myProfileProvider` | `AsyncNotifierProvider` | own `UserPrivateProfile` |
  | `userProfileProvider` | `AsyncNotifierProvider.family` | another user's profile |
  | `myViolationsProvider` | `FutureProvider.autoDispose` | moderation history |
  | `userLocationsProvider` | `AsyncNotifierProvider.family` | the visited-locations map |
- **Model** — `User` (`shared/models/user.dart`), manual
  `fromJson`/`toJson`/`copyWith`.
- Profile screens use the Editorial layout; the map is `flutter_map` +
  OpenStreetMap.
- The delete flow is Tier-3 destructive: `confirmTypedDestructiveAction()`.

## Known gaps / TODOs

- **A decorative message button ships with no action.**
  `features/profile/presentation/widgets/follow_action_row.dart:39` —
  *"Decorative message button placeholder — not yet wired to a route."* A 46×46
  mail-icon container with no `onTap` is visible to users. Either wire direct
  messaging or remove the affordance.
- **`GET /users/by-username/{username}` has no client and is a functional
  duplicate** — `GET /users/{identifier}` already accepts a username.
- `security_audit_log` is written by the password paths and read by nothing.
- Four error codes on the deletion path (`reauth_required`,
  `google_reauth_required`, `google_account_mismatch`, `incorrect_password` in
  its uncoded twin) have no client localization, and three are not referenced
  anywhere in `lib/`.

## Related

- [authentication.md](authentication.md) · [google-sign-in.md](google-sign-in.md) · [passwords-and-email.md](passwords-and-email.md)
- [follows.md](follows.md) — the counters and the private-account flip
- [blocking.md](blocking.md) — the blocks list lives here
- [image-pipeline.md](image-pipeline.md) — avatar and cover processing
- [image-moderation.md](image-moderation.md) — the scan the URL validator forces
- [text-moderation.md](text-moderation.md) — display name and bio
- [feed-and-search.md](feed-and-search.md) — search, and `public_profile_text`
- [legal-and-age-gate.md](legal-and-age-gate.md) — `date_of_birth`, `tos_current`
- [admin-and-appeals.md](admin-and-appeals.md) — `is_active`, `moderation_status`
- [reference/data-model.md](../reference/data-model.md)
