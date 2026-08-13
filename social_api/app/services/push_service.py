"""
services/push_service.py — Deliver a notification to a device via FCM HTTP v1.

Push is a LATENCY IMPROVEMENT over the client's 60 s badge poll, never a
replacement for it. FCM delivery is best-effort: OEM battery managers kill
background processes, iOS throttles, tokens go stale silently. The poller is
what makes the feed eventually correct; this makes it fast.

ZERO NEW DEPENDENCIES. FCM HTTP v1 wants an OAuth2 bearer token from a service
account, which is exactly what `google-auth` mints — and that is already
installed for Google Sign-In. So this is a `requests.post` like every other
outbound call here, not an SDK.

FAILS OPEN, like email_service and unlike jira_service: nobody is standing in
front of a dashboard waiting for this, and a Google outage must never 500 a
user's follow or save. Every failure is logged and swallowed.

THE CALL IS BLOCKING, AND THAT IS CORRECT — same reasoning as
text_moderation_providers: every write path is a sync `def` endpoint that
FastAPI runs in a threadpool, so a blocking call with a timeout never touches
the event loop. Making this async would force those endpoints to `async def`
and put the sync SQLAlchemy session on the loop, which is the actual hazard.
"""

from __future__ import annotations

import json
import logging
import threading
import uuid
from dataclasses import dataclass
from enum import Enum
from typing import TYPE_CHECKING, Any

from sqlalchemy import event, select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.constants import push_i18n
from app.database import SessionLocal
from app.models.device_token import DeviceToken

if TYPE_CHECKING:
    from app.config import Settings

logger = logging.getLogger(__name__)

# The key notify() stashes PendingPush snapshots under, on the request's own
# Session.info. Nothing else may write it.
PENDING_KEY = "pending_pushes"

_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_SEND_URL = "https://fcm.googleapis.com/v1/projects/{project}/messages:send"

# FCM's answer when the app was uninstalled or the token was replaced. Either
# way the row is dead and keeping it wastes a request on every future send.
_DEAD_TOKEN_CODES = {"UNREGISTERED", "INVALID_ARGUMENT"}

# google-auth caches the access token on the Credentials object and knows its
# own expiry (~1 h), so this is refreshed rarely. Guarded because after_commit
# runs on whichever threadpool thread served the request.
_creds_lock = threading.Lock()
_creds: Any = None


@dataclass(frozen=True)
class PendingPush:
    """Everything needed to render and address one push, captured while the
    transaction is still open.

    A snapshot rather than the ORM row on purpose: after commit the row's
    attributes are expired, and touching one would fire a lazy reload on a
    session that is between transactions. Resolving it up front also means the
    dispatcher never queries anything but device_tokens.
    """

    user_id: uuid.UUID
    type: str
    subtype: str | None
    # Carried separately from actor_name: the name renders the sentence, the id
    # is what the client taps through to (/profile/{id} on follow rows).
    actor_id: uuid.UUID | None
    actor_name: str | None
    entity_type: str | None
    entity_id: uuid.UUID | None
    entity_title: str | None


def is_enabled(settings: "Settings") -> bool:
    """True when push is fully configured. A partial config is OFF rather than
    a startup error — same "unset = invisible" rule as JIRA_* and ADMIN_BASIC_*
    — but the gap is named, because it is almost certainly a typo."""
    required = {
        "FCM_PROJECT_ID": settings.FCM_PROJECT_ID,
        "FCM_SERVICE_ACCOUNT_JSON": settings.FCM_SERVICE_ACCOUNT_JSON,
    }
    missing = [name for name, value in required.items() if not value]
    if missing and len(missing) < len(required):
        logger.warning(
            "Push notifications disabled — missing env vars: %s",
            ", ".join(missing),
        )
    return not missing


def _access_token(settings: "Settings") -> str | None:
    """A bearer token for the FCM API, minted from the service account and
    reused until it expires. None on any failure — the caller fails open."""
    global _creds
    try:
        from google.auth.transport.requests import Request
        from google.oauth2 import service_account

        with _creds_lock:
            if _creds is None:
                info = json.loads(settings.FCM_SERVICE_ACCOUNT_JSON or "{}")
                _creds = service_account.Credentials.from_service_account_info(
                    info, scopes=[_SCOPE]
                )
            # `valid` is False both before the first refresh and after expiry.
            if not _creds.valid:
                _creds.refresh(Request())
            return _creds.token
    except Exception:
        # Bad JSON, a revoked key, no network. Logged once per send attempt;
        # the next notification retries from scratch.
        logger.exception("Could not mint an FCM access token")
        with _creds_lock:
            _creds = None  # force a clean rebuild rather than reusing a bad one
        return None


def send(db: Session, push: PendingPush, settings: "Settings") -> None:
    """Deliver one notification to every device the recipient has registered.

    `db` is a session of the caller's choosing — the dispatcher hands it a
    fresh one rather than the request's, so the token pruning below can commit
    without re-entering the after_commit hook that called us.
    """
    if not is_enabled(settings):
        return

    tokens = db.execute(
        select(DeviceToken).where(DeviceToken.user_id == push.user_id)
    ).scalars().all()
    if not tokens:
        return

    bearer = _access_token(settings)
    if bearer is None:
        return

    url = _SEND_URL.format(project=settings.FCM_PROJECT_ID)
    dead: list[DeviceToken] = []

    for device in tokens:
        title, body = push_i18n.render(
            type=push.type,
            subtype=push.subtype,
            actor_name=push.actor_name,
            entity_title=push.entity_title,
            locale=device.locale,
        )
        outcome = _post(url, bearer, device, title, body, push, settings)
        if outcome is _Outcome.dead:
            dead.append(device)
        elif outcome is _Outcome.unreachable:
            # This whole call runs inline in the user's request, between their
            # commit and their response. If FCM did not answer for one device it
            # will not answer for the next, so stopping here bounds the delay at
            # ONE timeout instead of one per registered device.
            logger.warning("FCM unreachable — abandoning this notification")
            break

    if dead:
        for device in dead:
            db.delete(device)
        db.commit()
        logger.info("Pruned %d dead FCM token(s)", len(dead))


