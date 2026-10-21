"""
test_itinerary_form.py — the itinerary form's save, fields and cover in one request.

The Edit itinerary form used to save in two requests: POST|DELETE /image, then
PATCH /itineraries/{id} carrying an If-Match read before the first one. A cover
write that changed the row (a first cover, a removal, a scan that flagged or
errored) moved updated_at, so the PATCH answered 412 — the cover saved, the
fields did not, and every retry failed the same way. PATCH
/itineraries/{id}/form carries both under one guard; POST /itineraries/form
does the same for a create.

Storage is redirected to a per-test directory at both seams (image_service's
save funnel and the router's deletes), so "nothing stored" is exact. Rekognition
and the text provider are the stubs test_image_moderation.py and
test_text_moderation_endpoints.py already use, counting their calls.
"""

from __future__ import annotations

import inspect
import json
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from conftest import (
    TestingSessionLocal, auth_headers, edit_now, locked_headers, register_user,
)
from test_image_moderation import _StubRekognition, _enable_moderation, _make_jpeg
from test_text_moderation_endpoints import MINORS, REJECT, CountingProvider
from translation_helpers import engines  # noqa: F401 — a fixture
from app.config import get_settings
from app.models.image_moderation_log import ImageModerationLog
from app.models.itinerary import Itinerary
from app.models.legal_escalation import LegalEscalation
from app.models.user import User
from app.routers import itineraries as itineraries_router
from app.services import moderation_service, translation_service
from app.services import text_moderation_service as tms
from app.storage.filesystem import FilesystemStorage


EXPLICIT = [{"Name": "Explicit Nudity", "ParentName": "", "Confidence": 95.0}]
SUGGESTIVE = [{"Name": "Suggestive", "ParentName": "", "Confidence": 60.0}]


# ---------------------------------------------------------------------------
# Fixtures and helpers
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def store(tmp_path):
    store = FilesystemStorage(str(tmp_path), "/uploads")
    with patch("app.services.image_service.storage", return_value=store), \
         patch("app.routers.itineraries.storage", return_value=store):
        yield store


@pytest.fixture()
def owner(client):
    return register_user(client, "owner", "owner@example.com")


@pytest.fixture()
def hdrs(owner):
    return auth_headers(owner["access_token"])


@pytest.fixture()
def trip(client, owner) -> str:
    r = client.post("/itineraries/", json={"title": "Coast walk", "visibility": "public"},
                    headers=auth_headers(owner["access_token"]))
    assert r.status_code == 201, r.text
    return r.json()["id"]


class _CountingRekognition(_StubRekognition):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.calls = 0

    def detect_moderation_labels(self, **kwargs):
        self.calls += 1
        return super().detect_moderation_labels(**kwargs)


def _rekognition(monkeypatch, labels=None, raises=False) -> _CountingRekognition:
    _enable_moderation(monkeypatch)
    stub = _CountingRekognition(labels=labels, raises=raises)
    monkeypatch.setattr(moderation_service, "_rekognition_client", lambda settings: stub)
    return stub


def _text_provider(monkeypatch, scores=None) -> CountingProvider:
    monkeypatch.setattr(get_settings(), "TEXT_MODERATION_PROVIDER", "openai")
    monkeypatch.setattr(get_settings(), "OPENAI_API_KEY", "test-key")
    stub = CountingProvider(scores)
    monkeypatch.setattr(tms, "get_provider_chain", lambda settings: [stub])
    return stub


def _parts(fields, *, image=None, remove_cover=False, raw_fields=None) -> dict:
    # Always multipart, as the app sends it: a filename-less part is a form field.
    parts = {"fields": (None, raw_fields if raw_fields is not None else json.dumps(fields))}
    if remove_cover:
        parts["remove_cover"] = (None, "true")
    if image is not None:
        parts["image"] = ("cover.jpg", image, "image/jpeg")
    return parts


def _save_form(client, trip, headers, fields=None, **kwargs):
    return client.patch(f"/itineraries/{trip}/form", files=_parts(fields, **kwargs),
                        headers=headers)


