# App links (shared links open the app)

**Status:** shipped (**off unless configured** — the association files 404 until their ids are set)
**Tables:** none
**Config:** `IOS_APP_IDS`, `ANDROID_APP_PACKAGE`, `ANDROID_CERT_SHA256`, `IOS_APP_STORE_ID`, `APP_STORE_URL`, `PLAY_STORE_URL`

## Purpose

A shared link — `https://ntripi.app/share/i/{id}` for a trip, `/share/u/{username}`
for a profile — opens the trip or profile **in the app** on a phone that has it
(iOS Universal Links, Android App Links). Without the app it opens the share
page, which encourages the app first and always lets the visitor **continue on
the web**. A link that cannot be opened gets one of exactly two answers: **no
access** or **not available**.

## Rules

### Which links are claimed

**Share links only: `/share/i/*` and `/share/u/*`.** Emailed token links
(`/reset-password`, `/verify-email`, `/appeal/{token}`) are server-rendered forms
and must keep opening in the browser, so the claim is never widened to `/*` — the
Flutter cookbook's example does exactly that.

The claim is one contract across four places, changed together:

| Where | What it says |
|---|---|
| `social_api/app/services/app_links.py` `APP_LINK_PATHS` | the paths in `apple-app-site-association` |
| `social_flutter/android/app/src/main/AndroidManifest.xml` | the `autoVerify` intent filter: `https`, host `ntripi.app`, `pathPrefix` `/share/i/` and `/share/u/` |
| `social_flutter/ios/Runner/Runner.entitlements` | `applinks:ntripi.app` (host only — iOS takes the paths from the AASA) |
| `social_flutter/lib/core/router/app_links.dart` `appLinkLocation` | the in-app route each path opens |

`test_app_links.py` pins the server's half (every claimed prefix is a real
`/share` route); `test/app_links_native_config_test.dart` pins the client's three
to each other and to the `SHARE_BASE_URL` host the release scripts build with.

**The native configs hard-code `ntripi.app`.** The associated domain is part of
the signed app's identity — validated against the provisioning profile, verified
by Android at install — like the bundle id and the Google client ids already in
`Info.plist`. It cannot be runtime config; a build for another domain is a
different app. The guard test is what keeps it equal to `SHARE_BASE_URL`.

### The association files

- `GET /.well-known/apple-app-site-association` — `{"applinks": {"details":
  [{"appIDs": IOS_APP_IDS, "components": [{"/": "/share/i/*"}, {"/": "/share/u/*"}]}]}}`.
  The `components` form needs iOS 13; the deployment target is 15.
- `GET /.well-known/assetlinks.json` — one `delegate_permission/common.handle_all_urls`
  statement for `ANDROID_APP_PACKAGE` with every `ANDROID_CERT_SHA256`.
- Both are fetched by machines (Apple's CDN, Google's verifier), never people.
  Each must answer **200 `application/json` at exactly that path**: a redirect, an
  HTML error page or a bot challenge fails the association silently, and every
  link keeps opening in the browser with nothing logged anywhere.
- **Unset = invisible**: unconfigured, both answer the same 404 as an unknown path
  (`ApiError` `not_found`, like `/internal/moderation-sweep`).
- `Cache-Control: public, max-age=3600` — identical for every visitor and keyed by
  nothing but the URL. `ETagMiddleware` keeps an endpoint-set `Cache-Control`.
- **Android needs the fingerprint of every certificate a shipped build is signed
  with**: the Play app-signing key (every Play install, internal testing included)
  and the upload key (locally built releases). `_validate_app_links` normalises
  either spelling (keytool's colons, the Play Console's case) and refuses a value
  that is not 32 hex bytes, a package without fingerprints or the reverse, a
  malformed `TEAMID.bundle.id`, a non-numeric `IOS_APP_STORE_ID`, and a non-https
  store URL — a typo there verifies nothing and fails nowhere visible.

### Delivery inside the app

Flutter's own deep linking (on by default since 3.27, set explicitly:
`FlutterDeepLinkingEnabled` in `Info.plist`, `flutter_deeplinking_enabled` in the
manifest) hands the URL to go_router as a navigation to its path. **No plugin**:
a plugin such as `app_links` would need deep linking turned off, and the engine
already handles both lifecycles, UIScene included. Neither navigation may land as
it arrives — a cold start's would skip splash, a warm one's is a `go()` that
replaces the stack — so `app_links.dart` intercepts both:

