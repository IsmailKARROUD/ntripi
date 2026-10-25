"""
services/moderation_service.py — automated image moderation (AWS Rekognition).

The only upload-time scan: the client-side NSFW pre-check is the fast/free
bouncer, and Cloudflare's CSAM Scanning Tool hash-matches known material at the
edge but only once content is being *served*, so this is the last gate before
anything is stored. Runs a Rekognition `DetectModerationLabels` scan on the
*processed* JPEG bytes, after Pillow processing but before storage, so rejected
content is never written.

Three outcomes:
  - reject  — an explicit-nudity / violence / gore label ≥ REJECT_THRESHOLD.
              Image is NOT stored; the router turns ModerationRejectedError into
              a 422. The decision is still logged (committed before the raise).
  - flag    — any moderation label ≥ FLAG_THRESHOLD. Image IS stored, a log row
              is written, and the operator is emailed (best-effort).
  - approve — no labels above the flag threshold.

Graceful degradation: if the AWS call errors or times out, the upload is
ALLOWED (logged as 'error_allowed', itinerary marked 'pending') — an AWS outage
must never block legitimate users — and the operator is emailed, at most once
an hour (operator_alerts). Scanning switched on without its credentials stores
uploads unscanned too, and emails the same way.

Every operator email is built on the event loop and only sent from a worker
thread: send_email is a blocking requests.post with a 10 s timeout, and this
module runs on the loop.

Every scan opportunistically deletes log rows older than LOG_RETENTION (no cron
— same pattern as report_service.scrub_expired_ip_hashes).

Only label names + confidences are persisted, never the raw AWS response
(data minimization — cleaner to migrate providers later).
"""

from __future__ import annotations

import asyncio
import hashlib
import html
import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import TYPE_CHECKING, Any

from sqlalchemy import delete, or_
from sqlalchemy.orm import Session

from app.models.image_moderation_log import ImageModerationLog
from app.services import operator_alerts
from app.services.email_service import send_email
from app.services.share_service import absolute_storage_url

if TYPE_CHECKING:
    import uuid

    from app.config import Settings
    from app.models.user import User

logger = logging.getLogger(__name__)

# Rekognition top-level (L1) categories that trigger a hard reject. Both the
# pre-2023 and the v7 taxonomy names are listed so a taxonomy migration on AWS's
# side never silently downgrades a reject to a flag.
REJECT_CATEGORIES = frozenset({
    "Explicit Nudity",      # pre-v7 top-level
    "Explicit",             # v7 top-level (sexual activity / explicit nudity)
    "Violence",
    "Graphic Violence",
    "Visually Disturbing",  # gore, corpses, self-injury
})

# Audit rows are kept for legal defensibility, then dropped.
LOG_RETENTION = timedelta(days=90)

# The one action retention never touches (written by admin_service.csam_takedown).
PRESERVED_ACTION = "rejected_csam"


class ModerationRejectedError(Exception):
    """Raised when an image fails the hard-reject scan. Carries the matched
    labels so the caller can log/inspect them if needed."""

    def __init__(self, labels: list[dict[str, Any]]) -> None:
        self.labels = labels
        super().__init__("Image rejected by automated moderation.")


@dataclass
class ModerationContext:
    """Everything the scan needs that process_and_store doesn't have: the DB
    session for the log row, who/what is being scanned, and the storage key for
    the flag-notification email. `action` is filled in by the scan and read back
    by the router (to set itinerary.moderation_status)."""

    db: Session
    settings: "Settings"
    target_kind: str  # 'itinerary_cover' | 'avatar' | 'user_cover'
    uploader: "User"
    storage_key: str
    itinerary_id: "uuid.UUID | None" = None
    # The itinerary is being created in this request and has no row yet — the
    # audit row is linked to it by attach_itinerary after the caller's flush.
    itinerary_pending: bool = False
    action: str = field(default="approved")  # OUT param
    log: "ImageModerationLog | None" = field(default=None)  # OUT param


def is_enabled(settings: "Settings") -> bool:
    """True only when moderation is switched on AND all AWS creds are present.
    Missing creds while enabled is logged on every call so misconfiguration is
    obvious (mirrors the storage factory's fallback warning), and
    moderate_or_raise emails the operator about it once an hour."""
    if not settings.MODERATION_ENABLED:
        return False
    missing = _missing_settings(settings)
    if missing:
        logger.warning(
            "MODERATION_ENABLED=True but missing env vars: %s — skipping scans",
            ", ".join(missing),
        )
        return False
    return True


