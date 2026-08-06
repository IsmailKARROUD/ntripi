"""
services/jira_service.py — File a bug report as a Jira issue.

Operator-initiated only, from the "Create Jira issue" button on /admin/bugs.
Nothing in the user-facing request path touches this module.

Unlike the other third-party integrations here, this one FAILS CLOSED. Email
(email_service) and image moderation (moderation_service) swallow their errors
because a provider outage must not 500 a user's request; here the operator is
standing in front of the dashboard waiting to see an issue key, so a silently
dropped failure would be worse than useless. Every failure raises JiraError and
the router renders it as a red flash carrying Jira's own message.

PRIVACY: the payload carries the reporter's @username but never their email.
The operator notification email does include it (bug_report_service), but that
is one inbox — a Jira project is usually visible to a whole team.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Any

from app.services.share_service import absolute_storage_url

if TYPE_CHECKING:
    from app.config import Settings
    from app.models.bug_report import BugReport
    from app.models.user import User

logger = logging.getLogger(__name__)

_ISSUE_PATH = "/rest/api/3/issue"

# Jira rejects a longer summary outright rather than truncating it.
_SUMMARY_MAX = 255


class JiraError(Exception):
    """Anything that stopped us creating the issue. The message is shown to the
    operator, so it must stay human-readable and free of credentials."""


def is_enabled(settings: "Settings") -> bool:
    """True when Jira is fully configured. A partial config is treated as OFF
    (the button is not rendered) rather than as a startup error — same rule as
    ADMIN_BASIC_*, where an unset credential makes the feature invisible."""
    required = {
        "JIRA_BASE_URL": settings.JIRA_BASE_URL,
        "JIRA_EMAIL": settings.JIRA_EMAIL,
        "JIRA_API_TOKEN": settings.JIRA_API_TOKEN,
        "JIRA_PROJECT_KEY": settings.JIRA_PROJECT_KEY,
    }
    missing = [name for name, value in required.items() if not value]
    if missing and len(missing) < len(required):
        # Some set, some not — almost certainly a typo rather than a deliberate
        # opt-out, so name the gap instead of failing silently.
        logger.warning(
            "Jira hand-off disabled — missing env vars: %s", ", ".join(missing)
        )
    return not missing


def browse_base(settings: "Settings") -> str:
    """Base for issue permalinks (<base>/browse/NTRIPI-6)."""
    return (settings.JIRA_BASE_URL or "").rstrip("/")


def create_issue(
    report: "BugReport", reporter: "User | None", settings: "Settings"
) -> str:
    """Create the Jira issue and return its key (e.g. "NTRIPI-6")."""
    if not is_enabled(settings):
        raise JiraError("Jira is not configured.")

    # Operators paste base URLs with a trailing slash; //rest/... is a 404.
    url = f"{browse_base(settings)}{_ISSUE_PATH}"
    payload = {
        "fields": {
            "project": {"key": settings.JIRA_PROJECT_KEY},
            "issuetype": {"name": settings.JIRA_ISSUE_TYPE},
            "summary": _summary(report),
            "description": _adf(_description_lines(report, reporter, settings)),
        }
    }

    try:
        import requests  # local import: only this path needs it

        resp = requests.post(
            url,
            json=payload,
            auth=(settings.JIRA_EMAIL, settings.JIRA_API_TOKEN),
            headers={"Accept": "application/json"},
            timeout=settings.JIRA_TIMEOUT_SECONDS,
        )
    except Exception as exc:
        logger.exception("Jira request failed for bug report %s", report.id)
        raise JiraError(f"Could not reach Jira: {exc!r}") from exc

    if resp.status_code not in (200, 201):
        # Jira's error body names the offending field — a wrong JIRA_ISSUE_TYPE
        # is the most common first failure, and this is what diagnoses it.
        detail = resp.text[:500]
        logger.error("Jira returned HTTP %s: %s", resp.status_code, detail)
        raise JiraError(f"Jira returned HTTP {resp.status_code}: {detail}")

    try:
        key = resp.json()["key"]
    except Exception as exc:
        logger.exception("Jira response unparseable for bug report %s", report.id)
        raise JiraError(f"Jira response unparseable: {exc!r}") from exc

    logger.info("Filed bug report %s as Jira issue %s", report.id, key)
    return key


def _summary(report: "BugReport") -> str:
    """`[category] first line of the message`, clipped to Jira's limit."""
    first_line = " ".join(report.message.split())
    summary = f"[{report.category or 'bug'}] {first_line}"
    if len(summary) > _SUMMARY_MAX:
        summary = summary[: _SUMMARY_MAX - 1].rstrip() + "…"
    return summary


def _description_lines(
    report: "BugReport", reporter: "User | None", settings: "Settings"
) -> list[str]:
    def field(value: str | None) -> str:
        return value or "—"

    # @username only — never reporter.email. See the module docstring.
    who = f"@{reporter.username}" if reporter is not None else "Signed out"

    lines = [
        f"Reported by: {who}",
        f"App: {field(report.app_version)} on {field(report.platform)}",
        f"Device: {field(report.device_model)} · {field(report.os_version)}",
        f"Locale / theme: {field(report.locale)} · {field(report.theme_mode)}",
        f"Screen: {field(report.route)}",
        "",
        report.message,
    ]
    if report.screenshot_key:
        # Absolute: filesystem storage returns a relative /uploads/... path,
        # which is dead text inside a Jira ticket.
        lines += ["", f"Screenshot: {absolute_storage_url(report.screenshot_key, settings)}"]
    lines += ["", f"Filed via Ntripi /admin/bugs · report {report.id}"]
    return lines


def _adf(lines: list[str]) -> dict[str, Any]:
    """Wrap plain lines in Atlassian Document Format.

    REST v3 rejects a plain string for `description`; this doc/paragraph/text
    subset is the whole of ADF we need. An empty line becomes an empty
    paragraph — ADF text nodes may not carry an empty string.
    """
    return {
        "type": "doc",
        "version": 1,
        "content": [
            {
                "type": "paragraph",
                "content": ([{"type": "text", "text": line}] if line else []),
            }
            for line in lines
        ],
    }
