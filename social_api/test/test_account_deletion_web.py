"""
test_account_deletion_web.py — deleting an account without the app.

The flow at /delete-account (Google Play's deletion URL): an address goes in,
a single-use link comes out by email, the page it opens says what will go, and
its button erases through the same account_service.erase_account the app uses.

  TestRequest        — the page in six languages; the same answer, and no
                       database session at all, for every address.
  TestLink           — the email, the confirm page that never spends the link,
                       the erasure, and every link that must be refused.
  TestSuspended      — warned first, then the address is blocked on both
                       sign-up paths, before any paid moderation call.
  TestDeferral       — under an open legal escalation: recorded, the operator
                       told, the requester told nothing more; the sweep erases
                       it once the escalation closes and emails the address.
  TestAdmin          — the Legal lane lists waiting deletions; a block lifts.
  TestEmailBuilder   — English output unchanged by the move; Arabic RTL.
"""

import re
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.routing import APIRoute
from markupsafe import escape
from fastapi.testclient import TestClient
from sqlalchemy import select

from app.constants.help import article
from app.i18n import SUPPORTED, TRANSLATIONS
from app.main import app
from app.models.email_token import EmailToken
from app.models.itinerary import Itinerary
from app.models.legal_escalation import LegalEscalation
from app.models.user import User
from app.services import email_service, email_token_service

from conftest import (
    ADMIN_BASIC, TestingSessionLocal, admin_session, auth_headers, make_admin,
    patch_google_verifier, register_user,
)

REQUEST = "/web/delete-account-request"
CONFIRM = "/delete-account/confirm"
ERASE = "/web/delete-account"


def _tr(key: str, lang: str = "en") -> str:
    return TRANSLATIONS[key][lang]


def _shown(key: str, lang: str = "en") -> str:
    """A translation as a page prints it — Jinja escapes `'` to &#39;."""
    return str(escape(_tr(key, lang)))


@pytest.fixture()
def outbox(monkeypatch):
    """Every email account_service sends, as (to, subject, html)."""
    sent = []
    monkeypatch.setattr(
        "app.services.email_service.send_email",
        lambda to, subject, html: sent.append((to, subject, html)),
    )
    return sent


def _link_token(html: str) -> str:
    return re.search(r"/delete-account/confirm\?token=([A-Za-z0-9_\-]+)", html).group(1)


def _request_link(client: TestClient, outbox: list, email: str, lang: str = "en") -> str:
    before = len(outbox)
    r = client.post(f"{REQUEST}?lang={lang}", data={"email": email})
    assert r.status_code == 200
    assert len(outbox) == before + 1, "no link was emailed"
    return _link_token(outbox[-1][2])


def _user(email: str) -> User | None:
    db = TestingSessionLocal()
    try:
        return db.execute(select(User).where(User.email == email)).scalar_one_or_none()
    finally:
        db.close()


def _set(email: str, **fields) -> None:
    db = TestingSessionLocal()
    try:
        user = db.execute(select(User).where(User.email == email)).scalar_one()
        for name, value in fields.items():
            setattr(user, name, value)
        db.commit()
    finally:
        db.close()


def _escalate_a_trip_of(email: str) -> uuid.UUID:
    db = TestingSessionLocal()
    try:
        owner = db.execute(select(User).where(User.email == email)).scalar_one()
        trip = Itinerary(user_id=owner.id, title="Held trip")
        db.add(trip)
        db.flush()
        escalation = LegalEscalation(target_type="itinerary", target_id=trip.id, source="report")
        db.add(escalation)
        db.commit()
        return escalation.id
    finally:
        db.close()


def _dependency_names(dependant, seen=None) -> set[str]:
    seen = set() if seen is None else seen
    for dep in dependant.dependencies:
        seen.add(getattr(dep.call, "__name__", type(dep.call).__name__))
        _dependency_names(dep, seen)
    return seen


# ---------------------------------------------------------------------------
# The request
# ---------------------------------------------------------------------------

