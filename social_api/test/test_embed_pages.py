"""
test_embed_pages.py — /embed/*, the one page every Google map is drawn through.

Pinned: invisible without GOOGLE_MAPS_EMBED_API_KEY; only the documented
parameters, each validated, and nothing from a refused request echoed back;
the Google URL is built here with the key; and /embed is the only path family
our own pages may frame — every other route still answers DENY.
"""

from __future__ import annotations

import html
import re
from urllib.parse import parse_qs, urlparse

import pytest

from app.config import get_settings
from app.middleware import is_embed_path

PLACE_ID = "ChIJLU7jZClu5kcR4PcOOO6p3I0"


@pytest.fixture()
def embed_key(monkeypatch):
    monkeypatch.setattr(get_settings(), "GOOGLE_MAPS_EMBED_API_KEY", "test-embed-key")


def _src(response) -> tuple[str, dict[str, list[str]]]:
    match = re.search(r'<iframe src="([^"]+)"', response.text)
    assert match, response.text
    url = html.unescape(match.group(1))
    parsed = urlparse(url)
    return f"{parsed.scheme}://{parsed.netloc}{parsed.path}", parse_qs(parsed.query)


@pytest.mark.parametrize("path", [
    f"/embed/place?id={PLACE_ID}",
    "/embed/point?lat=48.85&lng=2.35",
    "/embed/search?q=Eiffel",
    "/embed/directions?points=1,2|3,4",
])
def test_without_the_key_there_is_no_map(client, path):
    assert client.get(path).status_code == 404


def test_a_place_by_its_id(client, embed_key):
    response = client.get(f"/embed/place?id={PLACE_ID}&language=fr")

    assert response.status_code == 200
    base, query = _src(response)
    assert base == "https://www.google.com/maps/embed/v1/place"
    assert query == {"key": ["test-embed-key"], "q": [f"place_id:{PLACE_ID}"],
                     "zoom": ["12"], "language": ["fr"]}
    assert '<html lang="fr">' in response.text


def test_a_point_and_a_search(client, embed_key):
    _, point = _src(client.get("/embed/point?lat=48.858370&lng=-2.5"))
    assert point["q"] == ["48.85837,-2.5"]
    assert point["language"] == ["en"]

    _, search = _src(client.get("/embed/search?q=Caf%C3%A9 de Flore"))
    assert search["q"] == ["Café de Flore"]


def test_a_route_with_waypoints_and_no_travel_mode(client, embed_key):
    response = client.get(
        f"/embed/directions?points=48.85,2.35|place_id:{PLACE_ID}|50.85,4.35"
    )

    assert response.status_code == 200
    base, query = _src(response)
    assert base == "https://www.google.com/maps/embed/v1/directions"
    assert query["origin"] == ["48.85,2.35"]
    assert query["waypoints"] == [f"place_id:{PLACE_ID}"]
    assert query["destination"] == ["50.85,4.35"]
    assert "mode" not in query


def test_twenty_two_points_is_the_most_a_route_takes(client, embed_key):
    points = "|".join(f"{i}.5,{i}.5" for i in range(22))
    assert client.get(f"/embed/directions?points={points}").status_code == 200
    assert client.get(f"/embed/directions?points={points}|9,9").status_code == 400
    assert client.get("/embed/directions?points=1,2").status_code == 400


@pytest.mark.parametrize("path", [
    "/embed/place?id=not/an/id",
    "/embed/place",
    "/embed/point?lat=91&lng=0",
    "/embed/point?lat=nan&lng=0",
    "/embed/point?lat=1",
    "/embed/search?q=",
    "/embed/search?q=" + "x" * 201,
    "/embed/directions?points=1,2|place_id:bad id",
    "/embed/directions?points=1,2|3",
    f"/embed/place?id={PLACE_ID}&language=xx",
    # `lang` would make LanguageCookieMiddleware set the web cookie.
    f"/embed/place?id={PLACE_ID}&lang=fr",
    f"/embed/place?id={PLACE_ID}&id={PLACE_ID}",
    f"/embed/place?id={PLACE_ID}&key=attacker",
])
def test_anything_else_is_refused_and_nothing_is_echoed(client, embed_key, path):
    response = client.get(path + "&marker=<script>x</script>"
                          if "?" in path else path + "?marker=<script>x</script>")
    assert response.status_code == 400
    assert response.text == ""
    assert "set-cookie" not in response.headers

    plain = client.get(path)
    assert plain.status_code == 400
    assert plain.headers["cache-control"] == "no-store"


def test_only_embed_pages_may_be_framed_and_only_by_us(client, embed_key, monkeypatch):
    page = client.get(f"/embed/place?id={PLACE_ID}")
    assert page.headers["x-frame-options"] == "SAMEORIGIN"
    csp = page.headers["content-security-policy"]
    assert "frame-ancestors 'self'" in csp
    assert "default-src 'none'" in csp and "frame-src https://www.google.com" in csp
    assert page.headers["x-robots-tag"] == "noindex"
    assert page.headers["cache-control"] == "public, max-age=86400"

    # As a .env file delivers it: the quotes around self stripped.
    monkeypatch.setattr(get_settings(), "EMBED_FRAME_ANCESTORS",
                        "self http://localhost:5555")
    dev = client.get(f"/embed/place?id={PLACE_ID}")
    assert "frame-ancestors 'self' http://localhost:5555" in dev.headers[
        "content-security-policy"]

    for other in ("/health", "/privacy", "/embedded"):
        response = client.get(other)
        assert response.headers["x-frame-options"] == "DENY", other
        assert response.headers["content-security-policy"] == "frame-ancestors 'none'"


def test_embed_paths_match_on_a_segment_boundary():
    assert is_embed_path("/embed")
    assert is_embed_path("/embed/place")
    assert not is_embed_path("/embedded")
    assert not is_embed_path("/embedx/place")