def _missing_settings(settings: "Settings") -> list[str]:
    """Names of the unset settings a scan needs — never their values."""
    return [
        name for name, value in (
            ("MODERATION_AWS_ACCESS_KEY_ID", settings.MODERATION_AWS_ACCESS_KEY_ID),
            ("MODERATION_AWS_SECRET_ACCESS_KEY", settings.MODERATION_AWS_SECRET_ACCESS_KEY),
            ("MODERATION_AWS_REGION", settings.MODERATION_AWS_REGION),
        ) if not value
    ]


# Lazy boto3 client singleton. A module global (not lru_cache) because pydantic
# Settings isn't hashable; tests monkeypatch _rekognition_client wholesale so
# this is never reached under test.
_client_singleton = None


def _rekognition_client(settings: "Settings"):
    """Lazy boto3 Rekognition client singleton. 3 s timeouts and a single
    attempt keep a slow AWS from hurting upload UX (we fail open on error)."""
    global _client_singleton
    if _client_singleton is None:
        import boto3
        from botocore.config import Config

        _client_singleton = boto3.client(
            "rekognition",
            region_name=settings.MODERATION_AWS_REGION,
            aws_access_key_id=settings.MODERATION_AWS_ACCESS_KEY_ID,
            aws_secret_access_key=settings.MODERATION_AWS_SECRET_ACCESS_KEY,
            config=Config(
                connect_timeout=3,
                read_timeout=3,
                retries={"max_attempts": 1},
            ),
        )
    return _client_singleton


async def moderate_or_raise(processed: bytes, ctx: ModerationContext) -> None:
    """Scan `processed` (the final JPEG bytes) and act on the result.

    On reject: logs 'rejected', commits (so the audit row survives the router's
    422 rollback), and raises ModerationRejectedError. On flag: logs 'flagged',
    emails the operator, sets ctx.action='flagged'. On approve: logs 'approved'.
    On AWS error: logs 'error_allowed', sets ctx.action='error_allowed', alerts
    the operator (at most hourly), returns (upload proceeds). ctx.action
    defaults to 'approved' and is left untouched when moderation is disabled —
    or switched on without its credentials, which alerts the operator too."""
    settings = ctx.settings
    if not is_enabled(settings):
        if settings.MODERATION_ENABLED:
            # Switched on but unable to run: a misconfiguration, not a choice.
            await _notify_unscanned(
                settings, "not_configured", missing=_missing_settings(settings)
            )
        return  # ctx.action stays 'approved'; no log row when disabled

    image_hash = hashlib.sha256(processed).hexdigest()

    try:
        client = _rekognition_client(settings)
        response = await asyncio.to_thread(
            client.detect_moderation_labels,
            Image={"Bytes": processed},
            MinConfidence=settings.MODERATION_FLAG_THRESHOLD,
        )
    except Exception as exc:
        # Fail open: an AWS outage/timeout must never block a legitimate upload.
        logger.exception("Rekognition scan failed — allowing upload (pending review)")
        ctx.action = "error_allowed"
        _log_decision(ctx.db, image_hash=image_hash, ctx=ctx, action="error_allowed", labels=[])
        await _notify_unscanned(settings, "scan_failed", error=exc)
        return

    raw_labels = response.get("ModerationLabels", [])
    labels = [
        {"name": lbl["Name"], "confidence": round(lbl["Confidence"], 2)}
        for lbl in raw_labels
    ]

    if _should_reject(raw_labels, settings.MODERATION_REJECT_THRESHOLD):
        ctx.action = "rejected"
        _log_decision(ctx.db, image_hash=image_hash, ctx=ctx, action="rejected", labels=labels)
        # The router raises next, rolling back its own transaction — commit the
        # audit row now so the reject is never lost.
        ctx.db.commit()
        raise ModerationRejectedError(labels)

    if labels:
        ctx.action = "flagged"
        _log_decision(ctx.db, image_hash=image_hash, ctx=ctx, action="flagged", labels=labels)
        try:
            await _notify_flagged(ctx, labels)
        except Exception:
            # A mail outage must never fail the upload the user just made.
            logger.exception("moderation flag notification email failed")
        return

    ctx.action = "approved"
    _log_decision(ctx.db, image_hash=image_hash, ctx=ctx, action="approved", labels=[])


