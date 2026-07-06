"""test_web_i18n.py — Verifies web pages render French/Arabic via
Accept-Language / ?lang= while defaulting to English (so the existing
test_web/test_share suites, which send no language header, stay green).
Arabic must also flip the document to dir="rtl".
"""

from fastapi.testclient import TestClient


class TestWebI18n:
    def test_default_is_english(self, client: TestClient):
        resp = client.get("/login")
        assert resp.status_code == 200
        assert "Sign in to Ntripi" in resp.text
        assert 'lang="en"' in resp.text
        assert 'dir="ltr"' in resp.text

    def test_accept_language_fr_renders_french(self, client: TestClient):
        resp = client.get("/login", headers={"Accept-Language": "fr-FR,fr;q=0.9"})
        assert resp.status_code == 200
        assert "Connectez-vous à Ntripi" in resp.text
        assert 'lang="fr"' in resp.text
        # HTML must advertise language variance for caches.
        assert "accept-language" in resp.headers.get("vary", "").lower()

    def test_lang_query_override_wins_and_sets_cookie(self, client: TestClient):
        # ?lang=fr beats an English Accept-Language header.
        resp = client.get(
            "/register?lang=fr", headers={"Accept-Language": "en-US,en;q=0.9"}
        )
        assert resp.status_code == 200
        assert "Créez votre compte Ntripi" in resp.text
        assert resp.cookies.get("ntripi_lang") == "fr"

    def test_share_not_found_localized(self, client: TestClient):
        resp = client.get(
            "/share/i/00000000-0000-0000-0000-000000000000?lang=fr"
        )
        assert resp.status_code == 404
        assert "Itinéraire introuvable" in resp.text

    def test_accept_language_ar_renders_arabic_rtl(self, client: TestClient):
        resp = client.get("/login", headers={"Accept-Language": "ar-MA,ar;q=0.9"})
        assert resp.status_code == 200
        assert "سجّل الدخول إلى Ntripi" in resp.text
        assert 'lang="ar"' in resp.text
        assert 'dir="rtl"' in resp.text
        assert "accept-language" in resp.headers.get("vary", "").lower()

    def test_lang_query_ar_wins_and_sets_cookie(self, client: TestClient):
        resp = client.get(
            "/register?lang=ar", headers={"Accept-Language": "en-US,en;q=0.9"}
        )
        assert resp.status_code == 200
        assert "أنشئ حسابك على Ntripi" in resp.text
        assert 'dir="rtl"' in resp.text
        assert resp.cookies.get("ntripi_lang") == "ar"

    def test_share_not_found_arabic(self, client: TestClient):
        resp = client.get(
            "/share/i/00000000-0000-0000-0000-000000000000?lang=ar"
        )
        assert resp.status_code == 404
        assert "خط السير غير موجود" in resp.text

    def test_switcher_lists_other_languages(self, client: TestClient):
        # 3-way switcher: current language absent, the other two linked.
        resp = client.get("/login?lang=ar")
        assert '?lang=en' in resp.text and '?lang=fr' in resp.text
        assert '?lang=ar' not in resp.text.replace("/login?lang=ar", "")
