"""
test_push.py — Tests for FCM push delivery.

The interesting behaviour is not "does it POST" — it is everything around the
POST: that a push is queued inside the transaction but only sent once that
transaction commits, that a rollback sends nothing, that the three notify()
suppression rules govern push exactly as they govern the feed row, and that a
dead token is pruned while a transient failure never costs a working device its
registration.

No live FCM: requests.post is monkeypatched everywhere. is_enabled() is False
by default (no FCM_* in the test env), so every test that wants a send has to
turn it on explicitly — which is also the "disabled changes nothing" test.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from conftest import TestingSessionLocal, auth_headers, register_user
from app.config import Settings
from app.constants import push_i18n
from app.models.device_token import DeviceToken
from app.models.notification import Notification
from app.services import notification_service, push_service


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _settings(**overrides) -> Settings:
    """A Settings with push switched on."""
    base = {
        "SECRET_KEY": "x" * 32,
        "FCM_PROJECT_ID": "test-project",
        "FCM_SERVICE_ACCOUNT_JSON": '{"type":"service_account"}',
    }
    base.update(overrides)
    return Settings(**base)


class _Resp:
    """Minimal stand-in for a requests.Response."""

    def __init__(self, status_code: int, payload: dict | None = None):
        self.status_code = status_code
        self._payload = payload or {}
        self.text = str(self._payload)

    def json(self) -> dict:
        return self._payload


def _enable(monkeypatch) -> None:
    """Turn push on for the code paths that read settings for themselves, and
    point the dispatcher at the test session factory so its own session sees
    the SQLite fixture rather than the real engine."""
    monkeypatch.setattr("app.services.notification_service.get_settings", _settings)
    monkeypatch.setattr("app.services.push_service.get_settings", _settings)
    monkeypatch.setattr(push_service, "_session_factory", TestingSessionLocal)


def _capture(monkeypatch) -> list[dict]:
    """Record request bodies; answer 200 to everything."""
    bodies: list[dict] = []

    def fake_post(url, json=None, headers=None, timeout=None):
        bodies.append(json)
        return _Resp(200, {})

    monkeypatch.setattr("requests.post", fake_post)
    # A real bearer needs a real service account; the transport is what we test.
    monkeypatch.setattr(push_service, "_access_token", lambda settings: "tok")
    return bodies


def _register(client, token: str, *, device="dev-1", locale="en") -> None:
    r = client.post(
        "/devices",
        json={"token": device, "platform": "android", "locale": locale},
        headers=auth_headers(token),
    )
    assert r.status_code == 204, r.text


def _tokens() -> list[DeviceToken]:
    db = TestingSessionLocal()
    try:
        return db.query(DeviceToken).all()
    finally:
        db.close()


def _uid(user: dict) -> uuid.UUID:
    return uuid.UUID(user["user_id"])


def _push(user_id: uuid.UUID, **overrides) -> push_service.PendingPush:
    """A PendingPush with sane defaults; each test names only what it cares
    about."""
    fields = {
        "user_id": user_id,
        "type": "new_follower",
        "subtype": None,
        "actor_id": None,
        "actor_name": "Alice",
        "entity_type": None,
        "entity_id": None,
        "entity_title": None,
    }
    fields.update(overrides)
    return push_service.PendingPush(**fields)


def _seed_device(user_id: uuid.UUID, token: str, locale: str = "en") -> None:
    """Insert a token directly. `user_id` must be a real user — the SQLite
    fixture enforces foreign keys, same as production."""
    db = TestingSessionLocal()
    try:
        db.add(
            DeviceToken(
                user_id=user_id, token=token, platform="ios", locale=locale
            )
        )
        db.commit()
    finally:
        db.close()


def _send(push: push_service.PendingPush) -> list[DeviceToken]:
    """Run one send and return the tokens that survived it."""
    db = TestingSessionLocal()
    try:
        push_service.send(db, push, _settings())
        return db.query(DeviceToken).all()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

def test_register_is_idempotent_and_refreshes_last_seen(client: TestClient):
    user = register_user(client, "regg", "reg@x.com")
    _register(client, user["access_token"])
    first = _tokens()[0].last_seen_at

    _register(client, user["access_token"])
    rows = _tokens()
    assert len(rows) == 1, "re-registering must update, not duplicate"
    assert rows[0].last_seen_at >= first


def test_registering_a_token_that_moved_accounts_reassigns_it(client: TestClient):
    """The whole reason `token` is UNIQUE: two people sharing a phone must not
    leave the first one receiving the second one's notifications."""
    alice = register_user(client, "alice", "alice@x.com")
    bobb = register_user(client, "bobb", "bob@x.com")

    _register(client, alice["access_token"], device="shared")
    _register(client, bobb["access_token"], device="shared")

    rows = _tokens()
    assert len(rows) == 1
    assert rows[0].user_id == _uid(bobb)


