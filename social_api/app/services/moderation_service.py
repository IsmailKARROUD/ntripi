"""
services/moderation_service.py — automated image moderation.

The only upload-time scan: the client-side NSFW pre-check is the fast/free
bouncer, and Cloudflare's CSAM Scanning Tool hash-matches known material at the
edge but only once content is being *served*, so this is the last gate before
anything is stored. Scans the *processed* JPEG bytes, after Pillow processing
but before storage, so rejected content is never written.

Two providers, and MODERATION_PROVIDER picks one: AWS Rekognition
`DetectModerationLabels` (the default) or Google Cloud Vision SafeSearch, called
in the EU. Each sits behind one seam (_PROVIDERS) that returns a verdict or
raises, so everything after the call is shared.

Three outcomes:
  - reject  — an explicit-nudity / violence / gore signal at the reject level.
              Image is NOT stored; the router turns ModerationRejectedError into
              a 422. The decision is still logged (committed before the raise).
  - flag    — any moderation signal at the flag level. Image IS stored, a log
              row is written, and the operator is emailed (best-effort).
  - approve — nothing at the flag level.

Graceful degradation: if the provider call errors, times out, or answers with
anything that is not a verdict, the upload is ALLOWED (logged as
'error_allowed', itinerary marked 'pending') — a provider outage must never
block legitimate users, and an answer we cannot read is never an approval — and
the operator is emailed, at most once an hour (operator_alerts). Scanning
switched on without the selected provider's settings stores uploads unscanned
too, and emails the same way.

Every operator email is built on the event loop and only sent from a worker
thread: send_email is a blocking requests.post with a 10 s timeout, and this
module runs on the loop.

Every scan opportunistically deletes log rows older than LOG_RETENTION (no cron
— same pattern as report_service.scrub_expired_ip_hashes).

Only what reached the flag level is persisted — a label name with Rekognition's
confidence or Cloud Vision's likelihood — never the raw provider response (data
minimization).
"""

from __future__ import annotations

import asyncio
import base64
import hashlib
import html
import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import TYPE_CHECKING, Any, Awaitable, Callable

import requests
from sqlalchemy import delete, or_
from sqlalchemy.orm import Session

from app.config import GOOGLE_LIKELIHOODS
from app.models.image_moderation_log import ImageModerationLog
from app.services import google_service_account, operator_alerts
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

# Cloud Vision's regional endpoint. With `parent` naming the eu location, Google
# stores and processes the image only in the EU.
_VISION_URL = "https://eu-vision.googleapis.com/v1/images:annotate"
_VISION_SCOPE = "https://www.googleapis.com/auth/cloud-vision"
# Rekognition's budget: 3 s to connect, 3 s to read, and requests never retries.
_VISION_TIMEOUT = (3, 3)
# The SafeSearch categories that can reject, and the wider set that can flag.
# `spoof` is never read: it detects edited images and memes, not harm.
_VISION_REJECT_CATEGORIES = ("adult", "violence")
_VISION_FLAG_CATEGORIES = ("adult", "violence", "racy", "medical")

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


class VisionAnswerError(Exception):
    """Cloud Vision answered, but not with a SafeSearch verdict we can act on —
    a failed scan, never an approval."""


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
    """True only when moderation is switched on AND the selected provider's
    settings are all present. Missing settings while enabled are logged on every
    call so misconfiguration is obvious (mirrors the storage factory's fallback
    warning), and moderate_or_raise emails the operator about it once an hour."""
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
    """Names of the unset settings the selected provider needs — never their
    values."""
    return [
        name for name in _PROVIDERS[settings.MODERATION_PROVIDER].settings
        if not getattr(settings, name)
    ]


