"""
tests/test_follow_counter_atomicity.py — the follow counters must not lose updates.

`bump_follow_counters` used to do the arithmetic in Python:

    followed.followers_count = max(0, followed.followers_count + delta)

which reads the count into an int and writes the result back. Under READ
COMMITTED that is the textbook lost update: two people following one account at
the same moment both read N, both write N+1, and the account is permanently one
follower short. Nothing failed loudly — the count just drifted.

Simulating two real transactions needs two connections, and this suite runs on a
single shared in-memory SQLite database. But the *condition* that produces a lost
update is reproducible without concurrency: a loaded ORM object whose counter no
longer matches its row. The tests below create exactly that — write the row out
from under the session, then bump — and assert the increment landed on the
committed value rather than the stale one.

Against the Python-arithmetic version those tests fail; against the SQL-UPDATE
version they pass. That is the point: a test that only follows sequentially
passes either way and proves nothing.
"""

import uuid

import pytest
from sqlalchemy import event, select, update

from app.models.user import User
from app.services.user_service import bump_follow_counters
from conftest import TestingSessionLocal, auth_headers, register_user


@pytest.fixture()
def db(client):
    """A session on the schema the `client` fixture creates and tears down.

    These tests drive the helper directly rather than over HTTP, but they still
    need the tables, and `client` is what runs create_all/drop_all.
    """
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()


def _make_user(db, *, followers=0, following=0) -> User:
    name = f"u{uuid.uuid4().hex[:10]}"
    user = User(
        id=uuid.uuid4(),
        username=name,
        username_lower=name.lower(),
        email=f"{uuid.uuid4().hex[:10]}@x.com",
        followers_count=followers,
        following_count=following,
    )
    db.add(user)
    db.commit()
    return user


def _row_counts(db, user_id) -> tuple[int, int]:
    """Read the counters as columns, which bypasses the identity map."""
    return tuple(db.execute(
        select(User.followers_count, User.following_count)
        .where(User.id == user_id)
    ).one())


def _write_behind_the_session(db, user_id, column, value: int) -> None:
    """Set `column` on the row from a DIFFERENT session, leaving `db`'s copy stale.

    It has to be another session. `db.execute(update(...))` is an ORM-enabled
    UPDATE and synchronizes the identity map, so writing through `db` itself
    would quietly refresh the very object this test needs to leave behind — and
    the test would then pass against the Python-arithmetic version too.

    The engine is a StaticPool over one in-memory connection, so the second
    session sees the same database with its own identity map.
    """
    other = TestingSessionLocal()
    try:
        other.execute(update(User).where(User.id == user_id).values({column: value}))
        other.commit()
    finally:
        other.close()


# ---------------------------------------------------------------------------
# The lost update itself
# ---------------------------------------------------------------------------

def test_increment_applies_to_committed_value_not_the_loaded_one(db):
    user = _make_user(db, followers=5)
    assert user.followers_count == 5  # what this session has loaded

    _write_behind_the_session(db, user.id, User.followers_count, 10)

    bump_follow_counters(db, None, user, 1)
    db.commit()

    # Python arithmetic would have written max(0, 5 + 1) = 6, silently
    # discarding the follow that landed in between.
    assert _row_counts(db, user.id)[0] == 11


def test_decrement_applies_to_committed_value_not_the_loaded_one(db):
    user = _make_user(db, following=5)
    _write_behind_the_session(db, user.id, User.following_count, 10)

    bump_follow_counters(db, user, None, -1)
    db.commit()

    assert _row_counts(db, user.id)[1] == 9


def test_both_sides_bump_in_one_call(db):
    follower = _make_user(db)
    followed = _make_user(db)

    bump_follow_counters(db, follower, followed, 1)
    db.commit()

    assert _row_counts(db, follower.id)[1] == 1   # following_count
    assert _row_counts(db, followed.id)[0] == 1   # followers_count


# ---------------------------------------------------------------------------
# Invariants the SQL version still has to honour
# ---------------------------------------------------------------------------

def test_counters_never_go_negative(db):
    """The clamp is a case() expression — SQLite has no GREATEST()."""
    user = _make_user(db, followers=0, following=0)

    bump_follow_counters(db, user, user, -1)
    db.commit()

    assert _row_counts(db, user.id) == (0, 0)


def test_clamp_only_floors_and_does_not_cap(db):
    """A negative delta on a healthy count still decrements normally."""
    user = _make_user(db, followers=4)

    bump_follow_counters(db, None, user, -1)
    db.commit()

    assert _row_counts(db, user.id)[0] == 3


def test_none_counterpart_is_skipped(db):
    """Callers pass a possibly-deleted counterpart; None must be a no-op."""
    user = _make_user(db)

    bump_follow_counters(db, None, None, 1)   # must not raise
    bump_follow_counters(db, user, None, 1)
    db.commit()

    assert _row_counts(db, user.id) == (0, 1)


def test_loaded_attribute_is_refreshed_after_the_write(db):
    """The UPDATE goes around the identity map, so the helper expires it."""
    user = _make_user(db, followers=3)

    bump_follow_counters(db, None, user, 1)

    # Reading through the ORM must not serve the pre-UPDATE value.
    assert user.followers_count == 4


def test_the_increment_is_emitted_as_sql_not_a_bound_literal(db):
    """The arithmetic must reference the column, not a value computed in Python.

    This is the invariant the concurrency safety rests on, asserted directly:
    `SET followers_count = followers_count + ?` re-reads the committed row,
    `SET followers_count = ?` cannot. Statement-shape assertions are usually a
    smell, but here the shape *is* the property under test.
    """
    user = _make_user(db)
    statements: list[str] = []

    @event.listens_for(db.bind, "before_cursor_execute")
    def _capture(conn, cursor, statement, params, context, executemany):
        if statement.lstrip().upper().startswith("UPDATE USERS"):
            statements.append(" ".join(statement.split()))

    try:
        bump_follow_counters(db, None, user, 1)
    finally:
        event.remove(db.bind, "before_cursor_execute", _capture)

    assert len(statements) == 1, statements
    set_clause = statements[0].split("SET", 1)[1].split("WHERE", 1)[0]
    assert "followers_count" in set_clause, (
        f"increment was computed in Python, not SQL: {statements[0]}"
    )


# ---------------------------------------------------------------------------
# End-to-end: the counters the API actually reports
# ---------------------------------------------------------------------------

def test_follow_then_unfollow_restores_counts(client):
    a = register_user(client, "counta", "counta@x.com")
    b = register_user(client, "countb", "countb@x.com")
    # Accounts are private by default, and a pending request deliberately does
    # not move the counters — make B public so the follow is auto-accepted.
    client.patch("/users/me", headers=auth_headers(b["access_token"]),
                 json={"is_private": False})
    target = f"/users/{b['user_id']}/follow"

    # Status asserted on both calls: a wrong path 404s, and the count assertions
    # below would then pass against a follow that never happened.
    assert client.post(target, headers=auth_headers(a["access_token"])).status_code == 201
    profile = client.get("/users/me", headers=auth_headers(b["access_token"])).json()
    assert profile["followers_count"] == 1

    assert client.delete(target, headers=auth_headers(a["access_token"])).status_code == 204
    profile = client.get("/users/me", headers=auth_headers(b["access_token"])).json()
    assert profile["followers_count"] == 0
