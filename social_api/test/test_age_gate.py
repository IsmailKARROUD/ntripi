"""
Tests for the 16+ age gate on every account-creation path, plus the
re-acceptance backfill for accounts that predate it.

Dates are built relative to date.today() rather than written as literals: a
hardcoded "2010-01-01" is under 16 today and over 16 in 2027, so a literal
would turn these into tests that quietly stop testing anything.
"""

from datetime import date, timedelta

import pytest
from sqlalchemy import select

from app.models.user import User
from app.services import google_people
from app.services.age_service import MINIMUM_AGE, calculate_age, is_old_enough
from conftest import (
    TestingSessionLocal,
    auth_headers,
    patch_google_verifier,
    register_user,
)


def _dob_for_age(years: int, offset_days: int = 0) -> str:
    """A birth date making someone exactly `years` old today, shifted by
    `offset_days` (positive = younger)."""
    today = date.today()
    try:
        birthday = today.replace(year=today.year - years)
    except ValueError:  # today is 29 Feb and that year had no 29 Feb
        birthday = today.replace(year=today.year - years, day=28)
    return (birthday + timedelta(days=offset_days)).isoformat()


def _find_user(email: str) -> User | None:
    db = TestingSessionLocal()
    try:
        return db.execute(
            select(User).where(User.email == email)
        ).scalar_one_or_none()
    finally:
        db.close()


def _register(client, dob: str, username="kiduser", email="kid@x.com"):
    return client.post("/auth/register", json={
        "username": username,
        "email": email,
        "password": "test1234",
        "tos_accepted": True,
        "date_of_birth": dob,
    })


def _google(client, **extra):
    # No date by default on purpose — several tests here are precisely about
    # what happens when neither Google nor the client supplies one.
    body = {"id_token": "fake", "tos_accepted": True}
    body.update(extra)
    return client.post("/auth/google", json=body)


class TestAgeArithmetic:
    def test_leap_day_birth_has_not_aged_on_28_feb(self):
        # Born 29 Feb 2008. On 28 Feb 2024 the birthday has not happened yet.
        assert calculate_age(date(2008, 2, 29), date(2024, 2, 28)) == 15
        assert calculate_age(date(2008, 2, 29), date(2024, 3, 1)) == 16

    def test_the_birthday_itself_counts(self):
        assert is_old_enough(date(2010, 8, 8), date(2026, 8, 8)) is True
        assert is_old_enough(date(2010, 8, 9), date(2026, 8, 8)) is False


class TestPasswordSignup:
    def test_under_the_minimum_is_refused(self, client):
        r = _register(client, _dob_for_age(MINIMUM_AGE, offset_days=1))

        assert r.status_code == 400
        assert r.json()["code"] == "underage"

    def test_refusal_creates_no_account(self, client):
        _register(client, _dob_for_age(MINIMUM_AGE, offset_days=1))

        assert _find_user("kid@x.com") is None

    def test_exactly_the_minimum_is_accepted(self, client):
        r = _register(client, _dob_for_age(MINIMUM_AGE))

        assert r.status_code == 201

    def test_the_date_is_stored_with_its_source(self, client):
        _register(client, _dob_for_age(30), username="adult", email="a@x.com")

        user = _find_user("a@x.com")
        assert user.date_of_birth == date.fromisoformat(_dob_for_age(30))
        assert user.dob_source == "self"

    def test_a_missing_date_is_a_422_not_a_400(self, client):
        # Shape errors and policy refusals must stay distinguishable — the
        # client shows a field error for one and a message for the other.
        r = client.post("/auth/register", json={
            "username": "nodob", "email": "n@x.com",
            "password": "test1234", "tos_accepted": True,
        })

        assert r.status_code == 422

    def test_a_future_date_is_rejected(self, client):
        r = _register(client, (date.today() + timedelta(days=1)).isoformat())

        assert r.status_code == 422

    def test_an_implausibly_old_date_is_rejected(self, client):
        r = _register(client, "1850-01-01")

        assert r.status_code == 422

    def test_the_age_gate_runs_before_moderation(self, client, monkeypatch):
        # An underage signup must not spend a paid provider call, exactly as
        # a missing ToS flag must not.
        called = False

        def _spy(*args, **kwargs):
            nonlocal called
            called = True
            raise AssertionError("moderation must not run for an underage signup")

        monkeypatch.setattr("app.routers.auth.moderate_or_422", _spy)
        r = _register(client, _dob_for_age(MINIMUM_AGE, offset_days=1))

        assert r.status_code == 400
        assert called is False


