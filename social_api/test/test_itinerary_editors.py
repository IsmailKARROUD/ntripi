"""
test_itinerary_editors.py — granting and revoking edit rights.

The load-bearing property here is that editing is a LAYER on visibility, not a
second ladder beside it: can_edit_itinerary delegates to can_view_itinerary on
every request, so a grant made this morning stops working the moment the person
loses view access — no revocation, no bookkeeping, no sweep. Several tests below
exist purely to prove that, one revocation mechanism at a time.
"""

from fastapi.testclient import TestClient

from conftest import (
    TestingSessionLocal, acquire_edit_lock, auth_headers, edit_headers,
    register_user,
)


def _itinerary(client: TestClient, hdrs: dict, visibility: str = "restricted") -> str:
    response = client.post(
        "/itineraries/",
        json={"title": "Shared Trip", "currency": "EUR", "visibility": visibility},
        headers=hdrs,
    )
    assert response.status_code == 201, response.text
    return response.json()["id"]


def _etag(client: TestClient, itinerary_id: str, hdrs: dict) -> str:
    response = client.get(f"/itineraries/{itinerary_id}", headers=hdrs)
    assert response.status_code == 200, response.text
    return response.headers["etag"]


def _cast(client: TestClient):
    """Alice (owner) and Bobby, both registered. Returns their headers + ids."""
    alice = register_user(client, "alice", "alice@example.com")
    bobby = register_user(client, "bobby", "bobby@example.com")
    return (
        auth_headers(alice["access_token"]), alice["user_id"],
        auth_headers(bobby["access_token"]), bobby["user_id"],
    )


def _grant(client: TestClient, itin_id: str, owner_hdrs: dict, user_id: str,
           grant_view: bool = True):
    return client.post(
        f"/itineraries/{itin_id}/editors",
        json={"user_id": user_id, "grant_view": grant_view}, headers=owner_hdrs,
    )


def _rename(client: TestClient, itin_id: str, hdrs: dict, token: str,
            title: str = "Edited by a collaborator"):
    return client.patch(
        f"/itineraries/{itin_id}", json={"title": title},
        headers=edit_headers(hdrs, _etag(client, itin_id, hdrs), token),
    )


# ---------------------------------------------------------------------------
# Granting
# ---------------------------------------------------------------------------

class TestGranting:
    def test_owner_can_grant_and_the_editor_can_write(self, client: TestClient):
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)

        response = _grant(client, itin_id, owner_hdrs, bob_id)
        assert response.status_code == 201, response.text
        assert response.json()["username"] == "bobby"

        token = acquire_edit_lock(client, itin_id, bob_hdrs)
        assert _rename(client, itin_id, bob_hdrs, token).status_code == 200

    def test_editor_can_write_subcontent_too(self, client: TestClient):
        """'The itinerary and all its subcontent' — stops, not just the header."""
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)
        token = acquire_edit_lock(client, itin_id, bob_hdrs)

        response = client.post(
            f"/itineraries/{itin_id}/stops",
            json={"place_name": "Lisbon", "is_free": True},
            headers=edit_headers(bob_hdrs, _etag(client, itin_id, bob_hdrs), token),
        )

        assert response.status_code == 201, response.text

    def test_only_the_owner_may_grant(self, client: TestClient):
        """An editor cannot recruit more editors — the grant is the owner's
        trust decision and does not come with the power to delegate it."""
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        carol = register_user(client, "carol", "carol@example.com")
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)

        response = _grant(client, itin_id, bob_hdrs, carol["user_id"])

        assert response.status_code == 403

    def test_granting_to_the_owner_is_refused(self, client: TestClient):
        owner_hdrs, alice_id, _, _ = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)

        response = _grant(client, itin_id, owner_hdrs, alice_id)

        assert response.status_code == 400
        assert response.json()["code"] == "editor_is_owner"

    def test_granting_twice_is_refused(self, client: TestClient):
        owner_hdrs, _, _, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)

        response = _grant(client, itin_id, owner_hdrs, bob_id)

        assert response.status_code == 409
        assert response.json()["code"] == "editor_exists"

    def test_the_new_editor_is_notified(self, client: TestClient):
        """Otherwise the grant is invisible and nobody ever uses it.

        The row has to name the itinerary too: "you were added as an editor"
        is not actionable until the reader knows which trip, and a restricted
        one is in no feed for them to go looking through."""
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)

        _grant(client, itin_id, owner_hdrs, bob_id)

        response = client.get("/notifications", headers=bob_hdrs)
        assert response.status_code == 200, response.text
        rows = response.json()["notifications"]
        assert [row["type"] for row in rows] == ["itinerary_editor_added"]
        assert rows[0]["entity_id"] == itin_id
        assert rows[0]["entity_title"] == "Shared Trip"
        assert rows[0]["actor_username"] == "alice"

    def test_granting_view_alongside_edit_notifies_once(self, client: TestClient):
        """grant_view writes an allowlist row on the way past, and that path has
        its own viewer notice — two rows for one action would be noise."""
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)

        _grant(client, itin_id, owner_hdrs, bob_id, grant_view=True)

        response = client.get("/notifications", headers=bob_hdrs)
        assert [row["type"] for row in response.json()["notifications"]] == [
            "itinerary_editor_added"
        ]