def attach_itinerary(ctx: ModerationContext) -> None:
    """Point a create-time scan's audit row at its itinerary, once the caller
    has flushed the itinerary — the image twin of text_moderation_service's
    attach_target.

    /admin/flagged finds a cover's trip only through target_itinerary_id, so a
    flagged or unscanned cover left unlinked could be neither approved nor
    removed from the dashboard.
    """
    if ctx.log is not None and ctx.log.target_itinerary_id is None:
        ctx.log.target_itinerary_id = ctx.itinerary_id


def _should_reject(raw_labels: list[dict[str, Any]], threshold: float) -> bool:
    """True if any label whose own name or parent name is a reject category
    meets the reject-confidence threshold. Checking ParentName catches child
    labels (e.g. 'Graphic Male Nudity' under 'Explicit Nudity')."""
    for lbl in raw_labels:
        if lbl["Confidence"] < threshold:
            continue
        if lbl.get("Name") in REJECT_CATEGORIES or lbl.get("ParentName") in REJECT_CATEGORIES:
            return True
    return False


def _log_decision(
    db: Session, *, image_hash: str, ctx: ModerationContext,
    action: str, labels: list[dict[str, Any]],
) -> None:
    """Insert the audit row and opportunistically purge expired rows. The caller
    owns the commit (except the reject path, which commits explicitly)."""
    ctx.log = ImageModerationLog(
        image_hash=image_hash,
        target_kind=ctx.target_kind,
        # A reject commits this row on the spot: naming an itinerary that is not
        # inserted yet would fail that commit on the foreign key.
        target_itinerary_id=None if ctx.itinerary_pending else ctx.itinerary_id,
        uploader_user_id=ctx.uploader.id,
        action=action,
        labels=labels,
    )
    db.add(ctx.log)
    cutoff = datetime.now(timezone.utc) - LOG_RETENTION
    db.execute(delete(ImageModerationLog).where(
        ImageModerationLog.created_at < cutoff,
        # CSAM hash matches are preserved indefinitely — the image was never
        # stored, so this row and its hash are the only surviving evidence of a
        # reportable event. See docs/csam_response_runbook.md.
        ImageModerationLog.action != PRESERVED_ACTION,
        # An unreviewed queue row is the moderator queue itself; purging it left
        # the image live and quietly out of review (the text purge already keeps
        # unreviewed decisions for the same reason).
        or_(
            ImageModerationLog.reviewed_at.is_not(None),
            ImageModerationLog.action.notin_(("flagged", "error_allowed")),
        ),
    ))


async def _notify_flagged(ctx: ModerationContext, labels: list[dict[str, Any]]) -> None:
    """Email the operator about a soft-flagged image (best-effort — caller
    swallows errors). Mirrors report_service.send_report_notification: guard on
    OPERATOR_EMAIL, escape user text, ship a ready-to-paste resolution snippet.
    The body is built here, on the event loop, because it reads the uploader's
    ORM row; only the blocking send goes to a worker thread. Never throttled:
    each flag is its own item to review."""
    settings = ctx.settings
    if not settings.OPERATOR_EMAIL:
        logger.warning(
            "image flagged (%s) but OPERATOR_EMAIL is unset — email skipped",
            ctx.target_kind,
        )
        return

    image_url = absolute_storage_url(ctx.storage_key, settings)
    uploader_line = (
        f"@{html.escape(ctx.uploader.username)} ({html.escape(ctx.uploader.email)})"
    )
    labels_html = "<br>".join(
        f"{html.escape(lbl['name'])}: {lbl['confidence']}%" for lbl in labels
    ) or "—"

    if ctx.target_kind == "itinerary_cover" and ctx.itinerary_id is not None:
        dismiss_sql = (
            f"UPDATE itineraries SET moderation_status = 'approved' "
            f"WHERE id = '{ctx.itinerary_id}';"
        )
        resolution_html = (
            "<p><strong>Resolve?</strong> Dismiss (keep the image):</p>"
            f"<pre>{html.escape(dismiss_sql)}</pre>"
            "<p>Or take it down: set <code>moderation_status = 'rejected'</code> and "
            f"<code>DELETE /itineraries/{ctx.itinerary_id}/image</code>.</p>"
        )
    else:
        resolution_html = (
            "<p>This is a user profile image — remove it via the storage console "
            "or by clearing the user's avatar/cover URL if action is needed.</p>"
        )

    body = f"""\
<h2>Image flagged by automated moderation</h2>
<p><strong>Type:</strong> {html.escape(ctx.target_kind)}<br>
<strong>Uploader:</strong> {uploader_line}<br>
<a href="{html.escape(image_url)}">{html.escape(image_url)}</a></p>
<p><strong>Labels (≥ flag threshold):</strong><br>
{labels_html}</p>
<hr>
{resolution_html}
"""

    await asyncio.to_thread(
        send_email,
        settings.OPERATOR_EMAIL,
        subject=f"[Ntripi] Image flagged: {ctx.target_kind}",
        html=body,
    )