def _create_form(client, token, fields, **kwargs):
    return client.post("/itineraries/form", files=_parts(fields, **kwargs),
                       headers=auth_headers(token))


def _row(trip: str) -> Itinerary | None:
    db = TestingSessionLocal()
    try:
        return db.get(Itinerary, uuid.UUID(trip))
    finally:
        db.close()


def _backdate(trip: str, seconds: int = 60) -> None:
    """Move updated_at back, as if the trip were last saved a minute ago.

    The column's server_default/onupdate render as CURRENT_TIMESTAMP on SQLite,
    which counts whole seconds: a write in the same second as the last one
    leaves the ETag where it was, which Postgres's now() never does. The tests
    about the ETag moving start here, so the move they test is real.
    """
    db = TestingSessionLocal()
    try:
        db.get(Itinerary, uuid.UUID(trip)).updated_at = (
            datetime.now(timezone.utc) - timedelta(seconds=seconds)
        )
        db.commit()
    finally:
        db.close()


def _all(model) -> list:
    db = TestingSessionLocal()
    try:
        return db.query(model).all()
    finally:
        db.close()


def _object(store, trip: str):
    return store._base.joinpath(f"itineraries/{trip}.jpg")


def _stored_covers(store) -> list:
    folder = store._base.joinpath("itineraries")
    return list(folder.glob("*.jpg")) if folder.exists() else []


def _upload_old_way(client, trip, hdrs):
    r = client.post(f"/itineraries/{trip}/image",
                    files={"file": ("cover.jpg", _make_jpeg(), "image/jpeg")}, headers=hdrs)
    assert r.status_code == 200, r.text
    return r.json()["cover_image_url"]


def _editor(client, trip, owner_hdrs) -> dict:
    user = register_user(client, "editor", "editor@example.com")
    r = client.post(f"/itineraries/{trip}/editors", json={"user_id": user["user_id"]},
                    headers=owner_hdrs)
    assert r.status_code == 201, r.text
    return auth_headers(user["access_token"])


# ---------------------------------------------------------------------------
# One request, one guard
# ---------------------------------------------------------------------------

def test_the_form_routes_are_sync_def():
    # FastAPI parses the multipart body before calling the endpoint, so a sync
    # def reads the UploadFile and reaches the async pipeline through anyio;
    # every end-to-end test below is the proof that this works.
    assert not inspect.iscoroutinefunction(itineraries_router.update_itinerary_form)
    assert not inspect.iscoroutinefunction(itineraries_router.create_itinerary_form)


def test_a_new_cover_and_a_title_in_one_request(client, store, hdrs, trip):
    _backdate(trip)
    headers = edit_now(client, trip, hdrs)

    r = _save_form(client, trip, headers, {"title": "Coast walk, revised"}, image=_make_jpeg())

    assert r.status_code == 200, r.text
    body = r.json()
    assert body["title"] == "Coast walk, revised"
    assert body["cover_image_url"].endswith(f"itineraries/{trip}.jpg")
    assert _object(store, trip).exists()
    row = _row(trip)
    assert row.title == "Coast walk, revised"
    assert row.cover_image_url == body["cover_image_url"]
    # The stamp moved, and the response carries the new one for the next save.
    stale = _save_form(client, trip, headers, {"currency": "MAD"})
    assert stale.status_code == 412
    again = _save_form(client, trip, {**headers, "If-Match": r.headers["etag"]},
                       {"currency": "MAD"})
    assert again.status_code == 200, again.text
    assert _row(trip).currency == "MAD"


def test_the_bugs_own_scenario_saves(client, store, hdrs, trip):
    """A cover change plus a field change, under the ETag read before either —
    the save that 412'd in production on 2026-10-20."""
    _backdate(trip)
    headers = edit_now(client, trip, hdrs)

    first_cover = _save_form(client, trip, headers, {"title": "With a photo"},
                             image=_make_jpeg())
    assert first_cover.status_code == 200, first_cover.text

    removal = _save_form(client, trip, {**headers, "If-Match": first_cover.headers["etag"]},
                         {"title": "Without it"}, remove_cover=True)
    assert removal.status_code == 200, removal.text
    row = _row(trip)
    assert (row.title, row.cover_image_url) == ("Without it", None)


