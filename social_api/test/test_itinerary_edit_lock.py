"""
test_itinerary_edit_lock.py — the edit lock, end to end over HTTP.

The requirement this file exists to prove is the awkward one: a device that has
been taken over must be unable to save, even though nothing told it and it still
believes it holds the claim. That is why the claim is a rotating server-minted
token and not a user id — and why a check performed only at acquire time would
not be enough.

Everything here goes through the API. Nothing reaches into the service layer
except backdate_lock_heartbeat, because there is no way to make a claim go stale
over HTTP and sleeping for five minutes is not a test.
"""

import pytest
from fastapi.testclient import TestClient

from app.config import get_settings
from conftest import (
    acquire_edit_lock, auth_headers, backdate_lock_heartbeat, edit_headers,
    etag_from_updated_at, register_user,
)


def _owner_with_itinerary(client: TestClient, visibility: str = "restricted"):
    """Alice, signed in, with one itinerary. Returns (id, headers, etag).

    'restricted' rather than the 'only_me' default because an editor must be
    able to VIEW what they edit — with only_me there is nobody to grant to.
    """
    user = register_user(client, "alice", "alice@example.com")
    hdrs = auth_headers(user["access_token"])
    response = client.post(
        "/itineraries/",
        json={"title": "Lock Trip", "currency": "EUR", "visibility": visibility},
        headers=hdrs,
    )
    assert response.status_code == 201, response.text
    body = response.json()
    return body["id"], hdrs, etag_from_updated_at(body["updated_at"])


def _add_editor(client: TestClient, itinerary_id: str, owner_hdrs: dict,
                username: str, email: str):
    """Register `username`, make them an editor, return their headers + id.

    grant_view because the itinerary is 'restricted': the owner is confirming
    they also want this person to be able to see it.
    """
    user = register_user(client, username, email)
    hdrs = auth_headers(user["access_token"])
    response = client.post(
        f"/itineraries/{itinerary_id}/editors",
        json={"user_id": user["user_id"], "grant_view": True}, headers=owner_hdrs,
    )
    assert response.status_code == 201, response.text
    return hdrs, user["user_id"]


def _etag(client: TestClient, itinerary_id: str, hdrs: dict) -> str:
    """The itinerary's current ETag. Granting an editor bumps updated_at, so a
    token captured at creation goes stale — only the tests that are ABOUT the
    ETag should be holding an old one."""
    response = client.get(f"/itineraries/{itinerary_id}", headers=hdrs)
    assert response.status_code == 200, response.text
    return response.headers["etag"]


def _rename(client: TestClient, itinerary_id: str, hdrs: dict, etag: str | None,
            token: str, title: str = "Renamed"):
    """One representative content mutation. PATCH is the cheapest write that
    goes through the guard. `etag=None` means "whatever is current"."""
    if etag is None:
        etag = _etag(client, itinerary_id, hdrs)
    return client.patch(
        f"/itineraries/{itinerary_id}",
        json={"title": title}, headers=edit_headers(hdrs, etag, token),
    )


# ---------------------------------------------------------------------------
# Claiming
# ---------------------------------------------------------------------------

