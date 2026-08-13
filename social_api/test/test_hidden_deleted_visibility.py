"""
test_hidden_deleted_visibility.py — Who can see moderated content.

The rules, enforced centrally in can_view_itinerary() plus the raw list/share
queries that bypass it:

  hidden_at set  → only the author (with a banner); gone from feed, other users'
                   profiles, saved lists, share pages, and the report endpoint.
                   The author can still edit it.
  deleted_at set → nobody, the author included (404 everywhere).
  owner banned   → all their content behaves as hidden until they are unbanned.

Also pins the ETag invariant: moderator flags must not bump updated_at, or the
author's in-flight edit session would start 412-ing.
"""

import pytest
from fastapi.testclient import TestClient

from conftest import (
    ADMIN_BASIC, TestingSessionLocal, admin_session, auth_headers, edit_now,
    locked_headers, make_admin, register_user,
)
from app.models.content_report import ContentReport
from app.models.itinerary import Itinerary


def _itinerary(client: TestClient, token: str, title: str = "Trip",
               visibility: str = "public") -> str:
    resp = client.post(
        "/itineraries/",
        json={"title": title, "currency": "EUR", "visibility": visibility},
        headers=auth_headers(token),
    )
    assert resp.status_code == 201, resp.json()
    return resp.json()["id"]


@pytest.fixture()
def world(client: TestClient, admin_enabled):
    """Author with a public itinerary, an unrelated viewer, and a signed-in admin."""
    author = register_user(client, "author", "author@test.com")
    viewer = register_user(client, "viewer", "viewer@test.com")
    itinerary_id = _itinerary(client, author["access_token"])

    register_user(client, "opsadmin", "ops@test.com")
    make_admin("ops@test.com")
    admin_session(client, "ops@test.com")

    return {"author": author, "viewer": viewer, "itinerary_id": itinerary_id}


def _flag(itinerary_id: str, field: str) -> None:
    """Set hidden_at/deleted_at directly — exercises the read paths without
    depending on the dashboard's form plumbing."""
    import uuid
    from datetime import datetime, timezone

    db = TestingSessionLocal()
    try:
        itinerary = db.get(Itinerary, uuid.UUID(itinerary_id))
        setattr(itinerary, field, datetime.now(timezone.utc))
        db.commit()
    finally:
        db.close()


def _ban(email: str) -> None:
    from sqlalchemy import select
    from app.models.user import User

    db = TestingSessionLocal()
    try:
        user = db.execute(select(User).where(User.email == email)).scalar_one()
        user.is_active = False
        db.commit()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Hidden
# ---------------------------------------------------------------------------

class TestHidden:

    def test_author_still_sees_it_with_the_hidden_flag(self, client, world):
        _flag(world["itinerary_id"], "hidden_at")
        resp = client.get(
            f"/itineraries/{world['itinerary_id']}",
            headers=auth_headers(world["author"]["access_token"]),
        )
        assert resp.status_code == 200
        assert resp.json()["hidden"] is True

    def test_live_itinerary_reports_hidden_false(self, client, world):
        resp = client.get(
            f"/itineraries/{world['itinerary_id']}",
            headers=auth_headers(world["author"]["access_token"]),
        )
        assert resp.json()["hidden"] is False

    def test_other_users_are_denied(self, client, world):
        _flag(world["itinerary_id"], "hidden_at")
        resp = client.get(
            f"/itineraries/{world['itinerary_id']}",
            headers=auth_headers(world["viewer"]["access_token"]),
        )
        assert resp.status_code == 403

    def test_dropped_from_the_public_feed(self, client, world):
        _flag(world["itinerary_id"], "hidden_at")
        resp = client.get(
            "/itineraries/feed", headers=auth_headers(world["viewer"]["access_token"])
        )
        assert all(i["id"] != world["itinerary_id"] for i in resp.json())

    def test_still_in_the_authors_own_list(self, client, world):
        _flag(world["itinerary_id"], "hidden_at")
        resp = client.get(
            "/itineraries/me", headers=auth_headers(world["author"]["access_token"])
        )
        assert any(i["id"] == world["itinerary_id"] for i in resp.json())

    def test_dropped_from_the_authors_public_profile(self, client, world):
        _flag(world["itinerary_id"], "hidden_at")
        resp = client.get(
            f"/users/{world['author']['user_id']}/itineraries",
            headers=auth_headers(world["viewer"]["access_token"]),
        )
        assert resp.json() == []

    def test_share_page_404s(self, client, world):
        _flag(world["itinerary_id"], "hidden_at")
        resp = client.get(f"/share/i/{world['itinerary_id']}")
        assert resp.status_code == 404

    def test_cannot_be_reported(self, client, world):
        _flag(world["itinerary_id"], "hidden_at")
        resp = client.post(
            "/reports",
            json={"itinerary_id": world["itinerary_id"], "reason": "spam"},
            headers=auth_headers(world["viewer"]["access_token"]),
        )
        # Same 404 as a missing itinerary — never leak that it was moderated.
        assert resp.status_code == 404
        assert resp.json()["code"] == "itinerary_not_found"

    def test_author_can_still_edit(self, client, world):
        _flag(world["itinerary_id"], "hidden_at")
        resp = client.patch(
            f"/itineraries/{world['itinerary_id']}",
            json={"title": "Renamed while hidden"},
            headers=edit_now(client, world["itinerary_id"],
                             auth_headers(world["author"]["access_token"])),
        )
        assert resp.status_code == 200