def test_the_two_request_flow_it_replaces_still_412s(client, store, hdrs, trip):
    # Why the form left the /image pair: it writes the row outside the guard, so
    # the PATCH behind it carries a stale If-Match. Kept as-is for installed builds.
    _backdate(trip)
    headers = edit_now(client, trip, hdrs)
    _upload_old_way(client, trip, hdrs)

    r = client.patch(f"/itineraries/{trip}", json={"title": "Renamed"}, headers=headers)

    assert r.status_code == 412
    assert r.json()["code"] == "itinerary_stale"


def test_the_old_cover_endpoints_still_work(client, store, hdrs, trip):
    url = _upload_old_way(client, trip, hdrs)
    assert _row(trip).cover_image_url == url
    assert _object(store, trip).exists()

    assert client.delete(f"/itineraries/{trip}/image", headers=hdrs).status_code == 204
    assert _row(trip).cover_image_url is None
    assert not _object(store, trip).exists()


def test_a_stale_if_match_is_412_with_nothing_stored_or_changed(
    client, store, hdrs, trip, monkeypatch,
):
    stale = client.get(f"/itineraries/{trip}", headers=hdrs).headers["etag"]
    _backdate(trip)  # another device saved since this one read the trip
    rekognition, text = _rekognition(monkeypatch), _text_provider(monkeypatch)

    r = _save_form(client, trip, locked_headers(client, trip, hdrs, stale),
                   {"title": "Too late"}, image=_make_jpeg())

    assert r.status_code == 412
    assert _row(trip).title == "Coast walk"
    assert _row(trip).cover_image_url is None
    assert not _object(store, trip).exists()
    assert rekognition.calls == 0 and text.calls == []


def test_without_the_claim_nothing_is_scanned_or_stored(client, store, hdrs, trip, monkeypatch):
    rekognition, text = _rekognition(monkeypatch), _text_provider(monkeypatch)
    etag = client.get(f"/itineraries/{trip}", headers=hdrs).headers["etag"]

    r = _save_form(client, trip, {**hdrs, "If-Match": etag}, {"title": "No claim"},
                   image=_make_jpeg())

    assert r.status_code == 428
    assert r.json()["code"] == "edit_lock_required"
    assert rekognition.calls == 0 and text.calls == []
    assert not _object(store, trip).exists()
    assert _row(trip).title == "Coast walk"


# ---------------------------------------------------------------------------
# Owner-only parts
# ---------------------------------------------------------------------------

def test_an_editor_saves_the_fields(client, store, hdrs, trip):
    editor_hdrs = _editor(client, trip, hdrs)

    r = _save_form(client, trip, edit_now(client, trip, editor_hdrs),
                   {"title": "Edited by a friend", "currency": "JPY"})

    assert r.status_code == 200, r.text
    assert (_row(trip).title, _row(trip).currency) == ("Edited by a friend", "JPY")


@pytest.mark.parametrize("change", ["image", "remove_cover"])
def test_a_cover_change_from_an_editor_refuses_the_whole_request(
    client, store, hdrs, trip, change,
):
    url = _upload_old_way(client, trip, hdrs)
    before = _object(store, trip).read_bytes()
    editor_hdrs = _editor(client, trip, hdrs)

    r = _save_form(
        client, trip, edit_now(client, trip, editor_hdrs), {"title": "Not saved"},
        image=_make_jpeg(900, 900) if change == "image" else None,
        remove_cover=change == "remove_cover",
    )

    assert r.status_code == 403
    assert r.json()["code"] == "itinerary_not_owner"
    row = _row(trip)
    assert (row.title, row.cover_image_url) == ("Coast walk", url)
    assert _object(store, trip).read_bytes() == before


def test_visibility_stays_the_owners(client, store, hdrs, trip):
    editor_hdrs = _editor(client, trip, hdrs)

    r = _save_form(client, trip, edit_now(client, trip, editor_hdrs),
                   {"title": "Hidden away", "visibility": "only_me"})

    assert r.status_code == 403
    assert r.json()["code"] == "itinerary_not_owner"
    assert (_row(trip).title, _row(trip).visibility) == ("Coast walk", "public")