def validate_credentials(settings: "Settings") -> None:
    """Log — never raise — at startup if Cloud Vision is selected but its key
    cannot be used. Same stance as push_service.validate_credentials: a bad
    paste must not cost the deploy, and must not wait for the first upload to
    surface. An unset key is the 'not_configured' alert's job, not this one's.
    """
    if (
        settings.MODERATION_PROVIDER != "google_vision"
        or not settings.MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON
    ):
        return
    google_service_account.validate(
        "MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON",
        settings.MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON,
        consequence="every image scan will fail", log=logger,
        # `parent` names the key's own project, so no project_id, no request.
        required=google_service_account.REQUIRED_FIELDS + ("project_id",),
    )


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


@dataclass(frozen=True)
class _Verdict:
    """What one scan decided. `labels` is what reached the flag level, in the
    provider's own terms."""

    action: str  # 'rejected' | 'flagged' | 'approved'
    labels: list[dict[str, Any]]


async def _scan_rekognition(processed: bytes, settings: "Settings") -> _Verdict:
    """Rekognition DetectModerationLabels. Asking only for labels at the flag
    threshold makes any label a flag; REJECT_CATEGORIES decide a reject."""
    client = _rekognition_client(settings)
    response = await asyncio.to_thread(
        client.detect_moderation_labels,
        Image={"Bytes": processed},
        MinConfidence=settings.MODERATION_FLAG_THRESHOLD,
    )
    raw_labels = response.get("ModerationLabels", [])
    labels = [
        {"name": lbl["Name"], "confidence": round(lbl["Confidence"], 2)}
        for lbl in raw_labels
    ]
    if _should_reject(raw_labels, settings.MODERATION_REJECT_THRESHOLD):
        return _Verdict("rejected", labels)
    return _Verdict("flagged" if labels else "approved", labels)


def _vision_access_token(settings: "Settings") -> str:
    """A Cloud Vision bearer from the moderation key — never FCM's. Raises on
    any failure, which fails the scan open. Bounded like the scan: the mint runs
    inside an upload, about once an hour."""
    return google_service_account.access_token(
        "MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON",
        settings.MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON,
        _VISION_SCOPE, timeout=_VISION_TIMEOUT,
    )


def _vision_safe_search(processed: bytes, settings: "Settings") -> dict[str, Any]:
    """Ask Cloud Vision's EU endpoint for SafeSearch on `processed` and return
    the image's safeSearchAnnotation. Blocking — the caller hands it to
    asyncio.to_thread. Raises on every answer that is not one: a non-2xx
    status, a body that is not JSON, a per-image error, no annotation."""
    project_id = google_service_account.parse(
        settings.MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON
    ).get("project_id")
    if not project_id:
        raise ValueError("MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON has no project_id")
    token = _vision_access_token(settings)

    response = requests.post(
        _VISION_URL,
        # The image, the feature and where to process it — nothing else: no
        # user, no email, no storage key, no URL (the text providers' rule).
        json={
            "requests": [{
                "image": {"content": base64.b64encode(processed).decode("ascii")},
                "features": [{"type": "SAFE_SEARCH_DETECTION"}],
            }],
            "parent": f"projects/{project_id}/locations/eu",
        },
        headers={"Authorization": f"Bearer {token}"},
        timeout=_VISION_TIMEOUT,
    )
    if not 200 <= response.status_code < 300:
        # _provider_error_code reads Google's status and reason off the body;
        # its message, which names the project, is never repeated.
        raise requests.HTTPError(
            f"Cloud Vision answered HTTP {response.status_code}", response=response
        )
    body = response.json()
    answers = body.get("responses") if isinstance(body, dict) else None
    first = answers[0] if isinstance(answers, list) and answers else None
    if not isinstance(first, dict):
        raise VisionAnswerError("no response for the image")
    if first.get("error"):
        raise VisionAnswerError("the image's response carries an error")
    annotation = first.get("safeSearchAnnotation")
    if not isinstance(annotation, dict):
        raise VisionAnswerError("no safeSearchAnnotation in the response")
    return annotation


