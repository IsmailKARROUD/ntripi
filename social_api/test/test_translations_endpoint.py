"""
test_translations_endpoint.py — POST /translations and GET /translations/config.

Engines are FakeTranslators patched into translation_service; no network. The
access matrix is the heart of it: a reader can only ever have translated what
they can read, and anything else answers `not_found` — the same answer whether
the content is missing, forbidden or taken down.
"""

import uuid
from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from conftest import TestingSessionLocal, auth_headers, register_user
from app.models.content_translation import ContentTranslation
from app.models.itinerary import Itinerary
from app.models.itinerary_rating import ItineraryRating
from app.models.user import User
from app.services.translation_providers import TranslatorUnavailableError
from app.services.translation_service import source_hash
from translation_fakes import FakeTranslator
from translation_helpers import (  # noqa: F401 — engines is a fixture
    TITLE, cached_count as _cached_count, engines, make_trip as _trip,
    set_row as _set, translate as _translate, trip_item as _trip_item, write as _write,
)


def _rating_id(trip_id) -> str:
    db = TestingSessionLocal()
    try:
        return str(db.execute(select(ItineraryRating.id).where(
            ItineraryRating.itinerary_id == uuid.UUID(trip_id))).scalars().first())
    finally:
        db.close()


def _review(client, token, trip_id, note="Beautiful route, but far too long for children."):
    r = client.post(f"/itineraries/{trip_id}/ratings", json={"stars": 4, "note": note},
                    headers=auth_headers(token))
    assert r.status_code == 201, r.text
    return _rating_id(trip_id)


@pytest.fixture()
def people(client):
    alice = register_user(client, "alice", "alice@example.com")
    bob = register_user(client, "bobby", "bob@example.com")
    return alice, bob


# ---------------------------------------------------------------------------
# On, off, signed out
# ---------------------------------------------------------------------------

class TestAvailability:

    def test_off_by_default_and_the_post_is_invisible(self, client: TestClient, people):
        alice, _ = people
        r = client.get("/translations/config", headers=auth_headers(alice["access_token"]))
        assert r.json() == {"enabled": False, "target_langs": []}
        trip_id = _trip(client, alice["access_token"])
        assert _translate(client, alice["access_token"], [_trip_item(trip_id)]).status_code == 404

    def test_config_lists_the_languages_when_on(self, client: TestClient, people, engines):
        alice, _ = people
        r = client.get("/translations/config", headers=auth_headers(alice["access_token"]))
        assert r.json() == {"enabled": True, "target_langs": ["en", "fr", "es", "de", "ar", "zh"]}

    def test_both_need_sign_in(self, client: TestClient, engines):
        assert client.get("/translations/config").status_code == 403
        r = client.post("/translations", json={"target_lang": "fr", "items": [
            _trip_item(str(uuid.uuid4()))]})
        assert r.status_code == 403


# ---------------------------------------------------------------------------
# Translating and caching
# ---------------------------------------------------------------------------