def test_locale_is_normalised_on_the_way_in(client: TestClient):
    user = register_user(client, "locl", "loc@x.com")
    _register(client, user["access_token"], locale="fr-CA")
    assert _tokens()[0].locale == "fr"

    _register(client, user["access_token"], locale="klingon")
    assert _tokens()[0].locale == "en", "junk degrades, never 422s"


def test_unknown_platform_is_422(client: TestClient):
    user = register_user(client, "plat", "plat@x.com")
    r = client.post(
        "/devices",
        json={"token": "t", "platform": "windows", "locale": "en"},
        headers=auth_headers(user["access_token"]),
    )
    assert r.status_code == 422


def test_unregister_is_idempotent_and_scoped(client: TestClient):
    alice = register_user(client, "aausr", "a2@x.com")
    bobb = register_user(client, "bbusr", "b2@x.com")
    _register(client, alice["access_token"], device="alice-dev")

    # Bob cannot delete Alice's token, and gets the same 204 a missing one gets
    # — another user's token is indistinguishable from one already gone.
    r = client.delete("/devices/alice-dev", headers=auth_headers(bobb["access_token"]))
    assert r.status_code == 204
    assert len(_tokens()) == 1

    r = client.delete("/devices/alice-dev", headers=auth_headers(alice["access_token"]))
    assert r.status_code == 204
    assert _tokens() == []

    # Already gone — still 204, never 404.
    r = client.delete("/devices/alice-dev", headers=auth_headers(alice["access_token"]))
    assert r.status_code == 204


def test_register_requires_auth(client: TestClient):
    r = client.post("/devices", json={"token": "t", "platform": "ios"})
    assert r.status_code in (401, 403)


# ---------------------------------------------------------------------------
# is_enabled
# ---------------------------------------------------------------------------

def test_disabled_by_default_and_partial_config_is_off():
    assert push_service.is_enabled(Settings(SECRET_KEY="x" * 32)) is False
    # Partial config is OFF, not a startup error — but it logs which var is
    # missing, because it is almost certainly a typo.
    partial = Settings(SECRET_KEY="x" * 32, FCM_PROJECT_ID="p")
    assert push_service.is_enabled(partial) is False
    assert push_service.is_enabled(_settings()) is True


# ---------------------------------------------------------------------------
# Queueing and the commit boundary
# ---------------------------------------------------------------------------

def test_nothing_is_queued_while_push_is_disabled(client: TestClient):
    """The default path: no FCM config, so notify() never even builds a
    snapshot and the feed behaves exactly as it did before push existed."""
    register_user(client, "qone", "q1@x.com")
    register_user(client, "qtwo", "q2@x.com")

    db = TestingSessionLocal()
    try:
        from app.models.user import User

        actor = db.query(User).filter(User.email == "q1@x.com").one()
        recipient = db.query(User).filter(User.email == "q2@x.com").one()
        notification_service.notify(
            db, user_id=recipient.id, type="new_follower", actor=actor
        )
        assert push_service.PENDING_KEY not in db.info
        db.rollback()
    finally:
        db.close()


def test_queued_push_is_sent_only_after_commit(monkeypatch, client: TestClient):
    alice = register_user(client, "cone", "c1@x.com")
    bobb = register_user(client, "ctwo", "c2@x.com")
    _register(client, bobb["access_token"], device="bob-dev")

    _enable(monkeypatch)
    sent = _capture(monkeypatch)

    db = TestingSessionLocal()
    try:
        from app.models.user import User

        actor = db.query(User).filter(User.email == "c1@x.com").one()
        recipient = db.query(User).filter(User.email == "c2@x.com").one()
        notification_service.notify(
            db, user_id=recipient.id, type="new_follower", actor=actor
        )
        assert len(db.info[push_service.PENDING_KEY]) == 1
        assert sent == [], "queued, not sent — the transaction is still open"

        db.commit()
    finally:
        db.close()

    assert len(sent) == 1
    message = sent[0]["message"]
    assert message["token"] == "bob-dev"
    assert message["notification"]["title"] == "@cone started following you"
    assert message["data"]["type"] == "new_follower"


