"""Canonical content-report reasons, ordered most → least severe.

A module of its own, with no imports, because two things need the list that
cannot import each other: the ContentReport model (its CHECK constraint) and
Settings (validating REPORT_HIDE_THRESHOLDS at boot — config loads before any
model can).
"""

REPORT_REASONS = (
    "csam", "sexual_content", "violence_threat",
    "hate_speech", "harassment", "other", "spam",
)
