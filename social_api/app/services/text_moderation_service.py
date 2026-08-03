"""
services/text_moderation_service.py — the text-moderation write-path gate.

The text counterpart to moderation_service (images), and deliberately the same
shape: a context dataclass carrying an `status` OUT param, fail-soft on provider
trouble, a decision row committed before any 422 so the audit survives the
router's rollback, and an opportunistic retention purge instead of a cron.

Flow per request:
  fields → one concatenated text → cache lookup → provider chain → policy →
  decision row → ctx.status

Four ways out, none of which blocks a user because a vendor is down:
  approved  — publish normally
  flagged   — publish, sits in the moderator queue (policy 'review')
  hidden    — publish-then-hide + legal escalation (policy 'hide_escalate')
  pending   — no provider answered; publish, sweep re-checks later
  (reject)  — raises TextModerationRejectedError; caller returns 422

The legal escalation belongs to the caller, which is the only party holding the
row to point at: callers pass ctx.escalate to moderation_actions.escalate_if_flagged
after their flush. The one exception is a rejected minors verdict, escalated from
here against the author — nothing was stored, so there is no content row.

Fields written together are scanned together in ONE provider call — a stop's
name, address and notes are one submission, not three.
"""

from __future__ import annotations

import hashlib
import html
import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import TYPE_CHECKING

from fastapi import status
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.errors import ApiError
from app.models.text_moderation_cache import TextModerationCache
from app.models.text_moderation_decision import TextModerationDecision
from app.services import moderation_policy
from app.services.email_service import send_email
from app.services.moderation_policy import POLICY_VERSION, PolicyDecision
from app.services.text_moderation_providers import (
    ProviderUnavailableError, get_provider_chain,
)

if TYPE_CHECKING:
    import uuid

    from app.config import Settings
    from app.models.user import User

logger = logging.getLogger(__name__)

# Policy outcome → the content-state value stored on the moderated record.
_OUTCOME_TO_STATUS = {
    "approve": "approved",
    "review": "flagged",
    "hide_escalate": "hidden",
}

# Content states ordered least → most severe. Automated writes may only raise
# severity (see apply_moderation_status): a clean text edit must not silently
# clear a pending image flag, and vice versa.
STATUS_SEVERITY = {
    "approved": 0,
    "pending": 1,
    "flagged": 2,
    "hidden": 3,
    "rejected": 4,
}

# One operator email per hour per degradation level — an outage during a busy
# hour would otherwise send one email per write. In-memory is sufficient for
# the same reason slowapi's store is: single-instance deployment.
_DEGRADATION_COOLDOWN = timedelta(minutes=60)
_last_degradation_notice: dict[str, datetime] = {}


class TextModerationRejectedError(Exception):
    """Raised when text fails the hard-reject thresholds. Carries category
    names only — the offending text is never echoed back to the client."""

    def __init__(self, categories: list[str]) -> None:
        self.categories = categories
        super().__init__("Text rejected by automated moderation.")


@dataclass
class TextModerationContext:
    """What the scan needs beyond the text itself. `status` and `decision_id`
    are OUT params, read back by the caller to stamp the content record."""

    db: Session
    settings: "Settings"
    target_type: str  # 'itinerary' | 'rating' | 'user'
    # None for a scan with no account behind it yet (registration) or anymore
    # (sweep re-check of content whose author deleted their account).
    author: "User | None"
    target_id: "uuid.UUID | None" = None
    source: str = "write"  # 'write' | 'recheck'
    status: str = field(default="approved")  # OUT param
    decision_id: "uuid.UUID | None" = field(default=None)  # OUT param
    escalate: bool = field(default=False)  # OUT param — minors hit, needs legal review


def is_enabled(settings: "Settings") -> bool:
    """True when a provider is configured. The OpenAI-without-key case can't
    reach here — config validation refuses to start the app."""
    return settings.TEXT_MODERATION_PROVIDER != "disabled"


def build_text(fields: dict[str, str | None]) -> str:
    """Join the submitted fields into one scannable document. Blank separators
    keep unrelated fields from forming accidental phrases across the boundary."""
    return "\n\n".join(
        value.strip() for value in fields.values() if value and value.strip()
    )


def content_hash(text: str, model: str) -> str:
    """Cache/audit key. Including model and policy version means a model swap
    or a threshold change makes every existing verdict unreachable — that is
    how cache invalidation happens, without a purge step.

    `model` is always the *configured* name, never the snapshot OpenAI echoes
    back: keying on the echoed value would move the key every time OpenAI
    rolls the alias, and nothing would ever hit the cache.
    """
    payload = f"{text}\x00{model}\x00{POLICY_VERSION}".encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def apply_moderation_status(record, status: str) -> None:
    """Raise `record.moderation_status` to `status` if that is more severe.

    Escalate-only because two independent tiers write this column (image and
    text): a clean caption edit must never clear an unresolved image flag.
    Moderator and appeal paths assign directly to lower it.
    """
    current = getattr(record, "moderation_status", None) or "approved"
    if STATUS_SEVERITY.get(status, 0) > STATUS_SEVERITY.get(current, 0):
        record.moderation_status = status


