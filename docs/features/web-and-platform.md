# Web surfaces and platform

**Status:** shipped
**Tables:** `waitlist`
**Config:** `ALLOWED_HOSTS`, `ALLOWED_ORIGINS`, `DEBUG`, `ANDROID_DOWNLOAD_URL`, `STORAGE_*`

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
| `LanguageCookieMiddleware` | `ProxyHeadersMiddleware` |
| `ETagMiddleware` | `ClientIPHeaderMiddleware` |
| `CORSMiddleware` | `TrustedHostMiddleware` |
| `SecurityHeadersMiddleware` | `ContentSizeLimitMiddleware` |
| `ContentSizeLimitMiddleware` | `SecurityHeadersMiddleware` |
| `TrustedHostMiddleware` | `CORSMiddleware` |
| `ClientIPHeaderMiddleware` | `ETagMiddleware` |
| `ProxyHeadersMiddleware` | `LanguageCookieMiddleware` → handlers |

`LanguageCookieMiddleware` is added **first** and is therefore the innermost
layer. It touches only `text/html` responses, so it does not affect the security
ordering.

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
- **`CORSMiddleware` uses explicit method and header lists, never `["*"]`.**
  Methods `GET POST PATCH DELETE OPTIONS`; headers `Content-Type`,
  `Authorization`, `If-Match`, `If-None-Match`, **`X-Edit-Lock`** — dropping the
  last would fail the browser preflight before an itinerary mutation is even sent.
- **`STATIC_PREFIXES` lives in `app/middleware/__init__.py`**, shared by the ETag
  and security-headers middleware. **Add a new static mount there, not in each
  middleware.**

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
| 60/minute | `/auth/refresh` |
| 3/hour | `/auth/forgot-password`, `/auth/resend-verification` |
| 10/hour | `/auth/accept-tos`, `/appeals`, `/web/appeal`, `POST /reports` |
| 30/minute | `GET /users/search`, `GET /itineraries/feed` |

**`POST /waitlist/join` and `GET /help/search` are the two unlimited public
POST/GET surfaces** — the latter deliberately, the former apparently not.

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
- **`DEBUG=False` disables `/docs` and `/redoc`** via `docs_url=None`. Never set
  `True` on Railway. (`/docs`, `/redoc` and `/openapi.json` appear in a local
  route dump only because the dev `.env` sets `DEBUG=True`.)
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

### i18n on the web

- **`SUPPORTED = ("en", "fr", "ar", "de", "es", "zh")`**; `RTL_LANGS = ("ar",)`;
  `LANG_NAMES` are deliberately untranslated.
- `resolve_lang`: **`?lang=` → `ntripi_lang` cookie → first supported
  `Accept-Language` primary subtag → `"en"`**.
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
- `HEALTHCHECK` uses Python's stdlib, because `curl` is not guaranteed in
  `python:3.11-slim`.
- **The filesystem backend needs a persistent volume at `/app/uploads`** or
  images vanish on redeploy.
- **`docs/` is in `.dockerignore`**, so this folder never enters the image.

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
  `/profile/me` wins.
- **The shell owns the keyboard for its tabs.** Its Scaffold lifts the tabs above
  the keyboard and the MediaQuery it hands them carries **no** keyboard inset
  (`.removeViewInsets`), so a tab's own Scaffold has nothing left to lift and
  keeps the default. A root-level route has no shell above it and lifts itself.
  The full contract is in [constraints.md](../constraints.md#keyboard).
- The app is **locked to portrait**.
- **Build-time config is `--dart-define`**: `API_BASE_URL`, `SHARE_BASE_URL`,
  `GOOGLE_MAPS_EMBED_API_KEY`.

## Known gaps / TODOs

- **The Dockerfile hardcodes three build values** (`Dockerfile:15`):
  `API_BASE_URL`, `SHARE_BASE_URL`, and **`GOOGLE_MAPS_EMBED_API_KEY=AIzaSy…`**.
  An Embed key necessarily ships to the client and this one is referrer-restricted,
  so exposure is not the issue — but it is a committed, un-rotatable build
  constant, against the project's own "no hardcoded values" rule. See
  [constraints.md](../constraints.md#known-deviations) and
  [backlog.md](../backlog.md).
- **`POST /waitlist/join` has no rate limit** while every other public POST does.
- **`waitlist.platform` is written and read nowhere** — no admin lane, no export.
- `WaitlistJoinBody` is the only inline router schema.
- **`ALLOWED_HOSTS` is absent from `.env.example`** along with 13 other settings.
- An abandoned `.CLAUDE.md.swp` (16 KB, untracked) sits in the repo root.
- Tests: `test_web.py`, `test_web_i18n.py`, `test_security_middleware.py`,
  `test_storage_factory.py`, `test_error_codes.py` all run.

## Related

- [help-centre.md](help-centre.md) — SEO, `robots.txt`, the language cookie's other half
- [legal-and-age-gate.md](legal-and-age-gate.md) · [passwords-and-email.md](passwords-and-email.md) · [admin-and-appeals.md](admin-and-appeals.md) — the server-rendered pages
- [sharing.md](sharing.md) — the other public HTML surface
- [image-pipeline.md](image-pipeline.md) — the `/uploads` mount and storage
- [etag-concurrency.md](etag-concurrency.md) — `ETagMiddleware`'s place in the stack
- [google-sign-in.md](google-sign-in.md) — the SPA meta-tag injection
- [collaborative-editing.md](collaborative-editing.md) — why `X-Edit-Lock` is in CORS
- [constraints.md](../constraints.md)