class TestClaiming:
    def test_owner_can_claim_and_gets_a_token(self, client: TestClient):
        itin_id, hdrs, _ = _owner_with_itinerary(client)

        response = client.post(f"/itineraries/{itin_id}/lock", json={}, headers=hdrs)

        assert response.status_code == 200, response.text
        body = response.json()
        assert body["token"]
        assert body["lock"]["is_you"] is True
        assert body["lock"]["state"] == "active"
        assert body["heartbeat_interval_seconds"] > 0

    def test_claim_body_is_optional(self, client: TestClient):
        """A client that posts nothing must still be able to start editing —
        takeover defaults to False, which is the safe direction."""
        itin_id, hdrs, _ = _owner_with_itinerary(client)

        response = client.post(f"/itineraries/{itin_id}/lock", headers=hdrs)

        assert response.status_code == 200, response.text

    def test_second_user_is_refused_while_the_claim_is_live(self, client: TestClient):
        itin_id, owner_hdrs, _ = _owner_with_itinerary(client)
        bob_hdrs, bob_id = _add_editor(client, itin_id, owner_hdrs, "bobby", "bobby@x.com")
        acquire_edit_lock(client, itin_id, bob_hdrs)

        carol_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "carol", "carol@x.com")
        response = client.post(f"/itineraries/{itin_id}/lock", json={}, headers=carol_hdrs)

        assert response.status_code == 423
        body = response.json()
        assert body["code"] == "itinerary_locked"
        lock = body["lock"]
        assert lock["holder_id"] == bob_id
        assert lock["holder_username"] == "bobby"
        assert lock["is_you"] is False
        assert lock["state"] == "active"
        # The countdown the other editor is shown comes from the server.
        assert lock["takeover_available_at"] > lock["last_heartbeat_at"]

    def test_same_user_on_a_second_device_is_refused_too(self, client: TestClient):
        """'The claim belongs to a person on one device.' The second device is
        told it is them, so the UI can offer to move the session rather than
        claiming somebody else is in the way."""
        itin_id, hdrs, _ = _owner_with_itinerary(client)
        acquire_edit_lock(client, itin_id, hdrs)

        response = client.post(f"/itineraries/{itin_id}/lock", json={}, headers=hdrs)

        assert response.status_code == 423
        assert response.json()["lock"]["is_you"] is True

    def test_same_user_second_device_may_take_over(self, client: TestClient):
        itin_id, hdrs, _ = _owner_with_itinerary(client)
        first = acquire_edit_lock(client, itin_id, hdrs)

        second = acquire_edit_lock(client, itin_id, hdrs, takeover=True)

        assert second != first  # rotated — the first device is now dead

    def test_a_non_editor_cannot_claim(self, client: TestClient):
        itin_id, owner_hdrs, _ = _owner_with_itinerary(client)
        stranger = register_user(client, "mallory", "mallory@x.com")

        response = client.post(
            f"/itineraries/{itin_id}/lock", json={},
            headers=auth_headers(stranger["access_token"]),
        )

        assert response.status_code in (403, 404)


# ---------------------------------------------------------------------------
# The requirement: an ejected device cannot save
# ---------------------------------------------------------------------------

class TestEjection:
    def test_taken_over_device_cannot_save(self, client: TestClient):
        """The named requirement. Bob's first device never learns it was
        displaced; it finds out by failing to save, not by failing to load."""
        itin_id, owner_hdrs, _ = _owner_with_itinerary(client)
        bob_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "bobby", "bobby@x.com")

        device_one = acquire_edit_lock(client, itin_id, bob_hdrs)
        device_two = acquire_edit_lock(client, itin_id, bob_hdrs, takeover=True)

        response = _rename(client, itin_id, bob_hdrs, None, device_one)

        assert response.status_code == 409, response.text
        assert response.json()["code"] == "edit_lock_lost"

        # ...and the claim that displaced it still works, so the failure is
        # about the token and not about the itinerary being wedged.
        assert _rename(client, itin_id, bob_hdrs, None, device_two).status_code == 200

    def test_owner_takeover_ejects_an_editor_mid_session(self, client: TestClient):
        itin_id, owner_hdrs, _ = _owner_with_itinerary(client)
        bob_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "bobby", "bobby@x.com")
        bob_token = acquire_edit_lock(client, itin_id, bob_hdrs)

        # The owner never waits out the TTL.
        owner_token = acquire_edit_lock(client, itin_id, owner_hdrs, takeover=True)

        assert _rename(client, itin_id, bob_hdrs, None, bob_token).status_code == 409
        assert _rename(client, itin_id, owner_hdrs, None, owner_token).status_code == 200

    def test_a_released_token_cannot_be_replayed(self, client: TestClient):
        itin_id, hdrs, etag = _owner_with_itinerary(client)
        token = acquire_edit_lock(client, itin_id, hdrs)

        client.delete(f"/itineraries/{itin_id}/lock",
                      headers={**hdrs, "X-Edit-Lock": token})

        response = _rename(client, itin_id, hdrs, etag, token)
        assert response.status_code == 409
        assert response.json()["code"] == "edit_lock_lost"

    def test_heartbeat_reports_the_loss(self, client: TestClient):
        """The ejected client should hear about it on its next ping rather than
        waiting until the user tries to save."""
        itin_id, owner_hdrs, _ = _owner_with_itinerary(client)
        bob_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "bobby", "bobby@x.com")
        bob_token = acquire_edit_lock(client, itin_id, bob_hdrs)
        acquire_edit_lock(client, itin_id, owner_hdrs, takeover=True)

        response = client.post(
            f"/itineraries/{itin_id}/lock/heartbeat",
            headers={**bob_hdrs, "X-Edit-Lock": bob_token},
        )

        assert response.status_code == 409
        assert response.json()["code"] == "edit_lock_lost"