def moderate_fields_or_raise(
    fields: dict[str, str | None], ctx: TextModerationContext
) -> None:
    """Scan `fields` and record the decision. Sets ctx.status; raises
    TextModerationRejectedError when the write must be blocked.

    Never raises for provider trouble — an outage degrades to the local
    classifier, then to 'pending', so a vendor incident cannot stop people
    posting, and cannot be mistaken for approval either.
    """
    settings = ctx.settings
    if not is_enabled(settings):
        return  # ctx.status stays 'approved'; no rows written when disabled

    text = build_text(fields)
    if not text:
        return  # nothing to scan (e.g. a PATCH that only cleared a field)

    key = content_hash(text, settings.TEXT_MODERATION_MODEL)

    cached = _lookup_cache(ctx.db, key)
    if cached is not None:
        decision = moderation_policy.evaluate(cached.scores)
        _finalize(ctx, decision, cached.scores, cached.provider, cached.model, hash_key=key)
        return

    result = _score_with_chain(text, ctx)
    if result is None:
        # Provider chain exhausted. Publish, but record it: 'pending' is the
        # non-silent state the sweep re-checks, never a silent approval.
        ctx.status = "pending"
        _write_decision(ctx, outcome="pending", scores={}, provider=None, model=None,
                        hash_key=key, queue_label=None)
        return

    decision = moderation_policy.evaluate(result.scores)
    _store_cache(ctx.db, key, decision, result, settings)
    _finalize(ctx, decision, result.scores, result.provider, result.model, hash_key=key)


def attach_target(ctx: TextModerationContext, target_id: "uuid.UUID") -> None:
    """Point this scan's decision row at the row it protects.

    A create-time scan runs before its target exists, so the decision lands with
    target_id NULL. Without this backfill the moderator queue would show a flag
    with nothing to review.
    """
    if ctx.decision_id is None:
        return
    row = ctx.db.get(TextModerationDecision, ctx.decision_id)
    if row is not None and row.target_id is None:
        row.target_id = target_id


def moderate_or_422(
    db: Session,
    settings: "Settings",
    *,
    target_type: str,
    author: "User | None",
    fields: dict[str, str | None],
    target_id: "uuid.UUID | None" = None,
    source: str = "write",
) -> TextModerationContext:
    """Router adapter: scan `fields`, or raise the 422 the client understands.

    Every text write path calls this instead of handling the domain exception
    itself. Call it from the endpoint BODY, never as a `Depends` — dependencies
    resolve before the body runs, and an If-Match conflict must produce its 412
    without first spending a moderation call.

    `author` is None at registration — the account does not exist yet. Whatever
    the caller does next must not have added rows to the session: the reject
    path commits to preserve its audit row, and would commit those too.

    The 422 carries category names, never the submitted text.
    """
    ctx = TextModerationContext(
        db=db, settings=settings, target_type=target_type,
        author=author, target_id=target_id, source=source,
    )
    try:
        moderate_fields_or_raise(fields, ctx)
    except TextModerationRejectedError as exc:
        raise ApiError(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            code="text_moderation_rejected",
            detail="This text appears to violate the community guidelines and was not saved.",
            extra={"categories": exc.categories},
        ) from exc
    return ctx


def _finalize(
    ctx: TextModerationContext,
    decision: PolicyDecision,
    scores: dict[str, float],
    provider: str | None,
    model: str | None,
    *,
    hash_key: str,
) -> None:
    """Turn a policy decision into a content state + decision row, raising on
    reject after the row is safely committed."""
    if decision.outcome == "reject":
        ctx.status = "rejected"
        _write_decision(ctx, outcome="reject", scores=scores, provider=provider,
                        model=model, hash_key=hash_key, queue_label=None)
        if moderation_policy.CSAM_CATEGORY in decision.categories and ctx.author is not None:
            # Nothing was stored, so no content row survives to point at —
            # escalate against the author, as csam_takedown does for a hash
            # match. Lazy import: moderation_actions reaches back into the
            # action layer, which must not be a module-level dependency here.
            from app.services import moderation_actions

            moderation_actions.escalate_if_flagged(
                ctx.db, "user", ctx.author,
                escalate_flag=True, decision_id=ctx.decision_id,
            )
        # The caller raises 422 next, rolling back its transaction — commit the
        # audit row now so the rejection is never lost.
        ctx.db.commit()
        raise TextModerationRejectedError(decision.categories)

    ctx.status = _OUTCOME_TO_STATUS[decision.outcome]
    ctx.escalate = decision.outcome == "hide_escalate"
    _write_decision(ctx, outcome=decision.outcome, scores=scores, provider=provider,
                    model=model, hash_key=hash_key, queue_label=decision.queue_label)


