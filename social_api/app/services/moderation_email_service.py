"""
services/moderation_email_service.py — telling an author their content was
actioned automatically.

This email is the DSA statement-of-reasons surface, so it has to carry real
content: what was actioned, which category triggered it, that no human decided
it, and how to contest it. A generic "your content violated our guidelines" is
not compliant and is not honest.

Tone rule: an automated hide pending review is NOT a finding of guilt. Copy says
what happened and what the author can do — it does not admonish. Getting this
wrong on a false positive is how you lose a legitimate user.

Best-effort like every other mail path (send_email swallows failures); the caller
sends after commit so a mail outage can never roll back the action.
"""

from __future__ import annotations

import html
import logging
import uuid

from app.services import appeal_token, email_service

logger = logging.getLogger(__name__)

# Classifier/report category → the phrase the author actually reads. Raw
# category ids ("sexual/minors", "illicit/violent") are internal.
_CATEGORY_PHRASES = {
    "csam": "content involving minors",
    "sexual/minors": "content involving minors",
    "sexual_content": "sexual content",
    "sexual": "sexual content",
    "violence_threat": "threats of violence",
    "violence": "violent content",
    "violence/graphic": "graphic violence",
    "hate_speech": "hate speech",
    "hate": "hate speech",
    "hate/threatening": "threatening hate speech",
    "harassment": "harassment",
    "harassment/threatening": "threatening harassment",
    "self-harm": "self-harm",
    "self-harm/intent": "self-harm",
    "self-harm/instructions": "self-harm",
    "illicit": "illegal activity",
    "illicit/violent": "violent illegal activity",
    "spam": "spam",
    "other": "a community-guidelines concern",
}

# Why the action fired — the author is entitled to know a machine decided it.
_TRIGGER_SENTENCES = {
    "auto_hide_reports": (
        "It was hidden automatically after several people reported it. "
        "No one has reviewed it yet."
    ),
    "auto_hide_sla": (
        "It was reported, and hidden automatically because we could not review "
        "the report in time. No one has reviewed it yet."
    ),
    "auto_reject": (
        "It was hidden automatically by our content classifier."
    ),
    "legal_escalate": (
        "It was hidden automatically and referred for review."
    ),
}


def describe_category(category: str | None) -> str:
    """Plain-language phrase for a category id."""
    if not category:
        return "a community-guidelines concern"
    return _CATEGORY_PHRASES.get(category, "a community-guidelines concern")


def build_reason(action: str, category: str | None) -> str:
    """The statement of reasons, stored on the audit row and shown to the author.

    Deliberately specific: this string is the DSA surface, so "violates our
    guidelines" would not satisfy it.
    """
    trigger = _TRIGGER_SENTENCES.get(action, _TRIGGER_SENTENCES["auto_reject"])
    return f"Automated action ({action}): flagged as {describe_category(category)}. {trigger}"


def send_auto_action_email(
    user,
    *,
    action: str,
    item_label: str,
    category: str | None,
    settings,
    log_id: uuid.UUID | None = None,
    target_type: str = "itinerary",
    target_id: uuid.UUID | None = None,
) -> None:
    """Tell `user` their content was hidden by an automated decision.

    `item_label` is the content's own title — it goes to the person who wrote it,
    so echoing it back is appropriate here (unlike the audit row or the operator
    alert, which hold no raw content).
    """
    from app.services.auth_service import _email_html  # lazy: auth stack is heavy

    trigger = _TRIGGER_SENTENCES.get(action, _TRIGGER_SENTENCES["auto_reject"])
    body = (
        f"“{html.escape(item_label)}” is no longer visible to other people on Ntripi. "
        f"{trigger} It was flagged as {describe_category(category)}."
        "<br><br>"
        "If you believe this is wrong, you can ask us to review it — appeals are "
        "read by a person. Your content is not deleted, and nothing else about "
        "your account has changed."
        f"<br><br>Questions: {html.escape(settings.ABUSE_CONTACT_EMAIL)}"
    )

    token = appeal_token.mint_appeal_token(user.id, target_type, target_id, log_id)
    link = appeal_token.appeal_link(token)

    email_service.send_email(
        to=user.email,
        subject="Ntripi — your content was hidden pending review",
        html=_email_html(
            "Your content was hidden pending review",
            body,
            "Ask us to review this",
            link,
        ),
    )
