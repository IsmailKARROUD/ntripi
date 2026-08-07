"""
constants/guidelines.py — Community Guidelines served via GET /guidelines and
included in the GET /auth/tos payload.

Backend-owned for the same reason as the ToS: revising the rules is a deploy,
not an app-store submission.

The categories deliberately mirror what the stack actually enforces —
moderation_policy.CATEGORY_THRESHOLDS and report_service's canonical reasons.
Publishing a rule nothing enforces, or enforcing a category no rule announces,
is the discrepancy an app-store reviewer looks for.

The bodies live in app/constants/legal/<lang>.py; English is authoritative.
"""

from app.constants import legal

GUIDELINES_VERSION = "1.1"
GUIDELINES_DATE = "2026-08-06"


def get_guidelines(lang: str = "en") -> str:
    return legal.document(lang, "GUIDELINES")