def _score_with_chain(text: str, ctx: TextModerationContext):
    """Try each provider in order; return the first result, or None if all fail.
    Falling back from the primary is itself an event worth telling the operator
    about — a silent permanent downgrade to the wordlist would be worse than
    the outage."""
    chain = get_provider_chain(ctx.settings)
    for index, provider in enumerate(chain):
        try:
            result = provider.score(text)
        except ProviderUnavailableError as exc:
            logger.warning("text moderation provider %s unavailable: %s", provider.name, exc)
            continue
        except Exception as exc:  # defensive: a provider bug is still an outage
            logger.exception("text moderation provider %s raised: %r", provider.name, exc)
            continue
        if index > 0:
            _notify_degraded(ctx.settings, "fallback", provider.name)
        return result

    _notify_degraded(ctx.settings, "pending", None)
    return None


def _lookup_cache(db: Session, key: str):
    """Return a live cache row for `key`, or None. Expired rows are purged
    opportunistically (no cron — same pattern as scrub_expired_ip_hashes)."""
    now = datetime.now(timezone.utc)
    db.execute(delete(TextModerationCache).where(TextModerationCache.expires_at < now))

    row = db.execute(
        select(TextModerationCache).where(TextModerationCache.cache_key == key)
    ).scalar_one_or_none()
    if row is None:
        return None
    if _as_aware(row.expires_at) < now:
        return None
    return row


def _store_cache(
    db: Session, key: str, decision: PolicyDecision, result, settings: "Settings"
) -> None:
    """Insert the verdict, unless an identical key already landed (a concurrent
    request scanning the same text)."""
    exists = db.execute(
        select(TextModerationCache.cache_key).where(TextModerationCache.cache_key == key)
    ).scalar_one_or_none()
    if exists is not None:
        return
    now = datetime.now(timezone.utc)
    db.add(TextModerationCache(
        cache_key=key,
        outcome=decision.outcome,
        scores=result.scores,
        provider=result.provider,
        model=result.model,
        created_at=now,
        expires_at=now + timedelta(days=settings.TEXT_MODERATION_CACHE_TTL_DAYS),
    ))


def _write_decision(
    ctx: TextModerationContext,
    *,
    outcome: str,
    scores: dict[str, float],
    provider: str | None,
    model: str | None,
    hash_key: str,
    queue_label: str | None,
) -> None:
    """Append the audit/queue row and purge expired reviewed rows. The caller
    owns the commit (except the reject path, which commits explicitly)."""
    row = TextModerationDecision(
        content_hash=hash_key,
        target_type=ctx.target_type,
        target_id=ctx.target_id,
        author_user_id=ctx.author.id if ctx.author is not None else None,
        outcome=outcome,
        scores={k: round(float(v), 4) for k, v in (scores or {}).items()},
        provider=provider,
        model=model,
        policy_version=POLICY_VERSION,
        source=ctx.source,
        queue_label=queue_label,
    )
    ctx.db.add(row)
    ctx.db.flush()  # populate row.id so the caller can link an escalation to it
    ctx.decision_id = row.id

    cutoff = datetime.now(timezone.utc) - timedelta(
        days=ctx.settings.TEXT_MODERATION_LOG_RETENTION_DAYS
    )
    # Unreviewed rows are the moderator queue — retention must never empty it.
    ctx.db.execute(
        delete(TextModerationDecision).where(
            TextModerationDecision.created_at < cutoff,
            TextModerationDecision.reviewed_at.isnot(None),
        )
    )


def _notify_degraded(settings: "Settings", level: str, provider_name: str | None) -> None:
    """Tell the operator the moderation tier is degraded — falling back to the
    local wordlist, or scanning nothing at all. Throttled per level so an
    outage sends one email an hour, not one per write. Best-effort: a mail
    failure must never surface to the user who just posted."""
    now = datetime.now(timezone.utc)
    last = _last_degradation_notice.get(level)
    if last is not None and now - last < _DEGRADATION_COOLDOWN:
        return
    _last_degradation_notice[level] = now

    if level == "fallback":
        logger.warning(
            "text moderation degraded: primary provider unavailable, using %s",
            provider_name,
        )
        subject = "[Ntripi] Text moderation degraded — using fallback provider"
        body = (
            "<h2>Text moderation fell back</h2>"
            "<p>The primary provider is unavailable; text is being scanned by "
            f"<strong>{html.escape(provider_name or 'the fallback provider')}</strong>, "
            "which is much coarser than the primary classifier.</p>"
        )
    else:
        logger.warning("text moderation degraded: no provider available, content is pending")
        subject = "[Ntripi] Text moderation unavailable — content publishing as pending"
        body = (
            "<h2>Text moderation is not running</h2>"
            "<p>Every configured provider failed. New text is publishing with "
            "status <code>pending</code> and will be re-checked by the sweep once "
            "a provider recovers. Nothing is being silently approved.</p>"
        )

    body += (
        f"<p>Detected at {html.escape(now.isoformat())} (UTC). "
        "Further notices for this level are suppressed for one hour.</p>"
    )

    if not settings.OPERATOR_EMAIL:
        return  # already logged above; nowhere to send it
    try:
        send_email(settings.OPERATOR_EMAIL, subject=subject, html=body)
    except Exception:
        logger.exception("text moderation degradation email failed")


def _as_aware(value: datetime) -> datetime:
    """SQLite hands back naive datetimes; treat them as UTC (matches
    token_util.as_aware_utc)."""
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value
