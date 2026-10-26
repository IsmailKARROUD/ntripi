"""
test_app_links.py — shared links that open the installed app.

Coverage:
  TestAssociationFiles — apple-app-site-association + assetlinks.json: invisible
                         (404) unset, exact JSON when set, never cached privately,
                         and every claimed path is a real share route
  TestAppLinkSettings  — each refusal of _validate_app_links, and fingerprint
                         normalisation
  TestShareCta         — every share page's way in: the web app link, store
                         buttons (waitlist until set), the Android intent link,
                         the Smart App Banner; no ntripi://
  TestOneStorePerPhone — every page with store buttons decides the platform
                         once, in <head>, so a phone is shown its own store
                         only; both stay in the HTML for laptops and no-JS
  TestSignedInReader   — a reader signed in on the web goes straight into the
                         web app, decided in <head> from the web app's hint
  TestAndroidAppCheck  — the manifest Chrome reads to say the app is installed,
                         and the pages that link it
  TestOpenHost         — the iPhone button on APP_OPEN_HOST, the settings that
                         guard it, and the host serving nothing but .well-known
"""

from pathlib import Path
from urllib.parse import unquote

import pytest
from pydantic import ValidationError

from app.config import Settings, get_settings
from app.main import app
from app.services.app_links import APP_LINK_PATHS, WEB_SESSION_HINT_KEY

from conftest import auth_headers, register_user

IOS_APP_ID = "K8G92959RF.com.ismailkarroud.ntripi"
PACKAGE = "com.ismailkarroud.ntripi"
# Two made-up certificates, as keytool prints one and the Play Console the other.
PLAY_SHA256 = ":".join(["8F"] * 32)
UPLOAD_SHA256_BARE = "ab" * 32
UPLOAD_SHA256 = ":".join(["AB"] * 32)

_BASE = {
    "DATABASE_URL": "postgresql://user:pass@localhost/db",
    "SECRET_KEY": "x" * 32,
}


def _settings(**overrides) -> Settings:
    # _env_file=None keeps a developer's local .env out of these assertions.
    return Settings(**{**_BASE, **overrides}, _env_file=None)


@pytest.fixture
def configured(monkeypatch):
    """Every app-link setting set, as production will have them."""
    s = get_settings()
    monkeypatch.setattr(s, "share_base_url", "https://ntripi.app")
    monkeypatch.setattr(s, "IOS_APP_IDS", IOS_APP_ID)
    monkeypatch.setattr(s, "ANDROID_APP_PACKAGE", PACKAGE)
    monkeypatch.setattr(s, "ANDROID_CERT_SHA256", f"{PLAY_SHA256},{UPLOAD_SHA256_BARE}")
    monkeypatch.setattr(s, "IOS_APP_STORE_ID", "1234567890")
    monkeypatch.setattr(s, "APP_STORE_URL", "https://apps.apple.com/app/id1234567890")
    monkeypatch.setattr(
        s, "PLAY_STORE_URL", f"https://play.google.com/store/apps/details?id={PACKAGE}"
    )
    return s


def _public_itinerary(client, *, visibility="public", title="Lisbon in three days"):
    user = register_user(client, "linker", "linker@example.com")
    r = client.post(
        "/itineraries/",
        json={"title": title, "visibility": visibility},
        headers=auth_headers(user["access_token"]),
    )
    assert r.status_code == 201, r.json()
    return r.json()


def _public_profile(client, username="openbook"):
    user = register_user(client, username, f"{username}@example.com")
    r = client.patch("/users/me", json={"is_private": False},
                     headers=auth_headers(user["access_token"]))
    assert r.status_code == 200, r.json()
    return user


# ---------------------------------------------------------------------------
# TestAssociationFiles
# ---------------------------------------------------------------------------

