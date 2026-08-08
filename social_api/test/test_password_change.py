"""
test_password_change.py — Authenticated in-app password change (/auth/change-password).

The HIBP breach check is disabled per-test by monkeypatching pwned_service.is_pwned
(so tests never hit the network); one test flips it on to assert the rejection.
Emails are captured via email_service.send_email like the reset-password tests.
"""

import app.services.email_service as email_service_mod
import app.services.pwned_service as pwned_mod
from conftest import register_user, auth_headers, TestingSessionLocal


def _no_pwned(monkeypatch, pwned: bool = False):
    """Force the breach check to a deterministic result (default: not breached)."""
    monkeypatch.setattr(pwned_mod, "is_pwned", lambda password: pwned)


def _capture_emails(monkeypatch):
    sent = []
    monkeypatch.setattr(
        email_service_mod,
        "send_email",
        lambda to, subject, html: sent.append({"to": to, "subject": subject, "html": html}),
    )
    return sent


def _change(client, token, current, new):
    return client.post(
        "/auth/change-password",
        json={"current_password": current, "new_password": new},
        headers=auth_headers(token),
    )


def test_change_password_happy_path_rotates_and_revokes(client, monkeypatch):
    _no_pwned(monkeypatch)
    reg = register_user(client, "changer", "changer@example.com", password="oldpass123")
    old_access, old_refresh = reg["access_token"], reg["refresh_token"]

    r = _change(client, old_access, "oldpass123", "newpass456")
    assert r.status_code == 200, r.json()
    body = r.json()
    new_refresh = body["refresh_token"]
    assert body["access_token"] and new_refresh != old_refresh

    # Old refresh token was revoked; the reissued one still works.
    assert client.post("/auth/refresh", json={"refresh_token": old_refresh}).status_code == 401
    assert client.post("/auth/refresh", json={"refresh_token": new_refresh}).status_code == 200

    # New password logs in; the old one no longer does.
    assert client.post("/auth/login", json={
        "identifier": "changer@example.com", "password": "newpass456"}).status_code == 200
    assert client.post("/auth/login", json={
        "identifier": "changer@example.com", "password": "oldpass123"}).status_code == 401


def test_change_password_wrong_current_is_403(client, monkeypatch):
    # 403, not 401 — a 401 would trip the Flutter AuthInterceptor into logging
    # the user out mid-flow. The session is valid; only the re-auth check failed.
    _no_pwned(monkeypatch)
    reg = register_user(client, "wrongcur", "wrongcur@example.com", password="oldpass123")
    r = _change(client, reg["access_token"], "notmypassword1", "newpass456")
    assert r.status_code == 403
    assert "current password" in r.json()["detail"].lower()


def test_change_password_too_short_is_422(client, monkeypatch):
    _no_pwned(monkeypatch)
    reg = register_user(client, "shortpw", "shortpw@example.com", password="oldpass123")
    r = _change(client, reg["access_token"], "oldpass123", "ab1")
    assert r.status_code == 422


def test_change_password_no_digit_is_422(client, monkeypatch):
    _no_pwned(monkeypatch)
    reg = register_user(client, "nodigit", "nodigit@example.com", password="oldpass123")
    r = _change(client, reg["access_token"], "oldpass123", "onlyletters")
    assert r.status_code == 422


def test_change_password_reuse_of_current_is_400(client, monkeypatch):
    _no_pwned(monkeypatch)
    reg = register_user(client, "reusecur", "reusecur@example.com", password="oldpass123")
    r = _change(client, reg["access_token"], "oldpass123", "oldpass123")
    assert r.status_code == 400
    assert "reuse" in r.json()["detail"].lower()


def test_change_password_reuse_of_history_is_400(client, monkeypatch):
    _no_pwned(monkeypatch)
    reg = register_user(client, "reusehist", "reusehist@example.com", password="oldpass123")
    token = reg["access_token"]

    first = _change(client, token, "oldpass123", "newpass456")
    assert first.status_code == 200
    token = first.json()["access_token"]

    # Trying to cycle back to the very first password must be rejected.
    r = _change(client, token, "newpass456", "oldpass123")
    assert r.status_code == 400
    assert "reuse" in r.json()["detail"].lower()


def test_change_password_breached_is_400(client, monkeypatch):
    _no_pwned(monkeypatch, pwned=True)  # pretend HIBP flags the new password
    reg = register_user(client, "breached", "breached@example.com", password="oldpass123")
    r = _change(client, reg["access_token"], "oldpass123", "newpass456")
    assert r.status_code == 400
    assert "breach" in r.json()["detail"].lower()


def test_change_password_google_only_account_is_400(client, monkeypatch):
    _no_pwned(monkeypatch)
    import app.routers.auth as auth_router
    monkeypatch.setattr(
        auth_router, "verify_google_id_token",
        lambda t: {"sub": "g-nochange", "email": "gonly@gmail.com",
                   "email_verified": True, "name": "G", "picture": None},
    )
    g = client.post("/auth/google", json={"id_token": "fake", "tos_accepted": True, "date_of_birth": "2000-01-01"})
    token = g.json()["access_token"]
    r = _change(client, token, "anything1", "newpass456")
    assert r.status_code == 400
    assert "no password" in r.json()["detail"].lower()


def test_change_password_sends_confirmation_email(client, monkeypatch):
    _no_pwned(monkeypatch)
    reg = register_user(client, "mailer", "mailer@example.com", password="oldpass123")
    sent = _capture_emails(monkeypatch)  # capture only the confirmation, not registration's
    r = _change(client, reg["access_token"], "oldpass123", "newpass456")
    assert r.status_code == 200
    assert len(sent) == 1
    assert sent[0]["to"] == "mailer@example.com"
    assert "changed" in sent[0]["subject"].lower()
    # "Secure your account" must deep-link into the Flutter web app (/app/, hash
    # routing) — a bare /forgot-password is served by neither backend nor SPA.
    assert "/app/#/forgot-password" in sent[0]["html"]


def test_change_password_writes_audit_rows(client, monkeypatch):
    _no_pwned(monkeypatch)
    reg = register_user(client, "auditor", "auditor@example.com", password="oldpass123")
    user_id = reg["user_id"]
    token = reg["access_token"]

    _change(client, token, "wrongpass1", "newpass456")  # failed → one audit row
    _change(client, token, "oldpass123", "newpass456")  # success → another row

    import uuid
    from app.models.security_audit_log import SecurityAuditLog
    db = TestingSessionLocal()
    try:
        events = {
            e.event_type
            for e in db.query(SecurityAuditLog)
            .filter(SecurityAuditLog.user_id == uuid.UUID(user_id))
            .all()
        }
    finally:
        db.close()
    assert "password_change_failed" in events
    assert "password_change" in events


def test_change_password_requires_auth(client):
    r = client.post(
        "/auth/change-password",
        json={"current_password": "x", "new_password": "newpass456"},
    )
    assert r.status_code in (401, 403)


def test_me_exposes_has_password(client, monkeypatch):
    _no_pwned(monkeypatch)
    reg = register_user(client, "haspw", "haspw@example.com", password="oldpass123")
    me = client.get("/users/me", headers=auth_headers(reg["access_token"]))
    assert me.status_code == 200
    assert me.json()["has_password"] is True
