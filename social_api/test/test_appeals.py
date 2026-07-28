"""
test_appeals.py — The user appeals workflow.

Two submission paths (authenticated API, and the signed-link web form a
suspended user must use because they cannot authenticate at all), the two
throttles that keep it from becoming a complaint loop (one open appeal per item,
30-day lock after a rejection), and the three operator decisions.
"""

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from conftest import (
    ADMIN_BASIC, TestingSessionLocal, admin_session, auth_headers, make_admin,
    register_user,
)
from app.models.appeal import Appeal
from app.models.content_report import ContentReport
from app.models.itinerary import Itinerary
from app.models.moderation_log import ModerationLog
from app.models.user import User
from app.services import appeal_token


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _itinerary(client: TestClient, token: str, title: str = "Trip") -> str:
    resp = client.post(
        "/itineraries/",
        json={"title": title, "currency": "EUR", "visibility": "public"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 201, resp.json()
    return resp.json()["id"]


def _moderate(client: TestClient, itinerary_id: str, reporter_token: str,
              action: str, reason: str = "policy violation") -> None:
    """Run a real dashboard action so a moderation_log row exists to appeal."""
    client.post(
        "/reports",
        json={"itinerary_id": itinerary_id, "reason": "nsfw"},
        headers=auth_headers(reporter_token),
    )
    db = TestingSessionLocal()
    try:
        report_id = str(
            db.query(ContentReport)
            .filter(ContentReport.resolution == "pending").first().id
        )
    finally:
        db.close()
    resp = client.post(
        f"/admin/reports/{report_id}/action",
        data={"action": action, "reason": reason},
        auth=ADMIN_BASIC, follow_redirects=False,
    )
    assert resp.status_code == 303


@pytest.fixture()
def world(client: TestClient, admin_enabled):
    author = register_user(client, "author", "author@test.com")
    reporter = register_user(client, "reporter", "reporter@test.com")
    itinerary_id = _itinerary(client, author["access_token"])
    register_user(client, "opsadmin", "ops@test.com")
    make_admin("ops@test.com")
    admin_session(client, "ops@test.com")
    return {"author": author, "reporter": reporter, "itinerary_id": itinerary_id}


def _appeal_row() -> Appeal:
    db = TestingSessionLocal()
    try:
        return db.query(Appeal).one()
    finally:
        db.close()


def _itinerary_row(itinerary_id: str) -> Itinerary:
    db = TestingSessionLocal()
    try:
        return db.get(Itinerary, uuid.UUID(itinerary_id))
    finally:
        db.close()


def _user_row(email: str) -> User:
    from sqlalchemy import select

    db = TestingSessionLocal()
    try:
        return db.execute(select(User).where(User.email == email)).scalar_one()
    finally:
        db.close()


def _submit(client: TestClient, token: str, target_type: str, target_id: str,
            reason: str = "This was my own photo, not explicit."):
    return client.post(
        "/appeals",
        json={"target_type": target_type, "target_id": target_id, "reason": reason},
        headers=auth_headers(token),
    )


# ---------------------------------------------------------------------------
# Authenticated submission
# ---------------------------------------------------------------------------

class TestSubmitViaApi:

    def test_author_can_appeal_a_removal(self, client, world):
        _moderate(client, world["itinerary_id"], world["reporter"]["access_token"], "delete")

        resp = _submit(client, world["author"]["access_token"],
                       "itinerary", world["itinerary_id"])
        assert resp.status_code == 201
        body = resp.json()
        assert body["status"] == "pending"
        assert body["target_id"] == world["itinerary_id"]

    def test_second_open_appeal_is_refused(self, client, world):
        _moderate(client, world["itinerary_id"], world["reporter"]["access_token"], "delete")
        _submit(client, world["author"]["access_token"], "itinerary", world["itinerary_id"])

        resp = _submit(client, world["author"]["access_token"],
                       "itinerary", world["itinerary_id"], reason="please reconsider again")
        assert resp.status_code == 409
        assert resp.json()["code"] == "appeal_already_pending"

    def test_appeal_requires_an_explanation(self, client, world):
        _moderate(client, world["itinerary_id"], world["reporter"]["access_token"], "delete")
        resp = _submit(client, world["author"]["access_token"],
                       "itinerary", world["itinerary_id"], reason="   ")
        # Blank-after-strip is caught by the service; Pydantic catches empty strings.
        assert resp.status_code in (422, 400)

    def test_cannot_appeal_someone_elses_content(self, client, world):
        _moderate(client, world["itinerary_id"], world["reporter"]["access_token"], "delete")
        resp = _submit(client, world["reporter"]["access_token"],
                       "itinerary", world["itinerary_id"])
        assert resp.status_code == 404
        assert resp.json()["code"] == "appeal_target_not_found"

    def test_cannot_appeal_without_a_moderation_action(self, client, world):
        resp = _submit(client, world["author"]["access_token"],
                       "itinerary", world["itinerary_id"])
        assert resp.status_code == 404

    def test_warning_is_appealable(self, client, world):
        _moderate(client, world["itinerary_id"], world["reporter"]["access_token"], "warn")
        resp = _submit(client, world["author"]["access_token"],
                       "user", world["author"]["user_id"])
        assert resp.status_code == 201


class TestCooldown:

    def _uphold(self, client: TestClient) -> None:
        appeal = _appeal_row()
        resp = client.post(
            f"/admin/appeals/{appeal.id}/decide",
            data={"decision": "uphold", "admin_response": "decision stands"},
            auth=ADMIN_BASIC, follow_redirects=False,
        )
        assert resp.status_code == 303

    def test_rejected_appeal_locks_the_item_for_30_days(self, client, world):
        _moderate(client, world["itinerary_id"], world["reporter"]["access_token"], "delete")
        _submit(client, world["author"]["access_token"], "itinerary", world["itinerary_id"])
        self._uphold(client)

        resp = _submit(client, world["author"]["access_token"], "itinerary",
                       world["itinerary_id"], reason="I still disagree")
        assert resp.status_code == 429
        assert resp.json()["code"] == "appeal_cooldown"

    def test_reappeal_allowed_once_the_cooldown_expires(self, client, world):
        _moderate(client, world["itinerary_id"], world["reporter"]["access_token"], "delete")
        _submit(client, world["author"]["access_token"], "itinerary", world["itinerary_id"])
        self._uphold(client)

        # Backdate the decision past the window.
        db = TestingSessionLocal()
        try:
            appeal = db.query(Appeal).one()
            appeal.updated_at = datetime.now(timezone.utc) - timedelta(days=31)
            db.commit()
        finally:
            db.close()

        resp = _submit(client, world["author"]["access_token"], "itinerary",
                       world["itinerary_id"], reason="new evidence")
        assert resp.status_code == 201


# ---------------------------------------------------------------------------
# Violations feed
# ---------------------------------------------------------------------------

class TestViolationsFeed:

    def test_lists_actions_against_the_user(self, client, world):
        _moderate(client, world["itinerary_id"], world["reporter"]["access_token"],
                  "delete", "explicit imagery")

        resp = client.get(
            "/appeals/violations",
            headers=auth_headers(world["author"]["access_token"]),
        )
        assert resp.status_code == 200
        items = resp.json()["violations"]
        assert len(items) == 1
        assert items[0]["action"] == "delete"
        assert items[0]["item_title"] == "Trip"
        assert items[0]["active"] is True
        assert items[0]["appealable"] is True
        assert items[0]["appeal_status"] is None

    def test_reflects_a_pending_appeal(self, client, world):
        _moderate(client, world["itinerary_id"], world["reporter"]["access_token"], "delete")
        _submit(client, world["author"]["access_token"], "itinerary", world["itinerary_id"])

        items = client.get(
            "/appeals/violations",
            headers=auth_headers(world["author"]["access_token"]),
        ).json()["violations"]
        assert items[0]["appeal_status"] == "pending"
        assert items[0]["appealable"] is False

    def test_other_users_actions_are_not_listed(self, client, world):
        _moderate(client, world["itinerary_id"], world["reporter"]["access_token"], "delete")
        items = client.get(
            "/appeals/violations",
            headers=auth_headers(world["reporter"]["access_token"]),
        ).json()["violations"]
        assert items == []

    def test_empty_for_a_clean_account(self, client, world):
        resp = client.get(
            "/appeals/violations",
            headers=auth_headers(world["author"]["access_token"]),
        )
        assert resp.json()["violations"] == []


# ---------------------------------------------------------------------------
# Operator decisions
# ---------------------------------------------------------------------------

class TestDecisions:

    def _open_appeal(self, client, world, action: str = "delete"):
        _moderate(client, world["itinerary_id"], world["reporter"]["access_token"], action)

        if action == "ban":
            # A banned account is locked out of the API, so its appeal can only
            # arrive through the emailed token form.
            db = TestingSessionLocal()
            try:
                log = db.query(ModerationLog).filter(ModerationLog.action == "ban").one()
                token = appeal_token.mint_appeal_token(
                    uuid.UUID(world["author"]["user_id"]), "user",
                    uuid.UUID(world["author"]["user_id"]), log.id,
                )
            finally:
                db.close()
            resp = client.post(
                "/web/appeal", data={"token": token, "reason": "I did nothing wrong."}
            )
            assert "Appeal received" in resp.text
        else:
            assert _submit(client, world["author"]["access_token"],
                           "itinerary", world["itinerary_id"]).status_code == 201
        return _appeal_row()

    def _decide(self, client, appeal_id, decision, note="reviewed"):
        return client.post(
            f"/admin/appeals/{appeal_id}/decide",
            data={"decision": decision, "admin_response": note},
            auth=ADMIN_BASIC, follow_redirects=False,
        )

    def test_queue_links_the_itinerary_for_the_reviewer(self, client, world):
        self._open_appeal(client, world)
        resp = client.get("/admin/appeals", auth=ADMIN_BASIC)
        assert resp.status_code == 200
        assert f"/admin/itineraries/{world['itinerary_id']}" in resp.text

    def test_restore_brings_content_back(self, client, world):
        appeal = self._open_appeal(client, world)
        assert _itinerary_row(world["itinerary_id"]).deleted_at is not None

        assert self._decide(client, appeal.id, "restore").status_code == 303

        itinerary = _itinerary_row(world["itinerary_id"])
        assert itinerary.deleted_at is None
        assert itinerary.hidden_at is None
        assert _appeal_row().status == "restored"

        # Visible to the author again.
        resp = client.get(
            f"/itineraries/{world['itinerary_id']}",
            headers=auth_headers(world["author"]["access_token"]),
        )
        assert resp.status_code == 200

    def test_restore_preserves_the_authors_etag(self, client, world):
        appeal = self._open_appeal(client, world)
        self._decide(client, appeal.id, "restore")

        db = TestingSessionLocal()
        try:
            row = db.get(Itinerary, uuid.UUID(world["itinerary_id"]))
            # created_at == updated_at still holds: no moderator flip ever bumped it.
            assert row.updated_at == row.created_at
        finally:
            db.close()

    def test_uphold_keeps_the_penalty(self, client, world):
        appeal = self._open_appeal(client, world)
        assert self._decide(client, appeal.id, "uphold").status_code == 303

        assert _appeal_row().status == "upheld"
        assert _itinerary_row(world["itinerary_id"]).deleted_at is not None

    def test_reduce_turns_a_removal_into_a_hide(self, client, world):
        appeal = self._open_appeal(client, world)
        assert self._decide(client, appeal.id, "reduce").status_code == 303

        itinerary = _itinerary_row(world["itinerary_id"])
        assert itinerary.deleted_at is None
        assert itinerary.hidden_at is not None
        assert _appeal_row().status == "reduced"

    def test_reduce_turns_a_ban_into_a_warning(self, client, world):
        appeal = self._open_appeal(client, world, action="ban")
        assert _user_row("author@test.com").is_active is False

        assert self._decide(client, appeal.id, "reduce").status_code == 303
        assert _user_row("author@test.com").is_active is True

    def test_restore_lifts_a_ban(self, client, world):
        appeal = self._open_appeal(client, world, action="ban")
        assert self._decide(client, appeal.id, "restore").status_code == 303
        assert _user_row("author@test.com").is_active is True

    def test_decision_is_audit_logged(self, client, world):
        appeal = self._open_appeal(client, world)
        self._decide(client, appeal.id, "restore", note="author was right")

        db = TestingSessionLocal()
        try:
            rows = db.query(ModerationLog).filter(
                ModerationLog.action == "appeal_restore"
            ).all()
            assert len(rows) == 1
            assert rows[0].reason == "author was right"
            assert rows[0].content_snapshot["original_action"] == "delete"
        finally:
            db.close()

    def test_an_appeal_cannot_be_decided_twice(self, client, world):
        appeal = self._open_appeal(client, world)
        self._decide(client, appeal.id, "uphold")
        resp = self._decide(client, appeal.id, "restore")
        assert resp.status_code == 303
        # Still upheld — the second decision was refused, not applied.
        assert _appeal_row().status == "upheld"

    def test_queue_shows_pending_appeals(self, client, world):
        self._open_appeal(client, world)
        resp = client.get("/admin/appeals", auth=ADMIN_BASIC)
        assert resp.status_code == 200
        assert "author" in resp.text


# ---------------------------------------------------------------------------
# Public token form (the path a suspended user must use)
# ---------------------------------------------------------------------------

class TestPublicAppealForm:

    def _ban_and_token(self, client, world) -> str:
        _moderate(client, world["itinerary_id"], world["reporter"]["access_token"], "ban")
        db = TestingSessionLocal()
        try:
            log = db.query(ModerationLog).filter(ModerationLog.action == "ban").one()
            return appeal_token.mint_appeal_token(
                uuid.UUID(world["author"]["user_id"]), "user",
                uuid.UUID(world["author"]["user_id"]), log.id,
            )
        finally:
            db.close()

    def test_banned_user_cannot_use_the_api_but_can_use_the_form(self, client, world):
        token = self._ban_and_token(client, world)

        # The API is closed to them entirely.
        api = _submit(client, world["author"]["access_token"], "user",
                      world["author"]["user_id"])
        assert api.status_code == 403
        assert api.json()["code"] == "account_deactivated"

        form = client.get(f"/appeal/{token}")
        assert form.status_code == 200
        assert "Appeal a decision" in form.text

        submitted = client.post(
            "/web/appeal",
            data={"token": token, "reason": "I was hacked, this wasn't me."},
        )
        assert submitted.status_code == 200
        assert "Appeal received" in submitted.text
        assert _appeal_row().status == "pending"

    def test_form_rejects_a_garbage_token(self, client, world):
        resp = client.get("/appeal/not-a-real-token")
        assert resp.status_code == 200
        assert "invalid or has expired" in resp.text

    def test_form_rejects_an_api_access_token(self, client, world):
        """An access token is signed with the same key but carries no
        scope="appeal" claim, so it must not authorize the form."""
        resp = client.get(f"/appeal/{world['author']['access_token']}")
        assert "invalid or has expired" in resp.text

    def test_duplicate_submission_is_refused(self, client, world):
        token = self._ban_and_token(client, world)
        client.post("/web/appeal", data={"token": token, "reason": "first try"})
        resp = client.post("/web/appeal", data={"token": token, "reason": "second try"})
        assert "already have an appeal pending" in resp.text

    def test_request_link_page_never_reveals_account_existence(self, client, world):
        for email in ("author@test.com", "nobody@example.com"):
            resp = client.post("/web/appeal-request", data={"email": email})
            assert resp.status_code == 200
            assert "Check your email" in resp.text