# ---------------------------------------------------------------------------
# Mandatory claim on every write
# ---------------------------------------------------------------------------

class TestGuardIsMandatory:
    def test_saving_without_a_claim_is_refused(self, client: TestClient):
        itin_id, hdrs, etag = _owner_with_itinerary(client)

        response = client.patch(
            f"/itineraries/{itin_id}", json={"title": "Nope"},
            headers={**hdrs, "If-Match": etag},
        )

        assert response.status_code == 428
        assert response.json()["code"] == "edit_lock_required"

    def test_lock_is_checked_before_if_match(self, client: TestClient):
        """Order matters. After a takeover the ETag has usually moved too, and
        412 would send the user to reload into a screen they still cannot save
        from — 409 is the actionable truth."""
        itin_id, owner_hdrs, _ = _owner_with_itinerary(client)
        bob_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "bobby", "bobby@x.com")
        bob_token = acquire_edit_lock(client, itin_id, bob_hdrs)
        # What bob's open editor is holding, captured before anything moved.
        bob_etag = _etag(client, itin_id, bob_hdrs)
        owner_token = acquire_edit_lock(client, itin_id, owner_hdrs, takeover=True)

        # The owner writes, so bob's ETag is now stale as well as his claim.
        assert _rename(client, itin_id, owner_hdrs, None, owner_token).status_code == 200

        response = _rename(client, itin_id, bob_hdrs, bob_etag, bob_token)
        assert response.status_code == 409
        assert response.json()["code"] == "edit_lock_lost"

    def test_a_forged_token_is_refused(self, client: TestClient):
        """Only the hash is stored, so a guessed token cannot match."""
        itin_id, hdrs, etag = _owner_with_itinerary(client)
        acquire_edit_lock(client, itin_id, hdrs)

        response = _rename(client, itin_id, hdrs, etag, "not-a-real-token")

        assert response.status_code == 409

    def test_stops_require_a_claim_too(self, client: TestClient):
        """The guard covers subcontent, not just the itinerary row."""
        itin_id, hdrs, etag = _owner_with_itinerary(client)

        response = client.post(
            f"/itineraries/{itin_id}/stops", json={"place_name": "Paris", "is_free": True},
            headers={**hdrs, "If-Match": etag},
        )

        assert response.status_code == 428
        assert response.json()["code"] == "edit_lock_required"


# ---------------------------------------------------------------------------
# Decay
# ---------------------------------------------------------------------------