async def _notify_unscanned(
    settings: "Settings", situation: str, *,
    error: Exception | None = None, missing: list[str] | None = None,
) -> None:
    """Tell the operator uploads are being stored unscanned: a scan that raised
    ('scan_failed'), or scanning switched on without its settings
    ('not_configured'). At most one email an hour per situation
    (operator_alerts); with OPERATOR_EMAIL unset, a WARNING instead.

    Names the exception's class and the provider's error code, never its
    message: a provider's message can carry the request URL, key included. Nor
    the image, its key or its uploader — the alert is about the tier.
    """
    try:
        now = datetime.now(timezone.utc)
        if situation == "scan_failed":
            error_name = type(error).__name__
            code = _provider_error_code(error)
            described = f"{error_name} {code}" if code else error_name
            log_line = (
                f"image moderation unavailable: scan failed ({described}), "
                "uploads stored unscanned"
            )
            subject = "[Ntripi] Image moderation unavailable — uploads stored unscanned"
            flagged_url = f"{settings.share_base_url}/admin/flagged"
            code_line = (
                f"<br><strong>Provider error code:</strong> {html.escape(code)}"
                if code else ""
            )
            body = (
                "<h2>Image moderation is not running</h2>"
                "<p>An image scan failed, so uploads are being stored without one. "
                "Each is logged and waits in "
                f'<a href="{html.escape(flagged_url)}">/admin/flagged</a> as '
                "“Not scanned”. Nothing is rejected automatically until scans "
                "succeed again.</p>"
                f"<p><strong>Exception:</strong> {html.escape(error_name)}{code_line}</p>"
            )
        else:
            names = ", ".join(missing or ())
            log_line = (
                f"image moderation not configured: missing {names}, "
                "uploads stored unscanned"
            )
            subject = "[Ntripi] Image moderation not configured — uploads stored unscanned"
            body = (
                "<h2>Image moderation is switched on but cannot run</h2>"
                "<p><code>MODERATION_ENABLED</code> is True, but these settings are "
                f"missing: <code>{html.escape(names)}</code>. Uploads are stored "
                "unscanned and leave no audit row, so they do <strong>not</strong> "
                "reach /admin/flagged. Nothing is rejected automatically.</p>"
            )
        body += (
            f"<p>Detected at {html.escape(now.isoformat())} (UTC). "
            "Further notices are suppressed for one hour.</p>"
        )
        await asyncio.to_thread(
            operator_alerts.notify_operator,
            settings, f"image_moderation:{situation}",
            subject=subject, body=body, log_line=log_line,
        )
    except Exception:
        # The upload is going ahead; its alert must never be what fails it.
        logger.exception("image moderation outage alert failed (%s)", situation)


def _provider_error_code(error: Exception | None) -> str | None:
    """The provider's error code when the exception carries one in botocore's
    shape — exc.response["Error"]["Code"], e.g. 'UnrecognizedClientException'.
    Duck-typed, so swapping the provider needs no change here."""
    response = getattr(error, "response", None)
    detail = response.get("Error") if isinstance(response, dict) else None
    code = detail.get("Code") if isinstance(detail, dict) else None
    return code if isinstance(code, str) and code else None