class TestAssociationFiles:

    @pytest.mark.parametrize("path", [
        "/.well-known/apple-app-site-association",
        "/.well-known/assetlinks.json",
    ])
    def test_unconfigured_is_invisible(self, client, path):
        r = client.get(path)
        assert r.status_code == 404
        assert r.json()["code"] == "not_found"

    def test_apple_app_site_association(self, client, configured):
        r = client.get("/.well-known/apple-app-site-association")
        assert r.status_code == 200
        # Apple rejects anything but JSON, and follows no redirect.
        assert r.headers["content-type"] == "application/json"
        assert r.json() == {
            "applinks": {
                "details": [{
                    "appIDs": [IOS_APP_ID],
                    "components": [{"/": "/share/i/*"}, {"/": "/share/u/*"}],
                }]
            }
        }

    def test_assetlinks(self, client, configured):
        r = client.get("/.well-known/assetlinks.json")
        assert r.status_code == 200
        assert r.headers["content-type"] == "application/json"
        assert r.json() == [{
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": PACKAGE,
                # Both spellings normalised to what the verifier compares.
                "sha256_cert_fingerprints": [PLAY_SHA256, UPLOAD_SHA256],
            },
        }]

    @pytest.mark.parametrize("path", [
        "/.well-known/apple-app-site-association",
        "/.well-known/assetlinks.json",
    ])
    def test_publicly_cacheable(self, client, configured, path):
        # The endpoint's own header survives ETagMiddleware's private default.
        assert client.get(path).headers["cache-control"] == "public, max-age=3600"

    def test_every_claimed_path_is_a_share_route(self):
        routes = {getattr(route, "path", "") for route in app.routes}
        for pattern in APP_LINK_PATHS:
            prefix = pattern.removesuffix("*")
            assert any(r.startswith(prefix) and r.startswith("/share/") for r in routes), (
                f"{pattern} is claimed for the app but no /share route serves it"
            )


# ---------------------------------------------------------------------------
# TestAppLinkSettings
# ---------------------------------------------------------------------------

class TestAppLinkSettings:

    def test_off_by_default(self):
        s = _settings()
        assert s.ios_app_ids == []
        assert s.android_cert_sha256 == []

    def test_fingerprints_are_normalised(self):
        s = _settings(ANDROID_APP_PACKAGE=PACKAGE,
                      ANDROID_CERT_SHA256=f" {UPLOAD_SHA256_BARE} ,{PLAY_SHA256.lower()}")
        assert s.android_cert_sha256 == [UPLOAD_SHA256, PLAY_SHA256]

    @pytest.mark.parametrize("app_id", [
        "com.ismailkarroud.ntripi",          # no team id
        "k8g92959rf.com.ismailkarroud.ntripi",  # team ids are uppercase
        "K8G92959RF.ntripi",                 # not reverse-DNS
    ])
    def test_malformed_ios_app_id_refuses_to_start(self, app_id):
        with pytest.raises(ValidationError, match="IOS_APP_IDS"):
            _settings(IOS_APP_IDS=app_id)

    @pytest.mark.parametrize("fingerprint", ["AB:CD", "Z" * 64, "AB" * 33])
    def test_malformed_fingerprint_refuses_to_start(self, fingerprint):
        with pytest.raises(ValidationError, match="ANDROID_CERT_SHA256"):
            _settings(ANDROID_APP_PACKAGE=PACKAGE, ANDROID_CERT_SHA256=fingerprint)

    def test_package_without_fingerprint_refuses_to_start(self):
        with pytest.raises(ValidationError, match="set together"):
            _settings(ANDROID_APP_PACKAGE=PACKAGE)

    def test_fingerprint_without_package_refuses_to_start(self):
        with pytest.raises(ValidationError, match="set together"):
            _settings(ANDROID_CERT_SHA256=PLAY_SHA256)

    def test_malformed_package_refuses_to_start(self):
        with pytest.raises(ValidationError, match="ANDROID_APP_PACKAGE"):
            _settings(ANDROID_APP_PACKAGE="ntripi", ANDROID_CERT_SHA256=PLAY_SHA256)

    def test_non_numeric_store_id_refuses_to_start(self):
        with pytest.raises(ValidationError, match="IOS_APP_STORE_ID"):
            _settings(IOS_APP_STORE_ID="id1234567890")

    @pytest.mark.parametrize("name", ["APP_STORE_URL", "PLAY_STORE_URL"])
    def test_insecure_store_url_refuses_to_start(self, name):
        with pytest.raises(ValidationError, match=name):
            _settings(**{name: "http://apps.apple.com/app/id1"})


# ---------------------------------------------------------------------------
# TestShareCta
# ---------------------------------------------------------------------------

def _all_share_pages(client):
    """One of each share page that carries the app-or-web call to action."""
    public = _public_itinerary(client)
    owner_token = register_user(client, "privateer", "privateer@example.com")["access_token"]
    r = client.post("/itineraries/", json={"title": "Secret", "visibility": "followers"},
                    headers=auth_headers(owner_token))
    private = r.json()
    _public_profile(client, "openbook")
    register_user(client, "closedbook", "closedbook@example.com")  # private by default
    return {
        "public trip": (f"/share/i/{public['id']}", f"/share/i/{public['id']}"),
        "private trip": (f"/share/i/{private['id']}", f"/share/i/{private['id']}"),
        "public profile": ("/share/u/openbook", "/share/u/openbook"),
        "private profile": ("/share/u/closedbook", "/share/u/closedbook"),
    }