def test_an_upload_needs_a_verified_email_but_the_fields_do_not(
    client, store, owner, hdrs, trip,
):
    db = TestingSessionLocal()
    try:
        db.get(User, uuid.UUID(owner["user_id"])).email_verified = False
        db.commit()
    finally:
        db.close()
    headers = edit_now(client, trip, hdrs)

    refused = _save_form(client, trip, headers, {"title": "With a photo"}, image=_make_jpeg())
    assert refused.status_code == 403
    assert refused.json()["code"] == "email_unverified"
    assert not _object(store, trip).exists()

    fields_only = _save_form(client, trip, headers, {"title": "Words only"})
    assert fields_only.status_code == 200, fields_only.text


# ---------------------------------------------------------------------------
# Removing the cover
# ---------------------------------------------------------------------------

def test_remove_clears_the_url_and_deletes_the_object_after_the_commit(
    client, store, hdrs, trip, monkeypatch,
):
    _upload_old_way(client, trip, hdrs)
    seen = []
    real_delete = store.delete

    async def delete_once_committed(key):
        seen.append((key, _row(trip).cover_image_url))
        await real_delete(key)

    monkeypatch.setattr(store, "delete", delete_once_committed)

    r = _save_form(client, trip, edit_now(client, trip, hdrs), {"title": "No photo"},
                   remove_cover=True)

    assert r.status_code == 200, r.text
    assert r.json()["cover_image_url"] is None
    # When the object went, the row was already committed without it.
    assert seen == [(f"itineraries/{trip}.jpg", None)]
    assert not _object(store, trip).exists()


def test_a_failed_delete_after_the_commit_keeps_the_save(client, store, hdrs, trip, monkeypatch):
    _upload_old_way(client, trip, hdrs)

    async def storage_down(key):
        raise RuntimeError("storage outage")

    monkeypatch.setattr(store, "delete", storage_down)

    r = _save_form(client, trip, edit_now(client, trip, hdrs), {"title": "No photo"},
                   remove_cover=True)

    assert r.status_code == 200, r.text
    assert (_row(trip).title, _row(trip).cover_image_url) == ("No photo", None)


def test_an_image_and_remove_cover_together_is_a_422(client, store, hdrs, trip):
    r = _save_form(client, trip, edit_now(client, trip, hdrs), {"title": "Both"},
                   image=_make_jpeg(), remove_cover=True)

    assert r.status_code == 422
    assert r.json()["detail"][0]["loc"] == ["body", "remove_cover"]
    assert _row(trip).title == "Coast walk"


# ---------------------------------------------------------------------------
# Validation and moderation
# ---------------------------------------------------------------------------

def test_a_bad_field_is_fastapis_own_422_under_the_fields_part(client, store, hdrs, trip):
    headers = edit_now(client, trip, hdrs)

    form = _save_form(client, trip, headers, {"title": ""})
    patch_ = client.patch(f"/itineraries/{trip}", json={"title": ""}, headers=headers)

    assert form.status_code == patch_.status_code == 422
    form_error, patch_error = form.json()["detail"][0], patch_.json()["detail"][0]
    assert form_error["loc"] == ["body", "fields", "title"]
    assert patch_error["loc"] == ["body", "title"]
    # Same error, same keys — only the location names the part it came from.
    assert {k: v for k, v in form_error.items() if k != "loc"} == \
           {k: v for k, v in patch_error.items() if k != "loc"}


def test_fields_that_are_not_json_are_a_422(client, store, hdrs, trip):
    r = _save_form(client, trip, edit_now(client, trip, hdrs), raw_fields="title=oops")

    assert r.status_code == 422
    assert r.json()["detail"][0]["loc"] == ["body", "fields"]