| When the link arrives | What happens | Hook |
|---|---|---|
| Cold start | parked; the app goes to `/splash`, which restores the session and opens it **over home** | the redirect's first step, `appLinkLaunchRedirect` |
| While splash is up | parked for splash | `appLinkOnEnter` → `Block.stop()` |
| Signed out | parked, and opened by the next sign-in (password, Google or registration) | `appLinkOnEnter` → `Block.stop()`; `landHome` |
| Signed in, app running | opened **over the current screen** — Back returns to it, unsaved text survives | `appLinkOnEnter` → `Block.then(openFromOutside)` |
| The same link again, already open | nothing — never stacked twice | `appLinkOnEnter` |

- **Every landing goes through `landHome(router, {pushRoute})`** — splash, the two
  login paths, registration: a tray tap or a parked link opens over home in one
  navigation (`pushOverHome`), otherwise home. A parked link is consumed either
  way.
- **A link is parked while signed out; a tray tap is dropped.** A tray entry
  belongs to the session that was open when it was sent; a link belongs to no
  session, and someone who just installed the app is exactly who taps one before
  signing up.
- `appLinkOnEnter` reads the visible page from `current`, never from
  `routerDelegate.currentConfiguration.uri`: after a push the match list's own uri
  stays at the route the pushes sit on.