def test_rollback_sends_nothing(monkeypatch, client: TestClient):
    """A push cannot be un-sent, so the event actually happening is the
    precondition for telling anyone about it."""
    register_user(client, "rone", "r1@x.com")
    bobb = register_user(client, "rtwo", "r2@x.com")
    _register(client, bobb["access_token"], device="bob-dev")

    _enable(monkeypatch)
    sent = _capture(monkeypatch)

    db = TestingSessionLocal()
    try:
        from app.models.user import User

        actor = db.query(User).filter(User.email == "r1@x.com").one()
        recipient = db.query(User).filter(User.email == "r2@x.com").one()
        notification_service.notify(
            db, user_id=recipient.id, type="new_follower", actor=actor
        )
        db.rollback()
        # The stale snapshot must not ride out on whatever commits next.
        db.commit()
    finally:
        db.close()

    assert sent == []


def test_a_muted_type_pushes_nothing(monkeypatch, client: TestClient):
    """Push inherits the suppression rules for free by hanging off notify()."""
    owner = register_user(client, "mown", "m1@x.com")
    saver = register_user(client, "msav", "m2@x.com")
    _register(client, owner["access_token"], device="owner-dev")

    r = client.patch(
        "/users/me",
        json={"notify_saves": False},
        headers=auth_headers(owner["access_token"]),
    )
    assert r.status_code == 200

    _enable(monkeypatch)
    sent = _capture(monkeypatch)

    itinerary = client.post(
        "/itineraries/",
        json={"title": "Trip", "visibility": "public"},
        headers=auth_headers(owner["access_token"]),
    ).json()
    r = client.post(
        f"/itineraries/{itinerary['id']}/save",
        headers=auth_headers(saver["access_token"]),
    )
    assert r.status_code in (200, 201, 204), r.text

    assert sent == []
    db = TestingSessionLocal()
    try:
        assert db.query(Notification).count() == 0
    finally:
        db.close()


def test_a_save_pushes_with_the_itinerary_title(monkeypatch, client: TestClient):
    """End-to-end through a real endpoint: the title is resolved inside the
    transaction, so the tray entry can name the itinerary."""
    owner = register_user(client, "sown", "s1@x.com")
    saver = register_user(client, "ssav", "s2@x.com")
    _register(client, owner["access_token"], device="owner-dev")

    _enable(monkeypatch)
    sent = _capture(monkeypatch)

    itinerary = client.post(
        "/itineraries/",
        json={"title": "Kyoto in spring", "visibility": "public"},
        headers=auth_headers(owner["access_token"]),
    ).json()
    r = client.post(
        f"/itineraries/{itinerary['id']}/save",
        headers=auth_headers(saver["access_token"]),
    )
    assert r.status_code in (200, 201, 204), r.text

    assert len(sent) == 1, sent
    notification = sent[0]["message"]["notification"]
    assert notification["title"] == "@ssav saved one of your itineraries"
    assert notification["body"] == "Kyoto in spring"


def test_a_user_with_no_device_costs_no_request(monkeypatch, client: TestClient):
    alice = register_user(client, "nodv", "n1@x.com")
    bobb = register_user(client, "ntwo", "n2@x.com")

    _enable(monkeypatch)
    sent = _capture(monkeypatch)

    client.post(
        f"/users/{bobb['user_id']}/follow",
        headers=auth_headers(alice["access_token"]),
    )
    assert sent == []


# ---------------------------------------------------------------------------
# Token pruning
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "response",
    [
        _Resp(404, {"error": {"status": "UNREGISTERED"}}),
        _Resp(400, {"error": {"details": [{"errorCode": "INVALID_ARGUMENT"}]}}),
    ],
)
def test_a_dead_token_is_pruned(monkeypatch, client: TestClient, response):
    user = register_user(client, "dead", "dead@x.com")
    _seed_device(_uid(user), "doomed")

    monkeypatch.setattr(push_service, "_access_token", lambda settings: "tok")
    monkeypatch.setattr("requests.post", lambda *a, **k: response)

    assert _send(_push(_uid(user))) == []