def test_rejected_text_stores_nothing_and_changes_nothing(
    client, store, hdrs, trip, monkeypatch,
):
    headers = edit_now(client, trip, hdrs)
    rekognition = _rekognition(monkeypatch)
    _text_provider(monkeypatch, REJECT)

    r = _save_form(client, trip, headers, {"title": "Something hateful"}, image=_make_jpeg())

    assert r.status_code == 422
    assert r.json()["code"] == "text_moderation_rejected"
    assert rekognition.calls == 0
    assert not _object(store, trip).exists()
    row = _row(trip)
    assert (row.title, row.cover_image_url) == ("Coast walk", None)


def test_a_rejected_image_changes_no_field(client, store, hdrs, trip, monkeypatch):
    headers = edit_now(client, trip, hdrs)
    _rekognition(monkeypatch, labels=EXPLICIT)

    r = _save_form(client, trip, headers, {"title": "New title", "currency": "MAD"},
                   image=_make_jpeg())

    assert r.status_code == 422
    assert r.json()["code"] == "image_moderation_rejected"
    row = _row(trip)
    assert (row.title, row.currency, row.cover_image_url) == ("Coast walk", "EUR", None)
    assert row.moderation_status == "approved"
    assert not _object(store, trip).exists()
    # The reject's audit row survived the 422, pointing at the trip.
    (log,) = _all(ImageModerationLog)
    assert (log.action, log.target_itinerary_id) == ("rejected", uuid.UUID(trip))


def test_a_scan_error_saves_and_marks_the_trip_pending(client, store, hdrs, trip, monkeypatch):
    headers = edit_now(client, trip, hdrs)
    _rekognition(monkeypatch, raises=True)

    r = _save_form(client, trip, headers, {"title": "Saved anyway"}, image=_make_jpeg())

    assert r.status_code == 200, r.text
    row = _row(trip)
    assert (row.title, row.moderation_status) == ("Saved anyway", "pending")
    assert _object(store, trip).exists()


@pytest.mark.parametrize("image, status", [
    (_make_jpeg(), 422),             # the scan refuses it
    (_make_jpeg(100, 100), 400),     # too small to process
])
def test_a_minors_verdict_whose_cover_is_refused_is_still_escalated(
    client, store, owner, hdrs, trip, monkeypatch, image, status,
):
    headers = edit_now(client, trip, hdrs)
    _rekognition(monkeypatch, labels=EXPLICIT)
    _text_provider(monkeypatch, MINORS)

    r = _save_form(client, trip, headers, {"title": "Flagged words"}, image=image)

    assert r.status_code == status
    # Nothing was stored, so the signal is raised against the author — as a
    # rejected minors verdict is — rather than lost with the rollback.
    (escalation,) = _all(LegalEscalation)
    assert (escalation.target_type, str(escalation.target_id)) == ("user", owner["user_id"])
    assert escalation.decision_id is not None
    row = _row(trip)
    assert (row.title, row.hidden_at) == ("Coast walk", None)


def test_a_public_title_change_is_pretranslated(client, store, hdrs, trip, monkeypatch, engines):
    monkeypatch.setattr(get_settings(), "TRANSLATION_PRETRANSLATE_LANGS", "fr")
    scheduled = []
    monkeypatch.setattr(translation_service, "pretranslate_title",
                        lambda itinerary_id, settings: scheduled.append(itinerary_id))

    r = _save_form(client, trip, edit_now(client, trip, hdrs), {"title": "A new public title"})

    assert r.status_code == 200, r.text
    assert scheduled == [uuid.UUID(trip)]


# ---------------------------------------------------------------------------
# POST /itineraries/form — create with a cover
# ---------------------------------------------------------------------------

def test_create_with_a_cover_in_one_request(client, store, owner):
    r = _create_form(client, owner["access_token"],
                     {"title": "Islands", "visibility": "public", "currency": "EUR"},
                     image=_make_jpeg())

    assert r.status_code == 201, r.text
    trip = r.json()["id"]
    assert r.json()["cover_image_url"].endswith(f"itineraries/{trip}.jpg")
    assert _object(store, trip).exists()
    row = _row(trip)
    assert (row.title, row.cover_image_url) == ("Islands", r.json()["cover_image_url"])