class TestRequest:
    @pytest.mark.parametrize("lang", SUPPORTED)
    def test_the_page_speaks_every_language_and_shows_what_stays(self, client, lang):
        r = client.get(f"/delete-account?lang={lang}")
        assert r.status_code == 200
        assert _shown("delete_heading", lang) in r.text
        keeps = next(b for b in article(lang, "your-data-and-privacy").blocks
                     if b.anchor == "what-deletion-keeps")
        assert keeps.heading in r.text
        assert ('dir="rtl"' in r.text) == (lang == "ar")

    def test_the_request_route_takes_no_database_session(self):
        """The structural half of "the same timing for every address": with no
        session the route cannot look anything up before it answers."""
        route = next(r for r in app.routes
                     if isinstance(r, APIRoute) and r.path == REQUEST)
        assert "get_db" not in _dependency_names(route.dependant)

    def test_every_address_gets_the_same_answer(self, client, outbox):
        register_user(client, "known", "known@x.com")
        register_user(client, "banned", "banned@x.com")
        _set("banned@x.com", is_active=False)
        outbox.clear()  # registration's verification emails

        answers = [
            client.post(REQUEST, data={"email": address})
            for address in ("known@x.com", "banned@x.com", "nobody@x.com")
        ]

        assert {r.status_code for r in answers} == {200}
        assert len({r.text for r in answers}) == 1
        assert _shown("delete_sent_heading") in answers[0].text
        # A suspended account gets its link too; an unknown address gets nothing.
        assert sorted(to for to, _, _ in outbox) == ["banned@x.com", "known@x.com"]

    def test_an_empty_address_shows_the_form_again(self, client, outbox):
        r = client.post(REQUEST, data={"email": "   "})
        assert r.status_code == 200
        assert _shown("delete_email_required") in r.text
        assert outbox == []

    def test_the_request_is_rate_limited_with_a_page_in_the_readers_language(
        self, client, outbox,
    ):
        """A person can reach this limit; slowapi's JSON would be raw English."""
        answers = [client.post(f"{REQUEST}?lang=fr", data={"email": "x@x.com"})
                   for _ in range(6)]
        assert [r.status_code for r in answers[:5]] == [200] * 5
        limited = answers[5]
        assert limited.status_code == 429
        assert "text/html" in limited.headers["content-type"]
        assert limited.headers["retry-after"]
        assert _shown("delete_rate_limited_body", "fr") in limited.text


# ---------------------------------------------------------------------------
# The link
# ---------------------------------------------------------------------------

class TestLink:
    def test_the_email_is_in_the_page_language_and_so_is_its_link(self, client, outbox):
        register_user(client, "lena", "lena@x.com")
        token = _request_link(client, outbox, "LENA@x.com ", lang="de")

        to, subject, html = outbox[-1]
        assert to == "lena@x.com"
        assert subject == _tr("delete_email_subject", "de")
        assert f"/delete-account/confirm?token={token}&amp;lang=de" in html
        assert _tr("email_button_fallback", "de") in html

    def test_the_confirm_page_never_spends_the_link(self, client, outbox):
        register_user(client, "alice", "alice@x.com")
        token = _request_link(client, outbox, "alice@x.com")

        for _ in range(2):  # a mail scanner, then the owner
            r = client.get(f"{CONFIRM}?token={token}")
            assert r.status_code == 200
            assert "@alice" in r.text
            assert _shown("delete_confirm_button") in r.text
        assert _user("alice@x.com") is not None

    def test_the_button_erases_the_account(self, client, outbox):
        alice = register_user(client, "alice", "alice@x.com")
        token = _request_link(client, outbox, "alice@x.com")

        r = client.post(ERASE, data={"token": token})

        assert r.status_code == 200
        assert _shown("delete_done_heading") in r.text
        assert _user("alice@x.com") is None
        assert client.get("/users/me", headers=auth_headers(alice["access_token"])).status_code == 401
        # Spent: the same link again is refused, and erases nothing twice.
        again = client.post(ERASE, data={"token": token})
        assert _shown("delete_link_invalid") in again.text

    def test_a_wrong_expired_or_other_purpose_link_is_refused(self, client, outbox):
        register_user(client, "alice", "alice@x.com")
        token = _request_link(client, outbox, "alice@x.com")
        db = TestingSessionLocal()
        try:
            user = db.execute(select(User).where(User.email == "alice@x.com")).scalar_one()
            reset = email_token_service.issue(
                db, user.id, email_token_service.PURPOSE_PASSWORD_RESET, timedelta(hours=1),
            )
            row = db.execute(
                select(EmailToken).where(EmailToken.purpose == email_token_service.PURPOSE_ACCOUNT_DELETE)
            ).scalar_one()
            row.expires_at = datetime.now(timezone.utc) - timedelta(minutes=1)
            db.commit()
        finally:
            db.close()

        for bad in ("not-a-token", token, reset):  # unknown, expired, a reset link
            assert _shown("delete_link_invalid") in client.get(f"{CONFIRM}?token={bad}").text
            assert _shown("delete_link_invalid") in client.post(ERASE, data={"token": bad}).text
        assert _user("alice@x.com") is not None


