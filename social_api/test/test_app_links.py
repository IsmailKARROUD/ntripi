"""
test_app_links.py — shared links that open the installed app.

Coverage:
  TestAssociationFiles — apple-app-site-association + assetlinks.json: invisible
                         (404) unset, exact JSON when set, never cached privately,
                         and every claimed path is a real share route
  TestAppLinkSettings  — each refusal of _validate_app_links, and fingerprint
                         normalisation
  TestShareCta         — app first, web second on every share page: store
                         buttons (waitlist until set), the Android intent link,
                         the Smart App Banner, Continue on web; no ntripi://
"""

from urllib.parse import unquote

import pytest
from pydantic import ValidationError

from app.config import Settings, get_settings
from app.main import app
from app.services.app_links import APP_LINK_PATHS

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
            assert "data-app-open hidden" in html, name
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
