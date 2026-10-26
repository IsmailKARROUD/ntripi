# App links (shared links open the app)

**Status:** shipped (**off unless configured** — the association files 404 until their ids are set)
**Tables:** none
**Config:** `IOS_APP_IDS`, `ANDROID_APP_PACKAGE`, `ANDROID_CERT_SHA256`, `IOS_APP_STORE_ID`, `APP_STORE_URL`, `PLAY_STORE_URL`, `APP_OPEN_HOST`

## Purpose

A shared link — `https://ntripi.app/share/i/{id}` for a trip, `/share/u/{username}`
for a profile — opens the trip or profile **in the app** when it is tapped on a
phone that has it (iOS Universal Links, Android App Links). In a browser where the
reader is signed in to Ntripi, it opens the trip in the web app at once. Anywhere
else it opens the share page — a teaser (see
[sharing.md](sharing.md#what-a-reader-without-an-account-sees)) with one way in,
**See the full trip**, which signs the visitor in on the web and opens it — and on
a phone, **Open in Ntripi**. A link that cannot be opened gets one of exactly two
answers: **no access** or **not available**.

**A typed or pasted link never opens an app**, on either platform, and neither
does any `/app/#/…` address (the web app's own). Only a tap on a `/share/…` link
in another app — a chat, an email, a note — reaches the app; and no page can
open an app by itself, only offer the tap.

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
| `social_flutter/ios/Runner/Runner.entitlements` | `applinks:ntripi.app` and `applinks:open.ntripi.app` (hosts only — iOS takes the paths from the AASA, served the same on both) |
| `social_flutter/lib/core/router/app_links.dart` `appLinkLocation` | the in-app route each path opens |

`test_app_links.py` pins the server's half (every claimed prefix is a real
`/share` route); `test/app_links_native_config_test.dart` pins the client's three
to each other and to the `SHARE_BASE_URL` host the release scripts build with —
the entitlements to exactly that host and `open.` + it, which is what
`APP_OPEN_HOST` must name.

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

### Opening the app from the page

A share page open in a phone's browser means the OS did not hand the link to the
app — pasted, typed, opened in an in-app browser. The page then offers **Open in
Ntripi**; it can never open the app without the tap.

- **Android: Chrome says whether the app is installed.** The app vouches for the
  site in `asset_statements` (`AndroidManifest.xml` → `res/values/strings.xml`,
  `namespace: web`, `https://ntripi.app`), and the page links
  `/manifest.webmanifest`, whose `related_applications` names the package.
  `navigator.getInstalledRelatedApps()` (Chrome 80+) then answers, and
  `reader_head` (`_app_links.html`, in `<head>`) records it on `<html data-app>`:
  `pending` → `installed` or `absent`. Installed: the intent button (**Open in
  Ntripi**, `data-app-open="android"`) comes first and leads, the web button
  turns tonal, the store badges and the nav's **Get the app** go. Absent: the
  button is hidden — it could only lead to the store. A browser without the
  check (Firefox, in-app browsers) or no answer within 800 ms: the tonal button
  as before. The manifest has `display: browser` and no
  `prefer_related_applications`, so the page is never offered as an installable
  web app and Chrome never pushes the store listing.
- **iPhone: a second host.** iOS opens an app only for a tap on a link to
  another domain than the page's, so the button (`data-app-open="ios"`,
  `rel="nofollow"`) links `https://{APP_OPEN_HOST}/share/…` — `open.ntripi.app`,
  claimed in the entitlements beside `ntripi.app`. With the app, the tap opens
  it on the trip (`appLinkLocation` ignores the host). Without it, Safari loads
  the URL, and `OpenHostMiddleware` (`app/middleware/open_host.py`) answers
  302 → the same page on `SHARE_BASE_URL` with `?app=missing`, where the script
  shows "The Ntripi app didn't open on this device" in place of the button.
  iOS cannot tell a page whether an app is installed, so the button stays under
  **See the full trip** until the App Store is live (`store-first` then moves
  the whole row up).
- **The open host serves nothing but `/.well-known/*`.** Apple's CDN fetches the
  AASA from every claimed host and must get a 200; any other path there gets a
  301 to `SHARE_BASE_URL`. A second copy of the site would have its own
  localStorage, out of reach of the share pages' signed-in check below.
- `APP_OPEN_HOST` is validated at startup: a bare host name, not the share host
  (a same-domain tap opens nothing), and only with `IOS_APP_IDS`. Unset, no
  iPhone button is rendered and the middleware does nothing.

### A reader already signed in on the web

The share pages and the web app share an origin, so the page can read the web
app's localStorage — but not its tokens, which flutter_secure_storage keeps
encrypted. So the web app keeps **one plain entry while a session lasts**:
`ntripi_web_session_until`, the refresh token's expiry (`web_session_hint.dart`;
the key is `app_links.WEB_SESSION_HINT_KEY` on the server). `saveTokens` writes
it and `clearAllTokens` removes it — the only two places tokens change, so login,
registration, Google, a refresh, sign-out, a suspension and a rejected refresh
all keep it true — and `main.dart` syncs it once at launch for sessions older
than the entry.

