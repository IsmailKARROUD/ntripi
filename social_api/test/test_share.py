"""
test_share.py — Tests for the public share landing page endpoint.

GET /share/i/{itinerary_id} returns HTML, not JSON.
No authentication required for any of these tests.

Coverage:
  TestSharePublicItinerary:
    - The teaser and nothing else: title, cover, rating, description
    - No owner, no stops, no stats — the rest is behind sign-in
    - The preview card says what the page says
    - The one way in: the web app, at the same trip; stores live only once set
    - Rate limited per IP, with an HTML 429

  TestSharePrivateItinerary:
    - followers-only itinerary shows minimal page (no stops)
    - restricted itinerary shows minimal page (no stops)
    - neither page, nor its preview card, names the trip, the owner or the cover
    - only_me itinerary returns 404

  TestShareNotFound:
    - Non-existent UUID returns 404
    - A malformed or cut-short id gets the same HTML page, not JSON
"""

import uuid

import pytest
from fastapi.testclient import TestClient

from app.models.itinerary import Itinerary

from conftest import TestingSessionLocal, auth_headers, edit_now, register_user


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def create_itinerary(client, token, *, visibility="public", title="Test Trip"):
    r = client.post(
        "/itineraries/",
        json={"title": title, "visibility": visibility},
        headers=auth_headers(token),
    )
    assert r.status_code == 201, r.json()
    return r.json()


def add_stop(client, token, itinerary_id, *, place_name):
    # No anchor: the server appends a new track. Stop role (origin/arrival) is
    # derived client-side, never sent.
    r = client.post(
        f"/itineraries/{itinerary_id}/stops",
        json={"place_name": place_name},
        headers=edit_now(client, itinerary_id, auth_headers(token)),
    )
    assert r.status_code == 201, r.json()
    return r.json()


def share_url(itinerary_id):
    return f"/share/i/{itinerary_id}"


def set_fields(itinerary_id, **fields):
    """Write columns the API sets only through other flows (cover upload, the
    rating aggregate) — only the stored values matter here."""
    db = TestingSessionLocal()
    try:
        row = db.get(Itinerary, uuid.UUID(itinerary_id))
        for name, value in fields.items():
            setattr(row, name, value)
        db.commit()
    finally:
        db.close()


def set_cover(itinerary_id, url):
    """Give a trip a cover without the upload pipeline — only the URL matters."""
    set_fields(itinerary_id, cover_image_url=url)


def og_description(html):
    return html.split('property="og:description" content="', 1)[1].split('"', 1)[0]


# ---------------------------------------------------------------------------
# TestSharePublicItinerary
# ---------------------------------------------------------------------------