def _google_vision_verdict(annotation: dict[str, Any], settings: "Settings") -> _Verdict:
    """SafeSearch read on Google's own levels, never as percentages: reject on
    adult or violence at MODERATION_GOOGLE_REJECT_LIKELIHOOD or above; flag on
    adult, violence, racy or medical at MODERATION_GOOGLE_FLAG_LIKELIHOOD or
    above. An UNKNOWN adult or violence is a failed scan, never an approval."""
    rank = {level: i for i, level in enumerate(GOOGLE_LIKELIHOODS)}
    # proto3 JSON omits an enum left at zero, and Google's zero is UNKNOWN: an
    # absent category was never classified, so it must not read as unlikely.
    levels = {name: annotation.get(name, "UNKNOWN") for name in _VISION_FLAG_CATEGORIES}
    if any(levels[name] not in rank for name in _VISION_REJECT_CATEGORIES):
        raise VisionAnswerError("adult or violence has no likelihood (UNKNOWN)")

    flag_at = rank[settings.MODERATION_GOOGLE_FLAG_LIKELIHOOD]
    reject_at = rank[settings.MODERATION_GOOGLE_REJECT_LIKELIHOOD]
    labels = [
        {"name": name, "likelihood": levels[name]}
        for name in _VISION_FLAG_CATEGORIES
        if rank.get(levels[name], -1) >= flag_at
    ]
    if any(rank[levels[name]] >= reject_at for name in _VISION_REJECT_CATEGORIES):
        return _Verdict("rejected", labels)
    return _Verdict("flagged" if labels else "approved", labels)


async def _scan_google_vision(processed: bytes, settings: "Settings") -> _Verdict:
    """Cloud Vision SafeSearch, off the event loop like the Rekognition call."""
    annotation = await asyncio.to_thread(_vision_safe_search, processed, settings)
    return _google_vision_verdict(annotation, settings)


@dataclass(frozen=True)
class _Provider:
    """One scanner behind the seam: how a log line names it, the settings it
    cannot run without (by name), and its scan — a verdict, or an exception
    moderate_or_raise fails open on."""

    label: str
    settings: tuple[str, ...]
    scan: Callable[[bytes, "Settings"], Awaitable[_Verdict]]


# One entry per config.IMAGE_MODERATION_PROVIDERS name. MODERATION_PROVIDER
# picks the entry, and nothing after the scan knows which one ran.
_PROVIDERS = {
    "rekognition": _Provider(
        "Rekognition",
        (
            "MODERATION_AWS_ACCESS_KEY_ID",
            "MODERATION_AWS_SECRET_ACCESS_KEY",
            "MODERATION_AWS_REGION",
        ),
        _scan_rekognition,
    ),
    "google_vision": _Provider(
        "Cloud Vision", ("MODERATION_GOOGLE_SERVICE_ACCOUNT_JSON",), _scan_google_vision,
    ),
}


