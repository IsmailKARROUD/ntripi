"""test_web_i18n.py — Verifies web pages render French/Arabic via
Accept-Language / ?lang= while defaulting to English (so the existing
test_web/test_share suites, which send no language header, stay green).
Arabic must also flip the document to dir="rtl".

Uses /reset-password as the rendered-page vehicle — the login/register pages
were removed (auth lives in the Flutter app; /login now 302s to /app/).
"""

from fastapi.testclient import TestClient


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

    def test_switcher_lists_other_languages(self, client: TestClient):
        # Current language absent from the switcher, every other one linked.
        #
        # Scoped to <nav> rather than the whole document: the page now also
        # carries a canonical link and an hreflang set, and both legitimately
        # name the language currently being served.
        resp = client.get("/reset-password?lang=ar")
        nav = resp.text.split("<nav>")[1].split("</nav>")[0]
        assert "?lang=ar" not in nav
        for code in ("en", "fr", "de", "es", "zh"):
            assert f"?lang={code}" in nav

    def test_switcher_links_are_relative_and_keep_the_query(self, client: TestClient):
        # A bare "?lang=xx" replaces the whole query string, so the switcher has
        # to merge into it — otherwise /help/search?q=… loses the search on
        # every language switch.
        resp = client.get("/help/search?q=track&lang=fr")
        nav = resp.text.split("<nav>")[1].split("</nav>")[0]
        assert "q=track" in nav
        # Relative, so the request's host is never baked into the markup.
        assert "http://testserver" not in nav