class _Outcome(Enum):
    """What one send attempt tells us to do next."""

    sent = "sent"
    # This token will never work again — delete the row.
    dead = "dead"
    # FCM answered, but with something transient (500, 401, a rate limit). The
    # device keeps its registration; the badge poll covers the miss.
    failed = "failed"
    # FCM did not answer at all. Says nothing about this device, but everything
    # about whether the next one is worth waiting for.
    unreachable = "unreachable"


def _post(
    url: str,
    bearer: str,
    device: DeviceToken,
    title: str,
    body: str | None,
    push: PendingPush,
    settings: "Settings",
) -> _Outcome:
    """Send to one device. Only `dead` may cost a device its registration — a
    network blip or a 500 must never, since that is unrecoverable without a
    reinstall."""
    notification: dict[str, str] = {"title": title}
    if body:
        notification["body"] = body

    payload = {
        "message": {
            "token": device.token,
            "notification": notification,
            # Every value must be a string — FCM v1 rejects a non-string data
            # value outright. This is what the client routes the tap on.
            "data": {
                k: str(v)
                for k, v in {
                    "type": push.type,
                    "subtype": push.subtype,
                    "entity_type": push.entity_type,
                    "entity_id": push.entity_id,
                    # Null on moderation rows, deliberately: naming the
                    # reporter to the author would out them.
                    "actor_id": push.actor_id,
                }.items()
                if v is not None
            },
            "android": {"priority": "high"},
            # `sound` is what makes iOS actually alert rather than deliver
            # silently; the badge count is deliberately not set here, since the
            # server would have to recount on every send to keep it honest.
            "apns": {"payload": {"aps": {"sound": "default"}}},
        }
    }

    try:
        import requests  # local import: only this path needs it

        resp = requests.post(
            url,
            json=payload,
            headers={"Authorization": f"Bearer {bearer}"},
            timeout=settings.FCM_TIMEOUT_SECONDS,
        )
    except Exception as exc:
        # Fail open — see the module docstring. The badge poll still corrects
        # the client within a minute.
        logger.warning("FCM request failed: %r", exc)
        return _Outcome.unreachable

    if resp.status_code == 200:
        return _Outcome.sent

    if _is_dead_token(resp):
        logger.info("FCM reports a dead token (HTTP %s)", resp.status_code)
        return _Outcome.dead

    # 401/403 is a config problem (wrong project, key revoked, API not
    # enabled) and will repeat on every send until someone looks at it.
    logger.error("FCM returned HTTP %s: %s", resp.status_code, resp.text[:500])
    return _Outcome.failed


# ── Dispatch ────────────────────────────────────────────────────────────────
#
# Push is sent AFTER COMMIT and never from inside notify(). notify() adds its
# row to the caller's transaction and does not commit, so sending from there
# would push for transactions that later roll back — and a push, unlike a row,
# cannot be rolled back. The listener below is what makes "the event actually
# happened" the precondition for telling anyone about it.
#
# Swappable so tests can hand the dispatcher a session bound to their SQLite
# fixture instead of the real engine.
_session_factory = SessionLocal


@event.listens_for(Session, "after_commit")
def _dispatch_pending_pushes(session: Session) -> None:
    """Drain and send whatever notify() queued on this session."""
    # Popped first, and unconditionally: a send that raises must not leave the
    # queue in place for the next commit on this session to send twice.
    pending: list[PendingPush] = session.info.pop(PENDING_KEY, None) or []
    if not pending:
        return

    try:
        settings = get_settings()
        if not is_enabled(settings):
            return
        # A SEPARATE session, deliberately. Pruning a dead token needs a commit,
        # and committing on `session` here would re-enter this very listener.
        # It also keeps a push failure from touching the request's transaction.
        own = _session_factory()
        try:
            for push in pending:
                send(own, push, settings)
        finally:
            own.close()
    except Exception:
        # An exception escaping after_commit would surface as a 500 on a write
        # that already succeeded — the worst possible outcome for a best-effort
        # side channel.
        logger.exception("Push dispatch failed")


@event.listens_for(Session, "after_soft_rollback")
def _drop_pending_pushes(session: Session, previous_transaction: Any) -> None:
    """A rolled-back transaction notified nobody, so nothing may be sent.

    Without this the snapshots would sit on the session and go out with
    whatever commits next — announcing an event that never happened.
    """
    session.info.pop(PENDING_KEY, None)


def _is_dead_token(resp: Any) -> bool:
    """True when FCM says this specific registration token is gone.

    404/UNREGISTERED is the uninstall case; 400/INVALID_ARGUMENT means the
    string is not a token we can ever deliver to. Anything else — including a
    500 — is transient and must NOT cost the user their registration.
    """
    if resp.status_code not in (400, 404):
        return False
    try:
        error = resp.json().get("error", {})
    except Exception:
        return False
    if error.get("status") in _DEAD_TOKEN_CODES:
        return True
    return any(
        detail.get("errorCode") in _DEAD_TOKEN_CODES
        for detail in error.get("details", [])
        if isinstance(detail, dict)
    )
