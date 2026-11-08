"""
test_map_links.py — a stop's map link leads to Google Maps and nowhere else.

The samples live in social_flutter/test/support/map_link_samples.json, which
the app's own test reads too: the server's is_google_maps_link and the app's
isGoogleMapsUrl answer the same way for every one of them, or one of the two
suites fails.

Coverage:
  test_a_google_maps_link_is_accepted / test_anything_else_is_refused
                    — every sample, through the check and the schema validator
  TestStopWrites    — a redirect link is refused on create and on update, and a
                      refused update leaves the stored link as it was
"""

import json
import uuid
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.schemas.itinerary import validate_google_maps_url
from app.validators.map_link import is_google_maps_link
from conftest import TestingSessionLocal, auth_headers, edit_now, register_user

API = Path(__file__).resolve().parents[1]
SAMPLES = (
    API.parent / "social_flutter" / "test" / "support" / "map_link_samples.json"
)


def _samples(kind: str) -> list[str]:
    assert SAMPLES.exists(), (
        f"{SAMPLES} is missing — the server and the app share this list, so "
        "the test runs with the whole monorepo checked out"
    )
    return [case["url"] for case in json.loads(SAMPLES.read_text("utf-8"))[kind]]


@pytest.mark.parametrize("url", _samples("accept"))
def test_a_google_maps_link_is_accepted(url):
    assert is_google_maps_link(url)
    # Stored without the blanks around it, exactly as typed otherwise.
    assert validate_google_maps_url(url) == url.strip(" \t\n\r\f\v")


@pytest.mark.parametrize("url", _samples("refuse"))
def test_anything_else_is_refused(url):
    assert not is_google_maps_link(url)
    with pytest.raises(ValueError):
        validate_google_maps_url(url)


def test_no_link_is_still_allowed():
    assert validate_google_maps_url(None) is None


class TestStopWrites:
    REDIRECT = "https://maps.google.com/url?q=https://phish.example"

    def _trip(self, client: TestClient):
        user = register_user(client, "alice", "alice@example.com")
        hdrs = auth_headers(user["access_token"])
        r = client.post("/itineraries/", json={"title": "Links", "currency": "EUR"},
                        headers=hdrs)
        assert r.status_code == 201, r.text
        return r.json()["id"], hdrs

    def test_a_redirect_link_is_refused_on_create(self, client: TestClient):
        itin_id, hdrs = self._trip(client)
        r = client.post(f"/itineraries/{itin_id}/stops",
                        json={"place_name": "Trap", "map_url": self.REDIRECT},
                        headers=edit_now(client, itin_id, hdrs))
        assert r.status_code == 422, r.text

    def test_a_refused_update_leaves_the_stored_link(self, client: TestClient):
        from app.models.stop import Stop

        itin_id, hdrs = self._trip(client)
        good = "https://maps.app.goo.gl/abc123"
        r = client.post(f"/itineraries/{itin_id}/stops",
                        json={"place_name": "Gem", "map_url": good},
                        headers=edit_now(client, itin_id, hdrs))
        assert r.status_code == 201, r.text
        stop_id = r.json()["id"]

        r = client.patch(
            f"/itineraries/{itin_id}/stops/{stop_id}",
            json={"map_url": "https://www.google.com/maps/../url?q=https://phish.example"},
            headers=edit_now(client, itin_id, hdrs),
        )
        assert r.status_code == 422, r.text

        db = TestingSessionLocal()
        try:
            assert db.get(Stop, uuid.UUID(stop_id)).map_url == good
        finally:
            db.close()