class TestSharePublicItinerary:

    def test_public_itinerary_returns_the_teaser(self, client):
        alice = register_user(client, "alice_share", "alice_share@test.com")
        token = alice["access_token"]
        itinerary = create_itinerary(
            client, token, visibility="public", title="Weekend in Paris"
        )
        client.patch(
            f"/itineraries/{itinerary['id']}",
            json={"description": "Two slow days on foot."},
            headers=edit_now(client, itinerary["id"], auth_headers(token)),
        )
        set_cover(itinerary["id"], "https://images.example/paris.jpg")

        r = client.get(share_url(itinerary["id"]))

        assert r.status_code == 200
        assert "text/html" in r.headers["content-type"]
        assert "Weekend in Paris" in r.text
        assert "Two slow days on foot." in r.text
        assert "https://images.example/paris.jpg" in r.text

    def test_public_teaser_names_no_owner(self, client):
        """The owner is not teaser content — the trip page names nobody."""
        alice = register_user(client, "alice_owner", "alice_owner@test.com",
                              display_name="Alice Owner")
        itinerary = create_itinerary(client, alice["access_token"], visibility="public")

        r = client.get(share_url(itinerary["id"]))

        assert "alice_owner" not in r.text
        assert "Alice Owner" not in r.text

    def test_open_graph_tags_present(self, client):
        alice = register_user(client, "alice_og", "alice_og@test.com")
        token = alice["access_token"]
        itinerary = create_itinerary(
            client, token, visibility="public", title="OG Test Trip"
        )

        r = client.get(share_url(itinerary["id"]))

        assert r.status_code == 200
        assert 'property="og:title"' in r.text
        assert 'property="og:description"' in r.text
        assert 'property="og:url"' in r.text
        assert 'property="og:image"' in r.text

    def test_public_itinerary_keeps_its_stops_behind_sign_in(self, client):
        alice = register_user(client, "alice_stops", "alice_stops@test.com")
        token = alice["access_token"]
        itinerary = create_itinerary(
            client, token, visibility="public", title="3-Stop Adventure"
        )
        add_stop(client, token, itinerary["id"], place_name="Eiffel Tower")
        add_stop(client, token, itinerary["id"], place_name="Louvre Museum")

        r = client.get(share_url(itinerary["id"]))

        assert r.status_code == 200
        assert "3-Stop Adventure" in r.text
        assert "Eiffel Tower" not in r.text
        assert "Louvre Museum" not in r.text
        # Nor the stats the old page carried.
        assert "2 stops" not in r.text

    def test_rating_shows_average_and_count(self, client):
        alice = register_user(client, "alice_rated", "alice_rated@test.com")
        itinerary = create_itinerary(client, alice["access_token"], visibility="public")
        set_fields(itinerary["id"], rating_avg=4.5, rating_count=12)

        html = client.get(share_url(itinerary["id"])).text

        assert "4.5" in html
        assert "12 ratings" in html

    def test_card_says_what_the_page_says(self, client):
        alice = register_user(client, "alice_card", "alice_card@test.com")
        token = alice["access_token"]
        itinerary = create_itinerary(client, token, visibility="public")
        client.patch(
            f"/itineraries/{itinerary['id']}",
            json={"description": "Markets at dawn, the old port by night."},
            headers=edit_now(client, itinerary["id"], auth_headers(token)),
        )
        set_fields(itinerary["id"], rating_avg=4.6, rating_count=3)

        card = og_description(client.get(share_url(itinerary["id"])).text)

        assert card == "★ 4.6 (3) · Markets at dawn, the old port by night."

    def test_card_falls_back_when_there_is_nothing_to_say(self, client):
        alice = register_user(client, "alice_bare", "alice_bare@test.com")
        itinerary = create_itinerary(client, alice["access_token"], visibility="public")

        card = og_description(client.get(share_url(itinerary["id"])).text)

        assert card == "A trip on Ntripi"

    def test_long_description_is_cut_on_a_word_in_the_card(self, client):
        alice = register_user(client, "alice_long", "alice_long@test.com")
        token = alice["access_token"]
        itinerary = create_itinerary(client, token, visibility="public")
        long_text = "word " * 80
        client.patch(
            f"/itineraries/{itinerary['id']}",
            json={"description": long_text},
            headers=edit_now(client, itinerary["id"], auth_headers(token)),
        )

        card = og_description(client.get(share_url(itinerary["id"])).text)

        assert card.endswith("word…")
        assert len(card) <= 151

    def test_the_way_in_is_the_web_app_at_the_same_trip(self, client):
        alice = register_user(client, "alice_gate", "alice_gate@test.com")
        itinerary = create_itinerary(client, alice["access_token"], visibility="public")

        html = client.get(share_url(itinerary["id"])).text

        assert f'href="/app/#/share/i/{itinerary["id"]}"' in html
        assert "See the full trip" in html
        assert "Free account needed" in html
        # The reinstall hint waits for a live store.
        assert "data-store-hint hidden" in html

    def test_public_itinerary_requires_no_auth(self, client):
        alice = register_user(client, "alice_noauth", "alice_noauth@test.com")
        token = alice["access_token"]
        itinerary = create_itinerary(client, token, visibility="public")

        # Deliberately no Authorization header.
        r = client.get(share_url(itinerary["id"]))

        assert r.status_code == 200

    def test_rate_limited_with_an_html_page(self, client, monkeypatch):
        from app.config import get_settings

        alice = register_user(client, "alice_limit", "alice_limit@test.com")
        itinerary = create_itinerary(client, alice["access_token"], visibility="public")
        monkeypatch.setattr(get_settings(), "SHARE_RATE_LIMIT", "2/minute")

        codes = [client.get(share_url(itinerary["id"])).status_code for _ in range(2)]
        r = client.get(share_url(itinerary["id"]))

        assert codes == [200, 200]
        assert r.status_code == 429
        # A browser gets a page, not slowapi's JSON.
        assert "text/html" in r.headers["content-type"]
        assert r.headers["retry-after"] == "60"
        assert "Too many requests" in r.text

    def test_other_limited_routes_keep_the_json_429(self, client, monkeypatch):
        from app.config import get_settings

        monkeypatch.setattr(get_settings(), "REPORT_RATE_LIMIT", "1/minute")
        body = {"itinerary_id": str(uuid.uuid4()), "reason": "spam"}
        client.post("/reports", json=body)
        r = client.post("/reports", json=body)

        assert r.status_code == 429
        assert r.headers["content-type"].startswith("application/json")


