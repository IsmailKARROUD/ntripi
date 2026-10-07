"""
test_translation_limits.py — what a reader and an engine may spend.

Per reader: fields that reach an engine, per clock hour (cache hits are free).
Per engine: characters per UTC day. Both are atomic conditional upserts: a
refused reservation counts nothing, and the counter can never pass its cap.
"""

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from conftest import TestingSessionLocal, register_user
from app.config import get_settings
from app.models.translation_usage import TranslationProviderUsage, TranslationUserUsage
from app.services import translation_usage
from app.services.translation_providers import TranslatorQuotaExceededError
from translation_fakes import FakeTranslator
from translation_helpers import (  # noqa: F401 — engines is a fixture
    engines, make_trip, translate, trip_item,
)

NOW = datetime(2026, 10, 7, 14, 25, tzinfo=timezone.utc)


@pytest.fixture()
def reader(client):
    return register_user(client, "reader", "reader@example.com")


# ---------------------------------------------------------------------------
# The counters themselves
# ---------------------------------------------------------------------------

class TestCounters:

    def test_a_reader_reservation_stops_exactly_at_the_limit(self, client: TestClient, reader):
        user_id = uuid.UUID(reader["user_id"])
        db = TestingSessionLocal()
        try:
            granted = [translation_usage.reserve_user_fields(db, user_id, 3, 10, NOW)
                       for _ in range(5)]
            db.commit()
            total = db.execute(select(TranslationUserUsage.fields)).scalar_one()
        finally:
            db.close()
        assert granted == [True, True, True, False, False]
        assert total == 9  # refused reservations counted nothing

    def test_a_reservation_bigger_than_the_limit_is_refused_outright(self, client: TestClient, reader):
        db = TestingSessionLocal()
        try:
            assert not translation_usage.reserve_user_fields(
                db, uuid.UUID(reader["user_id"]), 11, 10, NOW)
            assert db.execute(select(TranslationUserUsage)).first() is None
        finally:
            db.close()

    def test_a_new_hour_starts_from_zero(self, client: TestClient, reader):
        user_id = uuid.UUID(reader["user_id"])
        db = TestingSessionLocal()
        try:
            assert translation_usage.reserve_user_fields(db, user_id, 10, 10, NOW)
            assert not translation_usage.reserve_user_fields(db, user_id, 1, 10, NOW)
            assert translation_usage.reserve_user_fields(
                db, user_id, 1, 10, NOW + timedelta(hours=1))
        finally:
            db.close()

    def test_an_engine_budget_stops_exactly_at_the_cap(self, client: TestClient):
        db = TestingSessionLocal()
        try:
            granted = [translation_usage.reserve_provider_chars(db, "openai", 400, 1000, NOW.date())
                       for _ in range(3)]
            db.commit()
            chars = db.execute(select(TranslationProviderUsage.chars)).scalar_one()
        finally:
            db.close()
        assert granted == [True, True, False]
        assert chars == 800

    def test_no_budget_means_unlimited_and_unrecorded(self, client: TestClient):
        db = TestingSessionLocal()
        try:
            assert translation_usage.reserve_provider_chars(db, "fake", 10**9, None, NOW.date())
            assert db.execute(select(TranslationProviderUsage)).first() is None
        finally:
            db.close()

    def test_an_exhausted_engine_is_refused_until_tomorrow(self, client: TestClient):
        db = TestingSessionLocal()
        try:
            translation_usage.mark_provider_exhausted(db, "azure", 60_000, NOW.date())
            assert not translation_usage.reserve_provider_chars(db, "azure", 1, 60_000, NOW.date())
            assert translation_usage.reserve_provider_chars(
                db, "azure", 1, 60_000, NOW.date() + timedelta(days=1))
        finally:
            db.close()

    def test_purge_drops_only_counters_no_limit_reads(self, client: TestClient, reader):
        user_id = uuid.UUID(reader["user_id"])
        db = TestingSessionLocal()
        try:
            translation_usage.reserve_user_fields(db, user_id, 1, 10, NOW - timedelta(days=3))
            translation_usage.reserve_user_fields(db, user_id, 1, 10, NOW)
            translation_usage.reserve_provider_chars(db, "openai", 1, 10, (NOW - timedelta(days=91)).date())
            translation_usage.reserve_provider_chars(db, "openai", 1, 10, NOW.date())
            assert translation_usage.purge(db, NOW) == 2
            assert len(db.execute(select(TranslationUserUsage)).all()) == 1
            assert len(db.execute(select(TranslationProviderUsage)).all()) == 1
        finally:
            db.close()


# ---------------------------------------------------------------------------
# Through the endpoint
# ---------------------------------------------------------------------------

class TestReaderQuota:

    def test_over_the_limit_misses_are_refused_and_hits_still_served(
        self, client: TestClient, monkeypatch, reader, engines,
    ):
        monkeypatch.setattr(get_settings(), "TRANSLATION_USER_HOURLY_LIMIT", 2)
        owner = register_user(client, "owner", "owner@example.com")
        first_trip = make_trip(client, owner["access_token"])
        second_trip = make_trip(client, owner["access_token"],
                                title="Three days of hiking in the green hills",
                                description="Long climbs, windy ridges and a lake to swim in.")

        assert translate(client, reader["access_token"], [trip_item(first_trip)]).json()[
            "items"][0]["fields"]["title"]["status"] == "translated"

        refused = translate(client, reader["access_token"], [trip_item(second_trip)]).json()
        assert {f["status"] for f in refused["items"][0]["fields"].values()} == {"rate_limited"}

        again = translate(client, reader["access_token"], [trip_item(first_trip)]).json()
        assert again["items"][0]["fields"]["title"]["status"] == "translated"
        assert len(engines.first.calls) == 1  # the refusal reached no engine


class TestEngineBudgets:

    def test_a_spent_budget_hands_over_to_the_next_engine(
        self, client: TestClient, reader, engines,
    ):
        owner = register_user(client, "owner", "owner@example.com")
        trip = make_trip(client, owner["access_token"])
        engines.chain = [FakeTranslator("first", daily_char_budget=10), FakeTranslator("second")]

        r = translate(client, reader["access_token"], [trip_item(trip)])
        assert {f["provider"] for f in r.json()["items"][0]["fields"].values()} == {"second"}
        assert engines.chain[0].calls == []

    def test_every_budget_spent_leaves_the_original(self, client: TestClient, reader, engines):
        owner = register_user(client, "owner", "owner@example.com")
        trip = make_trip(client, owner["access_token"])
        engines.chain = [FakeTranslator("first", daily_char_budget=10),
                         FakeTranslator("second", daily_char_budget=10)]

        r = translate(client, reader["access_token"], [trip_item(trip)])
        assert {f["status"] for f in r.json()["items"][0]["fields"].values()} == {"unavailable"}

    def test_an_engine_out_of_quota_is_skipped_for_the_rest_of_the_day(
        self, client: TestClient, reader, engines,
    ):
        owner = register_user(client, "owner", "owner@example.com")
        trip = make_trip(client, owner["access_token"])
        other = make_trip(client, owner["access_token"], title="Another harbour walk at dawn",
                          description="Short and quiet, with coffee by the water.")
        first = FakeTranslator("first", fail=TranslatorQuotaExceededError("quota"),
                               daily_char_budget=100_000)
        engines.chain = [first, FakeTranslator("second")]

        translate(client, reader["access_token"], [trip_item(trip)])
        translate(client, reader["access_token"], [trip_item(other)])
        assert len(first.calls) == 1  # asked once, then marked spent for the day
