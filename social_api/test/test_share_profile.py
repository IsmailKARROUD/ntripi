"""
test_share_profile.py — Tests for GET /share/u/{username}.

Returns HTML, not JSON, and requires no authentication.

Coverage:
  TestSharePublicProfile   — rich page, OG tags, public itineraries listed
  TestSharePrivateProfile  — minimal page, no bio / counts / itineraries
  TestShareProfileNotFound — unknown handle and deactivated account both 404
  TestShareProfileModeration — hidden profile text degrades to the handle
"""

from app.models.user import User

from conftest import TestingSessionLocal, auth_headers, register_user


def make_public(client, token):
    """Accounts default to is_private=True, so the public branch needs a flip."""
    r = client.patch("/users/me", json={"is_private": False},
                     headers=auth_headers(token))
    assert r.status_code == 200, r.json()
    return r.json()


def set_user_field(username: str, **fields) -> None:
    """Write a column the API deliberately does not expose (ban, moderation)."""
    db = TestingSessionLocal()
    try:
        row = db.query(User).filter(User.username_lower == username).one()
        for k, v in fields.items():
            setattr(row, k, v)
        db.commit()
    finally:
        db.close()


class TestSharePublicProfile:
    def test_renders_name_handle_and_bio(self, client):
        user = register_user(client, "wanderer", "w@example.com",
                             display_name="Wanderer W")
        make_public(client, user["access_token"])
        client.patch("/users/me", json={"bio": "Chasing trains since 2019."},
                     headers=auth_headers(user["access_token"]))

        r = client.get("/share/u/wanderer")

        assert r.status_code == 200
        assert "text/html" in r.headers["content-type"]
        assert "Wanderer W" in r.text
        assert "@wanderer" in r.text
        assert "Chasing trains since 2019." in r.text

    def test_has_open_graph_tags(self, client):
        user = register_user(client, "oguser", "og@example.com",
                             display_name="OG User")
        make_public(client, user["access_token"])

        r = client.get("/share/u/oguser")

        assert 'property="og:type"' in r.text
        assert 'content="profile"' in r.text
        assert 'property="og:title"' in r.text
        assert "/share/u/oguser" in r.text

    def test_lookup_is_case_insensitive(self, client):
        """username_lower is the lookup key, so the handle's case must not matter."""
        user = register_user(client, "mixedcase", "mc@example.com")
        make_public(client, user["access_token"])

        assert client.get("/share/u/MixedCase").status_code == 200

    def test_no_auth_header_required(self, client):
        user = register_user(client, "anonvisitor", "anon@example.com")
        make_public(client, user["access_token"])

        r = client.get("/share/u/anonvisitor")

        assert r.status_code == 200

    def test_lists_public_itineraries_only(self, client):
        user = register_user(client, "lister", "l@example.com")
        token = user["access_token"]
        make_public(client, token)

        for title, visibility in [
            ("Public Trip", "public"),
            ("Secret Trip", "only_me"),
            ("Followers Trip", "followers"),
        ]:
            r = client.post("/itineraries/",
                            json={"title": title, "visibility": visibility},
                            headers=auth_headers(token))
            assert r.status_code == 201, r.json()

        r = client.get("/share/u/lister")

        assert "Public Trip" in r.text
        # A non-public itinerary must not be named on a page anyone can load.
        assert "Secret Trip" not in r.text
        assert "Followers Trip" not in r.text

    def test_empty_state_when_no_public_itineraries(self, client):
        user = register_user(client, "newbie", "n@example.com")
        make_public(client, user["access_token"])

        r = client.get("/share/u/newbie")

        assert r.status_code == 200
        assert "No public itineraries yet." in r.text


class TestSharePrivateProfile:
    def test_private_profile_shows_minimal_page(self, client):
        user = register_user(client, "shyperson", "shy@example.com",
                             display_name="Shy Person")
        token = user["access_token"]
        # Accounts are private by default; set a bio to prove it is withheld.
        client.patch("/users/me", json={"bio": "My private notes."},
                     headers=auth_headers(token))
        client.post("/itineraries/",
                    json={"title": "Hidden Journey", "visibility": "public"},
                    headers=auth_headers(token))

        r = client.get("/share/u/shyperson")

        assert r.status_code == 200
        assert "Shy Person" in r.text
        assert "@shyperson" in r.text
        # Neither the bio nor any itinerary leaks from a private account.
        assert "My private notes." not in r.text
        assert "Hidden Journey" not in r.text


class TestShareProfileNotFound:
    def test_unknown_username_returns_404(self, client):
        r = client.get("/share/u/nobody-here")

        assert r.status_code == 404
        assert "text/html" in r.headers["content-type"]

    def test_deactivated_account_returns_404(self, client):
        """A banned account must be indistinguishable from one that never existed."""
        user = register_user(client, "banned", "b@example.com")
        make_public(client, user["access_token"])

        set_user_field("banned", is_active=False)

        assert client.get("/share/u/banned").status_code == 404


class TestShareProfileModeration:
    def test_hidden_profile_text_degrades_to_handle(self, client):
        """moderation_status covers display_name + bio only — the page still renders."""
        user = register_user(client, "flagged", "f@example.com",
                             display_name="Rude Name")
        token = user["access_token"]
        make_public(client, token)
        client.patch("/users/me", json={"bio": "Rude bio."},
                     headers=auth_headers(token))

        set_user_field("flagged", moderation_status="hidden")

        r = client.get("/share/u/flagged")

        assert r.status_code == 200
        assert "Rude Name" not in r.text
        assert "Rude bio." not in r.text
        assert "@flagged" in r.text
