"""
test_email_verification.py — Email-verification flow (register → email link →
verified) + resend. Emails are captured, never sent.
"""

import re

import app.services.email_service as email_service_mod
from conftest import register_user, auth_headers


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


def _register_unverified(client, username, email):
    # Register directly (NOT the verified conftest helper) → user stays unverified.
    r = client.post("/auth/register", json={
        "username": username, "email": email, "password": "test1234", "tos_accepted": True, "date_of_birth": "2000-01-01"})
    assert r.status_code == 201, r.json()
    return r.json()


def test_register_sends_verification_email(client, monkeypatch):
    sent = _capture_emails(monkeypatch)
    _register_unverified(client, "verifyme", "verify@example.com")
    assert len(sent) == 1
    assert sent[0]["to"] == "verify@example.com"
    assert "verify-email?token=" in sent[0]["html"]


def test_verify_link_marks_verified_and_unlocks_gate(client, monkeypatch):
    sent = _capture_emails(monkeypatch)
    reg = _register_unverified(client, "gateuser", "gate@example.com")
    token = _token_from(sent[0]["html"])

    # Unverified → gated action blocked.
    blocked = client.post("/itineraries/", json={"title": "T", "visibility": "public"},
                          headers=auth_headers(reg["access_token"]))
    assert blocked.status_code == 403

    page = client.get(f"/verify-email?token={token}")
    assert page.status_code == 200
    assert "verified" in page.text.lower()

    # Now allowed.
    ok = client.post("/itineraries/", json={"title": "T", "visibility": "public"},
                     headers=auth_headers(reg["access_token"]))
    assert ok.status_code == 201


def test_verify_token_is_single_use(client, monkeypatch):
    sent = _capture_emails(monkeypatch)
    _register_unverified(client, "once", "once@example.com")
    token = _token_from(sent[0]["html"])
    assert "verified" in client.get(f"/verify-email?token={token}").text.lower()
    assert "verified" not in client.get(f"/verify-email?token={token}").text.lower()


def test_verify_with_bad_token_shows_invalid_page(client):
    r = client.get("/verify-email?token=garbage")
    assert r.status_code == 200
    assert "no longer valid" in r.text.lower()


def test_resend_verification_sends_a_new_link(client, monkeypatch):
    sent = _capture_emails(monkeypatch)
    reg = _register_unverified(client, "resend", "resend@example.com")
    sent.clear()  # drop the registration email
    r = client.post("/auth/resend-verification", headers=auth_headers(reg["access_token"]))
    assert r.status_code == 200
    assert len(sent) == 1
    assert "verify-email?token=" in sent[0]["html"]


def test_resend_is_noop_when_already_verified(client, monkeypatch):
    sent = _capture_emails(monkeypatch)
    reg = register_user(client, "already", "already@example.com")  # verified via helper
    sent.clear()
    r = client.post("/auth/resend-verification", headers=auth_headers(reg["access_token"]))
    assert r.status_code == 200
    assert sent == []  # already verified → nothing sent