class TestTranslating:

    def test_translates_then_answers_from_the_cache(self, client: TestClient, people, engines):
        alice, bob = people
        trip_id = _trip(client, alice["access_token"])

        first = _translate(client, bob["access_token"], [_trip_item(trip_id)])
        assert first.status_code == 200, first.text
        item = first.json()["items"][0]
        assert item["status"] == "ok"
        assert item["fields"]["title"] == {
            "status": "translated", "text": f"[fr] {TITLE}",
            "provider": "first", "source_lang": "en",
        }
        assert _cached_count() == 2

        second = _translate(client, bob["access_token"], [_trip_item(trip_id)])
        assert second.json() == first.json()
        assert len(engines.first.calls) == 1  # the second answer was the cache's

    def test_same_language_and_empty_fields_never_reach_an_engine(
        self, client: TestClient, people, engines,
    ):
        alice, bob = people
        trip_id = _trip(client, alice["access_token"], description=None)

        r = _translate(client, bob["access_token"], [_trip_item(trip_id)], lang="en")
        fields = r.json()["items"][0]["fields"]
        assert fields["title"]["status"] == "same_language"
        assert fields["description"]["status"] == "empty"
        assert engines.first.calls == []

    def test_an_engine_that_finds_the_target_language_is_same_language(
        self, client: TestClient, people, engines,
    ):
        """Detection may be unsure on save; the engine settles it, and the
        answer is cached so the next reader does not pay for it."""
        alice, bob = people
        trip_id = _trip(client, alice["access_token"], title="Kyoto 3 jours", description=None)
        engines.first.source_lang = "fr"

        r = _translate(client, bob["access_token"], [_trip_item(trip_id, ("title",))])
        assert r.json()["items"][0]["fields"]["title"]["status"] == "same_language"
        _translate(client, bob["access_token"], [_trip_item(trip_id, ("title",))])
        assert len(engines.first.calls) == 1

    def test_one_request_carries_a_stop_and_its_annotations(self, client: TestClient, people, engines):
        alice, bob = people
        token = alice["access_token"]
        trip_id = _trip(client, token)
        stop = _write(client, token, trip_id, "POST", f"/itineraries/{trip_id}/stops", {
            "place_name": "Le Vieux-Port",
            "notes": "Arrive early, the market closes at noon on Sundays.",
        })
        note = _write(client, token, trip_id, "POST",
                      f"/itineraries/{trip_id}/stops/{stop['id']}/annotations",
                      {"type": "advice", "content": "Bring cash for the ferry, cards fail often."})

        r = _translate(client, bob["access_token"], [
            {"content_type": "stop", "content_id": stop["id"], "fields": ["notes"]},
            {"content_type": "stop_annotation", "content_id": note["id"], "fields": ["content"]},
        ])
        statuses = [item["fields"] for item in r.json()["items"]]
        assert statuses[0]["notes"]["status"] == "translated"
        assert statuses[1]["content"]["status"] == "translated"
        assert len(engines.first.calls) == 1  # one engine call for the batch

    def test_leg_notes_are_translatable(self, client: TestClient, people, engines):
        alice, bob = people
        token = alice["access_token"]
        trip_id = _trip(client, token)
        a = _write(client, token, trip_id, "POST", f"/itineraries/{trip_id}/stops", {"place_name": "A"})
        b = _write(client, token, trip_id, "POST", f"/itineraries/{trip_id}/stops", {"place_name": "B"})
        segment = _write(client, token, trip_id, "POST", f"/itineraries/{trip_id}/segments", {
            "from_stop_id": a["id"], "to_stop_id": b["id"],
            "legs": [{"position": 1, "mode": "metro",
                      "notes": "Take the green line and get off at the old town."}],
        })

        r = _translate(client, bob["access_token"], [{
            "content_type": "transport_leg", "content_id": segment["legs"][0]["id"],
            "fields": ["notes"]}])
        assert r.json()["items"][0]["fields"]["notes"]["status"] == "translated"

    def test_an_edit_makes_the_old_translation_unreachable(self, client: TestClient, people, engines):
        alice, bob = people
        token = alice["access_token"]
        trip_id = _trip(client, token)
        _translate(client, bob["access_token"], [_trip_item(trip_id, ("description",))])

        new_text = "Three busy days in the hills, with long climbs and windy viewpoints."
        _write(client, token, trip_id, "PATCH", f"/itineraries/{trip_id}", {"description": new_text})
        r = _translate(client, bob["access_token"], [_trip_item(trip_id, ("description",))])

        assert r.json()["items"][0]["fields"]["description"]["text"] == f"[fr] {new_text}"
        assert len(engines.first.calls) == 2
        assert _cached_count() == 1  # the old text's translation went with the edit


# ---------------------------------------------------------------------------
# Fallback and failure
# ---------------------------------------------------------------------------