`reader_head`, in each teaser page's `<head>`, reads it before the body is
drawn: live (or with an end it cannot read, which counts as live, as
`hasLiveRefreshToken` does) → `location.replace(web_app_url)` with the body
hidden, so the reader never sees the teaser. `replace`, never `assign`: Back must
not land on a page that sends it forward again. On Android it first waits up to
800 ms for Chrome's installed-app answer, and an installed app wins: the page
stays, with **Open in Ntripi** first. iOS cannot answer, so there a signed-in
browser goes to the web app even with the app installed. A session that turns
out dead — revoked elsewhere — reaches the web app's splash, fails its refresh
and is parked through the sign-in, as **See the full trip** would have been. The
entry is an end time and nothing else: every script on the origin can read it.

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

### The share pages: a teaser and one way in

Built by `app_links.cta_context(share_url, settings)` and the macros in
`templates/_app_links.html` (imported `with context`: `_` is a context-processor
value); `_share_layout.html` calls `app_links_head` and `app_links_script`, and
each page calls `teaser_gate`:

- **See the full trip** / **See the full profile** — `/app/#/share/i/<id>` or
  `/app/#/share/u/<name>`: the Flutter web build runs the same router hooks, so
  a visitor signed in on the web lands on the trip at once, and one who is not is
  sent to sign in (the link parked, `ParkedLinkNotice` saying so) and lands on it
  after. **First by default**: before launch the stores lead to a waitlist, and a
  desktop cannot install from a store page at all. Until 2026-10-19 this was the
  secondary **Continue on web** under a full, readable trip.
- **Store buttons** — `APP_STORE_URL` / `PLAY_STORE_URL`, else the homepage
  waitlist (`/#get-the-app`), the same honest pre-launch destination the help CTA
  uses. The nav's **Get the app** points there too, swapped for the visitor's own
  store on a phone. **A phone sees only its own store**: Google Play on Android,
  the App Store on an iPhone — and on an iPad, whose Safari has reported a Mac
  since iPadOS 13 and is told apart by its touch points. `platform_head`
  (`_app_links.html`) decides once, in `<head>` before a badge is parsed, onto
  `<html data-platform>`, and one CSS rule hides the other store;
  `app_links_script` reads that answer rather than the User-Agent again. A
  laptop, an unknown device and a browser without JavaScript get both, and both
  are always in the HTML. **Once a store is live** (`app_store_live` /
  `play_store_live`: its URL is set), `app_links_script` moves the store row
  above the web button on a phone of that platform and reveals "Once it's
  installed, tap the link again to open it in the app" — installing does not
  carry the link into the app. A desktop keeps the web button first. Launch day
  is still a variable change.