@pytest.mark.parametrize(
    "response",
    [
        _Resp(500, {"error": {"status": "INTERNAL"}}),
        _Resp(503, {}),
        _Resp(401, {"error": {"status": "UNAUTHENTICATED"}}),
    ],
)
def test_a_transient_failure_keeps_the_token(
    monkeypatch, client: TestClient, response
):
    """A 500, or a misconfigured key, must never cost a working device its
    registration — that would be unrecoverable without a reinstall."""
    user = register_user(client, "keep", "keep@x.com")
    _seed_device(_uid(user), "survivor")

    monkeypatch.setattr(push_service, "_access_token", lambda settings: "tok")
    monkeypatch.setattr("requests.post", lambda *a, **k: response)

    assert len(_send(_push(_uid(user)))) == 1


def test_a_network_error_keeps_the_token_and_does_not_raise(
    monkeypatch, client: TestClient
):
    user = register_user(client, "netw", "net@x.com")
    _seed_device(_uid(user), "survivor")

    monkeypatch.setattr(push_service, "_access_token", lambda settings: "tok")

    def boom(*a, **k):
        raise OSError("no route to host")

    monkeypatch.setattr("requests.post", boom)

    assert len(_send(_push(_uid(user)))) == 1


def test_an_unreachable_fcm_abandons_the_rest_of_the_devices(
    monkeypatch, client: TestClient
):
    """This runs inline in the user's request. If FCM did not answer for the
    first device it will not answer for the third, and waiting out a timeout
    per device is how a follow ends up taking 15 seconds."""
    user = register_user(client, "many", "many@x.com")
    for i in range(3):
        _seed_device(_uid(user), "device-$i".replace("$i", str(i)))

    attempts: list[int] = []

    def boom(*a, **k):
        attempts.append(1)
        raise OSError("timed out")

    monkeypatch.setattr(push_service, "_access_token", lambda settings: "tok")
    monkeypatch.setattr("requests.post", boom)

    survivors = _send(_push(_uid(user)))
    assert len(attempts) == 1, "stopped after the first unreachable device"
    assert len(survivors) == 3, "and nobody lost their registration"


def test_a_transient_http_failure_still_tries_the_other_devices(
    monkeypatch, client: TestClient
):
    """A 500 came FROM FCM, so it is reachable — the next device may well
    succeed and must still be attempted."""
    user = register_user(client, "mixd", "mixd@x.com")
    for i in range(3):
        _seed_device(_uid(user), "device-$i".replace("$i", str(i)))

    attempts: list[int] = []

    def five_hundred(*a, **k):
        attempts.append(1)
        return _Resp(500, {"error": {"status": "INTERNAL"}})

    monkeypatch.setattr(push_service, "_access_token", lambda settings: "tok")
    monkeypatch.setattr("requests.post", five_hundred)

    assert len(_send(_push(_uid(user)))) == 3
    assert len(attempts) == 3


def test_a_missing_access_token_sends_nothing_and_does_not_raise(
    monkeypatch, client: TestClient
):
    """A bad service-account key fails open, like every other outbound call
    here — the badge poll still corrects the client within a minute."""
    user = register_user(client, "nokey", "nokey@x.com")
    _seed_device(_uid(user), "device")

    monkeypatch.setattr(push_service, "_access_token", lambda settings: None)
    posted: list = []
    monkeypatch.setattr("requests.post", lambda *a, **k: posted.append(1))

    assert len(_send(_push(_uid(user)))) == 1
    assert posted == []


# ---------------------------------------------------------------------------
# Payload
# ---------------------------------------------------------------------------

def test_moderation_push_names_no_reporter_and_no_reason(
    monkeypatch, client: TestClient
):
    """The tray entry is visible on a lock screen. It may say that something
    was hidden, and nothing about who reported it or why."""
    user = register_user(client, "modu", "mod@x.com")
    _seed_device(_uid(user), "device")
    sent = _capture(monkeypatch)

    _send(
        _push(
            _uid(user),
            type="moderation_action",
            subtype="auto_hide_reports",
            actor_name=None,
            entity_type="itinerary",
            entity_id=uuid.uuid4(),
            entity_title="Kyoto in spring",
        )
    )

    message = sent[0]["message"]
    # Only title and body are ever drawn on a lock screen; `data` is invisible.
    visible = message["notification"]
    assert visible["title"] == "“Kyoto in spring” was hidden"
    assert visible["body"] == "Tap for details and to appeal"
    assert "report" not in str(visible).lower()
    assert "reason" not in str(visible).lower()
    # No actor at all: naming the reporter to the author would out them.
    assert "actor_id" not in message["data"]


