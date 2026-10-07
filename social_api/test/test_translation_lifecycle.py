"""
test_translation_lifecycle.py — the translation cache follows its source text.

Translations are seeded straight into content_translations, so these tests
depend only on the lifecycle rules, not on how a translation gets made:

  * every write of translatable text stamps source_lang;
  * an edit drops the translations whose source text it replaced — only those;
  * every delete takes the deleted content's translations with it, including
    content a database cascade removed underneath it (a stop's annotations, its
    segments' legs);
  * deleting a trip or an account cascades through itinerary_id, while an
    anonymised review keeps its translations, because the review is kept.
"""

import uuid

from fastapi.testclient import TestClient
from sqlalchemy import func, select

from conftest import TestingSessionLocal, auth_headers, edit_now, register_user
from app.models.content_translation import ContentTranslation
from app.models.itinerary_rating import ItineraryRating
from app.services.translation_service import source_hash

EN_TITLE = "A slow weekend walking around the old harbour"
EN_DESCRIPTION = (
    "We spent two quiet days walking along the harbour, eating fresh fish and "
    "watching the boats come in at sunset."
)
FR_DESCRIPTION = (
    "Nous avons passé deux jours tranquilles à marcher le long du port, à manger "
    "du poisson frais et à regarder les bateaux rentrer au coucher du soleil."
)
FR_NOTES = "Arrivez tôt le matin pour éviter la foule, le marché ferme à midi."
DE_ANNOTATION = "Die Fähre fährt sonntags nur zweimal, also plant genug Zeit ein."
ES_ANNOTATION = "Llevad agua y crema solar, no hay sombra en todo el camino."
IT_LEG_NOTES = "Prendete la metro verde e scendete alla fermata del centro storico."
EN_REVIEW = "Beautiful route, but the second day was far too long for children."


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _trip(client, token, *, title=EN_TITLE, description=EN_DESCRIPTION) -> str:
    r = client.post(
        "/itineraries/",
        json={"title": title, "description": description, "visibility": "public"},
        headers=auth_headers(token),
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _hdrs(client, token, itinerary_id) -> dict:
    return edit_now(client, itinerary_id, auth_headers(token))


def _stop(client, token, itinerary_id, *, notes=FR_NOTES, place_name="Le Vieux-Port") -> dict:
    r = client.post(
        f"/itineraries/{itinerary_id}/stops",
        json={"place_name": place_name, "notes": notes},
        headers=_hdrs(client, token, itinerary_id),
    )
    assert r.status_code == 201, r.text
    return r.json()


def _stop_annotation(client, token, itinerary_id, stop_id, content=DE_ANNOTATION) -> dict:
    r = client.post(
        f"/itineraries/{itinerary_id}/stops/{stop_id}/annotations",
        json={"type": "advice", "content": content},
        headers=_hdrs(client, token, itinerary_id),
    )
    assert r.status_code == 201, r.text
    return r.json()


def _trip_annotation(client, token, itinerary_id, content=ES_ANNOTATION) -> dict:
    r = client.post(
        f"/itineraries/{itinerary_id}/annotations",
        json={"type": "info", "content": content},
        headers=_hdrs(client, token, itinerary_id),
    )
    assert r.status_code == 201, r.text
    return r.json()


def _segment(client, token, itinerary_id, from_id, to_id, notes=IT_LEG_NOTES) -> dict:
    r = client.post(
        f"/itineraries/{itinerary_id}/segments",
        json={"from_stop_id": from_id, "to_stop_id": to_id,
              "legs": [{"position": 1, "mode": "metro", "notes": notes}]},
        headers=_hdrs(client, token, itinerary_id),
    )
    assert r.status_code == 201, r.text
    return r.json()


def _review(client, token, itinerary_id, note=EN_REVIEW) -> str:
    r = client.post(
        f"/itineraries/{itinerary_id}/ratings",
        json={"stars": 4, "note": note},
        headers=auth_headers(token),
    )
    assert r.status_code == 201, r.text
    db = TestingSessionLocal()
    try:
        return str(db.execute(
            select(ItineraryRating.id).where(
                ItineraryRating.itinerary_id == uuid.UUID(itinerary_id)
            ).order_by(ItineraryRating.created_at.desc())
        ).scalars().first())
    finally:
        db.close()


def _seed(itinerary_id, content_type, content_id, field, text, *, lang="fr") -> None:
    """Cache a translation of `text`: current while `text` is the field's
    present value, stale once the field holds anything else."""
    db = TestingSessionLocal()
    try:
        db.add(ContentTranslation(
            itinerary_id=uuid.UUID(itinerary_id),
            content_type=content_type,
            content_id=uuid.UUID(content_id),
            field=field,
            target_lang=lang,
            source_hash=source_hash(text),
            translated_text=f"[{lang}] {text}",
            provider="fake",
        ))
        db.commit()
    finally:
        db.close()


def _cached(content_type=None, content_id=None) -> list[str]:
    """Fields with a cached translation, optionally for one piece of content."""
    db = TestingSessionLocal()
    try:
        query = select(ContentTranslation.field)
        if content_type is not None:
            query = query.where(ContentTranslation.content_type == content_type)
        if content_id is not None:
            query = query.where(ContentTranslation.content_id == uuid.UUID(content_id))
        return sorted(db.execute(query).scalars().all())
    finally:
        db.close()


def _total() -> int:
    db = TestingSessionLocal()
    try:
        return db.execute(select(func.count(ContentTranslation.id))).scalar_one()
    finally:
        db.close()


def _detail(client, token, itinerary_id) -> dict:
    r = client.get(f"/itineraries/{itinerary_id}", headers=auth_headers(token))
    assert r.status_code == 200, r.text
    return r.json()


# ---------------------------------------------------------------------------
# source_lang is stamped on every write
# ---------------------------------------------------------------------------

class TestSourceLangIsStamped:

    def test_trip_language_is_read_from_title_and_description(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        trip_id = _trip(client, alice["access_token"])
        assert _detail(client, alice["access_token"], trip_id)["source_lang"] == "en"

    def test_rewriting_the_trip_redetects_it(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        trip_id = _trip(client, token)

        r = client.patch(
            f"/itineraries/{trip_id}",
            json={"title": "Un week-end lent autour du vieux port",
                  "description": FR_DESCRIPTION},
            headers=_hdrs(client, token, trip_id),
        )
        assert r.status_code == 200, r.text
        assert _detail(client, token, trip_id)["source_lang"] == "fr"

    def test_every_translatable_row_reports_its_language(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        bob = register_user(client, "bobby", "bob@example.com")
        token = alice["access_token"]
        trip_id = _trip(client, token)
        stop_a = _stop(client, token, trip_id)
        stop_b = _stop(client, token, trip_id, place_name="La Corniche")

        assert stop_a["source_lang"] == "fr"
        assert _stop_annotation(client, token, trip_id, stop_a["id"])["source_lang"] == "de"
        assert _trip_annotation(client, token, trip_id)["source_lang"] == "es"
        segment = _segment(client, token, trip_id, stop_a["id"], stop_b["id"])
        assert segment["legs"][0]["source_lang"] == "it"

        _review(client, bob["access_token"], trip_id)
        page = client.get(f"/itineraries/{trip_id}/ratings",
                          headers=auth_headers(bob["access_token"])).json()
        assert page["ratings"][0]["source_lang"] == "en"

    def test_a_stops_language_ignores_its_place_name(self, client: TestClient):
        """A French place name must not make English notes read as French."""
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        trip_id = _trip(client, token)
        stop = _stop(
            client, token, trip_id,
            place_name="Cathédrale Notre-Dame de la Garde",
            notes="Climb up early in the morning, the view over the whole city is worth it.",
        )
        assert stop["source_lang"] == "en"

    def test_text_that_carries_no_language_stays_null(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        trip_id = _trip(client, token)
        stop = _stop(client, token, trip_id)
        assert _stop_annotation(client, token, trip_id, stop["id"], content="👍👍")[
            "source_lang"] is None


# ---------------------------------------------------------------------------
# Edits drop the translations they outgrew — and only those
# ---------------------------------------------------------------------------

class TestEditsDropStaleTranslations:

    def test_editing_one_field_keeps_the_others(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        trip_id = _trip(client, token)
        _seed(trip_id, "itinerary", trip_id, "title", EN_TITLE)
        _seed(trip_id, "itinerary", trip_id, "description", EN_DESCRIPTION)

        r = client.patch(f"/itineraries/{trip_id}",
                         json={"description": "A different description entirely, about the hills."},
                         headers=_hdrs(client, token, trip_id))
        assert r.status_code == 200, r.text
        assert _cached("itinerary", trip_id) == ["title"]

    def test_a_translation_of_an_older_text_is_dropped_by_the_next_edit(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        trip_id = _trip(client, token)
        _seed(trip_id, "itinerary", trip_id, "description", "an older description")
        _seed(trip_id, "itinerary", trip_id, "title", EN_TITLE)

        client.patch(f"/itineraries/{trip_id}", json={"title": EN_TITLE},
                     headers=_hdrs(client, token, trip_id))
        assert _cached("itinerary", trip_id) == ["title"]

    def test_a_settings_only_edit_keeps_every_translation(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        trip_id = _trip(client, token)
        _seed(trip_id, "itinerary", trip_id, "title", EN_TITLE)

        r = client.patch(f"/itineraries/{trip_id}", json={"visibility": "followers"},
                         headers=_hdrs(client, token, trip_id))
        assert r.status_code == 200, r.text
        assert _cached("itinerary", trip_id) == ["title"]
        assert _detail(client, token, trip_id)["source_lang"] == "en"

    def test_annotation_type_change_keeps_its_translation_and_rewrite_drops_it(
        self, client: TestClient,
    ):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        trip_id = _trip(client, token)
        stop = _stop(client, token, trip_id)
        note = _stop_annotation(client, token, trip_id, stop["id"])
        _seed(trip_id, "stop_annotation", note["id"], "content", DE_ANNOTATION)
        url = f"/itineraries/{trip_id}/stops/{stop['id']}/annotations/{note['id']}"

        assert client.patch(url, json={"type": "caution"},
                            headers=_hdrs(client, token, trip_id)).status_code == 200
        assert _cached("stop_annotation", note["id"]) == ["content"]

        assert client.patch(url, json={"content": "Ganz anderer Hinweis zur Fähre am Abend."},
                            headers=_hdrs(client, token, trip_id)).status_code == 200
        assert _cached("stop_annotation", note["id"]) == []

    def test_trip_annotation_rewrite_drops_its_translation(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        trip_id = _trip(client, token)
        note = _trip_annotation(client, token, trip_id)
        _seed(trip_id, "itinerary_annotation", note["id"], "content", ES_ANNOTATION)

        r = client.patch(f"/itineraries/{trip_id}/annotations/{note['id']}",
                         json={"content": "Otra advertencia, esta vez sobre el viento."},
                         headers=_hdrs(client, token, trip_id))
        assert r.status_code == 200, r.text
        assert _cached("itinerary_annotation", note["id"]) == []

    def test_stop_notes_rewrite_drops_and_other_edits_keep(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        trip_id = _trip(client, token)
        stop = _stop(client, token, trip_id)
        _seed(trip_id, "stop", stop["id"], "notes", FR_NOTES)
        url = f"/itineraries/{trip_id}/stops/{stop['id']}"

        assert client.patch(url, json={"duration_min": 90},
                            headers=_hdrs(client, token, trip_id)).status_code == 200
        assert _cached("stop", stop["id"]) == ["notes"]

        assert client.patch(url, json={"notes": "Tout autre conseil pour cette étape."},
                            headers=_hdrs(client, token, trip_id)).status_code == 200
        assert _cached("stop", stop["id"]) == []

    def test_review_rewrite_drops_its_translation(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        bob = register_user(client, "bobby", "bob@example.com")
        trip_id = _trip(client, alice["access_token"])
        rating_id = _review(client, bob["access_token"], trip_id)
        _seed(trip_id, "rating", rating_id, "note", EN_REVIEW)

        _review(client, bob["access_token"], trip_id, note=EN_REVIEW)
        assert _cached("rating", rating_id) == ["note"]

        _review(client, bob["access_token"], trip_id, note="Changed my mind, it was great.")
        assert _cached("rating", rating_id) == []

    def test_leg_notes_rewrite_drops_its_translation(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        trip_id = _trip(client, token)
        stop_a, stop_b = _stop(client, token, trip_id), _stop(client, token, trip_id)
        segment = _segment(client, token, trip_id, stop_a["id"], stop_b["id"])
        leg_id = segment["legs"][0]["id"]
        _seed(trip_id, "transport_leg", leg_id, "notes", IT_LEG_NOTES)

        r = client.patch(f"/itineraries/{trip_id}/segments/{segment['id']}/legs/{leg_id}",
                         json={"notes": "Prendete invece l'autobus numero due."},
                         headers=_hdrs(client, token, trip_id))
        assert r.status_code == 200, r.text
        assert _cached("transport_leg", leg_id) == []


# ---------------------------------------------------------------------------
# Deletes take their translations with them
# ---------------------------------------------------------------------------

class TestDeletesTakeTheirTranslations:

    def _trip_with_everything(self, client, token):
        """A trip with two stops, notes, both annotation kinds and a segment,
        every piece carrying one cached translation."""
        trip_id = _trip(client, token)
        stop_a = _stop(client, token, trip_id)
        stop_b = _stop(client, token, trip_id, place_name="La Corniche")
        stop_note = _stop_annotation(client, token, trip_id, stop_a["id"])
        trip_note = _trip_annotation(client, token, trip_id)
        segment = _segment(client, token, trip_id, stop_a["id"], stop_b["id"])
        leg_id = segment["legs"][0]["id"]

        _seed(trip_id, "itinerary", trip_id, "title", EN_TITLE)
        _seed(trip_id, "stop", stop_a["id"], "notes", FR_NOTES)
        _seed(trip_id, "stop", stop_b["id"], "notes", FR_NOTES)
        _seed(trip_id, "stop_annotation", stop_note["id"], "content", DE_ANNOTATION)
        _seed(trip_id, "itinerary_annotation", trip_note["id"], "content", ES_ANNOTATION)
        _seed(trip_id, "transport_leg", leg_id, "notes", IT_LEG_NOTES)
        return {
            "trip": trip_id, "stop_a": stop_a["id"], "stop_b": stop_b["id"],
            "stop_note": stop_note["id"], "trip_note": trip_note["id"],
            "segment": segment["id"], "leg": leg_id,
        }

    def test_deleting_a_stop_annotation(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        ids = self._trip_with_everything(client, token)

        r = client.delete(
            f"/itineraries/{ids['trip']}/stops/{ids['stop_a']}/annotations/{ids['stop_note']}",
            headers=_hdrs(client, token, ids["trip"]),
        )
        assert r.status_code == 204, r.text
        assert _cached("stop_annotation") == []
        assert _total() == 5

    def test_deleting_a_trip_annotation(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        ids = self._trip_with_everything(client, token)

        r = client.delete(f"/itineraries/{ids['trip']}/annotations/{ids['trip_note']}",
                          headers=_hdrs(client, token, ids["trip"]))
        assert r.status_code == 204, r.text
        assert _cached("itinerary_annotation") == []
        assert _total() == 5

    def test_deleting_a_stop_takes_what_cascaded_with_it(self, client: TestClient):
        """The stop's annotations and its segment's legs are removed by the
        database; their translations must go too."""
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        ids = self._trip_with_everything(client, token)

        r = client.delete(f"/itineraries/{ids['trip']}/stops/{ids['stop_a']}",
                          headers=_hdrs(client, token, ids["trip"]))
        assert r.status_code == 204, r.text
        assert _cached("stop", ids["stop_a"]) == []
        assert _cached("stop_annotation") == []
        assert _cached("transport_leg") == []
        # Untouched: the other stop, the trip and its own annotation.
        assert _cached("stop", ids["stop_b"]) == ["notes"]
        assert _cached("itinerary") == ["title"]
        assert _cached("itinerary_annotation") == ["content"]

    def test_replacing_a_segments_legs(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        ids = self._trip_with_everything(client, token)

        r = client.patch(
            f"/itineraries/{ids['trip']}/segments/{ids['segment']}",
            json={"from_stop_id": ids["stop_a"], "to_stop_id": ids["stop_b"],
                  "legs": [{"position": 1, "mode": "bus", "notes": IT_LEG_NOTES}]},
            headers=_hdrs(client, token, ids["trip"]),
        )
        assert r.status_code == 200, r.text
        # Same words, but a new leg row: the old leg's translation has no owner.
        assert _cached("transport_leg") == []

    def test_deleting_a_segment(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        ids = self._trip_with_everything(client, token)

        r = client.delete(f"/itineraries/{ids['trip']}/segments/{ids['segment']}",
                          headers=_hdrs(client, token, ids["trip"]))
        assert r.status_code == 204, r.text
        assert _cached("transport_leg") == []
        assert _total() == 5

    def test_deleting_the_last_leg(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        ids = self._trip_with_everything(client, token)

        r = client.delete(
            f"/itineraries/{ids['trip']}/segments/{ids['segment']}/legs/{ids['leg']}",
            headers=_hdrs(client, token, ids["trip"]),
        )
        assert r.status_code == 204, r.text
        assert _cached("transport_leg") == []

    def test_reorder_that_deletes_a_segment(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        ids = self._trip_with_everything(client, token)

        r = client.post(f"/itineraries/{ids['trip']}/reorder",
                        json={"segments_to_delete": [ids["segment"]]},
                        headers=_hdrs(client, token, ids["trip"]))
        assert r.status_code == 200, r.text
        assert _cached("transport_leg") == []

    def test_deleting_a_review(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        bob = register_user(client, "bobby", "bob@example.com")
        trip_id = _trip(client, alice["access_token"])
        rating_id = _review(client, bob["access_token"], trip_id)
        _seed(trip_id, "rating", rating_id, "note", EN_REVIEW)

        r = client.delete(f"/itineraries/{trip_id}/ratings/me",
                          headers=auth_headers(bob["access_token"]))
        assert r.status_code == 204, r.text
        assert _cached("rating") == []

    def test_deleting_a_trip_cascades_and_spares_other_trips(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        ids = self._trip_with_everything(client, token)
        other_trip = _trip(client, token)
        _seed(other_trip, "itinerary", other_trip, "title", EN_TITLE)

        r = client.delete(f"/itineraries/{ids['trip']}", headers=auth_headers(token))
        assert r.status_code == 204, r.text
        assert _total() == 1
        assert _cached("itinerary", other_trip) == ["title"]

    def test_deleting_an_account_removes_its_trips_translations(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        self._trip_with_everything(client, token)

        r = client.request("DELETE", "/users/me", json={"password": "test1234"},
                           headers=auth_headers(token))
        assert r.status_code == 204, r.text
        assert _total() == 0

    def test_an_anonymised_review_keeps_its_translation(self, client: TestClient):
        """Account deletion keeps a review (author set to NULL), so the review's
        translation stays with it."""
        alice = register_user(client, "alice", "alice@example.com")
        bob = register_user(client, "bobby", "bob@example.com")
        trip_id = _trip(client, alice["access_token"])
        rating_id = _review(client, bob["access_token"], trip_id)
        _seed(trip_id, "rating", rating_id, "note", EN_REVIEW)

        r = client.request("DELETE", "/users/me", json={"password": "test1234"},
                           headers=auth_headers(bob["access_token"]))
        assert r.status_code == 204, r.text
        assert _cached("rating", rating_id) == ["note"]


# ---------------------------------------------------------------------------
# source_lang is appended, never inserted (JSON key order is the contract)
# ---------------------------------------------------------------------------

class TestSourceLangIsTheLastKey:

    def test_every_response_appends_it(self, client: TestClient):
        alice = register_user(client, "alice", "alice@example.com")
        token = alice["access_token"]
        trip_id = _trip(client, token)
        stop_a = _stop(client, token, trip_id)
        stop_b = _stop(client, token, trip_id)
        stop_note = _stop_annotation(client, token, trip_id, stop_a["id"])
        trip_note = _trip_annotation(client, token, trip_id)
        segment = _segment(client, token, trip_id, stop_a["id"], stop_b["id"])

        detail = _detail(client, token, trip_id)
        assert list(detail)[-2:] == ["can_edit", "source_lang"]
        assert list(stop_a)[-2:] == ["annotations", "source_lang"]
        assert list(stop_note)[-2:] == ["updated_at", "source_lang"]
        assert list(trip_note)[-2:] == ["updated_at", "source_lang"]
        assert list(segment["legs"][0])[-2:] == ["created_at", "source_lang"]
