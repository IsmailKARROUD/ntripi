"""
test_share_profile.py — Tests for GET /share/u/{username}.

Returns HTML, not JSON, and requires no authentication.

Coverage:
  TestSharePublicProfile   — the teaser: display name, @username, avatar; OG tags;
                             no bio, counts or itineraries (behind sign-in)
  TestSharePrivateProfile  — the same three fields, noindex
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
    def test_renders_name_handle_and_avatar(self, client):
        user = register_user(client, "wanderer", "w@example.com",
                             display_name="Wanderer W")
        make_public(client, user["access_token"])
        set_user_field("wanderer", avatar_url="https://images.example/w.jpg")

        r = client.get("/share/u/wanderer")

        assert r.status_code == 200
        assert "text/html" in r.headers["content-type"]
        assert "Wanderer W" in r.text
        assert "@wanderer" in r.text
        assert "https://images.example/w.jpg" in r.text

    def test_bio_and_counts_stay_behind_sign_in(self, client):
        user = register_user(client, "chatty", "chatty@example.com")
        make_public(client, user["access_token"])
        client.patch("/users/me", json={"bio": "Chasing trains since 2019."},
                     headers=auth_headers(user["access_token"]))

        r = client.get("/share/u/chatty")

        assert "Chasing trains since 2019." not in r.text
        assert "Followers" not in r.text
        assert 'href="/app/#/share/u/chatty"' in r.text
        assert "See the full profile" in r.text

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

    def test_lists_no_itineraries(self, client):
        """Even a public trip is not named here — bots find trips through their
        own share pages, people through the app."""
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

        assert "Public Trip" not in r.text
        assert "Secret Trip" not in r.text
        assert "Followers Trip" not in r.text

    def test_public_profile_is_indexable(self, client):
        user = register_user(client, "findme", "findme@example.com")
        make_public(client, user["access_token"])

        assert "noindex" not in client.get("/share/u/findme").text


class TestSharePrivateProfile:
    def test_private_profile_shows_the_same_three_fields(self, client):
        user = register_user(client, "shyperson", "shy@example.com",
                             display_name="Shy Person")
        token = user["access_token"]
        # Accounts are private by default; set a bio to prove it is withheld.
        client.patch("/users/me", json={"bio": "My private notes."},
                     headers=auth_headers(token))
        client.post("/itineraries/",
                    json={"title": "Hidden Journey", "visibility": "public"},
                    headers=auth_headers(token))
        set_user_field("shyperson", avatar_url="https://images.example/shy.jpg")

        r = client.get("/share/u/shyperson")

        assert r.status_code == 200
        assert "Shy Person" in r.text
        assert "@shyperson" in r.text
        assert "https://images.example/shy.jpg" in r.text
        # Neither the bio nor any itinerary leaks from a private account.
        assert "My private notes." not in r.text
        assert "Hidden Journey" not in r.text

    def test_private_profile_is_noindex(self, client):
        register_user(client, "hideme", "hideme@example.com")

        assert '<meta name="robots" content="noindex,follow">' in client.get(
            "/share/u/hideme"
        ).text


class TestShareProfileNotFound:
    def test_unknown_username_returns_404(self, client):
        r = client.get("/share/u/nobody-here")

        assert r.status_code == 404
        assert "text/html" in r.headers["content-type"]

    def test_dead_profile_link_says_account_not_itinerary(self, client):
        """The same words the app's ProfileUnavailableView uses."""
        r = client.get("/share/u/nobody-here")

        assert "Account unavailable" in r.text
        assert "itinerary" not in r.text.lower()

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
