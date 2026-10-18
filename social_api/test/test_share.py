"""
test_share.py — Tests for the public share landing page endpoint.

GET /share/i/{itinerary_id} returns HTML, not JSON.
No authentication required for any of these tests.

Coverage:
  TestSharePublicItinerary:
    - Rich landing page returned for public itinerary
    - Open Graph meta tags present
    - Stop names appear in HTML
    - No auth header required

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


def set_cover(itinerary_id, url):
    """Give a trip a cover without the upload pipeline — only the URL matters."""
    db = TestingSessionLocal()
    try:
        row = db.get(Itinerary, uuid.UUID(itinerary_id))
        row.cover_image_url = url
        db.commit()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# TestSharePublicItinerary
# ---------------------------------------------------------------------------

class TestSharePublicItinerary:

    def test_public_itinerary_returns_rich_landing_page(self, client):
        alice = register_user(client, "alice_share", "alice_share@test.com")
        token = alice["access_token"]
        itinerary = create_itinerary(
            client, token, visibility="public", title="Weekend in Paris"
        )

        r = client.get(share_url(itinerary["id"]))

        assert r.status_code == 200
        assert "text/html" in r.headers["content-type"]
        assert "Weekend in Paris" in r.text
        assert "alice_share" in r.text

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

    def test_public_itinerary_shows_stops(self, client):
        alice = register_user(client, "alice_stops", "alice_stops@test.com")
        token = alice["access_token"]
        itinerary = create_itinerary(
            client, token, visibility="public", title="3-Stop Adventure"
        )
        add_stop(client, token, itinerary["id"], place_name="Eiffel Tower")
        add_stop(client, token, itinerary["id"], place_name="Louvre Museum")
        add_stop(client, token, itinerary["id"], place_name="Arc de Triomphe")

        r = client.get(share_url(itinerary["id"]))

        assert r.status_code == 200
        assert "Eiffel Tower" in r.text
        assert "Louvre Museum" in r.text
        assert "Arc de Triomphe" in r.text

    def test_public_itinerary_requires_no_auth(self, client):
        alice = register_user(client, "alice_noauth", "alice_noauth@test.com")
        token = alice["access_token"]
        itinerary = create_itinerary(client, token, visibility="public")

        # Deliberately no Authorization header.
        r = client.get(share_url(itinerary["id"]))

        assert r.status_code == 200


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
