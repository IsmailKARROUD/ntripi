"""test_web_i18n.py — Verifies web pages render French/Arabic via
Accept-Language / ?lang= while defaulting to English (so the existing
test_web/test_share suites, which send no language header, stay green).
Arabic must also flip the document to dir="rtl".

Uses /reset-password as the rendered-page vehicle — the login/register pages
were removed (auth lives in the Flutter app; /login now 302s to /app/).
"""

import pytest
from fastapi.testclient import TestClient

from app.i18n import SUPPORTED, TRANSLATIONS


class TestWebI18n:
    def test_default_is_english(self, client: TestClient):
        resp = client.get("/reset-password")
        assert resp.status_code == 200
        assert "Set a new password" in resp.text
        assert 'lang="en"' in resp.text
        assert 'dir="ltr"' in resp.text

    def test_accept_language_fr_renders_french(self, client: TestClient):
        resp = client.get(
            "/reset-password", headers={"Accept-Language": "fr-FR,fr;q=0.9"}
        )
        assert resp.status_code == 200
        assert "Définir un nouveau mot de passe" in resp.text
        assert 'lang="fr"' in resp.text
        # HTML must advertise language variance for caches.
        assert "accept-language" in resp.headers.get("vary", "").lower()

    def test_lang_query_override_wins_and_sets_cookie(self, client: TestClient):
        # ?lang=fr beats an English Accept-Language header.
        resp = client.get(
            "/reset-password?lang=fr", headers={"Accept-Language": "en-US,en;q=0.9"}
        )
        assert resp.status_code == 200
        assert "Définir un nouveau mot de passe" in resp.text
        assert resp.cookies.get("ntripi_lang") == "fr"

    def test_share_not_found_localized(self, client: TestClient):
        resp = client.get(
            "/share/i/00000000-0000-0000-0000-000000000000?lang=fr"
        )
        assert resp.status_code == 404
        assert "Itinéraire introuvable" in resp.text

    def test_accept_language_ar_renders_arabic_rtl(self, client: TestClient):
        resp = client.get(
            "/reset-password", headers={"Accept-Language": "ar-MA,ar;q=0.9"}
        )
        assert resp.status_code == 200
        assert "عيّن كلمة مرور جديدة" in resp.text
        assert 'lang="ar"' in resp.text
        assert 'dir="rtl"' in resp.text
        assert "accept-language" in resp.headers.get("vary", "").lower()

    def test_lang_query_ar_wins_and_sets_cookie(self, client: TestClient):
        resp = client.get(
            "/reset-password?lang=ar", headers={"Accept-Language": "en-US,en;q=0.9"}
        )
        assert resp.status_code == 200
        assert "عيّن كلمة مرور جديدة" in resp.text
        assert 'dir="rtl"' in resp.text
        assert resp.cookies.get("ntripi_lang") == "ar"

    def test_share_not_found_arabic(self, client: TestClient):
        resp = client.get(
            "/share/i/00000000-0000-0000-0000-000000000000?lang=ar"
        )
        assert resp.status_code == 404
        # مسار, not خط سير — the glossary settled on the former for "itinerary"
        # on 2026-07-26 and i18n.py moved with it.
        assert "المسار غير موجود" in resp.text

    def test_switcher_lists_every_language_and_marks_the_current_one(
        self, client: TestClient
    ):
        # The switcher is a dropdown (same shape as home.html's), so unlike the
        # flat row it replaced it lists ALL six and marks the current one —
        # a menu that hides the language you are on cannot show you where you are.
        #
        # Scoped to <nav> rather than the whole document: the page also carries
        # a canonical link and an hreflang set, and both legitimately name the
        # language currently being served.
        resp = client.get("/reset-password?lang=ar")
        nav = resp.text.split("<nav>")[1].split("</nav>")[0]
        for code in ("en", "fr", "de", "es", "zh", "ar"):
            assert f"lang={code}" in nav
        assert 'class="lang-item is-active" href="/reset-password?lang=ar"' in nav
        assert 'aria-current="true"' in nav

    def test_switcher_links_are_relative_and_keep_the_query(self, client: TestClient):
        # A bare "?lang=xx" replaces the whole query string, so the switcher has
        # to merge into it — otherwise /help/search?q=… loses the search on
        # every language switch.
        resp = client.get("/help/search?q=track&lang=fr")
        nav = resp.text.split("<nav>")[1].split("</nav>")[0]
        assert "q=track" in nav
        # Relative, so the request's host is never baked into the markup.
        assert "http://testserver" not in nav


class TestHelpChromeCoverage:
    """The help centre's chrome is translated for all six languages even where
    the article prose is not, so the hub, breadcrumbs and search box read
    natively from day one. An English fallback here would be invisible: the page
    still renders, just half in the wrong language."""

    @pytest.mark.parametrize("lang", SUPPORTED)
    def test_every_help_key_has_every_language(self, lang):
        missing = [
            key for key, entry in TRANSLATIONS.items()
            if key.startswith(("help_", "nav_help", "footer_help"))
            and not entry.get(lang)
        ]
        assert not missing, f"{lang} missing: {missing}"

    @pytest.mark.parametrize("lang", SUPPORTED)
    def test_diagram_labels_are_translated(self, lang):
        """/help/app-map's two SVGs are inline precisely so their labels are real
        translatable text. They were hardcoded English string literals until the
        articles were translated, which would have left the diagrams as the one
        English island on an otherwise translated page."""
        keys = [k for k in TRANSLATIONS if k.startswith("help_diag_")]
        assert len(keys) >= 15, "the diagram labels are no longer being covered"
        for key in keys:
            assert TRANSLATIONS[key].get(lang), f"{key} has no {lang}"

    def test_diagram_labels_reach_the_page(self, client: TestClient):
        # The macro is imported `with context`; without that `_` is undefined
        # inside it, because it comes from a context processor and not env.globals.
        text = client.get("/help/app-map?lang=de").text
        assert "Vier Tage in Marrakesch" in text
        assert "Four days in Marrakech" not in text
