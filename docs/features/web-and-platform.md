# Web surfaces and platform

**Status:** shipped
**Tables:** `waitlist`
**Config:** `ALLOWED_HOSTS`, `ALLOWED_ORIGINS`, `DEBUG`, `ANDROID_DOWNLOAD_URL`, `STORAGE_*`; the app-link ids and store URLs (see [app-links.md](app-links.md#config))

## Purpose

Everything the FastAPI app serves that is not the JSON API or the help centre: the
marketing homepage, the pre-launch waitlist, the server-rendered auth pages, the
Flutter web app mount, `robots.txt`, the language cookie, and the middleware stack
the whole application sits inside.

## Rules

### The middleware stack

**`add_middleware` is LIFO — the last call is the outermost layer.** Code order in
`main.py` is the reverse of runtime order:

| Code order (first added = innermost) | Runtime request order (outermost first) |
|---|---|
| `RequestTimingMiddleware` | `ProxyHeadersMiddleware` |
| `OpenHostMiddleware` | `ClientIPHeaderMiddleware` |
| `LanguageCookieMiddleware` | `TrustedHostMiddleware` |
| `ETagMiddleware` | `ContentSizeLimitMiddleware` |
| `CORSMiddleware` | `SecurityHeadersMiddleware` |
| `SecurityHeadersMiddleware` | `CORSMiddleware` |
| `ContentSizeLimitMiddleware` | `ETagMiddleware` |
| `TrustedHostMiddleware` | `LanguageCookieMiddleware` |
| `ClientIPHeaderMiddleware` | `OpenHostMiddleware` |
| `ProxyHeadersMiddleware` | `RequestTimingMiddleware` → handlers |

`RequestTimingMiddleware` is added **first** and is therefore the innermost
layer; it rewrites nothing. `OpenHostMiddleware` comes next: on `APP_OPEN_HOST`
it answers everything but `/.well-known/*` with a redirect to `SHARE_BASE_URL`
(see [app-links.md](app-links.md#opening-the-app-from-the-page)), from inside
`SecurityHeadersMiddleware` so its redirects carry HSTS, and unset it does
nothing. `LanguageCookieMiddleware` touches only `text/html` responses. None of
the three affects the security ordering.

- **`ProxyHeadersMiddleware` is outermost** — it rewrites `X-Forwarded-Proto`
  into the scheme (HSTS needs it) and `X-Forwarded-For` into
  `request.client.host`. With `trusted_hosts="*"` uvicorn 0.41 takes the
  **leftmost** X-Forwarded-For entry, and Cloudflare appends to a client-supplied
  header rather than replacing it — so on its own that value is caller-chosen.
- **`ClientIPHeaderMiddleware` (`app/middleware/client_ip.py`) has the last word
  on the client IP**, which every `slowapi` limit keys on. It sets
  `request.client` from `CLIENT_IP_HEADER` (default `cf-connecting-ip`), a header
  Cloudflare overwrites; absent or unparseable, the X-Forwarded-For answer stands
  (local dev). Until 2026-09-28 any caller could forge its IP and walk past the
  login, register, forgot-password, report and appeal limits. A request that
  reaches Railway directly, bypassing Cloudflare, can still forge either header —
  closing that is edge configuration. See [decisions.md](../decisions.md).
- **`TrustedHostMiddleware`** reads `ALLOWED_HOSTS` (comma-separated). **The apex
  domain and the wildcard must both be listed separately**
  (`ntripi.app,*.ntripi.app`) — Starlette's wildcard does not match the bare
  apex.
- **`ContentSizeLimitMiddleware`** (`main.py:121`) — POST/PUT/PATCH/DELETE only,
  `Content-Length > 10 MB` → **413**. A secondary backstop: chunked encoding can
  omit `Content-Length`.
- **`SecurityHeadersMiddleware`** applies `X-Content-Type-Options: nosniff`,
  `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`,
  `Content-Security-Policy: frame-ancestors 'none'`, and — **HTTPS only** —
  `Strict-Transport-Security: max-age=31536000`.
  - **CSP uses only `frame-ancestors`** — `default-src 'self'` is meaningless for
    a JSON API.
  - **HSTS carries no `includeSubDomains`** — Cloudflare and `*.r2.dev` are not
    fully ours.
  - It skips `STATIC_PREFIXES`, matched on a segment boundary
    (`is_static_path`) — a bare `startswith("/app")` also skipped `/appeal/…`
    and `/appeals/…`, leaving the public appeal form frameable until 2026-09-28.
  - **`/embed/*` is the one framable path family** (`is_embed_path`, segment
    boundary): the Google map pages answer `X-Frame-Options: SAMEORIGIN` and
    `Content-Security-Policy: default-src 'none'; frame-src
    https://www.google.com; style-src 'unsafe-inline'; base-uri 'none';
    frame-ancestors <EMBED_FRAME_ANCESTORS>` (default `'self'`) plus
    `X-Robots-Tag: noindex`, so the web app and a listed local web build may
    frame them. See [places-and-maps.md](places-and-maps.md).
- **`CORSMiddleware` uses explicit method and header lists, never `["*"]`.**
  Methods `GET POST PATCH DELETE OPTIONS`; headers `Content-Type`,
  `Authorization`, `If-Match`, `If-None-Match`, **`X-Edit-Lock`** — dropping the
  last would fail the browser preflight before an itinerary mutation is even sent.
- **`RequestTimingMiddleware` (`app/middleware/request_timing.py`) logs a slow
  request at WARNING** — the only level Railway shows. A request slower than
  `SLOW_REQUEST_LOG_MS` (default 1000; `0` logs every request) gets one line:
  method, **route template** (never the path, so no id or username is logged),
  status, total time, database time and query count, outbound HTTP time per host,
  and the remainder:
  `slow request: POST /itineraries/{itinerary_id}/stops status=201 total=812ms db=45ms/14q ext=api.openai.com:610ms/1 other=157ms`.
  - **Log only, never a `Server-Timing` header** — a query count or a duration
    would tell any caller whether an account or a trip exists.
  - **Database time** comes from class-level `Engine` cursor-execute listeners;
    **outbound time** from wrapping the two seams every integration passes
    through, `requests.Session.send` and botocore's `URLLib3Session.send`
    (`install_outbound_hooks`, called in `main.py`). A new HTTP client library
    outside those two needs a hook there. A redirect is timed once.
  - The record rides a `ContextVar`, which anyio copies into the worker thread
    running a sync endpoint. The clock stops at the last body chunk, so a
    background task is not counted. It skips `/health` and `STATIC_PREFIXES`.
  - **FCM is never in a request's line.** Pushes are sent by the push worker
    after the request, in a context with no record (since 2026-10-22,
    [notifications.md](notifications.md)); until then a write that notified
    someone carried `ext=fcm.googleapis.com`.
  - Added 2026-10-20, after a Postgres service in another region slowed every
    save for weeks with nothing in the logs. See [decisions.md](../decisions.md).
- **`STATIC_PREFIXES` lives in `app/middleware/__init__.py`**, shared by the
  ETag, security-headers and request-timing middleware. **Add a new static mount
  there, not in each middleware.**

### Rate limiting

- `slowapi`, `Limiter(key_func=get_remote_address)`. **The singleton lives in
  `app/limiter.py`** to avoid a circular import — `main.py` imports routers, so
  routers cannot import from `main.py`. Import `limiter` in a router; set
  `app.state.limiter = limiter` in `main.py`.
- **In-memory store.** Sufficient for a single Railway instance; **needs Redis if
  horizontally scaled**. The same single-instance assumption appears in four
  places.

| Limit | Endpoints |
|---|---|
| 5/hour | `POST /auth/register`, `/auth/change-password`, `/web/appeal-request`, `/bug-reports` |
| 10/minute | `/auth/login`, `/auth/google`, `/users/me/avatar`, `/users/me/cover-image`, `/admin/login`, `/internal/moderation-sweep` |
| 60/minute | `/auth/refresh`, `POST /translations` |
| 3/hour | `/auth/forgot-password`, `/auth/resend-verification` |
| 10/hour | `/auth/accept-tos`, `/appeals`, `/web/appeal`, `POST /reports` |
| 30/minute | `GET /users/search`, `GET /itineraries/feed` |
| 120/minute (`SHARE_RATE_LIMIT`) | `GET /share/i/{id}`, `GET /share/u/{username}` |

The `/share` limit answers with an **HTML** page (`share_rate_limited.html`,
`Retry-After` set) rather than slowapi's JSON, because those pages are read in
browsers — `main.py`'s `_rate_limit_response` picks by path; every other limited
route keeps the JSON body.

**`POST /waitlist/join` and `GET /help/search` are the two unlimited public
POST/GET surfaces** — the latter deliberately, the former apparently not.

### The public surface

**A reader without an account — a person, a chat crawler, a search engine —
reaches the share-page teaser and nothing else**, and
`test_public_surface.py` proves it two ways:

- **Structurally**: it introspects `app.main.app.routes`, and every route whose
  dependency tree holds no `get_current_user` / `require_verified_email` must
  sit in `PUBLIC_ROUTES` with a category (teaser · help · legal · site ·
  auth-flow · token-form · machine-file · health · anonymous-write · internal).
  A new open route fails the suite until classified; a classified one that
  disappears fails it too. Every `/admin` route must carry the admin guard,
  mounts must be `/static`, `/uploads` or `/app`, and FastAPI's own pages exist
  only with `DEBUG`.
- **By sentinel**: a public trip, a private trip, a hidden trip and two profiles
  are seeded with a marker in every non-teaser field; every open GET (and every
  `/admin` page) is fetched signed out, plus the anonymous report POST, and a
  marker in any body or header fails it.

The Flutter half is `kPublicRoutes`, pinned by
`test/core/router/public_routes_test.dart`. See
[sharing.md](sharing.md#what-a-reader-without-an-account-sees).

### Exception handling

- `ApiError` → `{detail, code, **extra}` (`main.py:345`).
- A bare `Exception` → 500 `{"detail": "Internal server error"}`, **re-raised in
  `DEBUG`**.
- **The generic handler must re-raise `asyncio.CancelledError`,
  `KeyboardInterrupt` and `SystemExit`** — intercepting these breaks Starlette's
  lifespan and the async request lifecycle.

### Config invariants

- **`SECRET_KEY` is validated at startup with `Field(min_length=32)`** — anything
  shorter raises a `ValidationError` before the server accepts traffic. Generate
  with `openssl rand -hex 32`.
- **`DEBUG=False` disables `/docs`, `/redoc` and `/openapi.json`** via
  `docs_url` / `redoc_url` / `openapi_url=None`. Never set `True` on Railway.
  Until 2026-10-19 the raw schema stayed public in production — a map of every
  endpoint for a scraper. (All three appear in a local route dump only because
  the dev `.env` sets `DEBUG=True`.)
- **Four startup validators raise** — see [constraints.md](../constraints.md#config-via-env).

### Database engine

- Pool: `pool_size=10`, `max_overflow=20`, `pool_pre_ping=True`.
- **Statement timeout 30 s** via `connect_args={"options": "-c
  statement_timeout=30000"}`. **Alembic uses its own `NullPool` engine and is not
  affected.**

### Static mounts

| Mount | Condition |
|---|---|
| `/static` | always — `app/static/`, holds the default OG image |
| `{STORAGE_PUBLIC_URL_PREFIX}` (`/uploads`) | **only when `STORAGE_BACKEND == "filesystem"`** |
| `/app` | only if `/app/web_build` exists |

**`_SPAStaticFiles` regex-injects `GOOGLE_WEB_CLIENT_ID` into the SPA's
`<meta name="google-signin-client_id">` at serve time** (`main.py:62`) and caches
the result in memory — the web Google plugin reads its client id from that tag,
and the value cannot be baked in at build time.

**A page load under `/app/` that names no file is sent to its hash form**:
`/app/share/u/name` → 302 `/app/#/share/u/name`, query kept. The web app reads
only the part after `#` (it is on the hash URL strategy), so the path form
silently opened its home screen. Only a browser navigation is redirected — an
`Accept` asking for `text/html` — and the target is always `/app/#…`, so it
cannot leave the site; the app's own asset requests keep the `index.html`
fallback.

### i18n on the web

- **`SUPPORTED = ("en", "fr", "ar", "de", "es", "zh")`**; `RTL_LANGS = ("ar",)`;
  `LANG_NAMES` are deliberately untranslated.
- `resolve_lang`: **`?lang=` → `ntripi_lang` cookie → first supported
  `Accept-Language` primary subtag → `"en"`**. Share links carry no `?lang=`, so
  each reader gets their own device's language, not the sender's.
- **The app's first-launch language follows the same rule**:
  `firstSupportedLocale` (`lib/shared/data/app_locales.dart`) walks the device's
  whole language list for the first one the app ships, so a shared link's page
  and the web app's sign-in screen behind it agree. A language picked in the app
  wins, as the cookie does here.
- `translator(lang)` falls back **per key**; a missing key returns the key itself,
  surfacing loudly in dev.
- **`LanguageCookieMiddleware`** touches HTML responses only, adds
  `Vary: Accept-Language`, and writes the `ntripi_lang` cookie (1 year,
  `samesite=lax`, `path=/`) **only on a valid `?lang=` override**.
- **Adding a language to the app's locales requires adding it to `i18n.py`
  `SUPPORTED`** or the app's `?lang=` silently falls back to English.
- Three independent translation corpora: `i18n.TRANSLATIONS` (web chrome),
  `constants/legal/<lang>` (plain text), `constants/help/<lang>` (articles), plus
  `constants/push_i18n` (tray text).

### Waitlist

- **`POST /waitlist/join`** — 422 `waitlist_contact_required` if both contact
  fields are empty; a duplicate email raises `IntegrityError` which is **caught,
  rolled back and treated as success**.
- The client is the **website's** `home.html` `fetch('/waitlist/join')`, not the
  Flutter app (which only maps the error code).
- `WaitlistJoinBody` is defined **inline in the router** — the only schema in the
  project not in `schemas/`.
- The app is **pre-launch**, so the homepage's download buttons open the waitlist.
  A phone sees only its own store's button — `platform_head`, the share pages'
  rule ([app-links.md](app-links.md#the-share-pages-a-teaser-and-one-way-in)) —
  and the button's `data-store` is the `platform` the waitlist records; the
  generic buttons send `both`.
  `ANDROID_DOWNLOAD_URL` unset hides the APK button. `home.html` has a
  `location.hash` handler so a cross-page link to `/#get-the-app` works.

## Data model

`waitlist` — `email` VARCHAR(255) **UNIQUE and nullable**, `whatsapp`
VARCHAR(50), `platform` VARCHAR(10), `created_at`. Migration `a95274c6b972`. The
"at least one contact" rule is app-level only.

Full columns: [reference/data-model.md](../reference/data-model.md#waitlist).

## API surface

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/` | none | the marketing homepage |
| GET | `/health` | none | `{"status": "ok"}` |
| GET | `/login`, `/register` | none | **302 → `/app/`** — server-side auth was removed |
| GET | `/terms`, `/privacy`, `/guidelines` | none | see [legal-and-age-gate.md](legal-and-age-gate.md) |
| GET | `/reset-password`, `/verify-email` | none | see [passwords-and-email.md](passwords-and-email.md) |
| GET | `/appeal`, `/appeal/{token}` · POST `/web/appeal`, `/web/appeal-request` | none | see [admin-and-appeals.md](admin-and-appeals.md) |
| GET | `/robots.txt`, `/sitemap.xml`, `/llms.txt`, `/llms-full.txt` | none | see [help-centre.md](help-centre.md) |
| GET | `/.well-known/apple-app-site-association`, `/.well-known/assetlinks.json` | none | the app-link association files; **404 until configured** — see [app-links.md](app-links.md) |
| GET | `/manifest.webmanifest` | none | names the Android app (`related_applications`) so Chrome can tell a share page it is installed; **404 until `ANDROID_APP_PACKAGE` is set** — see [app-links.md](app-links.md) |
| POST | `/waitlist/join` | none, **no rate limit** | `{ok: true}` 201 |

The `web` router is registered **last** (`main.py:292`), after every literal
path, because it owns `/`.

## Hosting

**Railway** (single Dockerfile at the repo root, Root Directory empty) +
**Cloudflare** DNS/proxy + **Let's Encrypt** SSL. Deploys on push to `main`.
HTTPS is enforced at the TLD level — `.app` is on the HSTS preload list.

- The Dockerfile is multi-stage: a Flutter web build, then a Python runtime that
  copies `build/web` to `/app/web_build`. One image serves the API **and** the
  Flutter web app at `/app/`.
- **The container must not run as root** — the Dockerfile creates `appuser` and
  must keep `USER appuser`.
- `CMD` runs `alembic upgrade head` before uvicorn, so **migrations run at
  deploy**.
- The runtime stage is `python:3.14-slim`, the same interpreter as the
  development venv (see [decisions.md](../decisions.md)). `HEALTHCHECK` uses
  Python's stdlib, because `curl` is not guaranteed in a slim image.
- **The filesystem backend needs a persistent volume at `/app/uploads`** or
  images vanish on redeploy.
- **`docs/` is in `.dockerignore`**, so this folder never enters the image.
- **Postgres runs in the same Railway region as the API (EU West, Amsterdam).**
  A region is set per service, so moving the API never moves the database. Until
  2026-10-20 Postgres sat in a US region: every database round trip crossed the
  Atlantic (~120 ms), each save makes 8–20 of them one after another, and saves
  took 4–6 s. To check without signing in, time
  `https://ntripi.app/share/i/not-a-uuid` (refused before any query) against
  `https://ntripi.app/share/i/<a random UUID>` (one query); in the same region
  they answer in the same time. See [decisions.md](../decisions.md).

Railway env vars, and the full optional-integration matrix, are listed in
[constraints.md](../constraints.md#config-via-env).

## Flutter surface

`main.dart`'s widget wiring, outermost first:

```
ProviderScope
└── BetterFeedback              ← ABOVE MaterialApp (see bug-reports.md)
    └── MaterialApp.router
        └── builder: AnnotatedRegion
            └── TosGate
                └── NotificationPoller
                    └── PushGateway
                        └── ShakeToReport
                            └── child (the routed screen)
```

- `initFirebase()` runs **before** `runApp` so the background message handler is
  registered first; it swallows a missing config so the app still launches.
- **The router** (`core/router/app_router.dart`, 588 lines) has a
  `StatefulShellRoute.indexedStack` with **five branches** — `/search`,
  `/profile/me`, `/itineraries`, `/saved`, `/feed` — which keeps each tab's widget
  tree alive. Root-level routes (`/splash`, `/login`, `/register`,
  `/forgot-password`, `/suspended`, and every `/itineraries/:id/...` detail route)
  sit outside it. `/profile/:userId` is declared **after** the shell so
  `/profile/me` wins. `core/router/navigation_ext.dart` holds the two halves of
  safe navigation: `popOr` to leave a screen that may be the only route, and
  `pushOverHome` / `openFromOutside` to enter one from outside the app — see
  [notifications.md](notifications.md#flutter-surface).
- **Shared links are the router's other way in.** Its `onEnter`
  (`appLinkOnEnter`) and the first step of its redirect (`appLinkLaunchRedirect`),
  both in `core/router/app_links.dart`, intercept a `/share/i/…` or `/share/u/…`
  link so it never lands as it arrives: a cold start goes through splash, a link
  while running opens over the current screen, a link while signed out waits for
  the sign-in. Its landings are the root-level `/u/:username` and
  `/unavailable/:kind` — see [app-links.md](app-links.md).
- **On the web the address bar shows the screen on top** —
  `GoRouter.optionURLReflectsImperativeAPIs = true`, set in `main.dart` (it has
  no effect off the web). go_router's default showed the screen the pushes sit
  on: a trip opened from the feed left `#/feed` in the bar, a shared profile
  `#/profile/me`, and a reload landed there. Browser Back and Forward are
  unchanged — go_router already added a history entry per push. So every route
  is a URL the app can be started on, which brings two rules, both in the
  redirect and both in `app_links.dart`: **an editing form is never where the app
  starts** (`editingRouteLaunchRedirect`: the trip's or a stop's edit form and
  the add-stop form land on what they edit, the map picker on home — they save
  only under the edit claim the trip page takes before pushing them), and **a
  trip or profile URL opened signed out waits through the sign-in**
  (`signInRedirect` parks it, as a shared link is). Every route is classified
  one way or the other in `test/core/router/landing_routes_test.dart`, which
  fails on a new one.
- **Android's `MainActivity` is `launchMode="singleTask"`**, so a link tapped in
  another app reaches the running instance instead of starting a second copy in
  the caller's task. Flutter's own deep linking is on, stated explicitly in the
  manifest and `Info.plist`.
- **The shell owns the keyboard for its tabs.** Its Scaffold lifts the tabs above
  the keyboard and the MediaQuery it hands them carries **no** keyboard inset
  (`.removeViewInsets`), so a tab's own Scaffold has nothing left to lift and
  keeps the default. A root-level route has no shell above it and lifts itself.
  The full contract is in [constraints.md](../constraints.md#keyboard).
- **Every request to the API shares one connection pool**
  (`core/api/api_connection_pool_io.dart`). `createDioClient` and
  `createBareDio` both install `apiConnectionPool`, which keeps an unused
  connection open for 120 s (`kApiConnectionIdleTimeout`). Dio's own adapter
  closed it after 3 s, so most requests paid a TCP and TLS handshake. The
  timeout stays below Cloudflare's 400 s keep-alive, so the app always closes
  first. `main.dart` retires the pool when the app is hidden and when the device
  moves to another network (`networkChanges()`, in
  `core/connectivity/connectivity_service.dart`): later requests open a new
  connection, and requests under way finish on theirs. dart:io never checks a
  pooled connection before reusing it, and one kept through a sleep or a
  network switch may be dead. The web build hands requests to the browser, which
  keeps its own connections. See
  [decisions.md](../decisions.md#2026-10-25--the-app-keeps-its-connection-to-the-api-open-for-two-minutes).
- The app is **locked to portrait**.
- **Build-time config is `--dart-define`**: `API_BASE_URL`, `SHARE_BASE_URL`.
  The Maps Embed key left the build on 2026-10-31: it is the backend's
  `GOOGLE_MAPS_EMBED_API_KEY`, used inside `/embed/*`.

## Known gaps / TODOs

- **The Dockerfile hardcodes two build values** (`Dockerfile:13-14`):
  `API_BASE_URL` and `SHARE_BASE_URL`, which is what stops one image serving a
  staging environment. The third, the Maps Embed key, moved to the backend on
  2026-10-31. See [constraints.md](../constraints.md#known-deviations) and
  [backlog.md](../backlog.md).
- **A pooled connection the network drops silently while the app is open**,
  with no network change reported, still fails the request sent down it:
  dart:io never retries, and the pool is retired only when the app is hidden or
  the network changes.
- **`POST /waitlist/join` has no rate limit** while every other public POST does.
- **`waitlist.platform` is written and read nowhere** — no admin lane, no export.
- `WaitlistJoinBody` is the only inline router schema.
- **`ALLOWED_HOSTS` is absent from `.env.example`** along with 13 other settings.
- An abandoned `.CLAUDE.md.swp` (16 KB, untracked) sits in the repo root.
- Tests: `test_web.py`, `test_web_i18n.py`, `test_security_middleware.py`,
  `test_storage_factory.py`, `test_error_codes.py`, `test_request_timing.py` all
  run.

## Related

- [help-centre.md](help-centre.md) — SEO, `robots.txt`, the language cookie's other half
- [legal-and-age-gate.md](legal-and-age-gate.md) · [passwords-and-email.md](passwords-and-email.md) · [admin-and-appeals.md](admin-and-appeals.md) — the server-rendered pages
- [sharing.md](sharing.md) — the other public HTML surface
- [image-pipeline.md](image-pipeline.md) — the `/uploads` mount and storage
- [etag-concurrency.md](etag-concurrency.md) — `ETagMiddleware`'s place in the stack
- [google-sign-in.md](google-sign-in.md) — the SPA meta-tag injection
- [collaborative-editing.md](collaborative-editing.md) — why `X-Edit-Lock` is in CORS
- [app-links.md](app-links.md) — the `/.well-known` files, the link routing, `singleTask`
- [constraints.md](../constraints.md)
- [places-and-maps.md](places-and-maps.md) — the `/embed/*` map pages and their framing exception
