# Legal documents, ToS acceptance and the 16+ age gate

**Status:** shipped (the Google-sourced birthday half is **blocked externally**)
**Tables:** `users.tos_accepted_at`, `.tos_accepted_version`, `.date_of_birth`, `.dob_source`
**Config:** none (versions are code constants)

## Purpose

Three legal documents in six languages, served through one pipeline to both the
website and the app; an explicit ToS acceptance recorded on every signup path;
and a 16+ minimum age the ToS had asserted for a release before anything asked
for one.

## Rules

### The documents

| Document | Version | Date |
|---|---|---|
| Terms of Service | **3.1** | 2026-08-08 |
| Privacy Policy | **2.3** | 2026-10-07 |
| Community Guidelines | **1.1** | 2026-08-06 |

- **Bodies live in `app/constants/legal/<lang>.py`, one module per *language*
  (not per document)**, each exporting `TOS` / `PRIVACY` / `GUIDELINES` as
  **plain text**.
- **Plain text, never HTML.** The same string renders on the web page
  (`white-space: pre-wrap`) and in the Flutter sheet, which is a bare `Text`.
  HTML would need a renderer package on the client or a second copy of every
  document.
- `app/constants/{tos,privacy,guidelines}.py` keep the version/date constants and
  expose `get_tos(lang)` / `get_privacy(lang)` / `get_guidelines(lang)`, all
  through `legal.document()`, which **falls back to English twice over** —
  unknown language code, and a language module missing that document.
- **English is authoritative.** Every other language carries a
  prevailing-language clause from `i18n.py` (`legal_notice_terms` / `_privacy` /
  `_guidelines`, empty for `en`) — **one key per document, not one with a
  `{document}` placeholder**, because Arabic and Chinese put the noun where
  interpolation cannot reach it.
- **One template, `legal.html`, for all three routes.** They were three
  near-identical files, so `dir="{{ dir }}"` (Arabic needs RTL — the old
  `dir="ltr"` predates translation), the translated `<h1>`, and the "Last
  updated"/"Version" labels each had to be fixed three times.
- **`i18n.py` `SUPPORTED` must stay in step with the app's `kAppLocaleCodes`** —
  the app appends `?lang=<its locale>` when it opens a legal page in the browser,
  and a code missing there silently serves English.
- **`GET /auth/tos?lang=` returns all three documents plus their notices in one
  response.** Three consumers share it: the signup agreement, the Google consent
  sheet, and the re-acceptance gate.
- **Privacy §5 names every third party that receives user data, in every
  language** — an undisclosed processor is a GDPR breach and a store-label
  mismatch. Translation (2.3) added Microsoft (Azure AI Translator) and widened
  OpenAI to "moderation and translation"; §4 became "Automated content
  moderation **and translation**" rather than gaining a section, because §5 and
  §11 are cited by number in the bodies, six times over.
  `test_privacy_names_every_translation_engine` fails a language that drops
  Microsoft.

### Acceptance

- **`TOS_VERSION` is written verbatim into `users.tos_accepted_version` at
  signup, on both paths.** Bumping it is what makes "which document did this
  person agree to" answerable. **Rows are never backfilled.**
- **`GoogleAuthRequest.tos_accepted` defaults `False`.** Only the
  create-a-new-account branch reads it, answering 400 `tos_required`; sign-in and
  account-linking never consult it. **Never default it `True` anywhere** — an
  account created without an explicit acceptance is the App Store 1.2 / Play UGC
  violation this was all built to close.
- **The client's move is consent-on-demand**: post the token, and on
  `tos_required` show the sheet and re-post the *same* ID token with `True`
  (Google ID tokens live ~1 h, verification is stateless). Asking before the
  picker would re-prompt every returning Google user at every sign-in.
- **`POST /auth/accept-tos` never takes a version** — it stamps the server's own
  `TOS_VERSION`, so a client cannot claim acceptance of a document it never
  rendered. Its body (`AcceptTosRequest`) carries a date of birth and nothing
  else, and **is itself optional** so a client deployed before the age gate still
  works.