class TestShareCta:

    def test_unconfigured_pages_offer_the_waitlist_and_the_web(self, client):
        for name, (url, path) in _all_share_pages(client).items():
            html = client.get(url).text
            assert 'href="/#get-the-app"' in html, name
            # Nothing to open without a package: the Android button is absent.
            assert "intent://" not in html, name
            assert "apple-itunes-app" not in html, name
            assert f'href="/app/#{path}"' in html, name

    def test_configured_pages_link_the_stores_and_the_app(self, client, configured):
        for name, (url, path) in _all_share_pages(client).items():
            html = client.get(url).text
            assert 'href="https://apps.apple.com/app/id1234567890"' in html, name
            assert f"https://play.google.com/store/apps/details?id={PACKAGE}" in html, name
            # Android only, revealed by the script; hidden until then.
            assert f"intent://ntripi.app{path}#Intent;scheme=https;package={PACKAGE};" in html, name
            assert 'data-app-open="android" hidden' in html, name
            assert (
                f'<meta name="apple-itunes-app" content="app-id=1234567890, '
                f'app-argument=https://ntripi.app{path}">'
            ) in html, name
            assert f'href="/app/#{path}"' in html, name

    def test_intent_falls_back_to_an_absolute_url(self, client, monkeypatch):
        s = get_settings()
        monkeypatch.setattr(s, "share_base_url", "https://ntripi.app")
        monkeypatch.setattr(s, "ANDROID_APP_PACKAGE", PACKAGE)
        monkeypatch.setattr(s, "ANDROID_CERT_SHA256", PLAY_SHA256)
        public = _public_itinerary(client)
        html = client.get(f"/share/i/{public['id']}").text
        fallback = html.split("S.browser_fallback_url=", 1)[1].split(";end", 1)[0]
        # Chrome needs an absolute fallback; before launch it is the waitlist.
        assert unquote(fallback) == "https://ntripi.app/#get-the-app"

    def test_not_found_offers_the_stores_but_no_open_button(self, client, configured):
        r = client.get("/share/i/00000000-0000-0000-0000-000000000000")
        assert r.status_code == 404
        assert 'href="https://apps.apple.com/app/id1234567890"' in r.text
        # There is nothing to open in the app.
        assert "intent://" not in r.text
        assert "/app/#/share" not in r.text

    def test_no_page_links_the_unregistered_scheme(self, client, configured):
        for name, (url, _path) in _all_share_pages(client).items():
            assert "ntripi://" not in client.get(url).text, name


# ---------------------------------------------------------------------------
# TestOneStorePerPhone
# ---------------------------------------------------------------------------

TEMPLATES = Path(__file__).resolve().parents[1] / "app" / "templates"

# Every template that puts a store button on a page — written out, or through
# _app_links.html's store_badges / teaser_gate. A new one fails the first test
# until it is listed here, and so rendered and checked by the others.
STORE_BUTTON_TEMPLATES = {
    "home.html",
    "share_public.html",
    "share_private.html",
    "share_profile.html",
    "share_not_found.html",
}


def _store_button_pages(client) -> dict[str, str]:
    """A URL that renders each of STORE_BUTTON_TEMPLATES."""
    pages = _all_share_pages(client)
    return {
        "home.html": "/",
        "share_public.html": pages["public trip"][0],
        "share_private.html": pages["private trip"][0],
        "share_profile.html": pages["public profile"][0],
        "share_not_found.html": "/share/i/00000000-0000-0000-0000-000000000000",
    }


def _head(html: str) -> str:
    return html.split("</head>", 1)[0]


class TestOneStorePerPhone:

    def test_every_template_with_store_buttons_is_listed(self):
        found = {
            path.name for path in TEMPLATES.rglob("*.html")
            if path.name != "_app_links.html"
            and any(hook in path.read_text(encoding="utf-8")
                    for hook in ('data-store="', "store_badges(", "teaser_gate("))
        }
        assert found == STORE_BUTTON_TEMPLATES

    def test_the_platform_is_decided_in_the_head(self, client):
        # Before a badge is parsed, so a phone never sees the other one flash.
        for name, url in _store_button_pages(client).items():
            head = _head(client.get(url).text)
            assert "setAttribute('data-platform'" in head, name
            assert 'html[data-platform="android"] [data-store="ios"]' in head, name
            assert 'html[data-platform="ios"] [data-store="android"]' in head, name

    def test_the_platform_is_read_from_the_browser_once(self, client):
        # app_links_script takes platform_head's answer; a second test would drift.
        for name, url in _store_button_pages(client).items():
            assert client.get(url).text.count("navigator.userAgent") == 1, name

    def test_an_ipad_counts_as_ios(self, client):
        # Since iPadOS 13 its Safari reports a Mac; only the touch points differ.
        head = _head(client.get("/").text)
        assert "/Macintosh/.test(ua) && navigator.maxTouchPoints > 1" in head

    def test_both_stores_stay_in_the_html(self, client):
        # What a laptop, a browser without JS and a crawler get.
        for name, url in _store_button_pages(client).items():
            html = client.get(url).text
            assert 'data-store="ios"' in html, name
            assert 'data-store="android"' in html, name