# ---------------------------------------------------------------------------
# TestSharePrivateItinerary
# ---------------------------------------------------------------------------

class TestSharePrivateItinerary:

    def test_followers_itinerary_shows_minimal_page(self, client):
        alice = register_user(client, "alice_priv1", "alice_priv1@test.com")
        token = alice["access_token"]
        itinerary = create_itinerary(
            client, token, visibility="followers", title="Private Followers Trip"
        )
        add_stop(client, token, itinerary["id"], place_name="Secret Spot")

        r = client.get(share_url(itinerary["id"]))

        assert r.status_code == 200
        assert "text/html" in r.headers["content-type"]
        # Shows private message.
        assert "private" in r.text.lower()
        # Does NOT expose stop names.
        assert "Secret Spot" not in r.text
        # Does NOT expose full stats (no "stops" count etc.).
        assert "1 stop" not in r.text

    def test_restricted_itinerary_shows_minimal_page(self, client):
        alice = register_user(client, "alice_priv2", "alice_priv2@test.com")
        token = alice["access_token"]
        itinerary = create_itinerary(
            client, token, visibility="restricted", title="Restricted Trip"
        )
        add_stop(client, token, itinerary["id"], place_name="Hidden Gem")

        r = client.get(share_url(itinerary["id"]))

        assert r.status_code == 200
        assert "private" in r.text.lower()
        assert "Hidden Gem" not in r.text

    @pytest.mark.parametrize("visibility", ["followers", "restricted"])
    def test_private_page_names_nothing(self, client, visibility):
        """The page and its preview card reach everyone the link reaches — mostly
        people who cannot open the trip — so they carry no title, owner or cover."""
        owner = register_user(client, f"owner_{visibility}", f"o_{visibility}@test.com")
        itinerary = create_itinerary(
            client, owner["access_token"], visibility=visibility,
            title="Anniversary in Kyoto",
        )
        set_cover(itinerary["id"], "/uploads/itineraries/secret-cover.jpg")

        r = client.get(share_url(itinerary["id"]))

        assert r.status_code == 200
        assert "Anniversary in Kyoto" not in r.text
        assert f"owner_{visibility}" not in r.text
        assert "secret-cover.jpg" not in r.text
        # The card still exists, so the chat shows *something* — the default.
        assert 'property="og:image"' in r.text
        assert "ntripi-og-default.png" in r.text

    def test_only_me_itinerary_returns_404(self, client):
        alice = register_user(client, "alice_onlyme", "alice_onlyme@test.com")
        token = alice["access_token"]
        itinerary = create_itinerary(client, token, visibility="only_me")

        r = client.get(share_url(itinerary["id"]))

        assert r.status_code == 404
        assert "text/html" in r.headers["content-type"]
        # Must not leak that the itinerary exists.
        assert itinerary["title"] not in r.text


# ---------------------------------------------------------------------------
# TestShareNotFound
# ---------------------------------------------------------------------------

class TestShareNotFound:

    def test_nonexistent_itinerary_returns_404(self, client):
        nonexistent = "00000000-0000-0000-0000-000000000000"
        r = client.get(share_url(nonexistent))

        assert r.status_code == 404
        assert "text/html" in r.headers["content-type"]

    @pytest.mark.parametrize("bad_id", [
        "3fa85f64-5717-4562",  # cut short when it was copied
        "new",
        "not-a-uuid",
    ])
    def test_malformed_id_returns_the_html_404(self, client, bad_id):
        r = client.get(share_url(bad_id))

        # FastAPI would answer a typed route param with a raw JSON 422.
        assert r.status_code == 404
        assert "text/html" in r.headers["content-type"]
        assert "Itinerary not found" in r.text

    def test_private_og_tags_present(self, client):
        alice = register_user(client, "alice_privog", "alice_privog@test.com")
        token = alice["access_token"]
        itinerary = create_itinerary(
            client, token, visibility="followers", title="Follower OG Trip"
        )

        r = client.get(share_url(itinerary["id"]))

        # OG tags must exist on private pages too (for messaging app previews).
        assert r.status_code == 200
        assert 'property="og:title"' in r.text
        assert 'property="og:image"' in r.text