# ---------------------------------------------------------------------------
# "A user who can't see it can't be an editor"
# ---------------------------------------------------------------------------

class TestViewIsAPrerequisite:
    def test_granting_to_someone_who_cannot_view_is_refused(self, client: TestClient):
        owner_hdrs, _, _, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)

        response = _grant(client, itin_id, owner_hdrs, bob_id, grant_view=False)

        assert response.status_code == 409
        body = response.json()
        assert body["code"] == "editor_cannot_view"
        assert body["visibility"] == "restricted"
        # The client uses this to decide between "add them to viewers?" and
        # "you need to change the visibility first".
        assert body["can_fix_with_allowlist"] is True

    def test_grant_view_adds_them_to_the_allowlist(self, client: TestClient):
        """The owner said yes to the client's 'give them view access too?'."""
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)

        assert _grant(client, itin_id, owner_hdrs, bob_id).status_code == 201

        allowed = client.get(f"/itineraries/{itin_id}/allowed-users", headers=owner_hdrs)
        assert [row["user_id"] for row in allowed.json()] == [bob_id]
        assert client.get(f"/itineraries/{itin_id}", headers=bob_hdrs).status_code == 200

    def test_grant_view_will_not_change_visibility_for_only_me(self, client: TestClient):
        """There is no allowlist to join, and switching visibility is a privacy
        decision the owner has to make deliberately elsewhere."""
        owner_hdrs, _, _, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs, visibility="only_me")

        response = _grant(client, itin_id, owner_hdrs, bob_id)

        assert response.status_code == 409
        assert response.json()["can_fix_with_allowlist"] is False
        detail = client.get(f"/itineraries/{itin_id}", headers=owner_hdrs).json()
        assert detail["visibility"] == "only_me"

    def test_grant_view_will_not_downgrade_a_followers_itinerary(self, client: TestClient):
        """followers → restricted would silently cut off every follower."""
        owner_hdrs, _, _, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs, visibility="followers")

        response = _grant(client, itin_id, owner_hdrs, bob_id)

        assert response.status_code == 409
        assert response.json()["can_fix_with_allowlist"] is False
        detail = client.get(f"/itineraries/{itin_id}", headers=owner_hdrs).json()
        assert detail["visibility"] == "followers"

    def test_losing_the_allowlist_row_revokes_editing(self, client: TestClient):
        """The grant row survives; the ability does not. Nothing revoked it —
        can_edit_itinerary simply re-asked can_view_itinerary."""
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)
        token = acquire_edit_lock(client, itin_id, bob_hdrs)

        client.delete(f"/itineraries/{itin_id}/allowed-users/{bob_id}",
                      headers=owner_hdrs)

        response = client.patch(
            f"/itineraries/{itin_id}", json={"title": "No"},
            headers={**bob_hdrs, "If-Match": '"whatever"', "X-Edit-Lock": token},
        )
        assert response.status_code == 403

    def test_visibility_change_to_only_me_revokes_editing(self, client: TestClient):
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)
        bob_token = acquire_edit_lock(client, itin_id, bob_hdrs)

        owner_token = acquire_edit_lock(client, itin_id, owner_hdrs, takeover=True)
        assert client.patch(
            f"/itineraries/{itin_id}", json={"visibility": "only_me"},
            headers=edit_headers(
                owner_hdrs, _etag(client, itin_id, owner_hdrs), owner_token),
        ).status_code == 200

        response = client.patch(
            f"/itineraries/{itin_id}", json={"title": "No"},
            headers={**bob_hdrs, "If-Match": '"whatever"', "X-Edit-Lock": bob_token},
        )
        assert response.status_code in (403, 404)

    def test_a_block_revokes_editing(self, client: TestClient):
        """Blocking cuts visibility both ways, so it cuts editing too."""
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)
        token = acquire_edit_lock(client, itin_id, bob_hdrs)

        assert client.post(f"/users/{bob_id}/block",
                           headers=owner_hdrs).status_code in (201, 204)

        response = client.patch(
            f"/itineraries/{itin_id}", json={"title": "No"},
            headers={**bob_hdrs, "If-Match": '"whatever"', "X-Edit-Lock": token},
        )
        assert response.status_code in (403, 404)

    def test_a_moderator_hide_revokes_editing(self, client: TestClient):
        """Hidden content is owner-only, so an editor loses the pen as well as
        the view — without the moderation path knowing editors exist."""
        from datetime import datetime, timezone
        import uuid as _uuid
        from app.models.itinerary import Itinerary

        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)
        token = acquire_edit_lock(client, itin_id, bob_hdrs)

        db = TestingSessionLocal()
        try:
            itinerary = db.get(Itinerary, _uuid.UUID(itin_id))
            itinerary.hidden_at = datetime.now(timezone.utc)
            db.commit()
        finally:
            db.close()

        response = client.patch(
            f"/itineraries/{itin_id}", json={"title": "No"},
            headers={**bob_hdrs, "If-Match": '"whatever"', "X-Edit-Lock": token},
        )
        assert response.status_code == 403


