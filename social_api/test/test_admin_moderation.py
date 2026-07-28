"""
test_admin_moderation.py — Operator actions taken from the dashboard.

Covers the report queue (dismiss/hide/delete/warn/ban + bulk), the flagged-upload
queue, the reversals, and the two invariants that make the feature defensible:
every action writes exactly one audit row with a content snapshot, and a ban
locks the account out on the next request while revoking its refresh tokens.
"""

import io

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from conftest import (
    ADMIN_BASIC, TestingSessionLocal, admin_session, auth_headers, make_admin,
    register_user,
)
from app.models.content_report import ContentReport
from app.models.image_moderation_log import ImageModerationLog
from app.models.itinerary import Itinerary
from app.models.moderation_log import ModerationLog
from app.models.refresh_token import RefreshToken
from app.models.user import User


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _admin(client: TestClient) -> dict:
    account = register_user(client, "opsadmin", "ops@test.com")
    make_admin("ops@test.com")
    admin_session(client, "ops@test.com")
    return account


def _itinerary(client: TestClient, token: str, title: str = "Trip") -> str:
    resp = client.post(
        "/itineraries/",
        json={"title": title, "currency": "EUR", "visibility": "public"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 201, resp.json()
    return resp.json()["id"]


def _report(client: TestClient, itinerary_id: str, token: str,
            reason: str = "nsfw") -> str:
    resp = client.post(
        "/reports",
        json={"itinerary_id": itinerary_id, "reason": reason, "notes": "please look"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 201, resp.json()
    db = TestingSessionLocal()
    try:
        return str(db.query(ContentReport).one().id)
    finally:
        db.close()


def _logs(action: str | None = None) -> list[ModerationLog]:
    db = TestingSessionLocal()
    try:
        query = db.query(ModerationLog)
        if action:
            query = query.filter(ModerationLog.action == action)
        return query.all()
    finally:
        db.close()


def _itinerary_row(itinerary_id: str) -> Itinerary:
    db = TestingSessionLocal()
    try:
        return db.get(Itinerary, __import__("uuid").UUID(itinerary_id))
    finally:
        db.close()


def _user_row(email: str) -> User:
    from sqlalchemy import select

    db = TestingSessionLocal()
    try:
        return db.execute(select(User).where(User.email == email)).scalar_one()
    finally:
        db.close()


@pytest.fixture()
def scenario(client: TestClient, admin_enabled):
    """An admin, an author with a public itinerary, and a pending report on it."""
    author = register_user(client, "author", "author@test.com")
    itinerary_id = _itinerary(client, author["access_token"])
    reporter = register_user(client, "reporter", "reporter@test.com")
    report_id = _report(client, itinerary_id, reporter["access_token"])
    _admin(client)
    return {
        "author": author,
        "reporter": reporter,
        "itinerary_id": itinerary_id,
        "report_id": report_id,
    }


def _act(client: TestClient, report_id: str, action: str, reason: str = "policy violation"):
    return client.post(
        f"/admin/reports/{report_id}/action",
        data={"action": action, "reason": reason},
        auth=ADMIN_BASIC, follow_redirects=False,
    )


# ---------------------------------------------------------------------------
# Report queue actions
# ---------------------------------------------------------------------------

class TestReportActions:

    def test_dismiss_closes_report_without_touching_content(self, client, scenario):
        resp = _act(client, scenario["report_id"], "dismiss", "not a violation")
        assert resp.status_code == 303

        db = TestingSessionLocal()
        try:
            report = db.query(ContentReport).one()
            assert report.resolution == "dismissed"
            assert report.resolved_at is not None
        finally:
            db.close()

        itinerary = _itinerary_row(scenario["itinerary_id"])
        assert itinerary.hidden_at is None and itinerary.deleted_at is None

        logs = _logs("dismiss")
        assert len(logs) == 1
        assert logs[0].reason == "not a violation"

    def test_hide_sets_hidden_at_and_resolves_as_hidden(self, client, scenario):
        assert _act(client, scenario["report_id"], "hide").status_code == 303

        itinerary = _itinerary_row(scenario["itinerary_id"])
        assert itinerary.hidden_at is not None
        assert itinerary.deleted_at is None

        db = TestingSessionLocal()
        try:
            # Distinct from content_removed — the content still exists for its author.
            assert db.query(ContentReport).one().resolution == "content_hidden"
        finally:
            db.close()

    def test_delete_soft_deletes_and_snapshots_content(self, client, scenario):
        assert _act(client, scenario["report_id"], "delete", "explicit content").status_code == 303

        itinerary = _itinerary_row(scenario["itinerary_id"])
        assert itinerary.deleted_at is not None
        # Row survives — it is evidence, not a hard delete.
        assert itinerary.title == "Trip"

        logs = _logs("delete")
        assert len(logs) == 1
        snapshot = logs[0].content_snapshot
        assert snapshot["title"] == "Trip"
        assert snapshot["report_id"] == scenario["report_id"]

        db = TestingSessionLocal()
        try:
            assert db.query(ContentReport).one().resolution == "content_removed"
        finally:
            db.close()

    def test_warn_logs_against_the_author(self, client, scenario):
        assert _act(client, scenario["report_id"], "warn", "first warning").status_code == 303

        logs = _logs("warn")
        assert len(logs) == 1
        assert str(logs[0].target_id) == scenario["author"]["user_id"]
        assert logs[0].target_type == "user"
        # A warning does not touch the content or the account.
        assert _user_row("author@test.com").is_active is True

    def test_reason_is_mandatory(self, client, scenario):
        resp = _act(client, scenario["report_id"], "delete", reason="   ")
        assert resp.status_code == 303
        assert "error" in resp.headers["location"]
        assert _itinerary_row(scenario["itinerary_id"]).deleted_at is None
        assert _logs() == []

    def test_already_resolved_report_is_not_actioned_twice(self, client, scenario):
        _act(client, scenario["report_id"], "dismiss")
        resp = _act(client, scenario["report_id"], "delete")
        assert resp.status_code == 303
        assert "notice" in resp.headers["location"]
        assert _itinerary_row(scenario["itinerary_id"]).deleted_at is None


class TestBanFlow:

    def test_ban_locks_account_and_revokes_sessions(self, client, scenario):
        author_token = scenario["author"]["access_token"]
        # Sanity: the author can use the API before the ban.
        assert client.get("/users/me", headers=auth_headers(author_token)).status_code == 200

        assert _act(client, scenario["report_id"], "ban", "repeat offender").status_code == 303

        assert _user_row("author@test.com").is_active is False

        # Next authenticated request is refused with the coded 403 the Flutter
        # client watches for — no waiting for the 15-minute JWT to expire.
        resp = client.get("/users/me", headers=auth_headers(author_token))
        assert resp.status_code == 403
        assert resp.json()["code"] == "account_deactivated"

        db = TestingSessionLocal()
        try:
            tokens = db.query(RefreshToken).filter(
                RefreshToken.user_id == _user_row("author@test.com").id
            ).all()
            assert tokens and all(t.revoked_at is not None for t in tokens)
        finally:
            db.close()

    def test_unban_restores_access(self, client, scenario):
        _act(client, scenario["report_id"], "ban", "mistake")
        author_id = scenario["author"]["user_id"]

        resp = client.post(
            f"/admin/users/{author_id}/unban",
            data={"reason": "appeal accepted offline"},
            auth=ADMIN_BASIC, follow_redirects=False,
        )
        assert resp.status_code == 303
        assert _user_row("author@test.com").is_active is True
        assert len(_logs("unban")) == 1

    def test_banned_authors_content_disappears_from_the_feed(self, client, scenario):
        viewer = register_user(client, "viewer", "viewer@test.com")
        before = client.get("/itineraries/feed", headers=auth_headers(viewer["access_token"]))
        assert any(i["id"] == scenario["itinerary_id"] for i in before.json())

        _act(client, scenario["report_id"], "ban", "spam")

        after = client.get("/itineraries/feed", headers=auth_headers(viewer["access_token"]))
        assert after.status_code == 200
        assert all(i["id"] != scenario["itinerary_id"] for i in after.json())


class TestReversals:

    def test_unhide_makes_content_public_again(self, client, scenario):
        _act(client, scenario["report_id"], "hide")
        itinerary_id = scenario["itinerary_id"]

        resp = client.post(
            f"/admin/itineraries/{itinerary_id}/unhide",
            data={"reason": "reviewed, acceptable"},
            auth=ADMIN_BASIC, follow_redirects=False,
        )
        assert resp.status_code == 303
        assert _itinerary_row(itinerary_id).hidden_at is None
        assert len(_logs("unhide")) == 1


class TestBulkActions:

    def test_bulk_dismiss_resolves_every_selected_report(self, client, admin_enabled):
        author = register_user(client, "author", "author@test.com")
        reporter = register_user(client, "reporter", "reporter@test.com")
        ids = []
        for n in range(3):
            itinerary_id = _itinerary(client, author["access_token"], f"Trip {n}")
            client.post(
                "/reports",
                json={"itinerary_id": itinerary_id, "reason": "spam"},
                headers=auth_headers(reporter["access_token"]),
            )
        db = TestingSessionLocal()
        try:
            ids = [str(r.id) for r in db.query(ContentReport).all()]
        finally:
            db.close()
        assert len(ids) == 3
        _admin(client)

        resp = client.post(
            "/admin/reports/bulk",
            data={"action": "dismiss", "reason": "spam wave", "report_ids": ids},
            auth=ADMIN_BASIC, follow_redirects=False,
        )
        assert resp.status_code == 303

        db = TestingSessionLocal()
        try:
            assert all(r.resolution == "dismissed" for r in db.query(ContentReport).all())
        finally:
            db.close()
        assert len(_logs("dismiss")) == 3

    def test_bulk_delete_soft_deletes_every_target(self, client, scenario):
        resp = client.post(
            "/admin/reports/bulk",
            data={
                "action": "delete", "reason": "coordinated abuse",
                "report_ids": [scenario["report_id"]],
            },
            auth=ADMIN_BASIC, follow_redirects=False,
        )
        assert resp.status_code == 303
        assert _itinerary_row(scenario["itinerary_id"]).deleted_at is not None

    def test_bulk_requires_a_reason(self, client, scenario):
        resp = client.post(
            "/admin/reports/bulk",
            data={"action": "dismiss", "reason": "", "report_ids": [scenario["report_id"]]},
            auth=ADMIN_BASIC, follow_redirects=False,
        )
        assert "error" in resp.headers["location"]
        assert _logs() == []


# ---------------------------------------------------------------------------
# Flagged uploads queue
# ---------------------------------------------------------------------------

def _make_jpeg() -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (800, 800), color=(120, 140, 160)).save(buf, format="JPEG")
    return buf.getvalue()


def _seed_flagged(target_kind: str, itinerary_id=None, user_id=None) -> str:
    """Insert a flagged scan row the way moderation_service would."""
    import uuid as _uuid

    db = TestingSessionLocal()
    try:
        row = ImageModerationLog(
            image_hash="a" * 64,
            target_kind=target_kind,
            target_itinerary_id=_uuid.UUID(itinerary_id) if itinerary_id else None,
            uploader_user_id=_uuid.UUID(user_id) if user_id else None,
            action="flagged",
            labels=[{"name": "Suggestive", "confidence": 62.5}],
        )
        db.add(row)
        db.commit()
        return str(row.id)
    finally:
        db.close()


def _flagged_row(log_id: str) -> ImageModerationLog:
    import uuid as _uuid

    db = TestingSessionLocal()
    try:
        return db.get(ImageModerationLog, _uuid.UUID(log_id))
    finally:
        db.close()


class TestFlaggedQueue:

    def test_queue_lists_only_unreviewed_flags(self, client, scenario):
        _seed_flagged("itinerary_cover", itinerary_id=scenario["itinerary_id"])
        resp = client.get("/admin/flagged", auth=ADMIN_BASIC)
        assert resp.status_code == 200
        assert "Suggestive" in resp.text

    def test_approve_clears_the_flag(self, client, scenario):
        log_id = _seed_flagged("itinerary_cover", itinerary_id=scenario["itinerary_id"])
        resp = client.post(
            f"/admin/flagged/{log_id}/action",
            data={"action": "approve", "reason": "false positive"},
            auth=ADMIN_BASIC, follow_redirects=False,
        )
        assert resp.status_code == 303
        assert _flagged_row(log_id).reviewed_at is not None
        assert _itinerary_row(scenario["itinerary_id"]).moderation_status == "approved"

    def test_remove_clears_the_cover_and_marks_rejected(self, client, scenario):
        log_id = _seed_flagged("itinerary_cover", itinerary_id=scenario["itinerary_id"])
        resp = client.post(
            f"/admin/flagged/{log_id}/action",
            data={"action": "remove", "reason": "explicit"},
            auth=ADMIN_BASIC, follow_redirects=False,
        )
        assert resp.status_code == 303

        itinerary = _itinerary_row(scenario["itinerary_id"])
        assert itinerary.cover_image_url is None
        assert itinerary.moderation_status == "rejected"
        assert _flagged_row(log_id).reviewed_at is not None
        # The scan record itself is kept — it is the evidence.
        assert _flagged_row(log_id).image_hash == "a" * 64

    def test_remove_clears_an_avatar(self, client, scenario):
        author_id = scenario["author"]["user_id"]
        log_id = _seed_flagged("avatar", user_id=author_id)
        resp = client.post(
            f"/admin/flagged/{log_id}/action",
            data={"action": "remove", "reason": "explicit avatar"},
            auth=ADMIN_BASIC, follow_redirects=False,
        )
        assert resp.status_code == 303
        assert _user_row("author@test.com").avatar_url is None

    def test_ban_from_flagged_queue_reviews_the_row(self, client, scenario):
        author_id = scenario["author"]["user_id"]
        log_id = _seed_flagged("user_cover", user_id=author_id)
        resp = client.post(
            f"/admin/flagged/{log_id}/action",
            data={"action": "ban", "reason": "explicit uploads"},
            auth=ADMIN_BASIC, follow_redirects=False,
        )
        assert resp.status_code == 303
        assert _flagged_row(log_id).reviewed_at is not None
        assert _user_row("author@test.com").is_active is False

    def test_already_reviewed_row_is_not_actioned_twice(self, client, scenario):
        log_id = _seed_flagged("itinerary_cover", itinerary_id=scenario["itinerary_id"])
        client.post(
            f"/admin/flagged/{log_id}/action",
            data={"action": "approve", "reason": "ok"},
            auth=ADMIN_BASIC, follow_redirects=False,
        )
        resp = client.post(
            f"/admin/flagged/{log_id}/action",
            data={"action": "remove", "reason": "changed my mind"},
            auth=ADMIN_BASIC, follow_redirects=False,
        )
        assert "notice" in resp.headers["location"]
        assert _itinerary_row(scenario["itinerary_id"]).moderation_status == "approved"


# ---------------------------------------------------------------------------
# Itinerary detail page
# ---------------------------------------------------------------------------

def _seed_stop(itinerary_id: str, notes: str, place_name: str = "Back alley") -> None:
    """Insert a track + stop directly — driving the stop API would need the
    itinerary's live If-Match token for no extra coverage here."""
    import uuid as _uuid

    from app.models.stop import Stop
    from app.models.track import Track

    db = TestingSessionLocal()
    try:
        itinerary_uuid = _uuid.UUID(itinerary_id)
        track = Track(itinerary_id=itinerary_uuid, rank="a0")
        db.add(track)
        db.flush()
        db.add(Stop(
            itinerary_id=itinerary_uuid,
            track_id=track.id,
            rank="a0",
            place_name=place_name,
            notes=notes,
        ))
        db.commit()
    finally:
        db.close()


class TestItineraryDetail:

    def _url(self, itinerary_id: str) -> str:
        return f"/admin/itineraries/{itinerary_id}"

    def test_detail_page_renders_the_itinerary(self, client, scenario):
        resp = client.get(self._url(scenario["itinerary_id"]), auth=ADMIN_BASIC)
        assert resp.status_code == 200
        assert "Trip" in resp.text
        assert "author" in resp.text  # the author block

    def test_full_content_includes_stop_notes(self, client, scenario):
        _seed_stop(scenario["itinerary_id"], notes="meet the dealer behind the bins")
        resp = client.get(self._url(scenario["itinerary_id"]), auth=ADMIN_BASIC)
        assert resp.status_code == 200
        assert "meet the dealer behind the bins" in resp.text
        assert "Back alley" in resp.text

    def test_hidden_itinerary_still_opens_for_the_admin(self, client, scenario):
        _act(client, scenario["report_id"], "hide", "under review")
        itinerary_id = scenario["itinerary_id"]

        # The whole point: the public share page is 404 for exactly this state.
        assert client.get(f"/share/i/{itinerary_id}").status_code == 404
        resp = client.get(self._url(itinerary_id), auth=ADMIN_BASIC)
        assert resp.status_code == 200
        assert "Not publicly reachable" in resp.text

    def test_removed_itinerary_still_opens_for_the_admin(self, client, scenario):
        _act(client, scenario["report_id"], "delete", "policy violation")
        resp = client.get(self._url(scenario["itinerary_id"]), auth=ADMIN_BASIC)
        assert resp.status_code == 200
        assert "removed" in resp.text

    def test_public_itinerary_offers_the_share_link(self, client, scenario):
        resp = client.get(self._url(scenario["itinerary_id"]), auth=ADMIN_BASIC)
        assert f"/share/i/{scenario['itinerary_id']}" in resp.text

    def test_moderation_history_resolves_the_acting_admin(self, client, scenario):
        # admin_names is keyed by UUID; a type mismatch would silently render
        # "—" in the template, so assert the mapping at the service level.
        import uuid as _uuid

        from app.services import admin_service

        _act(client, scenario["report_id"], "hide", "under review")
        db = TestingSessionLocal()
        try:
            detail = admin_service.itinerary_detail(
                db, _uuid.UUID(scenario["itinerary_id"])
            )
            assert [row.action for row in detail["log_rows"]] == ["hide"]
            assert set(detail["admin_names"].values()) == {"opsadmin"}
        finally:
            db.close()

    def test_purged_itinerary_renders_the_gone_card(self, client, scenario):
        import uuid as _uuid

        resp = client.get(self._url(str(_uuid.uuid4())), auth=ADMIN_BASIC)
        assert resp.status_code == 404
        assert "no longer exists" in resp.text

    def test_basic_auth_is_required(self, client, scenario):
        # Panel configured but no credentials sent → 401 challenge. (The
        # unconfigured-panel 404 is covered in test_admin_auth.py.)
        assert client.get(self._url(scenario["itinerary_id"])).status_code == 401

    def test_admin_session_is_required(self, client, admin_enabled):
        import uuid as _uuid

        client.cookies.clear()
        resp = client.get(
            self._url(str(_uuid.uuid4())), auth=ADMIN_BASIC, follow_redirects=False,
        )
        assert resp.status_code == 303
        assert resp.headers["location"] == "/admin/login"

    def test_queues_link_to_the_detail_page(self, client, scenario):
        itinerary_id = scenario["itinerary_id"]
        link = f"/admin/itineraries/{itinerary_id}"

        assert link in client.get("/admin/reports", auth=ADMIN_BASIC).text

        _seed_flagged("itinerary_cover", itinerary_id=itinerary_id)
        assert link in client.get("/admin/flagged", auth=ADMIN_BASIC).text

        # A moderation-log row (and so the dashboard's recent list) links too.
        _act(client, scenario["report_id"], "hide", "under review")
        assert link in client.get("/admin/log", auth=ADMIN_BASIC).text
        assert link in client.get("/admin", auth=ADMIN_BASIC).text