class TestFallback:

    def test_an_engine_error_falls_through_to_the_next(self, client: TestClient, people, engines):
        alice, bob = people
        trip_id = _trip(client, alice["access_token"])
        engines.chain = [FakeTranslator("first", fail=TranslatorUnavailableError("503")),
                         FakeTranslator("second")]

        r = _translate(client, bob["access_token"], [_trip_item(trip_id)])
        assert {f["provider"] for f in r.json()["items"][0]["fields"].values()} == {"second"}

    def test_a_failed_check_falls_through_to_the_next(self, client: TestClient, people, engines):
        alice, bob = people
        description = "Book the boat ahead: https://example.com/boats"
        trip_id = _trip(client, alice["access_token"], description=description)
        engines.chain = [FakeTranslator("first", overrides={description: "Réservez le bateau."}),
                         FakeTranslator("second")]

        r = _translate(client, bob["access_token"], [_trip_item(trip_id)])
        fields = r.json()["items"][0]["fields"]
        assert fields["description"]["provider"] == "second"
        assert fields["title"]["provider"] == "first"

    def test_failures_are_answered_unavailable_and_never_cached(
        self, client: TestClient, people, engines,
    ):
        alice, bob = people
        trip_id = _trip(client, alice["access_token"])
        engines.chain = [FakeTranslator("first", fail=TranslatorUnavailableError("down"))]

        r = _translate(client, bob["access_token"], [_trip_item(trip_id)])
        fields = r.json()["items"][0]["fields"]
        assert fields["title"] == {"status": "unavailable", "text": None,
                                   "provider": None, "source_lang": None}
        assert _cached_count() == 0

        _translate(client, bob["access_token"], [_trip_item(trip_id)])
        assert len(engines.chain[0].calls) == 2  # asked again: nothing was cached

    def test_a_concurrent_insert_of_the_same_translation_is_not_an_error(
        self, client: TestClient, people, engines,
    ):
        """Two readers missing the same text at once both reach the insert; the
        second must not 500 on the unique key."""
        alice, bob = people
        trip_id = _trip(client, alice["access_token"], description=None)

        class _Racing(FakeTranslator):
            def translate(self, fields, target_lang):
                db = TestingSessionLocal()
                try:  # another request caches the same translation first
                    db.add(ContentTranslation(
                        itinerary_id=uuid.UUID(trip_id), content_type="itinerary",
                        content_id=uuid.UUID(trip_id), field="title", target_lang="fr",
                        source_hash=source_hash(TITLE), translated_text="[fr] racer",
                        provider="racer",
                    ))
                    db.commit()
                finally:
                    db.close()
                return super().translate(fields, target_lang)

        engines.chain = [_Racing("first")]
        r = _translate(client, bob["access_token"], [_trip_item(trip_id, ("title",))])
        assert r.status_code == 200, r.text
        assert r.json()["items"][0]["fields"]["title"]["status"] == "translated"
        assert _cached_count() == 1


# ---------------------------------------------------------------------------
# The request shape
# ---------------------------------------------------------------------------

class TestRequestShape:

    def test_a_language_not_offered_is_a_policy_refusal(self, client: TestClient, people, engines):
        alice, _ = people
        trip_id = _trip(client, alice["access_token"])
        r = _translate(client, alice["access_token"], [_trip_item(trip_id)], lang="it")
        assert r.status_code == 400
        assert r.json()["code"] == "translation_language_unsupported"

    @pytest.mark.parametrize("body", [
        {"target_lang": "fra", "items": [_trip_item(str(uuid.uuid4()))]},
        {"target_lang": "fr", "items": []},
        {"target_lang": "fr", "items": [{"content_type": "user",
                                         "content_id": str(uuid.uuid4()), "fields": ["bio"]}]},
        {"target_lang": "fr", "items": [{"content_type": "stop",
                                         "content_id": str(uuid.uuid4()), "fields": ["place_name"]}]},
        {"target_lang": "fr", "items": [_trip_item(str(uuid.uuid4()))] * 51},
    ], ids=["bad-lang", "no-items", "unknown-type", "place-name", "too-many"])
    def test_malformed_requests_are_422(self, client: TestClient, people, engines, body):
        alice, _ = people
        r = client.post("/translations", json=body, headers=auth_headers(alice["access_token"]))
        assert r.status_code == 422


# ---------------------------------------------------------------------------
# Access — never translate what the reader cannot see
# ---------------------------------------------------------------------------

