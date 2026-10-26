"""
services/push_service.py — Deliver a notification to a device via FCM HTTP v1.

Push is a LATENCY IMPROVEMENT over the client's 60 s badge poll, never a
replacement for it. FCM delivery is best-effort: OEM battery managers kill
background processes, iOS throttles, tokens go stale silently. The poller is
what makes the feed eventually correct; this makes it fast.

ZERO NEW DEPENDENCIES. FCM HTTP v1 wants an OAuth2 bearer token from a service
account, which is exactly what `google-auth` mints — and that is already
installed for Google Sign-In. So this is a `requests.post` like every other
outbound call here, not an SDK. The key's parsing and token cache live in
google_service_account, shared with Cloud Vision image moderation.

FAILS OPEN, like email_service and unlike jira_service: nobody is standing in
front of a dashboard waiting for this, and a Google outage must never 500 a
user's follow or save. Every failure is logged and swallowed.

THE CALL IS BLOCKING, AND THAT IS CORRECT — it runs on the push worker below,
never on the event loop and never inside a request. Until 2026-10-22 it ran in
the request's own thread, between its commit and its response, so every follow,
rating or save that notified someone waited on FCM (one timeout at worst).
"""

from __future__ import annotations

import contextvars
import logging
import uuid
from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import dataclass
from enum import Enum
from typing import TYPE_CHECKING, Any

from sqlalchemy import event, select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.constants import push_i18n
from app.database import SessionLocal
from app.models.device_token import DeviceToken
from app.services import google_service_account

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


def validate_credentials(settings: "Settings") -> None:
    """Log — never raise — if push is configured but the key cannot be used.

    Same rule as is_enabled()'s partial config: push is a best-effort side
    channel and a bad paste must not cost the whole deploy. But it must not be
    silent either; unconfigured push is invisible by design, and without this
    the first sign of broken push is a traceback under someone's first follow.
    """
    if not is_enabled(settings):
        return
    google_service_account.validate(
        "FCM_SERVICE_ACCOUNT_JSON", settings.FCM_SERVICE_ACCOUNT_JSON,
        consequence="push is off", log=logger,
    )


def _access_token(settings: "Settings") -> str | None:
    """A bearer token for the FCM API, minted from the service account and
    reused until it expires. None on any failure — the caller fails open."""
    try:
        return google_service_account.access_token(
            "FCM_SERVICE_ACCOUNT_JSON", settings.FCM_SERVICE_ACCOUNT_JSON, _SCOPE
        )
    except Exception:
        # Bad JSON, a revoked key, no network. Logged once per send attempt;
        # the helper dropped the credentials, so the next notification retries
        # from scratch.
        logger.exception("Could not mint an FCM access token")
        return None


def send(db: Session, push: PendingPush, settings: "Settings") -> None:
    """Deliver one notification to every device the recipient has registered.

    `db` is a session of the caller's choosing — the push worker hands it its
    own, never the request's, so the token pruning below can commit.
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
            # One worker sends every push in turn, so a stalled FCM holds up
            # everyone's notifications queued behind this one. If FCM did not
            # answer for one device it will not answer for the next: stopping
            # here bounds that at ONE timeout instead of one per device.
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
# Push is queued AFTER COMMIT and never from inside notify(). notify() adds its
# row to the caller's transaction and does not commit, so sending from there
# would push for transactions that later roll back — and a push, unlike a row,
# cannot be rolled back. The listener below is what makes "the event actually
# happened" the precondition for telling anyone about it.
#
# It then hands the batch to ONE background worker, so no request waits on FCM.
# One thread keeps sends in order and bounds what FCM costs the process: a
# stalled send delays the pushes behind it, never a user's write.
#
# Swappable so tests can hand the dispatcher a session bound to their SQLite
# fixture instead of the real engine.
_session_factory = SessionLocal

_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="push")


def _submit(fn, *args) -> Future:
    """Run `fn(*args)` on the push worker. In an empty context: the request that
    queued it has finished, so its request-timing record must not count a send
    it no longer waits for. Tests swap this to run inline."""
    return _executor.submit(contextvars.Context().run, fn, *args)


def _send_batch(pending: list[PendingPush], settings: "Settings") -> None:
    """Send one commit's pushes, on the worker. Logs, never raises."""
    try:
        # A SEPARATE session, deliberately. Pruning a dead token needs a commit,
        # and the request's session is not this thread's to use.
        own = _session_factory()
        try:
            for push in pending:
                send(own, push, settings)
        finally:
            own.close()
    except Exception:
        logger.exception("Push dispatch failed")


@event.listens_for(Session, "after_commit")
def _dispatch_pending_pushes(session: Session) -> None:
    """Drain whatever notify() queued on this session and hand it to the push
    worker."""
    # Popped first, and unconditionally: a send that raises must not leave the
    # queue in place for the next commit on this session to send twice.
    pending: list[PendingPush] = session.info.pop(PENDING_KEY, None) or []
    if not pending:
        return

    try:
        settings = get_settings()
        if not is_enabled(settings):
            return
        _submit(_send_batch, pending, settings)
    except Exception:
        # An exception escaping after_commit would surface as a 500 on a write
        # that already succeeded — the worst possible outcome for a best-effort
        # side channel. (A submit fails only while the process is shutting down.)
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

    404/UNREGISTERED is the uninstall case; 400/INVALID_ARGUMENT naming the
    token means the string is not one we can ever deliver to. Anything else —
    a payload error, a 500 — must NOT cost the user their registration.
    """
    if resp.status_code not in (400, 404):
        return False
    try:
        error = resp.json().get("error", {})
    except Exception:
        return False
    details = [d for d in error.get("details", []) if isinstance(d, dict)]
    codes = {error.get("status")} | {d.get("errorCode") for d in details}
    if "UNREGISTERED" in codes:
        return True
    if "INVALID_ARGUMENT" not in codes:
        return False
    # FCM answers INVALID_ARGUMENT for a malformed PAYLOAD too — pruning on the
    # code alone would unregister every device of every recipient over a bug of
    # ours. Only an error that names the token says the token itself is bad.
    names_token = any(
        violation.get("field") == "message.token"
        for detail in details
        for violation in detail.get("fieldViolations", [])
        if isinstance(violation, dict)
    )
    return names_token or "registration token" in (error.get("message") or "").lower()