# ---------------------------------------------------------------------------
# TestSignedInReader
# ---------------------------------------------------------------------------

class TestSignedInReader:

    def test_the_web_app_key_is_the_one_the_app_writes(self):
        # social_flutter lib/core/storage/web_session_hint.dart writes this very
        # key; the two sides share an origin, not code.
        assert WEB_SESSION_HINT_KEY == "ntripi_web_session_until"

    def test_every_teaser_page_sends_a_signed_in_reader_into_the_web_app(self, client):
        for name, (url, path) in _all_share_pages(client).items():
            head = _head(client.get(url).text)
            # Decided before the body is drawn, from the web app's hint.
            assert f'localStorage.getItem("{WEB_SESSION_HINT_KEY}")' in head, name
            assert f'var webApp = "/app/#{path}";' in head, name
            # replace, never assign: Back must not return to a page that redirects.
            assert "location.replace(webApp)" in head, name
            assert "location.assign" not in head, name
            assert "html[data-redirecting] body { visibility: hidden; }" in head, name

    def test_not_found_sends_nobody_anywhere(self, client, configured):
        html = client.get("/share/i/00000000-0000-0000-0000-000000000000").text
        assert WEB_SESSION_HINT_KEY not in html
        assert "location.replace" not in html

    def test_a_crawler_gets_the_teaser_in_the_html(self, client):
        # No hint, no redirect: the page itself is the same for every reader.
        pages = _all_share_pages(client)
        html = client.get(pages["public trip"][0]).text
        assert "Lisbon in three days" in html
        assert "data-gate" in html


# ---------------------------------------------------------------------------
# TestAndroidAppCheck
# ---------------------------------------------------------------------------

class TestAndroidAppCheck:

    def test_unconfigured_manifest_is_invisible(self, client):
        r = client.get("/manifest.webmanifest")
        assert r.status_code == 404
        assert r.json()["code"] == "not_found"

    def test_manifest_names_the_android_app(self, client, configured):
        r = client.get("/manifest.webmanifest")
        assert r.status_code == 200
        assert r.headers["content-type"].startswith("application/manifest+json")
        assert r.headers["cache-control"] == "public, max-age=3600"
        body = r.json()
        assert body["related_applications"] == [{"platform": "play", "id": PACKAGE}]
        # Never an installable web app, and never a nudge towards the store.
        assert body["display"] == "browser"
        assert "prefer_related_applications" not in body

    def test_pages_link_the_manifest_only_when_an_app_is_set(self, client, monkeypatch):
        pages = _all_share_pages(client)
        for name, (url, _path) in pages.items():
            head = _head(client.get(url).text)
            assert 'rel="manifest"' not in head, name
            assert "getInstalledRelatedApps" not in head, name
        s = get_settings()
        monkeypatch.setattr(s, "ANDROID_APP_PACKAGE", PACKAGE)
        monkeypatch.setattr(s, "ANDROID_CERT_SHA256", PLAY_SHA256)
        for name, (url, _path) in pages.items():
            head = _head(client.get(url).text)
            assert '<link rel="manifest" href="/manifest.webmanifest">' in head, name
            assert "navigator.getInstalledRelatedApps()" in head, name
            assert f'var pkg = "{PACKAGE}";' in head, name

    def test_the_app_button_waits_for_chromes_answer(self, client, configured):
        pages = _all_share_pages(client)
        head = _head(client.get(pages["public trip"][0]).text)
        # Hidden while Chrome is asked and when it says no; first when it says yes.
        assert 'html[data-app="pending"] [data-app-open="android"]' in head
        assert 'html[data-app="absent"] [data-app-open="android"]' in head
        assert 'html[data-app="installed"] [data-store]' in head
        html = client.get(pages["public trip"][0]).text
        assert 'html[data-app="installed"] .gate-stores { order: 0; }' in html


# ---------------------------------------------------------------------------
# TestOpenHost
# ---------------------------------------------------------------------------

OPEN_HOST = "open.ntripi.app"