def test_create_with_rejected_text_creates_and_stores_nothing(
    client, store, owner, monkeypatch,
):
    rekognition = _rekognition(monkeypatch)
    _text_provider(monkeypatch, REJECT)

    r = _create_form(client, owner["access_token"], {"title": "Something hateful"},
                     image=_make_jpeg())

    assert r.status_code == 422
    assert r.json()["code"] == "text_moderation_rejected"
    assert _all(Itinerary) == []
    assert _stored_covers(store) == []
    assert rekognition.calls == 0


def test_create_with_a_rejected_cover_creates_nothing(client, store, owner, monkeypatch):
    _rekognition(monkeypatch, labels=EXPLICIT)

    r = _create_form(client, owner["access_token"], {"title": "Islands"}, image=_make_jpeg())

    assert r.status_code == 422
    assert r.json()["code"] == "image_moderation_rejected"
    assert _all(Itinerary) == []
    assert _stored_covers(store) == []
    # Committed with no trip to point at: naming the unborn id would have
    # failed the reject's own commit on the foreign key.
    (log,) = _all(ImageModerationLog)
    assert (log.action, log.target_itinerary_id) == ("rejected", None)


def test_a_flagged_cover_at_create_is_linked_to_its_trip(client, store, owner, monkeypatch):
    _rekognition(monkeypatch, labels=SUGGESTIVE)

    r = _create_form(client, owner["access_token"], {"title": "Islands"}, image=_make_jpeg())

    assert r.status_code == 201, r.text
    trip = r.json()["id"]
    assert _row(trip).moderation_status == "flagged"
    # /admin/flagged finds the trip only through this column.
    (log,) = _all(ImageModerationLog)
    assert (log.action, log.target_itinerary_id) == ("flagged", uuid.UUID(trip))


def test_a_create_that_fails_after_storing_removes_the_object(
    client, store, owner, monkeypatch,
):
    def database_gone(moderation):
        raise RuntimeError("database went away")

    monkeypatch.setattr(itineraries_router, "attach_itinerary", database_gone)

    with pytest.raises(RuntimeError):
        _create_form(client, owner["access_token"], {"title": "Islands"}, image=_make_jpeg())

    assert _all(Itinerary) == []
    assert _stored_covers(store) == []


def test_create_with_a_cover_needs_a_verified_email(client, store):
    unverified = register_user(client, "newcomer", "newcomer@example.com", verified=False)

    r = _create_form(client, unverified["access_token"], {"title": "Islands"},
                     image=_make_jpeg())

    assert r.status_code == 403
    assert r.json()["code"] == "email_unverified"
    assert _stored_covers(store) == []


def test_create_through_the_form_needs_the_image(client, store, owner):
    r = _create_form(client, owner["access_token"], {"title": "Islands"})

    assert r.status_code == 422
    assert r.json()["detail"][0]["loc"] == ["body", "image"]
    assert _all(Itinerary) == []


def test_a_minors_verdict_at_create_whose_cover_is_refused_is_escalated(
    client, store, owner, monkeypatch,
):
    _rekognition(monkeypatch, labels=EXPLICIT)
    _text_provider(monkeypatch, MINORS)

    r = _create_form(client, owner["access_token"], {"title": "Flagged words"},
                     image=_make_jpeg())

    assert r.status_code == 422
    assert _all(Itinerary) == []
    (escalation,) = _all(LegalEscalation)
    assert (escalation.target_type, str(escalation.target_id)) == ("user", owner["user_id"])


def test_a_public_create_with_a_cover_is_pretranslated(client, store, owner, monkeypatch, engines):
    monkeypatch.setattr(get_settings(), "TRANSLATION_PRETRANSLATE_LANGS", "fr")
    scheduled = []
    monkeypatch.setattr(translation_service, "pretranslate_title",
                        lambda itinerary_id, settings: scheduled.append(itinerary_id))

    r = _create_form(client, owner["access_token"], {"title": "Islands", "visibility": "public"},
                     image=_make_jpeg())

    assert r.status_code == 201, r.text
    assert scheduled == [uuid.UUID(r.json()["id"])]
