"""
test_password_reset.py — Password-reset flow (email link → web form).

Emails are never sent: app.services.email_service.send_email is monkeypatched
to capture the message, from which we extract the reset token.
"""

import re

import app.services.email_service as email_service_mod
from conftest import register_user


def _capture_emails(monkeypatch):
    sent = []
    monkeypatch.setattr(
        email_service_mod,
        "send_email",
        lambda to, subject, html: sent.append({"to": to, "subject": subject, "html": html}),
    )
    return sent


def _token_from(html: str) -> str:
    m = re.search(r"token=([A-Za-z0-9_-]+)", html)
    assert m, f"no token in email html: {html}"
    return m.group(1)


def test_forgot_password_sends_link_for_existing_account(client, monkeypatch):
    register_user(client, "resetme", "reset@example.com")
    sent = _capture_emails(monkeypatch)  # capture only the reset email, not registration's
    r = client.post("/auth/forgot-password", json={"email": "reset@example.com"})
    assert r.status_code == 200
    assert len(sent) == 1
    assert sent[0]["to"] == "reset@example.com"
    assert "reset-password?token=" in sent[0]["html"]


def test_forgot_password_is_enumeration_safe(client, monkeypatch):
    sent = _capture_emails(monkeypatch)
    r = client.post("/auth/forgot-password", json={"email": "nobody@example.com"})
    assert r.status_code == 200  # identical response to the existing-account case
    assert sent == []  # but nothing is actually sent


def test_reset_updates_password_and_revokes_sessions(client, monkeypatch):
    register_user(client, "changer", "change@example.com", password="oldpass123")
    sent = _capture_emails(monkeypatch)
    client.post("/auth/forgot-password", json={"email": "change@example.com"})
    token = _token_from(sent[0]["html"])

    done = client.post("/web/reset-password", data={
        "token": token, "password": "newpass456", "password_confirm": "newpass456",
    })
    assert done.status_code == 200
    assert "Password updated" in done.text

    assert client.post("/auth/login", json={
        "identifier": "change@example.com", "password": "newpass456"}).status_code == 200
    assert client.post("/auth/login", json={
        "identifier": "change@example.com", "password": "oldpass123"}).status_code == 401


def test_reset_token_is_single_use(client, monkeypatch):
    register_user(client, "single", "single@example.com")
    sent = _capture_emails(monkeypatch)
    client.post("/auth/forgot-password", json={"email": "single@example.com"})
    token = _token_from(sent[0]["html"])

    first = client.post("/web/reset-password", data={
        "token": token, "password": "newpass456", "password_confirm": "newpass456"})
    assert "Password updated" in first.text
    second = client.post("/web/reset-password", data={
        "token": token, "password": "another789", "password_confirm": "another789"})
    assert "Password updated" not in second.text  # consumed → invalid page


def test_reset_password_mismatch_shows_error(client, monkeypatch):
    register_user(client, "mism", "mism@example.com")
    sent = _capture_emails(monkeypatch)
    client.post("/auth/forgot-password", json={"email": "mism@example.com"})
    token = _token_from(sent[0]["html"])
    r = client.post("/web/reset-password", data={
        "token": token, "password": "abcd1234", "password_confirm": "different1"})
    assert "do not match" in r.text.lower()


def test_reset_with_bad_token_shows_invalid_page(client):
    r = client.post("/web/reset-password", data={
        "token": "garbage", "password": "newpass456", "password_confirm": "newpass456"})
    assert "no longer valid" in r.text.lower()


def test_google_only_account_gets_no_reset_email(client, monkeypatch):
    # A Google-only account has no password — forgot-password must not email a link.
    import app.routers.auth as auth_router
    monkeypatch.setattr(
        auth_router, "verify_google_id_token",
        lambda t: {"sub": "g-noreset", "email": "gonly@gmail.com",
                   "email_verified": True, "name": "G", "picture": None},
    )
    client.post("/auth/google", json={"id_token": "fake", "tos_accepted": True, "date_of_birth": "2000-01-01"})
    sent = _capture_emails(monkeypatch)
    r = client.post("/auth/forgot-password", json={"email": "gonly@gmail.com"})
    assert r.status_code == 200
    assert sent == []