# ---------------------------------------------------------------------------
# Suspended accounts
# ---------------------------------------------------------------------------

class TestSuspended:
    def test_warned_then_erased_then_blocked_on_both_sign_up_paths(self, client, outbox, monkeypatch):
        register_user(client, "banned", "banned@x.com")
        _set("banned@x.com", is_active=False)
        token = _request_link(client, outbox, "banned@x.com")

        page = client.get(f"{CONFIRM}?token={token}")
        assert _shown("delete_confirm_suspended") in page.text
        client.post(ERASE, data={"token": token})
        assert _user("banned@x.com") is None

        scans = []
        monkeypatch.setattr("app.routers.auth.moderate_or_422",
                            lambda *a, **kw: scans.append(1))
        r = client.post("/auth/register", json={
            "username": "newbie", "email": "Banned@X.com", "password": "test1234",
            "tos_accepted": True, "date_of_birth": "2000-01-01",
        })
        assert (r.status_code, r.json()["code"]) == (400, "email_unavailable")
        assert scans == []  # refused before the paid scan

        patch_google_verifier(monkeypatch, sub="g-banned", email="banned@x.com")
        # The client's first post carries no acceptance: refused there, not
        # after the consent sheet and the birthday scope have been shown.
        r = client.post("/auth/google", json={"id_token": "fake"})
        assert (r.status_code, r.json()["code"]) == (400, "email_unavailable")
        r = client.post("/auth/google", json={
            "id_token": "fake", "tos_accepted": True, "date_of_birth": "2000-01-01",
        })
        assert (r.status_code, r.json()["code"]) == (400, "email_unavailable")

    def test_an_active_accounts_address_can_sign_up_again(self, client, outbox):
        register_user(client, "leaver", "leaver@x.com")
        client.post(ERASE, data={"token": _request_link(client, outbox, "leaver@x.com")})
        register_user(client, "leaver2", "leaver@x.com")


# ---------------------------------------------------------------------------
# Under an open legal escalation
# ---------------------------------------------------------------------------

class TestDeferral:
    def test_recorded_not_erased_then_erased_by_the_sweep_once_it_closes(
        self, client, outbox, monkeypatch,
    ):
        from app.config import get_settings
        from app.services import operator_alerts, sweep_service

        settings = get_settings()
        monkeypatch.setattr(settings, "OPERATOR_EMAIL", "ops@test.com")
        operator_mail = []
        monkeypatch.setattr(operator_alerts, "send_email",
                            lambda to, subject, html: operator_mail.append((to, subject, html)))
        register_user(client, "held", "held@x.com")
        escalation_id = _escalate_a_trip_of("held@x.com")
        token = _request_link(client, outbox, "held@x.com", lang="es")

        r = client.post(f"{ERASE}?lang=es", data={"token": token})

        assert _shown("delete_deferred_heading", "es") in r.text
        for word in ("escalat", "legal", "moderat"):  # the page never says why
            assert word not in r.text.lower().split("<main")[-1]
        user = _user("held@x.com")
        assert user is not None and user.erasure_requested_at is not None
        assert user.erasure_request_lang == "es"
        [(to, subject, html)] = operator_mail
        assert to == "ops@test.com" and "held" in html

        db = TestingSessionLocal()
        try:
            assert sweep_service.run_moderation_sweep(db, settings)["deferred_erasures"] == 0
            assert _user("held@x.com") is not None
            db.get(LegalEscalation, escalation_id).closed_at = datetime.now(timezone.utc)
            db.commit()
            outbox.clear()
            assert sweep_service.run_moderation_sweep(db, settings)["deferred_erasures"] == 1
        finally:
            db.close()
        assert _user("held@x.com") is None
        [(to, subject, _)] = outbox
        assert (to, subject) == ("held@x.com", _tr("deleted_email_subject", "es"))

    def test_the_sweep_counter_is_the_last_key(self, client):
        from app.config import get_settings
        from app.services import sweep_service

        db = TestingSessionLocal()
        try:
            counters = sweep_service.run_moderation_sweep(db, get_settings())
        finally:
            db.close()
        assert list(counters)[-1] == "deferred_erasures"