# ---------------------------------------------------------------------------
# What an editor may NOT do
# ---------------------------------------------------------------------------

class TestOwnerOnlyPowers:
    def test_editor_cannot_change_visibility(self, client: TestClient):
        """Mixed-authority endpoint: the guard admits them, the body does not."""
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)
        token = acquire_edit_lock(client, itin_id, bob_hdrs)

        response = client.patch(
            f"/itineraries/{itin_id}", json={"visibility": "public"},
            headers=edit_headers(bob_hdrs, _etag(client, itin_id, bob_hdrs), token),
        )

        assert response.status_code == 403
        assert response.json()["code"] == "itinerary_not_owner"

    def test_editor_cannot_delete_the_itinerary(self, client: TestClient):
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)

        response = client.delete(f"/itineraries/{itin_id}", headers=bob_hdrs)

        assert response.status_code == 403

    def test_editor_cannot_manage_the_allowlist(self, client: TestClient):
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        carol = register_user(client, "carol", "carol@example.com")
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)

        response = client.post(f"/itineraries/{itin_id}/allowed-users",
                               json={"user_id": carol["user_id"]}, headers=bob_hdrs)

        assert response.status_code == 403

    def test_editor_cannot_replace_the_cover_image(self, client: TestClient):
        """The cover is the itinerary's public face and every upload spends a
        paid moderation scan — it stayed with the owner."""
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)

        response = client.delete(f"/itineraries/{itin_id}/image", headers=bob_hdrs)

        assert response.status_code == 403


# ---------------------------------------------------------------------------
# Listing and revoking
# ---------------------------------------------------------------------------