class TestGoogleSignup:
    def test_people_api_date_wins_and_is_marked_google(self, client, monkeypatch):
        patch_google_verifier(monkeypatch, sub="g-1", email="g1@x.com")
        monkeypatch.setattr(
            google_people, "fetch_birthdate", lambda token, sub: date(1990, 5, 4)
        )

        r = _google(client, google_access_token="at", date_of_birth=_dob_for_age(20))

        assert r.status_code == 200
        user = _find_user("g1@x.com")
        assert user.date_of_birth == date(1990, 5, 4)
        assert user.dob_source == "google"

    def test_falls_back_to_the_posted_date_when_google_has_none(
        self, client, monkeypatch
    ):
        patch_google_verifier(monkeypatch, sub="g-2", email="g2@x.com")
        monkeypatch.setattr(google_people, "fetch_birthdate", lambda token, sub: None)

        r = _google(client, google_access_token="at", date_of_birth=_dob_for_age(20))

        assert r.status_code == 200
        user = _find_user("g2@x.com")
        assert user.dob_source == "self"

    def test_no_date_from_either_source_is_refused(self, client, monkeypatch):
        patch_google_verifier(monkeypatch, sub="g-3", email="g3@x.com")

        r = _google(client)

        assert r.status_code == 400
        assert r.json()["code"] == "dob_required"
        assert _find_user("g3@x.com") is None

    def test_underage_google_signup_is_refused(self, client, monkeypatch):
        patch_google_verifier(monkeypatch, sub="g-4", email="g4@x.com")

        r = _google(client, date_of_birth=_dob_for_age(MINIMUM_AGE, offset_days=1))

        assert r.status_code == 400
        assert r.json()["code"] == "underage"
        assert _find_user("g4@x.com") is None

    def test_returning_user_signs_in_without_a_date(self, client, monkeypatch):
        patch_google_verifier(monkeypatch, sub="g-5", email="g5@x.com")
        assert _google(client, date_of_birth=_dob_for_age(20)).status_code == 200

        # Second visit sends neither flag nor date — the sign-in branch must
        # not consult either, or every returning user is re-prompted forever.
        r = client.post("/auth/google", json={"id_token": "fake"})

        assert r.status_code == 200

    def test_linking_to_a_password_account_needs_no_date(self, client, monkeypatch):
        register_user(client, "linker", "linker@x.com")
        patch_google_verifier(monkeypatch, sub="g-6", email="linker@x.com")

        r = client.post("/auth/google", json={"id_token": "fake"})

        assert r.status_code == 200


class TestPeopleApiClient:
    """The People API reader itself. Every unusable answer must be None so the
    caller falls through to asking the user, never an exception."""

    class _Resp:
        def __init__(self, payload, status=200):
            self._payload = payload
            self.status_code = status

        def json(self):
            return self._payload

    def _patch(self, monkeypatch, payload, status=200):
        monkeypatch.setattr(
            google_people.requests, "get",
            lambda *a, **k: self._Resp(payload, status),
        )

    def test_reads_a_complete_date(self, monkeypatch):
        self._patch(monkeypatch, {
            "resourceName": "people/123",
            "birthdays": [{"date": {"year": 1990, "month": 5, "day": 4}}],
        })

        assert google_people.fetch_birthdate("at", "123") == date(1990, 5, 4)

    def test_a_hidden_year_is_unusable(self, monkeypatch):
        # Google publishes month and day with the year hidden for a great many
        # accounts, and that cannot answer an age question.
        self._patch(monkeypatch, {
            "resourceName": "people/123",
            "birthdays": [{"date": {"month": 5, "day": 4}}],
        })

        assert google_people.fetch_birthdate("at", "123") is None

    def test_account_source_beats_profile_source(self, monkeypatch):
        self._patch(monkeypatch, {
            "resourceName": "people/123",
            "birthdays": [
                {"date": {"year": 1980, "month": 1, "day": 1},
                 "metadata": {"source": {"type": "PROFILE"}}},
                {"date": {"year": 1990, "month": 5, "day": 4},
                 "metadata": {"source": {"type": "ACCOUNT"}}},
            ],
        })

        assert google_people.fetch_birthdate("at", "123") == date(1990, 5, 4)

    def test_a_subject_mismatch_is_ignored(self, monkeypatch):
        # The access token is a separate credential from the ID token. Without
        # this check, one account's token could claim another's birthday.
        self._patch(monkeypatch, {
            "resourceName": "people/999",
            "birthdays": [{"date": {"year": 1990, "month": 5, "day": 4}}],
        })

        assert google_people.fetch_birthdate("at", "123") is None

    def test_a_non_200_is_not_an_error(self, monkeypatch):
        self._patch(monkeypatch, {}, status=403)

        assert google_people.fetch_birthdate("at", "123") is None

    def test_a_network_failure_is_not_an_error(self, monkeypatch):
        def _boom(*a, **k):
            raise google_people.requests.RequestException("down")

        monkeypatch.setattr(google_people.requests, "get", _boom)

        assert google_people.fetch_birthdate("at", "123") is None