- **The re-acceptance gate is client-side** — `UserPrivateProfile.tos_current`
  (reads the `User.tos_current` property) plus `TosGate` in `main.dart`'s
  `MaterialApp.router` builder. It sits **there, not in `_AppShell`**, because
  many routes are declared at the router's root level and would slip past a
  shell-mounted gate. It is inert unless `hasSessionProvider` **and** a loaded
  profile **and** `tos_current == false`, so `/splash` `/login` `/register`
  `/suspended` need no allowlist. **Loading and error fall through** — a profile
  we could not read is not evidence of a stale agreement.
- **`hasSessionProvider`, not `authNotifierProvider`**, is the "is somebody
  signed in?" signal: splash restores a session without calling
  `setAuthenticated`, so the notifier is null for exactly the returning users the
  gate exists for.
- **`AcceptTermsScreen` always carries a sign-out action.** A gate with no exit is
  a lockout, and signing out is also how someone reaches account deletion.
- **The document sheet subscribes to `legalDocumentsProvider` from inside its own
  route.** `showModalBottomSheet` builds on a separate route, so a parent
  `setState` never reaches it — capturing the body at call time is what left it on
  "Loading…" forever. Three async states: spinner, body, and **error with Retry +
  open-in-browser**.

### The age gate

- **`app/services/age_service.py` is the single source of truth** —
  `MINIMUM_AGE = 16`, `MAX_PLAUSIBLE_AGE = 120`, `calculate_age`, `is_old_enough`,
  `is_plausible`. **No router re-implements the arithmetic.**
- **16 clears GDPR Art. 8 in every member state**, so no parental-consent path is
  ever needed. It does **not** imply contract capacity, which is why the ToS keeps
  its separate age-of-majority / guardian clause.
- **The comparison is a tuple compare** (`(today.month, today.day) < (dob.month,
  dob.day)`), which is what makes a 29 February birth turn 16 on 1 March.
  **`DateOfBirthField.isOldEnough` mirrors it on the client and the two must stay
  in step.**
- **Shape errors are 422, policy refusals are 400.** A future or >120-year date
  fails `_dob_must_be_plausible` in the schema; a real date under 16 answers
  **400 `underage`** from the router. The client renders a field error for one and
  a message for the other.
- **The age check runs *before* `moderate_or_422`**, exactly like the
  `tos_accepted` gate above it — an underage signup must not spend a paid provider
  call to earn its 400. **`create_user` re-checks** (it commits, so a later failure
  could not undo the account).
- **Three enforcement points**: `/auth/register`, the Google new-account branch,
  and `/auth/accept-tos`.
- **Only the Google create-a-new-account branch reads `date_of_birth` /
  `google_access_token`** — the same rule that governs `tos_accepted`. Sign-in and
  linking must never consult them or every returning user is re-prompted forever.
- **Google supplies the date when it can; the consent sheet is the guaranteed
  fallback.** Google ID tokens carry **no birthdate claim**; it needs the People
  API, the `user.birthday.read` **sensitive scope**, and an access token. Many
  accounts have no birthday, many more hide the **year** (`{month, day}` cannot
  answer an age question), and the scope is refusable. **`dob_source` records
  which source stood behind the account.**
- **`google_people.fetch_birthdate` verifies `resourceName == "people/{sub}"`** —
  the access token is a separate credential, so without this check a caller could
  pair their own ID token with an access token minted for a different Google
  account and inherit that account's birthday. It returns `None` for every
  unusable answer and **never raises**.
- **The client requests the birthday scope only after the server answers
  `tos_required`** — that 400 is the only signal the token means signup rather than
  sign-in. The client's People API read is a **prefill hint only**; the server
  re-reads it and its answer is what gets stored.
- **Existing accounts backfill at the re-acceptance gate.** `date_of_birth` is
  nullable and **never backfilled with a date nobody gave us**.
  `AcceptTermsScreen` shows the field exactly when
  `UserPrivateProfile.date_of_birth` is null, and `accept-tos` 400s `dob_required`
  until one arrives. **An existing date is never overwritten** — it is a
  declaration of record, and re-declaring on demand would defeat the gate.
- **`date_of_birth` is on `UserPrivateProfile` only** — never on `UserBase` or
  `UserPublicProfile`.

## Data model

