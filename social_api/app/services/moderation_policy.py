"""
services/moderation_policy.py — Ntripi's own text-moderation thresholds.

The provider's boolean `flagged` verdict is deliberately ignored: OpenAI tunes
it for general-purpose safety, we tune for a travel app where a stop note
saying "avoid this street at night" is legitimate content. Only the per-category
scores are consumed, against the thresholds below.

Each category has two thresholds producing four outcomes:
  approve        — publish normally
  review         — publish, queue for a moderator (status 'flagged')
  reject         — block the write, 422 to the client
  hide_escalate  — publish-then-immediately-hide + legal escalation (minors only)

POLICY_VERSION is part of the cache key: bumping it makes every cached verdict
unreachable, which is how a threshold change invalidates the cache.
"""

from __future__ import annotations

from dataclasses import dataclass, field

# Bump on ANY change to CATEGORY_THRESHOLDS or the evaluate() rules — cached
# verdicts keyed on the old version simply stop matching.
POLICY_VERSION = "1"

# (review_at, reject_at) per OpenAI omni-moderation category, most restrictive
# first. Categories absent from a provider response score 0.0.
CATEGORY_THRESHOLDS: dict[str, tuple[float, float]] = {
    "sexual/minors": (0.10, 0.20),
    "hate/threatening": (0.30, 0.60),
    "self-harm/intent": (0.30, 0.60),
    "self-harm/instructions": (0.30, 0.60),
    "sexual": (0.40, 0.70),
    "harassment/threatening": (0.40, 0.70),
    "self-harm": (0.40, 0.70),
    "hate": (0.50, 0.75),
    "violence/graphic": (0.50, 0.80),
    "illicit/violent": (0.50, 0.80),
    "harassment": (0.55, 0.80),
    "violence": (0.60, 0.85),
    "illicit": (0.60, 0.85),
}

# Self-harm review outcomes route to their own queue label: the appropriate
# response is support-oriented, not punitive, so this content is never
# auto-hidden on a classifier score alone.
SELF_HARM_CATEGORIES = frozenset({
    "self-harm",
    "self-harm/intent",
    "self-harm/instructions",
})
SELF_HARM_QUEUE_LABEL = "self_harm"

# Belgian law imposes obligations beyond hiding for this category, so it can
# never be closed as a routine moderation item.
CSAM_CATEGORY = "sexual/minors"

# Outcome severity, least to most. Used for "most severe wins" and for the
# escalate-only status merge in text_moderation_service.
OUTCOME_SEVERITY: dict[str, int] = {
    "approve": 0,
    "review": 1,
    "hide_escalate": 2,
    "reject": 3,
}

# Which report categories a classifier category corroborates. Used by the
# report-threshold rule: classifier signal + human report is high confidence,
# so the required reporter count drops by one.
_CATEGORY_TO_REPORT_REASON: dict[str, frozenset[str]] = {
    "sexual/minors": frozenset({"csam", "sexual_content"}),
    "sexual": frozenset({"sexual_content"}),
    "hate": frozenset({"hate_speech"}),
    "hate/threatening": frozenset({"hate_speech", "violence_threat"}),
    "harassment": frozenset({"harassment"}),
    "harassment/threatening": frozenset({"harassment", "violence_threat"}),
    "violence": frozenset({"violence_threat"}),
    "violence/graphic": frozenset({"violence_threat"}),
    "illicit": frozenset({"other"}),
    "illicit/violent": frozenset({"violence_threat", "other"}),
    "self-harm": frozenset({"other"}),
    "self-harm/intent": frozenset({"other"}),
    "self-harm/instructions": frozenset({"other"}),
}


@dataclass(frozen=True)
class PolicyDecision:
    """The outcome of applying Ntripi thresholds to one set of category scores."""

    outcome: str  # 'approve' | 'review' | 'reject' | 'hide_escalate'
    triggered: list[tuple[str, float]] = field(default_factory=list)
    queue_label: str | None = None  # 'self_harm' when a self-harm category drove a review

    @property
    def categories(self) -> list[str]:
        """Category names only — safe to return to a client (never the text)."""
        return [name for name, _ in self.triggered]


def evaluate(scores: dict[str, float]) -> PolicyDecision:
    """Apply the threshold table to provider scores. Most severe outcome wins.

    sexual/minors is special-cased: at or above its reject threshold the write
    is blocked; between review and reject the content is hidden *and* legally
    escalated rather than merely queued.
    """
    per_category: list[tuple[str, float, str]] = []

    for category, (review_at, reject_at) in CATEGORY_THRESHOLDS.items():
        score = float(scores.get(category, 0.0) or 0.0)
        if score >= reject_at:
            outcome = "reject"
        elif score >= review_at:
            # A minors hit that is only "review"-strong still gets taken down —
            # the cost asymmetry here is not comparable to other categories.
            outcome = "hide_escalate" if category == CSAM_CATEGORY else "review"
        else:
            continue
        per_category.append((category, score, outcome))

    if not per_category:
        return PolicyDecision(outcome="approve")

    worst = max(OUTCOME_SEVERITY[outcome] for _, _, outcome in per_category)
    final_outcome = next(
        name for name, severity in OUTCOME_SEVERITY.items() if severity == worst
    )
    triggered = [
        (category, round(score, 4))
        for category, score, _ in per_category
    ]
    triggered.sort(key=lambda item: item[1], reverse=True)

    queue_label = None
    if final_outcome == "review" and any(
        category in SELF_HARM_CATEGORIES
        for category, _, outcome in per_category
        if outcome == "review"
    ):
        queue_label = SELF_HARM_QUEUE_LABEL

    return PolicyDecision(
        outcome=final_outcome, triggered=triggered, queue_label=queue_label
    )


def is_above_review_threshold(scores: dict[str, float]) -> bool:
    """True if any category reaches its review threshold — the 'classifier
    already suspects this' signal used to lower report-hide thresholds."""
    return any(
        float(scores.get(category, 0.0) or 0.0) >= review_at
        for category, (review_at, _) in CATEGORY_THRESHOLDS.items()
    )


def category_matches_report_reason(category: str, reason: str) -> bool:
    """True if a classifier category corroborates a human report reason."""
    return reason in _CATEGORY_TO_REPORT_REASON.get(category, frozenset())


def scores_corroborate_reason(scores: dict[str, float], reason: str) -> bool:
    """True if any category at or above its review threshold corroborates the
    given report reason."""
    return any(
        float(scores.get(category, 0.0) or 0.0) >= review_at
        and category_matches_report_reason(category, reason)
        for category, (review_at, _) in CATEGORY_THRESHOLDS.items()
    )