async def moderate_or_raise(processed: bytes, ctx: ModerationContext) -> None:
    """Scan `processed` (the final JPEG bytes) with the selected provider and act
    on the result.

    On reject: logs 'rejected', commits (so the audit row survives the router's
    422 rollback), and raises ModerationRejectedError. On flag: logs 'flagged',
    emails the operator, sets ctx.action='flagged'. On approve: logs 'approved'.
    On a failed scan — the provider raised, timed out, or answered without a
    verdict: logs 'error_allowed', sets ctx.action='error_allowed', alerts the
    operator (at most hourly), returns (upload proceeds). ctx.action defaults
    to 'approved' and is left untouched when moderation is disabled — or
    switched on without the provider's settings, which alerts the operator too."""
    settings = ctx.settings
    if not is_enabled(settings):
        if settings.MODERATION_ENABLED:
            # Switched on but unable to run: a misconfiguration, not a choice.
            await _notify_unscanned(
                settings, "not_configured", missing=_missing_settings(settings)
            )
        return  # ctx.action stays 'approved'; no log row when disabled

    image_hash = hashlib.sha256(processed).hexdigest()
    provider = settings.MODERATION_PROVIDER
    entry = _PROVIDERS[provider]

    try:
        verdict = await entry.scan(processed, settings)
    except Exception as exc:
        # Fail open: a provider outage/timeout must never block a legitimate
        # upload — and an answer we could not read is never an approval.
        logger.exception("%s scan failed — allowing upload (pending review)", entry.label)
        ctx.action = "error_allowed"
        _log_decision(
            ctx.db, image_hash=image_hash, ctx=ctx, action="error_allowed",
            labels=[], provider=provider,
        )
        await _notify_unscanned(settings, "scan_failed", error=exc)
        return

    ctx.action = verdict.action
    _log_decision(
        ctx.db, image_hash=image_hash, ctx=ctx, action=verdict.action,
        labels=verdict.labels, provider=provider,
    )
    if verdict.action == "rejected":
        # The router raises next, rolling back its own transaction — commit the
        # audit row now so the reject is never lost.
        ctx.db.commit()
        raise ModerationRejectedError(verdict.labels)

    if verdict.action == "flagged":
        try:
            await _notify_flagged(ctx, verdict.labels)
        except Exception:
            # A mail outage must never fail the upload the user just made.
            logger.exception("moderation flag notification email failed")


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
    action: str, labels: list[dict[str, Any]], provider: str | None = None,
) -> None:
    """Insert the audit row and opportunistically purge expired rows. The caller
    owns the commit (except the reject path, which commits explicitly). Every
    scan passes the `provider` that ran."""
    ctx.log = ImageModerationLog(
        image_hash=image_hash,
        target_kind=ctx.target_kind,
        # A reject commits this row on the spot: naming an itinerary that is not
        # inserted yet would fail that commit on the foreign key.
        target_itinerary_id=None if ctx.itinerary_pending else ctx.itinerary_id,
        uploader_user_id=ctx.uploader.id,
        action=action,
        provider=provider,
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


def label_text(label: dict[str, Any]) -> str:
    """How an operator reads one stored label. The flag email and both admin
    pages (the `scan_label` filter) render through this: Cloud Vision's level as
    Google names it, Rekognition's confidence as a percentage — a level printed
    as a percentage would read 0%. A label with neither, such as a takedown's
    evidence, is just its name."""
    if not isinstance(label, dict):
        return str(label)
    name = str(label.get("name", "?"))
    likelihood = label.get("likelihood")
    if isinstance(likelihood, str):
        return f"{name} ({likelihood})"
    confidence = label.get("confidence")
    if isinstance(confidence, (int, float)):
        return f"{name} ({confidence:.0f}%)"
    return name


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
    labels_html = "<br>".join(html.escape(label_text(lbl)) for lbl in labels) or "—"

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
    """The provider's error code when the exception carries one — never its
    message, which for Google names the project and links to its console.

    Rekognition: botocore's exc.response["Error"]["Code"], e.g.
    'UnrecognizedClientException'. Cloud Vision: the HTTP error body's
    error.status, plus the first details[].reason when there is one, e.g.
    'PERMISSION_DENIED/SERVICE_DISABLED'. Duck-typed, so the alert imports
    neither provider's client."""
    response = getattr(error, "response", None)
    if isinstance(response, dict):
        detail = response.get("Error")
        code = detail.get("Code") if isinstance(detail, dict) else None
        return code if isinstance(code, str) and code else None
    return _google_error_code(response)


def _google_error_code(response: Any) -> str | None:
    """Google's `error.status`, with its first `details[].reason` when there is
    one, from an HTTP error response — or None for anything else."""
    try:
        body = response.json()
    except Exception:  # no response, no body, or not JSON
        return None
    error = body.get("error") if isinstance(body, dict) else None
    status = error.get("status") if isinstance(error, dict) else None
    if not isinstance(status, str) or not status:
        return None
    details = error.get("details")
    reason = next(
        (
            detail["reason"]
            for detail in (details if isinstance(details, list) else ())
            if isinstance(detail, dict)
            and isinstance(detail.get("reason"), str) and detail["reason"]
        ),
        None,
    )
    return f"{status}/{reason}" if reason else status