Four columns on `users`: `tos_accepted_at`, `tos_accepted_version` VARCHAR(16),
`date_of_birth` DATE nullable, `dob_source` VARCHAR(16) nullable. Plus the
`tos_current` property (`tos_accepted_version == TOS_VERSION`).

Migrations: `9dcbd2b7d34c` and `e493ea56a71b` (ToS version / accepted_at),
`2ddec1197cc9` (date of birth). Full columns:
[reference/data-model.md](../reference/data-model.md#users).

## API surface

| Method | Path | Auth | Rate | Request | Response |
|---|---|---|---|---|---|
| GET | `/auth/tos?lang=` | **none** | — | — | all three documents + versions + dates + notices + `abuse_contact` + `community_guidelines_url` |
| POST | `/auth/accept-tos` | Bearer | 10/h | `AcceptTosRequest{date_of_birth?}` — **body optional** | `UserPrivateProfile` |
| GET | `/terms`, `/privacy`, `/guidelines` | none | — | `?lang=` | HTML (`legal.html`) |

`tos_accepted` also appears on `RegisterRequest` and `GoogleAuthRequest`, and
`date_of_birth` on `RegisterRequest`, `GoogleAuthRequest` and `AcceptTosRequest`.

New error codes: `tos_required`, `underage`, `dob_required`.

## Flutter surface

- **`AcceptTermsScreen`** — **no route**; mounted by `TosGate`
  (`features/auth/presentation/widgets/tos_gate.dart`) inside
  `MaterialApp.router`'s builder.
- **`legalDocumentsProvider`** — `FutureProvider`
  (`features/auth/providers/legal_provider.dart`), subscribed from inside the
  sheet's own route.
- `DateOfBirthField` — mirrors `is_old_enough`, including the leap-year rule.
- l10n keys: `registerDob`, `registerDobHelp`, `registerDobHint`,
  `registerDobRequired`, `registerDobTooYoung`, `dobPickerHelp`, `dobFromGoogle`,
  `acceptTermsDobPrompt`, `googleConsentDobLabel`, plus `errorUnderage` /
  `errorDobRequired`, which `localizedApiError` maps from `underage` /
  `dob_required` so the signup and re-acceptance screens show them in the
  reader's language.

## Known gaps / TODOs

- **The Google-sourced half is blocked on OAuth verification** for
  `user.birthday.read` — a 100-test-user cap and an "unverified app" warning until
  it clears. The sheet fallback means everything else ships without waiting.
- **App Store privacy nutrition label and Play Data safety both need the DOB
  declared** — outstanding.
- **The six-language translations still need counsel review**, and English is
  authoritative in the meantime — the 2.3 translation paragraphs included.
- **ToS §12's list of service categories names neither push notifications nor
  translation.** It defers to the Privacy Policy for the list, and changing ToS
  text needs a `TOS_VERSION` bump, which sends every user through the
  re-acceptance gate — so it waits for the next ToS change that needs one.
- **App Store privacy label and Play Data safety must name Microsoft** before
  translation is switched on.
- Tests: `test_legal_documents.py`, `test_tos_acceptance.py`, `test_age_gate.py`,
  `test_web_i18n.py` all run.

## Related

- [authentication.md](authentication.md) — the two gates before moderation
- [google-sign-in.md](google-sign-in.md) — consent-on-demand and the People API
- [accounts-and-profiles.md](accounts-and-profiles.md) — the four columns, private-only DOB
- [text-moderation.md](text-moderation.md) — why the age check runs first
- [help-centre.md](help-centre.md) — shares `i18n.py` `SUPPORTED` and the SEO layer
- [web-and-platform.md](web-and-platform.md) — the server-rendered legal pages
- [reference/error-codes.md](../reference/error-codes.md#registration-tos-and-age-gate)
- [translations.md](translations.md) — the two engines Privacy §4 and §5 disclose

## OPEN QUESTIONS

- **The ratings clause says "score only", but account deletion keeps the review
  text.** The ToS ("anonymized form (score only, no identifying information)")
  and Privacy §10 ("score only, no user link") both say so, while
  `delete_my_account` only nulls `itinerary_ratings.user_id`: the `note` — and
  now its cached translations — survive. Either the deletion should clear the
  note, or both documents should say the text is kept. Undecided; the documents
  were left as they are in 2.3.