class TestDecay:
    def test_state_walks_active_to_idle_to_takeable(self, client: TestClient):
        settings = get_settings()
        itin_id, owner_hdrs, _ = _owner_with_itinerary(client)
        bob_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "bobby", "bobby@x.com")
        acquire_edit_lock(client, itin_id, bob_hdrs)

        def observed_state() -> str:
            response = client.get(f"/itineraries/{itin_id}/lock", headers=owner_hdrs)
            assert response.status_code == 200, response.text
            return response.json()["lock"]["state"]

        assert observed_state() == "active"

        backdate_lock_heartbeat(itin_id, settings.EDIT_LOCK_IDLE_SECONDS + 1)
        assert observed_state() == "idle"

        backdate_lock_heartbeat(itin_id, settings.EDIT_LOCK_TTL_SECONDS + 1)
        assert observed_state() == "takeable"

    def test_an_idle_claim_still_cannot_be_taken(self, client: TestClient):
        """Idle is presentational — 'they stepped away', not 'help yourself'."""
        settings = get_settings()
        itin_id, owner_hdrs, _ = _owner_with_itinerary(client)
        bob_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "bobby", "bobby@x.com")
        carol_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "carol", "carol@x.com")
        acquire_edit_lock(client, itin_id, bob_hdrs)
        backdate_lock_heartbeat(itin_id, settings.EDIT_LOCK_IDLE_SECONDS + 1)

        response = client.post(
            f"/itineraries/{itin_id}/lock", json={"takeover": True}, headers=carol_hdrs,
        )

        assert response.status_code == 423

    def test_a_takeable_claim_can_be_taken_by_another_editor(self, client: TestClient):
        settings = get_settings()
        itin_id, owner_hdrs, _ = _owner_with_itinerary(client)
        bob_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "bobby", "bobby@x.com")
        carol_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "carol", "carol@x.com")
        bob_token = acquire_edit_lock(client, itin_id, bob_hdrs)
        backdate_lock_heartbeat(itin_id, settings.EDIT_LOCK_TTL_SECONDS + 1)

        carol_token = acquire_edit_lock(client, itin_id, carol_hdrs, takeover=True)

        assert _rename(client, itin_id, carol_hdrs, None, carol_token).status_code == 200
        # And bob, who never noticed, is out.
        assert _rename(client, itin_id, bob_hdrs, None, bob_token).status_code == 409

    def test_takeover_flag_is_required_even_for_a_takeable_claim(self, client: TestClient):
        """A steal is always a deliberate second call the UI confirmed, never
        something a retry did by accident."""
        settings = get_settings()
        itin_id, owner_hdrs, _ = _owner_with_itinerary(client)
        bob_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "bobby", "bobby@x.com")
        carol_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "carol", "carol@x.com")
        acquire_edit_lock(client, itin_id, bob_hdrs)
        backdate_lock_heartbeat(itin_id, settings.EDIT_LOCK_TTL_SECONDS + 1)

        response = client.post(f"/itineraries/{itin_id}/lock", json={}, headers=carol_hdrs)

        assert response.status_code == 423
        assert response.json()["lock"]["state"] == "takeable"

    def test_heartbeat_keeps_a_claim_alive(self, client: TestClient):
        settings = get_settings()
        itin_id, owner_hdrs, _ = _owner_with_itinerary(client)
        bob_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "bobby", "bobby@x.com")
        carol_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "carol", "carol@x.com")
        bob_token = acquire_edit_lock(client, itin_id, bob_hdrs)
        backdate_lock_heartbeat(itin_id, settings.EDIT_LOCK_TTL_SECONDS + 1)

        response = client.post(
            f"/itineraries/{itin_id}/lock/heartbeat",
            headers={**bob_hdrs, "X-Edit-Lock": bob_token},
        )
        assert response.status_code == 200, response.text
        assert response.json()["state"] == "active"

        # Carol was one request away from taking it and now is not.
        assert client.post(
            f"/itineraries/{itin_id}/lock", json={"takeover": True}, headers=carol_hdrs,
        ).status_code == 423

    def test_an_unclaimed_stale_holder_may_still_save(self, client: TestClient):
        """Nobody took the claim, so refusing the save would throw away real
        work to enforce a deadline that was not holding anyone up."""
        settings = get_settings()
        itin_id, hdrs, etag = _owner_with_itinerary(client)
        token = acquire_edit_lock(client, itin_id, hdrs)
        backdate_lock_heartbeat(itin_id, settings.EDIT_LOCK_TTL_SECONDS * 2)

        assert _rename(client, itin_id, hdrs, etag, token).status_code == 200

    def test_saving_refreshes_the_heartbeat(self, client: TestClient):
        """Saving is activity — a busy editor must not decay into 'takeable'
        just because the ping timer is coarser than their typing."""
        settings = get_settings()
        itin_id, hdrs, etag = _owner_with_itinerary(client)
        token = acquire_edit_lock(client, itin_id, hdrs)
        backdate_lock_heartbeat(itin_id, settings.EDIT_LOCK_IDLE_SECONDS + 1)

        assert _rename(client, itin_id, hdrs, etag, token).status_code == 200

        response = client.get(f"/itineraries/{itin_id}/lock", headers=hdrs)
        assert response.json()["lock"]["state"] == "active"


# ---------------------------------------------------------------------------
# Releasing and reading
# ---------------------------------------------------------------------------