class TestListAndRevoke:
    def test_editors_can_see_who_else_holds_a_pen(self, client: TestClient):
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)

        response = client.get(f"/itineraries/{itin_id}/editors", headers=bob_hdrs)

        assert response.status_code == 200, response.text
        assert [row["user_id"] for row in response.json()] == [bob_id]

    def test_a_plain_viewer_cannot_list_editors(self, client: TestClient):
        owner_hdrs, _, _, bob_id = _cast(client)
        carol = register_user(client, "carol", "carol@example.com")
        itin_id = _itinerary(client, owner_hdrs, visibility="public")
        _grant(client, itin_id, owner_hdrs, bob_id, grant_view=False)

        response = client.get(f"/itineraries/{itin_id}/editors",
                              headers=auth_headers(carol["access_token"]))

        assert response.status_code == 403

    def test_revoking_stops_the_editor_writing(self, client: TestClient):
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)
        token = acquire_edit_lock(client, itin_id, bob_hdrs)

        assert client.delete(f"/itineraries/{itin_id}/editors/{bob_id}",
                             headers=owner_hdrs).status_code == 204

        response = client.patch(
            f"/itineraries/{itin_id}", json={"title": "No"},
            headers={**bob_hdrs, "If-Match": '"whatever"', "X-Edit-Lock": token},
        )
        assert response.status_code == 403

    def test_revoking_releases_their_claim(self, client: TestClient):
        """Otherwise a removed editor's claim blocks everyone until the TTL."""
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)
        acquire_edit_lock(client, itin_id, bob_hdrs)

        client.delete(f"/itineraries/{itin_id}/editors/{bob_id}", headers=owner_hdrs)

        state = client.get(f"/itineraries/{itin_id}/lock", headers=owner_hdrs)
        assert state.json()["lock"] is None
        # No takeover flag needed — there is nothing left to take over.
        assert client.post(f"/itineraries/{itin_id}/lock", json={},
                           headers=owner_hdrs).status_code == 200

    def test_revoking_a_non_editor_is_404(self, client: TestClient):
        owner_hdrs, _, _, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)

        response = client.delete(f"/itineraries/{itin_id}/editors/{bob_id}",
                                 headers=owner_hdrs)

        assert response.status_code == 404
        assert response.json()["code"] == "editor_not_found"

    def test_an_editor_may_remove_themselves(self, client: TestClient):
        """Walking away is the editor's own call — the owner is not a gatekeeper
        on the way out, only on the way in."""
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)
        token = acquire_edit_lock(client, itin_id, bob_hdrs)

        assert client.delete(f"/itineraries/{itin_id}/editors/{bob_id}",
                             headers=bob_hdrs).status_code == 204

        response = client.patch(
            f"/itineraries/{itin_id}", json={"title": "No"},
            headers={**bob_hdrs, "If-Match": '"whatever"', "X-Edit-Lock": token},
        )
        assert response.status_code == 403
        assert client.get(f"/itineraries/{itin_id}/editors",
                          headers=owner_hdrs).json() == []

    def test_leaving_keeps_view_access(self, client: TestClient):
        """Editing is a layer on viewing — peeling it off must not take the
        allowlist row underneath with it."""
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id, grant_view=True)

        client.delete(f"/itineraries/{itin_id}/editors/{bob_id}", headers=bob_hdrs)

        response = client.get(f"/itineraries/{itin_id}", headers=bob_hdrs)
        assert response.status_code == 200
        assert response.json()["can_edit"] is False

    def test_leaving_releases_your_own_claim(self, client: TestClient):
        """Same reasoning as a revoke: a claim nobody can use blocks everybody."""
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)
        acquire_edit_lock(client, itin_id, bob_hdrs)

        client.delete(f"/itineraries/{itin_id}/editors/{bob_id}", headers=bob_hdrs)

        state = client.get(f"/itineraries/{itin_id}/lock", headers=owner_hdrs)
        assert state.json()["lock"] is None
        # No takeover flag needed — there is nothing left to take over.
        assert client.post(f"/itineraries/{itin_id}/lock", json={},
                           headers=owner_hdrs).status_code == 200

    def test_an_editor_may_not_remove_another_editor(self, client: TestClient):
        """The self-revoke is not a foothold into the owner's editor list."""
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        carol = register_user(client, "carol", "carol@example.com")
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)
        _grant(client, itin_id, owner_hdrs, carol["user_id"])

        response = client.delete(
            f"/itineraries/{itin_id}/editors/{carol['user_id']}", headers=bob_hdrs)

        assert response.status_code == 403

    def test_a_stranger_may_not_remove_an_editor(self, client: TestClient):
        owner_hdrs, _, _, bob_id = _cast(client)
        carol = register_user(client, "carol", "carol@example.com")
        itin_id = _itinerary(client, owner_hdrs, visibility="public")
        _grant(client, itin_id, owner_hdrs, bob_id, grant_view=False)

        response = client.delete(f"/itineraries/{itin_id}/editors/{bob_id}",
                                 headers=auth_headers(carol["access_token"]))

        assert response.status_code == 403


# ---------------------------------------------------------------------------
# can_edit on the detail response
# ---------------------------------------------------------------------------

class TestCanEditFlag:
    def test_can_edit_is_per_viewer(self, client: TestClient):
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        carol = register_user(client, "carol", "carol@example.com")
        itin_id = _itinerary(client, owner_hdrs, visibility="public")
        _grant(client, itin_id, owner_hdrs, bob_id, grant_view=False)

        def can_edit(hdrs: dict) -> bool:
            return client.get(f"/itineraries/{itin_id}", headers=hdrs).json()["can_edit"]

        assert can_edit(owner_hdrs) is True
        assert can_edit(bob_hdrs) is True
        assert can_edit(auth_headers(carol["access_token"])) is False

    def test_can_edit_is_the_last_json_key(self, client: TestClient):
        """Field order is JSON key order and that is part of the contract —
        can_edit was appended, never inserted."""
        owner_hdrs, _, _, _ = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)

        body = client.get(f"/itineraries/{itin_id}", headers=owner_hdrs).json()

        assert list(body)[-1] == "can_edit"


# ---------------------------------------------------------------------------
# GET /itineraries/shared-with-me
# ---------------------------------------------------------------------------

