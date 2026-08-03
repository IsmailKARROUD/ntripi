"""
test_moderation_status_constraints.py — model/DB parity for moderation_status.

Regression guard for a silent schema drift: ck_itinerary_moderation_status was
created (b858424a1092) with the four image-moderation states and never widened
when 'hidden' arrived, while the ratings and users constraints (d3db17c28b44)
did gain it. Every automated hide of an itinerary raised CheckViolation in
Postgres — and the whole suite stayed green, because the test schema is built
from ORM metadata and the Itinerary model declared no constraint at all.

So the invariant here is not "the five strings are spelled right", it is:
every status the code can write must be permitted by every table that stores
one. The ladder is read from STATUS_SEVERITY rather than hardcoded, so adding
a sixth status fails these tests until each model is updated with it.
"""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy import CheckConstraint
from sqlalchemy.exc import IntegrityError

from conftest import TestingSessionLocal, auth_headers, register_user
from app.database import Base
from app.models.itinerary import Itinerary
from app.services.text_moderation_service import STATUS_SEVERITY


def _tables_with_status():
    return [
        table for table in Base.metadata.tables.values()
        if "moderation_status" in table.columns
    ]


def _status_check(table) -> CheckConstraint | None:
    for constraint in table.constraints:
        if isinstance(constraint, CheckConstraint) and \
                "moderation_status" in str(constraint.sqltext):
            return constraint
    return None


def test_every_status_table_declares_a_check(client):
    """A moderation_status column with no model-side CheckConstraint is exactly
    the hole this suite exists to close — SQLite would accept anything."""
    tables = _tables_with_status()
    assert tables, "no table carries moderation_status — did a model move?"

    missing = [table.name for table in tables if _status_check(table) is None]
    assert not missing, f"moderation_status with no CheckConstraint: {missing}"


@pytest.mark.parametrize("status", sorted(STATUS_SEVERITY))
def test_check_permits_every_ladder_status(client, status):
    """Any value apply_moderation_status can assign must be storable everywhere."""
    for table in _tables_with_status():
        sqltext = str(_status_check(table).sqltext)
        assert f"'{status}'" in sqltext, (
            f"{table.name} rejects '{status}', which the severity ladder can write"
        )


def test_itinerary_accepts_every_ladder_status(client):
    """The round-trip the original bug failed: 'hidden' hit the DB and raised."""
    token = register_user(client, "author", "author@example.com")["access_token"]
    response = client.post(
        "/itineraries/",
        json={"title": "A trip", "currency": "EUR", "visibility": "public"},
        headers=auth_headers(token),
    )
    assert response.status_code == 201, response.json()
    itinerary_id = uuid.UUID(response.json()["id"])

    for status in sorted(STATUS_SEVERITY):
        db = TestingSessionLocal()
        try:
            itinerary = db.get(Itinerary, itinerary_id)
            itinerary.moderation_status = status
            db.commit()
        finally:
            db.close()


def test_itinerary_rejects_an_unknown_status(client):
    """Proves the constraint is enforced here, not merely declared — otherwise
    the test above would pass against no constraint at all."""
    token = register_user(client, "author", "author@example.com")["access_token"]
    response = client.post(
        "/itineraries/",
        json={"title": "A trip", "currency": "EUR", "visibility": "public"},
        headers=auth_headers(token),
    )
    itinerary_id = uuid.UUID(response.json()["id"])

    db = TestingSessionLocal()
    try:
        itinerary = db.get(Itinerary, itinerary_id)
        itinerary.moderation_status = "quarantined"
        with pytest.raises(IntegrityError):
            db.commit()
    finally:
        db.rollback()
        db.close()