# ---------------------------------------------------------------------------
# Soft-deleted
# ---------------------------------------------------------------------------

class TestSoftDeleted:

    def test_author_gets_404(self, client, world):
        _flag(world["itinerary_id"], "deleted_at")
        resp = client.get(
            f"/itineraries/{world['itinerary_id']}",
            headers=auth_headers(world["author"]["access_token"]),
        )
        assert resp.status_code == 404

    def test_author_mutations_404(self, client, world):
        _flag(world["itinerary_id"], "deleted_at")
        resp = client.patch(
            f"/itineraries/{world['itinerary_id']}",
            json={"title": "Try to resurrect"},
            headers=auth_headers(world["author"]["access_token"]),
        )
        assert resp.status_code == 404

    def test_gone_from_the_authors_own_list(self, client, world):
        _flag(world["itinerary_id"], "deleted_at")
        resp = client.get(
            "/itineraries/me", headers=auth_headers(world["author"]["access_token"])
        )
        assert resp.json() == []

    def test_gone_from_the_feed_and_share_page(self, client, world):
        _flag(world["itinerary_id"], "deleted_at")
        feed = client.get(
            "/itineraries/feed", headers=auth_headers(world["viewer"]["access_token"])
        )
        assert all(i["id"] != world["itinerary_id"] for i in feed.json())
        assert client.get(f"/share/i/{world['itinerary_id']}").status_code == 404

    def test_row_and_evidence_survive(self, client, world):
        import uuid

        _flag(world["itinerary_id"], "deleted_at")
        db = TestingSessionLocal()
        try:
            row = db.get(Itinerary, uuid.UUID(world["itinerary_id"]))
            assert row is not None and row.title == "Trip"
        finally:
            db.close()


# ---------------------------------------------------------------------------
# Banned author
# ---------------------------------------------------------------------------

class TestBannedAuthorContent:

    def test_hidden_from_the_feed(self, client, world):
        _ban("author@test.com")
        resp = client.get(
            "/itineraries/feed", headers=auth_headers(world["viewer"]["access_token"])
        )
        assert all(i["id"] != world["itinerary_id"] for i in resp.json())

    def test_hidden_from_direct_reads(self, client, world):
        _ban("author@test.com")
        resp = client.get(
            f"/itineraries/{world['itinerary_id']}",
            headers=auth_headers(world["viewer"]["access_token"]),
        )
        assert resp.status_code == 403

    def test_share_page_404s(self, client, world):
        _ban("author@test.com")
        assert client.get(f"/share/i/{world['itinerary_id']}").status_code == 404

    def test_saved_copy_disappears_for_other_users(self, client, world):
        viewer_headers = auth_headers(world["viewer"]["access_token"])
        save = client.post(
            f"/itineraries/{world['itinerary_id']}/save", headers=viewer_headers
        )
        assert save.status_code in (200, 201, 204)
        before = client.get("/itineraries/saved", headers=viewer_headers)
        assert any(i["id"] == world["itinerary_id"] for i in before.json())

        _ban("author@test.com")

        after = client.get("/itineraries/saved", headers=viewer_headers)
        assert all(i["id"] != world["itinerary_id"] for i in after.json())


# ---------------------------------------------------------------------------
# ETag preservation
# ---------------------------------------------------------------------------

class TestEtagPreservation:

    def test_hiding_does_not_invalidate_the_authors_etag(self, client, world):
        """A moderator hide changes nothing the author can edit, so their
        in-flight If-Match token must keep working."""
        headers = auth_headers(world["author"]["access_token"])
        before = client.get(f"/itineraries/{world['itinerary_id']}", headers=headers)
        etag = before.headers["etag"]

        # Go through the real dashboard action, not a direct column write.
        reporter = register_user(client, "reporter", "reporter@test.com")
        client.post(
            "/reports",
            json={"itinerary_id": world["itinerary_id"], "reason": "nsfw"},
            headers=auth_headers(reporter["access_token"]),
        )
        db = TestingSessionLocal()
        try:
            report_id = str(db.query(ContentReport).one().id)
        finally:
            db.close()
        client.post(
            f"/admin/reports/{report_id}/action",
            data={"action": "hide", "reason": "under review"},
            auth=ADMIN_BASIC, follow_redirects=False,
        )

        after = client.get(f"/itineraries/{world['itinerary_id']}", headers=headers)
        assert after.json()["hidden"] is True
        assert after.headers["etag"] == etag

        # And the pre-hide token is still accepted by a real mutation.
        resp = client.post(
            f"/itineraries/{world['itinerary_id']}/stops",
            # The captured ETag is the point; the claim just gets us past the
            # guard so the ETag is the thing being tested.
            json={"place_name": "Paris", "is_free": True},
            headers=locked_headers(client, world["itinerary_id"], headers, etag),
        )
        assert resp.status_code == 201, resp.text
