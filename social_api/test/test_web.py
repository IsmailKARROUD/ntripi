"""
test/test_web.py — Tests for the marketing homepage and Flutter web mount.

Coverage:
  - All public GET pages return 200 with expected HTML content
  - Open Graph meta tags present on homepage
  - /login and /register redirect to /app/ (auth lives in the Flutter app)
  - Flutter web static mount behaviour (build present vs. missing)
  - GOOGLE_WEB_CLIENT_ID injection into the served index.html
"""

from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import _SPAStaticFiles


class TestPublicPages:
    def test_homepage_returns_html(self, client: TestClient):
        response = client.get("/")
        assert response.status_code == 200
        assert "text/html" in response.headers["content-type"]
        assert "Ntripi" in response.text
        assert "Continue on web" in response.text

    def test_homepage_has_open_graph_tags(self, client: TestClient):
        response = client.get("/")
        assert response.status_code == 200
        assert 'property="og:title"' in response.text
        assert 'property="og:description"' in response.text
        assert 'property="og:url"' in response.text
        assert 'property="og:image"' in response.text

    # Auth lives in the Flutter app — old links/bookmarks must land on /app/.
    def test_login_redirects_to_app(self, client: TestClient):
        response = client.get("/login", follow_redirects=False)
        assert response.status_code == 302
        assert response.headers["location"] == "/app/"

    def test_register_redirects_to_app(self, client: TestClient):
        response = client.get("/register", follow_redirects=False)
        assert response.status_code == 302
        assert response.headers["location"] == "/app/"

    def test_web_login_post_endpoint_removed(self, client: TestClient):
        response = client.post(
            "/web/login",
            data={"identifier": "a@example.com", "password": "password123"},
        )
        assert response.status_code == 404

    def test_web_register_post_endpoint_removed(self, client: TestClient):
        response = client.post("/web/register", data={})
        assert response.status_code == 404

    def test_privacy_page_renders(self, client: TestClient):
        response = client.get("/privacy")
        assert response.status_code == 200
        assert "Privacy" in response.text

    def test_terms_page_renders(self, client: TestClient):
        response = client.get("/terms")
        assert response.status_code == 200
        assert "Terms" in response.text


class TestFlutterWebMount:
    def test_app_path_returns_html_when_build_exists(self, tmp_path):
        """_SPAStaticFiles serves index.html at the mount root."""
        (tmp_path / "index.html").write_text(
            "<!DOCTYPE html><html><head></head><body>Flutter</body></html>"
        )
        test_app = FastAPI()
        test_app.mount("/app", _SPAStaticFiles(directory=str(tmp_path), html=True), name="fw")
        with TestClient(test_app) as c:
            resp = c.get("/app/")
        assert resp.status_code == 200
        assert "<html" in resp.text

    def test_app_subpath_falls_back_to_index(self, tmp_path):
        """Unmatched sub-paths return index.html so Flutter's client-side router handles them."""
        content = "<!DOCTYPE html><html><head></head><body>Flutter SPA</body></html>"
        (tmp_path / "index.html").write_text(content)
        test_app = FastAPI()
        test_app.mount("/app", _SPAStaticFiles(directory=str(tmp_path), html=True), name="fw")
        with TestClient(test_app) as c:
            resp = c.get("/app/itineraries/abc123")
        assert resp.status_code == 200
        assert "Flutter SPA" in resp.text

    def test_app_returns_404_when_build_missing(self, client: TestClient):
        """/app/ returns 404 in dev when the Flutter build directory is absent."""
        assert not Path("/app/web_build").exists(), (
            "/app/web_build should not exist in the test environment"
        )
        resp = client.get("/app/")
        assert resp.status_code == 404


_GSI_INDEX_HTML = (
    "<!DOCTYPE html><html><head>"
    '<meta name="google-signin-client_id" '
    'content="YOUR_WEB_CLIENT_ID.apps.googleusercontent.com">'
    "</head><body>Flutter</body></html>"
)


class TestGoogleClientIdInjection:
    """index.html is served with GOOGLE_WEB_CLIENT_ID injected into the
    google-signin-client_id meta tag — the value google_sign_in_web reads."""

    def _mounted_client(self, tmp_path) -> TestClient:
        (tmp_path / "index.html").write_text(_GSI_INDEX_HTML)
        test_app = FastAPI()
        test_app.mount(
            "/app", _SPAStaticFiles(directory=str(tmp_path), html=True), name="fw"
        )
        return TestClient(test_app)

    def test_meta_tag_gets_configured_client_id(self, tmp_path, monkeypatch):
        monkeypatch.setattr(
            get_settings(), "GOOGLE_WEB_CLIENT_ID", "test-id.apps.googleusercontent.com"
        )
        with self._mounted_client(tmp_path) as c:
            resp = c.get("/app/")
        assert resp.status_code == 200
        assert 'content="test-id.apps.googleusercontent.com"' in resp.text
        assert "YOUR_WEB_CLIENT_ID" not in resp.text
        # index.html must always revalidate — it carries the injected id and
        # references content-hashed assets that change on every deploy.
        assert resp.headers["cache-control"] == "no-cache"

    def test_spa_fallback_serves_injected_copy(self, tmp_path, monkeypatch):
        monkeypatch.setattr(
            get_settings(), "GOOGLE_WEB_CLIENT_ID", "test-id.apps.googleusercontent.com"
        )
        with self._mounted_client(tmp_path) as c:
            resp = c.get("/app/itineraries/deep-link")
        assert resp.status_code == 200
        assert 'content="test-id.apps.googleusercontent.com"' in resp.text

    def test_meta_tag_left_unchanged_when_client_id_unset(self, tmp_path, monkeypatch):
        monkeypatch.setattr(get_settings(), "GOOGLE_WEB_CLIENT_ID", "")
        with self._mounted_client(tmp_path) as c:
            resp = c.get("/app/")
        assert resp.status_code == 200
        assert "YOUR_WEB_CLIENT_ID.apps.googleusercontent.com" in resp.text