class TestReleaseAndRead:
    def test_release_frees_the_claim_for_everyone(self, client: TestClient):
        itin_id, owner_hdrs, _ = _owner_with_itinerary(client)
        bob_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "bobby", "bobby@x.com")
        bob_token = acquire_edit_lock(client, itin_id, bob_hdrs)

        response = client.delete(f"/itineraries/{itin_id}/lock",
                                 headers={**bob_hdrs, "X-Edit-Lock": bob_token})
        assert response.status_code == 204

        # No takeover flag needed — there is nothing to take over.
        assert client.post(
            f"/itineraries/{itin_id}/lock", json={}, headers=owner_hdrs,
        ).status_code == 200

    def test_release_is_idempotent(self, client: TestClient):
        """The client fires this from teardown, so a retry — or a claim the TTL
        already handed to someone else — must not raise."""
        itin_id, hdrs, _ = _owner_with_itinerary(client)
        token = acquire_edit_lock(client, itin_id, hdrs)

        for _ in range(3):
            response = client.delete(f"/itineraries/{itin_id}/lock",
                                     headers={**hdrs, "X-Edit-Lock": token})
            assert response.status_code == 204

    def test_owner_can_release_someone_elses_claim_without_a_token(self, client: TestClient):
        """'Unlock it from my other device' — the owner's escape hatch."""
        itin_id, owner_hdrs, _ = _owner_with_itinerary(client)
        bob_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "bobby", "bobby@x.com")
        acquire_edit_lock(client, itin_id, bob_hdrs)

        assert client.delete(f"/itineraries/{itin_id}/lock",
                             headers=owner_hdrs).status_code == 204

        response = client.get(f"/itineraries/{itin_id}/lock", headers=owner_hdrs)
        assert response.json()["lock"] is None

    def test_an_editor_cannot_release_another_editors_claim(self, client: TestClient):
        """Silent no-op rather than an error: release is idempotent by design,
        so what matters is that the claim survives."""
        itin_id, owner_hdrs, _ = _owner_with_itinerary(client)
        bob_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "bobby", "bobby@x.com")
        carol_hdrs, _ = _add_editor(client, itin_id, owner_hdrs, "carol", "carol@x.com")
        bob_token = acquire_edit_lock(client, itin_id, bob_hdrs)

        client.delete(f"/itineraries/{itin_id}/lock", headers=carol_hdrs)

        assert _rename(client, itin_id, bob_hdrs, None, bob_token).status_code == 200

    def test_lock_state_is_readable_by_anyone_who_can_view(self, client: TestClient):
        itin_id, owner_hdrs, _ = _owner_with_itinerary(client)
        client.patch(
            f"/itineraries/{itin_id}", json={"visibility": "public"},
            headers=edit_headers(
                owner_hdrs,
                etag_from_updated_at(
                    client.get(f"/itineraries/{itin_id}", headers=owner_hdrs)
                    .json()["updated_at"]
                ),
                acquire_edit_lock(client, itin_id, owner_hdrs, takeover=True),
            ),
        )
        viewer = register_user(client, "viewer", "viewer@x.com")

        response = client.get(f"/itineraries/{itin_id}/lock",
                              headers=auth_headers(viewer["access_token"]))

        assert response.status_code == 200, response.text
        # They can see somebody is editing; they still cannot edit.
        assert response.json()["can_edit"] is False

    def test_no_claim_reads_as_null(self, client: TestClient):
        itin_id, hdrs, _ = _owner_with_itinerary(client)

        response = client.get(f"/itineraries/{itin_id}/lock", headers=hdrs)

        assert response.status_code == 200
        assert response.json()["lock"] is None
        assert response.json()["can_edit"] is True


# ---------------------------------------------------------------------------
# Housekeeping
# ---------------------------------------------------------------------------

def test_sweep_purges_long_dead_claims(client: TestClient):
    """Correctness never depends on this — a surviving row still reads as
    takeable — but the table must not grow forever."""
    from app.services import edit_lock_service
    from app.services.sweep_service import run_moderation_sweep
    from conftest import TestingSessionLocal

    settings = get_settings()
    itin_id, hdrs, _ = _owner_with_itinerary(client)
    acquire_edit_lock(client, itin_id, hdrs)
    backdate_lock_heartbeat(
        itin_id,
        settings.EDIT_LOCK_TTL_SECONDS * (edit_lock_service.PURGE_TTL_MULTIPLE + 1),
    )

    db = TestingSessionLocal()
    try:
        counters = run_moderation_sweep(db, settings)
    finally:
        db.close()

    assert counters["edit_locks_purged"] == 1
    assert client.get(f"/itineraries/{itin_id}/lock", headers=hdrs).json()["lock"] is None