- Same rule as a notification tap (see [notifications.md](notifications.md#flutter-surface)):
  a screen opened from outside the app is never alone on its navigator, and leaves
  through `popOr` in every state.
- **Android uses `launchMode="singleTask"`.** With the template's `singleTop` +
  `taskAffinity=""`, a link tapped in Gmail or WhatsApp started a second copy of
  the app in the caller's task. `taskAffinity=""` stays (the template's guard
  against task hijacking); `singleTask` finds the running task by its root
  activity anyway. If a device ever shows two Ntripi entries in Recents after a
  warm link, dropping `taskAffinity=""` is the documented fallback.

### Where a link lands, and the two answers when it can't

`appLinkLocation` checks the id before anything is fetched:

| Link | Opens |
|---|---|
| `/share/i/<uuid>` | `/itineraries/<uuid>` |
| `/share/u/<name>` | `/u/<name>` → `ProfileByUsernameScreen`: `GET /users/{identifier}` with the handle (it takes either), then the profile by id (your own handle → your own profile) |
| `/share/i/<anything else>` — cut short, `new`, empty | `/unavailable/trip` — `new` can never open the create-trip form |
| `/share/u/` with no name | `/unavailable/profile` |

| Answer | When | In the app | On the web |
|---|---|---|---|
| **No access** | the trip is shared with followers or specific people and you are not in; also only-me, moderator-hidden, suspended owner, blocked either way — the API answers one 403 `itinerary_access_denied` for all of them | "You can't open this itinerary" + **Go back** (`ItineraryUnavailableView.noAccess`) | followers / specific people: the private page — **no title, owner or cover**, on the page or in its preview. Only-me, hidden, suspended: the not-available page, as before |
| **Not available** | deleted or never existed (404); a malformed link; a profile that is unknown, deleted, suspended or blocked | "This itinerary isn't available" + **Go back**; profiles: `ProfileUnavailableView` | the not-available 404 page — profile wording for profile links — with **Go to Ntripi** and the store buttons |

Neither answer says **why**, and neither has a Retry: both are answers, not
failures. The client branches on status and code only, so it reveals nothing the
API does not already say — and a block reads exactly like any other "not shared
with you". Offline and server errors keep message + **Retry** + **Go back**.

### The share pages: app first, web second

Built by `app_links.cta_context(share_url, settings)` and the macros in
`templates/_app_links.html` (imported `with context`: `_` is a context-processor
value):

- **Open in app** — Android only: a Chrome `intent://` URL for the same link with
  `package=` and an absolute `S.browser_fallback_url` (the Play URL, else the
  waitlist). It is rendered `hidden` and revealed by script on Android, because
  iOS never opens an app for a link to the page's own domain — there the button
  could only reload the page. The `[hidden]` CSS rule in `app_links_head` is
  load-bearing: every page styles its buttons with `display`, which beats the
  attribute.
- **Store buttons** — `APP_STORE_URL` / `PLAY_STORE_URL`, else the homepage
  waitlist (`/#get-the-app`), the same honest pre-launch destination the help CTA
  uses. The nav's **Get the app** points there too, swapped for the visitor's own
  store on a phone. Launch day is a variable change.
- **Smart App Banner** — `<meta name="apple-itunes-app">` with
  `app-argument=<share URL>`, only when `IOS_APP_STORE_ID` is set. Safari draws it
  only once the app is live in the store, never for a TestFlight-only build.
- **Continue on web** — `/app/#/share/i/<id>` or `/app/#/share/u/<name>`: the
  Flutter web build runs the same router hooks, so the web app signs the visitor
  in if needed and lands on the same trip or profile. Secondary to the app on
  purpose, never the first button; nothing redirects to a store or blocks a
  public trip from being read.
- The dead `ntripi://` scheme the pages used to link is gone — the app never
  registered it, and any app can register a custom scheme.

## Data model

None.

## API surface

| Method | Path | Auth | Response |
|---|---|---|---|
| GET | `/.well-known/apple-app-site-association` | none | AASA JSON, or 404 unconfigured (`include_in_schema=False`) |
| GET | `/.well-known/assetlinks.json` | none | Digital Asset Links JSON, or 404 unconfigured |
| GET | `/users/{identifier}` | bearer | `UserPublicProfile` — already took a handle as well as an id; `ProfileByUsernameScreen` resolves a link's handle with it. `/users/by-username/{username}` stays clientless |

`/share/i/{itinerary_id}` now takes its id as a string and parses it, so a
malformed or cut-short id renders the not-found page instead of FastAPI's raw
JSON 422.

## Config

| Variable | Default | Effect |
|---|---|---|
| `IOS_APP_IDS` | empty | `TEAMID.bundle.id`, comma-separated. Empty: the AASA 404s |
| `ANDROID_APP_PACKAGE` | empty | applicationId. Set together with the next, or startup refuses |
| `ANDROID_CERT_SHA256` | empty | SHA-256 of every signing certificate, comma-separated |
| `IOS_APP_STORE_ID` | empty | numeric App Store id; turns the Smart App Banner on |
| `APP_STORE_URL` / `PLAY_STORE_URL` | empty | download buttons; empty = the waitlist |

## Flutter surface

- `lib/core/router/app_links.dart` — `appLinkLocation`, `parkAppLink` /
  `takeParkedAppLink`, `appLinkLaunchRedirect` (the redirect's first step),
  `appLinkOnEnter` (the router's `onEnter`), `landHome`.
- `lib/core/storage/secure_storage.dart` — `hasLiveRefreshToken()`, the one
  "somebody is signed in" check the router, splash, `hasSessionProvider` and the
  link guard share.
- Root-level routes `/u/:username` (`ProfileByUsernameScreen`) and
  `/unavailable/:kind`.
- `features/itineraries/presentation/widgets/itinerary_unavailable_view.dart` —
  the two trip answers and `itineraryUnavailableFrom(error)`;
  `shared/widgets/unavailable_view.dart` — the layout they share with
  `ProfileUnavailableView`.
- Tests: `test/core/router/app_links_test.dart` (cold start through the real
  splash, warm delivery through `handlePushRoute`, parking, repeat taps, and every
  landing a root-level route), `test/app_links_native_config_test.dart`,
  `test/widgets/profile_by_username_screen_test.dart`, and the trip cases of
  `notification_destinations_exit_test.dart`.

## Known gaps / TODOs

- **No deferred deep linking.** Installing the app from the share page does not
  open the shared trip on first launch. See [backlog.md](../backlog.md).
- **No in-page "Open in app" on iOS** — Universal Links never fire for a link to
  the current page's own domain. A second subdomain would fix it; see the backlog.
- **Previews already in a chat stay.** Chat apps cache link previews per URL, so a
  private trip's card fetched before this release keeps its title and cover there.
- **Only `ntripi.app` is claimed** — not `www.ntripi.app`.
- The homepage's own download buttons still open the waitlist even once the store
  URLs are set. See the backlog.

## Related

- [sharing.md](sharing.md) — the pages these links open without the app
- [notifications.md](notifications.md) — the other way in from outside the app; `pushOverHome` / `openFromOutside`
- [web-and-platform.md](web-and-platform.md) — the route table, the middleware the association files pass through
- [visibility-and-access.md](visibility-and-access.md) — the single 403 behind "no access"
- [blocking.md](blocking.md) — why neither answer may say why
- [accounts-and-profiles.md](accounts-and-profiles.md) — immutable handles, the profile-by-handle lookup
- [help-centre.md](help-centre.md) — `share-a-trip-link`, `share-an-itinerary-privately`