class TestReacceptanceBackfill:
    def _strip_dob(self, email: str):
        db = TestingSessionLocal()
        try:
            user = db.execute(select(User).where(User.email == email)).scalar_one()
            user.date_of_birth = None
            user.dob_source = None
            user.tos_accepted_version = "1.0"
            db.commit()
        finally:
            db.close()

    def test_an_account_without_one_is_refused_until_it_supplies_one(self, client):
        token = register_user(client, "olduser", "old@x.com")["access_token"]
        self._strip_dob("old@x.com")

        r = client.post("/auth/accept-tos", headers=auth_headers(token))

        assert r.status_code == 400
        assert r.json()["code"] == "dob_required"

    def test_supplying_one_stores_it_and_clears_the_gate(self, client):
        token = register_user(client, "olduser", "old@x.com")["access_token"]
        self._strip_dob("old@x.com")

        r = client.post(
            "/auth/accept-tos",
            headers=auth_headers(token),
            json={"date_of_birth": _dob_for_age(30)},
        )

        assert r.status_code == 200
        assert r.json()["tos_current"] is True
        user = _find_user("old@x.com")
        assert user.date_of_birth == date.fromisoformat(_dob_for_age(30))
        assert user.dob_source == "self"

    def test_an_underage_declaration_is_refused(self, client):
        token = register_user(client, "olduser", "old@x.com")["access_token"]
        self._strip_dob("old@x.com")

        r = client.post(
            "/auth/accept-tos",
            headers=auth_headers(token),
            json={"date_of_birth": _dob_for_age(MINIMUM_AGE, offset_days=1)},
        )

        assert r.status_code == 400
        assert r.json()["code"] == "underage"
        assert _find_user("old@x.com").date_of_birth is None

    def test_an_existing_date_is_never_overwritten(self, client):
        # It is a declaration of record. Letting someone re-declare on demand
        # would defeat the gate entirely.
        token = register_user(client, "setuser", "set@x.com")["access_token"]
        original = _find_user("set@x.com").date_of_birth

        r = client.post(
            "/auth/accept-tos",
            headers=auth_headers(token),
            json={"date_of_birth": _dob_for_age(40)},
        )

        assert r.status_code == 200
        assert _find_user("set@x.com").date_of_birth == original

    def test_a_body_less_post_still_works_for_an_account_that_has_one(self, client):
        # Clients deployed before the age gate send no body at all.
        token = register_user(client, "legacy", "legacy@x.com")["access_token"]

        r = client.post("/auth/accept-tos", headers=auth_headers(token))

        assert r.status_code == 200


class TestPrivacy:
    def test_the_owner_sees_their_own_date(self, client):
        token = register_user(client, "meuser", "me@x.com")["access_token"]

        me = client.get("/users/me", headers=auth_headers(token)).json()

        assert me["date_of_birth"] == "2000-01-01"

    def test_another_users_profile_never_carries_it(self, client):
        register_user(client, "subject", "subject@x.com")
        viewer = register_user(client, "viewer", "viewer@x.com")["access_token"]

        profile = client.get(
            "/users/subject", headers=auth_headers(viewer)
        ).json()

        assert "date_of_birth" not in profile