@pytest.fixture
def open_host(configured, monkeypatch):
    monkeypatch.setattr(configured, "APP_OPEN_HOST", OPEN_HOST)
    return configured


class TestOpenHost:

    def test_no_iphone_button_without_the_host(self, client, configured):
        for name, (url, _path) in _all_share_pages(client).items():
            html = client.get(url).text
            assert 'data-app-open="ios" hidden' not in html, name
            assert "data-app-missed hidden" not in html, name
            assert OPEN_HOST not in html, name

    def test_iphone_button_points_at_the_second_host(self, client, open_host):
        for name, (url, path) in _all_share_pages(client).items():
            html = client.get(url).text
            assert (
                f'href="https://{OPEN_HOST}{path}" rel="nofollow" data-app-open="ios" hidden'
            ) in html, name
            assert "data-app-missed hidden" in html, name
            assert "didn&#39;t open on this device" in html, name

    def test_the_note_replaces_the_button_after_a_missed_open(self, client, open_host):
        html = client.get(_all_share_pages(client)["public trip"][0]).text
        # Back from the second host, an iPhone shows the note instead of the button.
        assert (
            "if (ios) reveal(/[?&]app=missing(&|$)/.test(location.search)"
            " ? '[data-app-missed]' : '[data-app-open=\"ios\"]');"
        ) in html

    @pytest.mark.parametrize("path", [
        "/.well-known/apple-app-site-association",
        "/.well-known/assetlinks.json",
    ])
    def test_association_files_answer_on_the_second_host(self, client, open_host, path):
        # Apple's CDN fetches the AASA from every claimed host: a 200, no redirect.
        r = client.get(path, headers={"host": OPEN_HOST}, follow_redirects=False)
        assert r.status_code == 200
        assert r.headers["content-type"].startswith("application/json")

    def test_a_share_link_that_loaded_comes_back_saying_so(self, client, open_host):
        r = client.get("/share/u/someone", headers={"host": OPEN_HOST}, follow_redirects=False)
        assert r.status_code == 302
        assert r.headers["location"] == "https://ntripi.app/share/u/someone?app=missing"
        trip = "/share/i/3fa85f64-5717-4562-b3fc-2c963f66afa6"
        r = client.get(trip, headers={"host": OPEN_HOST}, follow_redirects=False)
        assert r.headers["location"] == f"https://ntripi.app{trip}?app=missing"

    def test_everything_else_moves_to_the_main_host(self, client, open_host):
        r = client.get("/help?lang=fr", headers={"host": OPEN_HOST}, follow_redirects=False)
        assert r.status_code == 301
        assert r.headers["location"] == "https://ntripi.app/help?lang=fr"
        r = client.get("/", headers={"host": OPEN_HOST}, follow_redirects=False)
        assert r.status_code == 301
        assert r.headers["location"] == "https://ntripi.app/"

    def test_the_main_host_is_untouched(self, client, open_host):
        _public_profile(client, "openbook")
        r = client.get("/share/u/openbook", follow_redirects=False)
        assert r.status_code == 200

    def test_unset_the_host_serves_nothing_special(self, client, configured):
        _public_profile(client, "openbook")
        r = client.get("/share/u/openbook", headers={"host": OPEN_HOST}, follow_redirects=False)
        assert r.status_code == 200


class TestOpenHostSettings:

    def _ios(self, **overrides) -> Settings:
        return _settings(
            share_base_url="https://ntripi.app", IOS_APP_IDS=IOS_APP_ID, **overrides
        )

    def test_off_by_default(self):
        assert _settings().app_open_host == ""

    def test_host_is_compared_lowercase(self):
        assert self._ios(APP_OPEN_HOST=" Open.Ntripi.App ").app_open_host == OPEN_HOST

    @pytest.mark.parametrize("host", [
        "https://open.ntripi.app",
        "open.ntripi.app/share",
        "open.ntripi.app:443",
        "localhost",
    ])
    def test_anything_but_a_bare_host_refuses_to_start(self, host):
        with pytest.raises(ValidationError, match="bare host name"):
            self._ios(APP_OPEN_HOST=host)

    def test_the_share_host_itself_refuses_to_start(self):
        # A tap on a link to the page's own domain never opens an app on iOS.
        with pytest.raises(ValidationError, match="differ from SHARE_BASE_URL"):
            self._ios(APP_OPEN_HOST="ntripi.app")

    def test_a_host_without_an_ios_app_refuses_to_start(self):
        with pytest.raises(ValidationError, match="needs IOS_APP_IDS"):
            _settings(share_base_url="https://ntripi.app", APP_OPEN_HOST=OPEN_HOST)