def test_every_data_value_is_a_string(monkeypatch, client: TestClient):
    """FCM v1 rejects a non-string data value outright."""
    user = register_user(client, "datu", "dat@x.com")
    _seed_device(_uid(user), "device")
    sent = _capture(monkeypatch)

    _send(
        _push(
            _uid(user),
            type="itinerary_saved",
            actor_id=uuid.uuid4(),
            entity_type="itinerary",
            entity_id=uuid.uuid4(),
            entity_title="Trip",
        )
    )

    data = sent[0]["message"]["data"]
    assert data, "the client routes the tap on this"
    assert all(isinstance(v, str) for v in data.values())
    assert set(data) == {"type", "entity_type", "entity_id", "actor_id"}


def test_body_is_rendered_per_device_locale(monkeypatch, client: TestClient):
    """One account, two devices, two languages — which is exactly why locale
    lives on the token row rather than on users."""
    user = register_user(client, "poly", "poly@x.com")
    _seed_device(_uid(user), "fr-device", locale="fr")
    _seed_device(_uid(user), "ar-device", locale="ar")
    sent = _capture(monkeypatch)

    _send(_push(_uid(user)))

    titles = {c["message"]["notification"]["title"] for c in sent}
    assert titles == {"Alice s'est abonné(e) à vous", "بدأ Alice بمتابعتك"}


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

def test_render_falls_back_to_english_for_an_unknown_language():
    title, _ = push_i18n.render(
        type="new_follower", subtype=None, actor_name="A",
        entity_title=None, locale="pt",
    )
    assert title == "A started following you"


def test_render_uses_someone_when_the_actor_name_is_hidden():
    """A moderated display name must not reappear in a tray notification."""
    title, _ = push_i18n.render(
        type="new_follower", subtype=None, actor_name=None,
        entity_title=None, locale="es",
    )
    assert title == "Alguien empezó a seguirte"


def test_a_warning_does_not_render_as_a_takedown():
    """Branch order is load-bearing — 'warn' carries no entity title and would
    otherwise fall through to the hide wording."""
    title, body = push_i18n.render(
        type="moderation_action", subtype="warn", actor_name=None,
        entity_title=None, locale="en",
    )
    assert title == "You've received a moderation warning"
    assert body == "Tap to see why and to appeal"


def test_a_deleted_itinerary_renders_the_untitled_variant():
    title, _ = push_i18n.render(
        type="moderation_action", subtype="delete", actor_name=None,
        entity_title=None, locale="en",
    )
    assert title == "One of your itineraries was removed"


def test_an_unknown_type_still_renders_something():
    """A newer backend must never produce an empty tray entry."""
    title, body = push_i18n.render(
        type="something_new", subtype=None, actor_name=None,
        entity_title=None, locale="en",
    )
    assert title == "You have a new notification."
    assert body is None


# ---------------------------------------------------------------------------
# Retention
# ---------------------------------------------------------------------------

def test_the_sweep_purges_tokens_that_stopped_checking_in(client: TestClient):
    from app.services import sweep_service

    user = register_user(client, "swep", "sw@x.com")
    _register(client, user["access_token"], device="stale")
    _register(client, user["access_token"], device="fresh")

    settings = _settings()
    db = TestingSessionLocal()
    try:
        stale = db.query(DeviceToken).filter(DeviceToken.token == "stale").one()
        stale.last_seen_at = datetime.now(timezone.utc) - timedelta(
            days=settings.DEVICE_TOKEN_RETENTION_DAYS + 1
        )
        db.commit()

        counters: dict = {}
        sweep_service._purge(db, settings, counters)
        db.commit()
        assert counters["device_tokens_purged"] == 1
    finally:
        db.close()

    assert [t.token for t in _tokens()] == ["fresh"]


def test_deleting_the_account_takes_its_tokens(client: TestClient):
    """CASCADE: a deleted account must stop receiving push immediately, not at
    the next sweep."""
    user = register_user(client, "delu", "del@x.com")
    _register(client, user["access_token"], device="doomed")

    r = client.request(
        "DELETE",
        "/users/me",
        json={"password": "test1234"},
        headers=auth_headers(user["access_token"]),
    )
    assert r.status_code == 204, r.text
    assert _tokens() == []