# ---------------------------------------------------------------------------
# Admin
# ---------------------------------------------------------------------------

class TestAdmin:
    def _admin(self, client):
        register_user(client, "opsadmin", "ops@test.com")
        make_admin("ops@test.com")
        admin_session(client, "ops@test.com")

    def test_the_legal_lane_lists_waiting_deletions(self, client, admin_enabled, outbox):
        register_user(client, "held", "held@x.com")
        _escalate_a_trip_of("held@x.com")
        client.post(ERASE, data={"token": _request_link(client, outbox, "held@x.com")})
        self._admin(client)

        page = client.get("/admin/legal", auth=ADMIN_BASIC)

        assert page.status_code == 200
        assert "Deletion requests waiting" in page.text
        assert "held@x.com" in page.text and "Held by an open escalation" in page.text

    def test_lifting_a_block_lets_the_address_sign_up_again(self, client, admin_enabled, outbox):
        register_user(client, "banned", "banned@x.com")
        _set("banned@x.com", is_active=False)
        client.post(ERASE, data={"token": _request_link(client, outbox, "banned@x.com")})
        self._admin(client)

        r = client.post("/admin/signup-blocks/lift", data={"email": "BANNED@x.com"},
                        auth=ADMIN_BASIC, follow_redirects=False)
        assert r.status_code == 303 and "notice=" in r.headers["location"]

        register_user(client, "returned", "banned@x.com")

    def test_lifting_needs_an_admin(self, client, admin_enabled):
        r = client.post("/admin/signup-blocks/lift", data={"email": "a@x.com"},
                        auth=ADMIN_BASIC, follow_redirects=False)
        assert r.status_code in (303, 401, 403)
        assert "notice=" not in r.headers.get("location", "")


# ---------------------------------------------------------------------------
# The email builder
# ---------------------------------------------------------------------------

class TestEmailBuilder:
    # The builder's output before it moved out of auth_service and became
    # translatable — every English email still reads exactly this.
    ENGLISH = """\
<div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;max-width:480px;margin:0 auto;padding:24px;color:#1b2a22">
  <h2 style="color:#1F5E3A;margin:0 0 12px">Ntripi</h2>
  <h3 style="margin:0 0 8px">Heading</h3>
  <p style="color:#52615a;font-size:14px;margin:0 0 20px">Body.</p>
  <a href="https://ntripi.app/x" style="display:inline-block;background:#1F5E3A;color:#fff;
     text-decoration:none;font-weight:700;padding:12px 22px;border-radius:14px">Go</a>
  <p style="color:#8a9690;font-size:12px;margin:24px 0 0">
    If the button doesn't work, paste this link into your browser:<br>https://ntripi.app/x
  </p>
</div>"""

    def test_english_output_is_unchanged(self):
        assert email_service.branded_email_html(
            "Heading", "Body.", "Go", "https://ntripi.app/x",
        ) == self.ENGLISH

    def test_a_link_is_escaped_in_the_button_and_in_the_printed_line(self):
        """A raw `&lang=` is the entity `&lang;` to some mail clients: the URL
        becomes `…〈=en`, and the deletion link stops working."""
        html = email_service.branded_email_html(
            "h", "b", "g", "https://ntripi.app/x?token=abc&lang=fr",
        )
        assert html.count("https://ntripi.app/x?token=abc&amp;lang=fr") == 2
        assert "&lang" not in html

    def test_arabic_reads_right_to_left_with_its_own_fallback_line(self):
        html = email_service.branded_email_html("h", "b", "g", "https://ntripi.app/x", lang="ar")
        assert html.startswith('<div dir="rtl"')
        assert _tr("email_button_fallback", "ar") in html