class TestAccess:

    def _assert_not_found(self, client, token, items, engines):
        r = _translate(client, token, items)
        assert r.status_code == 200, r.text
        assert [item["status"] for item in r.json()["items"]] == ["not_found"] * len(items)
        assert all(item["fields"] == {} for item in r.json()["items"])
        assert engines.first.calls == []

    @pytest.mark.parametrize("visibility", ["only_me", "followers", "restricted"])
    def test_a_trip_the_reader_cannot_see(self, client: TestClient, people, engines, visibility):
        alice, bob = people
        trip_id = _trip(client, alice["access_token"], visibility=visibility)
        self._assert_not_found(client, bob["access_token"], [_trip_item(trip_id)], engines)

    def test_a_missing_id_looks_exactly_the_same(self, client: TestClient, people, engines):
        _, bob = people
        self._assert_not_found(client, bob["access_token"], [_trip_item(str(uuid.uuid4()))], engines)

    @pytest.mark.parametrize("blocker", ["owner", "reader"])
    def test_a_block_in_either_direction(self, client: TestClient, people, engines, blocker):
        alice, bob = people
        trip_id = _trip(client, alice["access_token"])
        if blocker == "owner":
            client.post(f"/users/{bob['user_id']}/block", headers=auth_headers(alice["access_token"]))
        else:
            client.post(f"/users/{alice['user_id']}/block", headers=auth_headers(bob["access_token"]))
        self._assert_not_found(client, bob["access_token"], [_trip_item(trip_id)], engines)

    def test_a_banned_owners_trip(self, client: TestClient, people, engines):
        alice, bob = people
        trip_id = _trip(client, alice["access_token"])
        _set(User, alice["user_id"], is_active=False)
        self._assert_not_found(client, bob["access_token"], [_trip_item(trip_id)], engines)

    def test_a_hidden_trip_even_for_its_owner(self, client: TestClient, people, engines):
        alice, _ = people
        trip_id = _trip(client, alice["access_token"])
        _set(Itinerary, trip_id, hidden_at=datetime.now(timezone.utc), moderation_status="hidden")
        self._assert_not_found(client, alice["access_token"], [_trip_item(trip_id)], engines)

    def test_a_soft_deleted_trip(self, client: TestClient, people, engines):
        alice, bob = people
        trip_id = _trip(client, alice["access_token"])
        _set(Itinerary, trip_id, deleted_at=datetime.now(timezone.utc))
        self._assert_not_found(client, bob["access_token"], [_trip_item(trip_id)], engines)

    def test_a_hidden_review_even_for_its_author(self, client: TestClient, people, engines):
        alice, bob = people
        trip_id = _trip(client, alice["access_token"])
        rating_id = _review(client, bob["access_token"], trip_id)
        _set(ItineraryRating, rating_id, moderation_status="hidden")
        self._assert_not_found(client, bob["access_token"], [
            {"content_type": "rating", "content_id": rating_id, "fields": ["note"]}], engines)

    def test_a_review_by_someone_the_reader_blocked(self, client: TestClient, people, engines):
        alice, bob = people
        carol = register_user(client, "carol", "carol@example.com")
        trip_id = _trip(client, alice["access_token"])
        rating_id = _review(client, carol["access_token"], trip_id)
        client.post(f"/users/{carol['user_id']}/block", headers=auth_headers(bob["access_token"]))
        self._assert_not_found(client, bob["access_token"], [
            {"content_type": "rating", "content_id": rating_id, "fields": ["note"]}], engines)

    def test_a_note_inside_a_private_trip(self, client: TestClient, people, engines):
        """Content is addressed by its own id; access follows it to its trip."""
        alice, bob = people
        token = alice["access_token"]
        trip_id = _trip(client, token, visibility="only_me")
        stop = _write(client, token, trip_id, "POST", f"/itineraries/{trip_id}/stops",
                      {"place_name": "Secret cove", "notes": "Only reachable at low tide."})
        note = _write(client, token, trip_id, "POST",
                      f"/itineraries/{trip_id}/stops/{stop['id']}/annotations",
                      {"type": "caution", "content": "The path floods after rain."})
        self._assert_not_found(client, bob["access_token"], [
            {"content_type": "stop", "content_id": stop["id"], "fields": ["notes"]},
            {"content_type": "stop_annotation", "content_id": note["id"], "fields": ["content"]},
        ], engines)

    def test_readable_and_unreadable_items_are_answered_separately(
        self, client: TestClient, people, engines,
    ):
        alice, bob = people
        public_id = _trip(client, alice["access_token"])
        private_id = _trip(client, alice["access_token"], visibility="only_me")

        r = _translate(client, bob["access_token"], [_trip_item(public_id), _trip_item(private_id)])
        assert [item["status"] for item in r.json()["items"]] == ["ok", "not_found"]
        assert engines.first.keys_seen and all(public_id in key for key in engines.first.keys_seen)

    def test_a_visible_review_is_translatable(self, client: TestClient, people, engines):
        alice, bob = people
        trip_id = _trip(client, alice["access_token"])
        rating_id = _review(client, bob["access_token"], trip_id)
        r = _translate(client, alice["access_token"], [
            {"content_type": "rating", "content_id": rating_id, "fields": ["note"]}])
        assert r.json()["items"][0]["fields"]["note"]["status"] == "translated"
