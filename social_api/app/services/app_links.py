"""
services/app_links.py — shared links that open the installed app.

A share link (/share/i/{id}, /share/u/{username}) is claimed by the iOS and
Android apps through two files the operating system fetches from this site:
Apple's apple-app-site-association and Android's assetlinks.json. Both are built
here from settings, and so is everything a share page needs to offer the app —
and the web app — to a visitor who did not land in the app.

The claimed paths are a contract with three places in social_flutter/ that must
change in the same commit: the AndroidManifest.xml intent filter, the
Runner.entitlements associated domains (hosts only — SHARE_BASE_URL's and
APP_OPEN_HOST's), and lib/core/router/app_links.dart, which maps each path to an
in-app route.
"""

from __future__ import annotations

from typing import TYPE_CHECKING
from urllib.parse import quote, urlsplit

if TYPE_CHECKING:
    from app.config import Settings

# Share links only. Emailed token links (reset password, verify email, appeal)
# are server-rendered forms and must keep opening in the browser.
APP_LINK_PATHS = ("/share/i/*", "/share/u/*")

# Before launch the stores have nothing to install: the homepage waitlist is the
# honest destination for a download button, the same one the help CTA uses.
WAITLIST_PATH = "/#get-the-app"

# The localStorage key the Flutter web app keeps while somebody is signed in on
# this site (social_flutter lib/core/storage/web_session_hint.dart writes it).
# Its value is when that session ends, nothing more: a share page reads it to
# send a signed-in reader straight into the web app. Same origin, so the same
# storage; change it on both sides in the same commit.
WEB_SESSION_HINT_KEY = "ntripi_web_session_until"


def apple_app_site_association(settings: "Settings") -> dict | None:
    """The AASA document, or None when no iOS app is configured."""
    app_ids = settings.ios_app_ids
    if not app_ids:
        return None
    return {
        "applinks": {
            "details": [
                {
                    "appIDs": app_ids,
                    "components": [{"/": path} for path in APP_LINK_PATHS],
                }
            ]
        }
    }


def asset_links(settings: "Settings") -> list | None:
    """The Digital Asset Links statement, or None when no Android app is set."""
    package = settings.ANDROID_APP_PACKAGE.strip()
    if not package:
        return None
    return [
        {
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": package,
                "sha256_cert_fingerprints": settings.android_cert_sha256,
            },
        }
    ]


def web_manifest(settings: "Settings") -> dict | None:
    """The web app manifest the share pages link, or None when no Android app
    is set.

    It exists for one field: related_applications is what lets Chrome on
    Android answer navigator.getInstalledRelatedApps() — whether the Ntripi
    app is installed — so a share page can put "Open in Ntripi" first. The app
    vouches for the site in return (asset_statements in AndroidManifest.xml).
    display "browser" keeps the page from ever being offered as an installable
    web app, and prefer_related_applications stays unset so Chrome never
    pushes the store listing on anyone.
    """
    package = settings.ANDROID_APP_PACKAGE.strip()
    if not package:
        return None
    return {
        "name": "Ntripi",
        "short_name": "Ntripi",
        "start_url": "/",
        "display": "browser",
        "related_applications": [{"platform": "play", "id": package}],
    }


def store_links(settings: "Settings") -> dict:
    """The two download buttons — the store listing once set, else the waitlist.

    `*_live` says the listing is real: only then may a share page put that
    store first on a phone, since before launch it is a waitlist.
    """
    app_store = settings.APP_STORE_URL.strip()
    play_store = settings.PLAY_STORE_URL.strip()
    return {
        "app_store_url": app_store or WAITLIST_PATH,
        "play_store_url": play_store or WAITLIST_PATH,
        "app_store_live": bool(app_store),
        "play_store_live": bool(play_store),
    }


def cta_context(share_url: str, settings: "Settings") -> dict:
    """Everything a share page needs to send a visitor to the app or the web.

    `share_url` is the page's own absolute URL (build_share_url /
    build_profile_share_url). The web app comes first — it signs the visitor
    in and lands on the same trip or profile — until a phone's own store is
    live, when the page puts that store first (_app_links.html). A reader
    already signed in on this site never sees the page: it goes straight to
    the web app, unless Chrome on Android says the app is installed, which
    puts "Open in Ntripi" first instead.
    """
    stores = store_links(settings)
    path = urlsplit(share_url).path
    open_host = settings.app_open_host
    return {
        **stores,
        "android_intent_url": _android_intent_url(
            share_url, stores["play_store_url"], settings
        ),
        # Chrome's installed-app check reads the manifest only when one is set.
        "android_package": settings.ANDROID_APP_PACKAGE.strip() or None,
        # iOS opens an app only for a tap on a link to another domain than the
        # page's, so the iPhone button points at the second host. Validated
        # at startup to come with IOS_APP_IDS.
        "ios_open_url": f"https://{open_host}{path}" if open_host else None,
        "ios_app_store_id": settings.IOS_APP_STORE_ID.strip() or None,
        "app_argument": share_url,
        # The Flutter web app is on the hash strategy, and its router maps the
        # same /share/* paths the phones receive — sign-in included.
        "web_app_url": f"/app/#{path}",
        "session_hint_key": WEB_SESSION_HINT_KEY,
    }


def _android_intent_url(
    share_url: str, fallback_url: str, settings: "Settings"
) -> str | None:
    """A Chrome intent URL: opens this link in the app when it is installed,
    otherwise sends the browser to `fallback_url`.

    The fallback must be absolute — Chrome refuses a relative one and would
    open the Play listing of a package that is not public yet.
    """
    package = settings.ANDROID_APP_PACKAGE.strip()
    if not package:
        return None
    if fallback_url.startswith("/"):
        fallback_url = f"{settings.share_base_url}{fallback_url}"
    parts = urlsplit(share_url)
    return (
        f"intent://{parts.netloc}{parts.path}#Intent;scheme={parts.scheme};"
        f"package={package};S.browser_fallback_url={quote(fallback_url, safe='')};end"
    )
