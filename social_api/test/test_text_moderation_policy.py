"""
test_text_moderation_policy.py — Ntripi's own threshold policy.

Pure unit tests, no DB and no HTTP: evaluate() turns provider scores into one
of four outcomes, and these assertions pin the boundaries so a future threshold
edit cannot quietly change behaviour without a failing test (and a matching
POLICY_VERSION bump).
"""

import pytest

from app.services.moderation_policy import (
    CATEGORY_THRESHOLDS,
    SELF_HARM_QUEUE_LABEL,
    category_matches_report_reason,
    evaluate,
    is_above_review_threshold,
    scores_corroborate_reason,
)


def test_clean_text_approves():
    assert evaluate({}).outcome == "approve"
    assert evaluate({"violence": 0.1, "hate": 0.2}).outcome == "approve"


def test_every_documented_category_is_present():
    """The 13 categories from the requirements table, no more, no fewer."""
    assert len(CATEGORY_THRESHOLDS) == 13
    assert CATEGORY_THRESHOLDS["sexual/minors"] == (0.10, 0.20)
    assert CATEGORY_THRESHOLDS["illicit"] == (0.60, 0.85)


@pytest.mark.parametrize(
    "category,review_at,reject_at",
    [(name, review, reject) for name, (review, reject) in CATEGORY_THRESHOLDS.items()],
)
def test_thresholds_are_boundaries_not_ranges(category, review_at, reject_at):
    """Just under review = approve; exactly at review = action; exactly at
    reject = reject. Inclusive lower bounds on both."""
    assert evaluate({category: review_at - 0.001}).outcome == "approve"
    assert evaluate({category: review_at}).outcome != "approve"
    assert evaluate({category: reject_at}).outcome == "reject"


def test_most_severe_outcome_wins():
    """A reject in one category is not diluted by approvals elsewhere."""
    decision = evaluate({"harassment": 0.9, "violence": 0.1})
    assert decision.outcome == "reject"

    decision = evaluate({"harassment": 0.6, "violence": 0.9})
    assert decision.outcome == "reject"


def test_review_and_reject_together_rejects():
    decision = evaluate({"hate": 0.55, "sexual": 0.95})
    assert decision.outcome == "reject"
    assert "sexual" in decision.categories


def test_minors_between_thresholds_escalates_rather_than_queues():
    """A minors hit that is only review-strong is still taken down — the cost
    asymmetry is not comparable to other categories."""
    decision = evaluate({"sexual/minors": 0.15})
    assert decision.outcome == "hide_escalate"


def test_minors_above_reject_threshold_rejects():
    assert evaluate({"sexual/minors": 0.25}).outcome == "reject"


def test_minors_escalation_beats_ordinary_review():
    decision = evaluate({"sexual/minors": 0.15, "harassment": 0.6})
    assert decision.outcome == "hide_escalate"


@pytest.mark.parametrize("category", [
    "self-harm", "self-harm/intent", "self-harm/instructions",
])
def test_self_harm_review_gets_its_own_queue_label(category):
    """Self-harm content routes to a distinct queue — the right response is
    support, not takedown."""
    review_at = CATEGORY_THRESHOLDS[category][0]
    decision = evaluate({category: review_at})
    assert decision.outcome == "review"
    assert decision.queue_label == SELF_HARM_QUEUE_LABEL


def test_self_harm_never_produces_an_auto_hide():
    """No self-harm score, however high, may auto-hide on the classifier alone:
    it either queues for review or rejects the write outright."""
    for category in ("self-harm", "self-harm/intent", "self-harm/instructions"):
        for score in (0.3, 0.5, 0.7, 0.95, 1.0):
            assert evaluate({category: score}).outcome != "hide_escalate"


def test_non_self_harm_review_has_no_queue_label():
    decision = evaluate({"harassment": 0.6})
    assert decision.outcome == "review"
    assert decision.queue_label is None


def test_queue_label_absent_when_self_harm_only_reaches_reject():
    """A rejected write never enters a queue, so it carries no label."""
    decision = evaluate({"self-harm/intent": 0.9})
    assert decision.outcome == "reject"
    assert decision.queue_label is None


def test_triggered_categories_are_sorted_by_score_and_carry_no_text():
    decision = evaluate({"harassment": 0.6, "hate": 0.7, "violence": 0.1})
    assert decision.categories == ["hate", "harassment"]
    assert all(isinstance(score, float) for _, score in decision.triggered)


def test_unknown_categories_from_a_newer_model_are_ignored():
    """A provider adding a category we have no threshold for must not crash or
    silently change a verdict."""
    assert evaluate({"brand-new-category": 0.99}).outcome == "approve"


def test_missing_and_null_scores_are_treated_as_zero():
    assert evaluate({"hate": None}).outcome == "approve"


def test_is_above_review_threshold():
    assert is_above_review_threshold({"harassment": 0.6}) is True
    assert is_above_review_threshold({"harassment": 0.1}) is False
    assert is_above_review_threshold({}) is False


def test_category_matches_report_reason():
    assert category_matches_report_reason("hate", "hate_speech") is True
    assert category_matches_report_reason("sexual/minors", "csam") is True
    assert category_matches_report_reason("hate", "spam") is False


def test_scores_corroborate_reason_requires_review_threshold():
    """A low hate score does not corroborate a hate_speech report — only a
    score the classifier itself would queue on counts."""
    assert scores_corroborate_reason({"hate": 0.55}, "hate_speech") is True
    assert scores_corroborate_reason({"hate": 0.10}, "hate_speech") is False
    assert scores_corroborate_reason({"hate": 0.55}, "spam") is False