def _shared_ids(client: TestClient, hdrs: dict) -> list[str]:
    response = client.get("/itineraries/shared-with-me", headers=hdrs)
    assert response.status_code == 200, response.text
    return [row["id"] for row in response.json()]


def _set_visibility(client: TestClient, itin_id: str, owner_hdrs: dict, value: str):
    """Owner changes visibility — needs its own claim, hence the takeover."""
    token = acquire_edit_lock(client, itin_id, owner_hdrs, takeover=True)
    return client.patch(
        f"/itineraries/{itin_id}", json={"visibility": value},
        headers=edit_headers(owner_hdrs, _etag(client, itin_id, owner_hdrs), token),
    )


class TestSharedWithMe:
    """The list an editor reaches their granted trips through. Without it a
    restricted itinerary is in no feed and no search, so the grant notification
    is the only way back — and that gets purged."""

    def test_editor_sees_the_trip_with_owner_attribution(self, client: TestClient):
        owner_hdrs, alice_id, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)

        body = client.get("/itineraries/shared-with-me", headers=bob_hdrs).json()

        assert [row["id"] for row in body] == [itin_id]
        # Attribution is the point: a shared card has to say whose trip it is.
        assert body[0]["owner"]["user_id"] == alice_id
        assert body[0]["owner"]["username"] == "alice"

    def test_owners_own_trips_never_appear(self, client: TestClient):
        """Mine and Shared are disjoint by construction — add_editor 400s on the
        owner — so the merged 'All' view needs no de-duplication."""
        owner_hdrs, _, _, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)

        assert _shared_ids(client, owner_hdrs) == []

    def test_a_stranger_sees_nothing(self, client: TestClient):
        owner_hdrs, _, _, bob_id = _cast(client)
        carol = register_user(client, "carol", "carol@example.com")
        itin_id = _itinerary(client, owner_hdrs, visibility="public")
        _grant(client, itin_id, owner_hdrs, bob_id, grant_view=False)

        assert _shared_ids(client, auth_headers(carol["access_token"])) == []

    def test_a_revoked_editor_no_longer_sees_it(self, client: TestClient):
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)
        assert _shared_ids(client, bob_hdrs) == [itin_id]

        assert client.delete(f"/itineraries/{itin_id}/editors/{bob_id}",
                             headers=owner_hdrs).status_code == 204

        assert _shared_ids(client, bob_hdrs) == []

    def test_self_removal_takes_it_off_the_list(self, client: TestClient):
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)

        assert client.delete(f"/itineraries/{itin_id}/editors/{bob_id}",
                             headers=bob_hdrs).status_code == 204

        assert _shared_ids(client, bob_hdrs) == []

    def test_visibility_drop_to_only_me_removes_it(self, client: TestClient):
        """The grant row survives; can_edit_itinerary is what drops the entry.
        This is the whole 'one ladder, re-derived per request' property."""
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)
        assert _shared_ids(client, bob_hdrs) == [itin_id]

        assert _set_visibility(client, itin_id, owner_hdrs, "only_me").status_code == 200

        assert _shared_ids(client, bob_hdrs) == []

    def test_a_block_removes_it(self, client: TestClient):
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)

        assert client.post(f"/users/{bob_id}/block",
                           headers=owner_hdrs).status_code in (201, 204)

        assert _shared_ids(client, bob_hdrs) == []

    def test_a_moderator_hide_removes_it(self, client: TestClient):
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)

        _stamp(itin_id, "hidden_at")

        assert _shared_ids(client, bob_hdrs) == []

    def test_a_soft_delete_removes_it(self, client: TestClient):
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)

        _stamp(itin_id, "deleted_at")

        assert _shared_ids(client, bob_hdrs) == []

    def test_rows_carry_the_summary_fields_a_card_needs(self, client: TestClient):
        owner_hdrs, _, bob_hdrs, bob_id = _cast(client)
        itin_id = _itinerary(client, owner_hdrs)
        _grant(client, itin_id, owner_hdrs, bob_id)

        row = client.get("/itineraries/shared-with-me", headers=bob_hdrs).json()[0]

        # Same shape as a feed row — the client parses both with FeedItem.
        for key in ("title", "visibility", "stops_count", "created_at", "owner"):
            assert key in row, key


def _stamp(itin_id: str, column: str) -> None:
    """Set a moderation timestamp directly — no endpoint exposes these."""
    from datetime import datetime, timezone
    import uuid as _uuid
    from app.models.itinerary import Itinerary

    db = TestingSessionLocal()
    try:
        setattr(db.get(Itinerary, _uuid.UUID(itin_id)), column,
                datetime.now(timezone.utc))
        db.commit()
    finally:
        db.close()