- **Open in Ntripi** — on Android a Chrome `intent://` URL for the same link
  with `package=` and an absolute `S.browser_fallback_url` (the Play URL, else
  the waitlist), led or hidden by Chrome's installed-app answer; on an iPhone a
  link to the same path on `APP_OPEN_HOST` — see
  [Opening the app from the page](#opening-the-app-from-the-page). Both are
  rendered `hidden` and revealed by script on their own platform only. The
  `[hidden]` CSS rule in `app_links_head` is load-bearing: the pages style their
  buttons with `display`, which beats the attribute.
- **Smart App Banner** — `<meta name="apple-itunes-app">` with
  `app-argument=<share URL>`, only when `IOS_APP_STORE_ID` is set. Safari draws it
  only once the app is live in the store, never for a TestFlight-only build.
- Without JavaScript every page stays at its safe default: web first, no
  app button, no hint, no redirect.
- The dead `ntripi://` scheme the pages used to link is gone — the app never
  registered it, and any app can register a custom scheme.

## Data model

None.

## API surface

| Method | Path | Auth | Response |
|---|---|---|---|
| GET | `/.well-known/apple-app-site-association` | none | AASA JSON, or 404 unconfigured (`include_in_schema=False`) |
| GET | `/.well-known/assetlinks.json` | none | Digital Asset Links JSON, or 404 unconfigured |
| GET | `/manifest.webmanifest` | none | `application/manifest+json` naming the Android app in `related_applications`, or 404 without `ANDROID_APP_PACKAGE` (`include_in_schema=False`) |
| any | anything on `APP_OPEN_HOST` | none | `/.well-known/*` as on the main host; `/share/i|u/…` → 302 the same page on `SHARE_BASE_URL` with `?app=missing`; anything else → 301 `SHARE_BASE_URL` |
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
| `APP_STORE_URL` / `PLAY_STORE_URL` | empty | download buttons; empty = the waitlist. Paste them without a country or language (no `/us/`, no `&hl=`), or the store opens in that one for everyone |
| `APP_OPEN_HOST` | empty | the second host the iPhone **Open in Ntripi** links (`open.ntripi.app`, as the entitlements claim). Needs `IOS_APP_IDS`; must differ from the share host. Set it only once the host answers — a Railway custom domain and a proxied Cloudflare CNAME — and Apple's CDN serves its AASA |

## Flutter surface

- `lib/core/router/app_links.dart` — `appLinkLocation`, `parkAppLink` /
  `takeParkedAppLink` / `parkedAppLink` (a listenable, never consumed) and
  `parkedLinkKind`, `appLinkLaunchRedirect` (the redirect's first step),
  `appLinkOnEnter` (the router's `onEnter`), `landHome`.
- `features/auth/presentation/widgets/parked_link_notice.dart` —
  `ParkedLinkNotice`, the line above the sign-in and sign-up forms while a link
  waits ("Sign in or create a free account to open the trip you were sent").
- `lib/core/storage/secure_storage.dart` — `hasLiveRefreshToken()`, the one
  "somebody is signed in" check the router, splash, `hasSessionProvider` and the
  link guard share; and the web session hint, written by `saveTokens`, removed by
  `clearAllTokens`, synced at launch by `syncWebSessionHint()`
  (`web_session_hint.dart`, `_web.dart` localStorage, `_io.dart` nothing).
- `lib/core/router/app_links.dart` also holds the web's landing rules, the
  redirect's two steps after `appLinkLaunchRedirect`: `editingRouteLaunchRedirect`
  (`editingRouteLanding`) and `signInRedirect` (`parkableLocation`); see
  [web-and-platform.md](web-and-platform.md#flutter-surface).
- Native: `android/app/src/main/res/values/strings.xml` (`asset_statements`) and
  its `<meta-data>` in the manifest; the second `applinks:` entry.
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
  open the shared trip on first launch; once a store is live the page tells a
  phone visitor to tap the link again. See [backlog.md](../backlog.md).
- **The iPhone button is off until the open host is set up**: a Railway custom
  domain, a proxied Cloudflare CNAME (with the Bot Fight skip rule covering its
  `/.well-known`), Apple's CDN serving its AASA, a build carrying the second
  `applinks:` entry, then `APP_OPEN_HOST`.
- **iOS cannot say whether the app is installed**, so an iPhone signed in on the
  web goes to the web app when a link is pasted into Safari, app or not; and the
  iPhone button is offered to readers without the app, who come back to the
  page with the "didn't open" note.
- **Android's installed-app check needs Chrome 80+** and a build carrying
  `asset_statements`; installs from before it, other browsers and in-app
  browsers get the tonal button as before.
- **A `/app/#/…` address never opens the app**, even tapped in a chat: it is the
  web app's own URL, and the app claims only `/share/*`. Ntripi's Share and Copy
  link always hand out the `/share/` form.
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
