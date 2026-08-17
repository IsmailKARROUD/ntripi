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

PRIVACY: the payload carries the BUG REPORTER's @username but never their email.
The operator notification email does include it (bug_report_service), but that
is one inbox — a Jira project is usually visible to a whole team. That rule is
about the end user who filed the bug; the acting ADMIN's email is a different
matter — see find_account_id.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Any, NamedTuple
from urllib.parse import urlparse

from app.services.share_service import absolute_storage_url

if TYPE_CHECKING:
    from app.config import Settings
    from app.models.bug_report import BugReport
    from app.models.user import User

logger = logging.getLogger(__name__)

_ISSUE_PATH = "/rest/api/3/issue"
# Project-scoped on purpose: it answers "is this person on THIS project", which
# is the question being asked. The site-wide /user/search does not.
_USER_SEARCH_PATH = "/rest/api/3/user/assignable/search"

# Jira rejects a longer summary outright rather than truncating it.
_SUMMARY_MAX = 255


class JiraError(Exception):
    """Anything that stopped us creating the issue. The message is shown to the
    operator, so it must stay human-readable and free of credentials."""


class JiraResult(NamedTuple):
    """The issue key, plus why attribution was lost when it was.

    A warning is not an error: the ticket exists either way, and `warning` only
    ever explains that its Reporter is the service account rather than the admin
    who clicked.
    """

    key: str
    warning: str | None = None


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
    """Jira site root — base for REST calls and issue permalinks
    (<base>/browse/NTRIPI-6).

    Normalised rather than used verbatim, because the URL an operator has to
    hand is the one in their address bar while looking at the board
    (https://site.atlassian.net/jira/software/projects/NTRIPI/boards/1), and a
    leftover path is an invisible misconfiguration: Jira Cloud's front end
    answers any unknown path with the web app's HTML at HTTP 200, so every call
    fails as a parse error rather than a 404. Only *.atlassian.net is trimmed to
    the origin — Cloud always serves REST from the site root, while a Server/DC
    install may legitimately sit under a context path (…/jira).
    """
    raw = (settings.JIRA_BASE_URL or "").strip().rstrip("/")
    if not raw:
        return ""
    if "://" not in raw:
        raw = f"https://{raw}"  # a bare hostname makes requests raise MissingSchema
    parsed = urlparse(raw)
    if parsed.path and (parsed.hostname or "").lower().endswith(".atlassian.net"):
        return f"{parsed.scheme}://{parsed.netloc}"
    return raw


def _json_or_error(resp: Any, url: str) -> Any:
    """Jira's parsed body, or a JiraError naming what came back instead.

    Worth its own function because the failure it describes is otherwise
    undiagnosable: a JIRA_BASE_URL that does not reach the REST API does not
    404, it returns the SPA shell with HTTP 200 and HTML, so the only symptom is
    a body that will not parse — and a bare "unparseable" gives the operator
    nothing to act on.
    """
    try:
        return resp.json()
    except ValueError as exc:
        content_type = resp.headers.get("Content-Type", "unknown")
        snippet = " ".join((resp.text or "")[:200].split())
        logger.error(
            "Jira returned a non-JSON body from %s (HTTP %s, %s): %s",
            url, resp.status_code, content_type, snippet,
        )
        raise JiraError(
            f"Jira returned HTTP {resp.status_code} with a {content_type} body, not "
            f"JSON. Check JIRA_BASE_URL is the site root "
            f"(https://your-site.atlassian.net) — a URL with a path left on the end "
            f"answers 200 with the Jira web app's HTML. Body starts: {snippet}"
        ) from exc


def find_account_id(email: str, settings: "Settings") -> str | None:
    """Jira accountId for an email address, or None if it cannot be resolved.

    Jira Cloud dropped username/email as user identifiers in the 2019 GDPR
    change — accountId is the only one left — so an email has to be looked up
    before it can be used for anything.

    NEVER RAISES, which is the opposite of create_issue's deliberate fail-closed
    stance and is the point: the operator is waiting on a ticket, not on
    attribution. Every failure here degrades to an unattributed issue plus a
    warning, and none of them may block the filing.

    PRIVACY: this sends the acting ADMIN's email to Jira as a search term. That
    is not the invariant the module docstring protects — that one is about the
    end user who filed the bug, whose address must never reach a whole Jira
    team. An operator's Jira identity is already visible to that team, and the
    address goes into a query string, never into the ticket.
    """
    try:
        import requests  # local import: only this path needs it

        url = f"{browse_base(settings)}{_USER_SEARCH_PATH}"
        resp = requests.get(
            url,
            params={"project": settings.JIRA_PROJECT_KEY, "query": email},
            auth=(settings.JIRA_EMAIL, settings.JIRA_API_TOKEN),
            headers={"Accept": "application/json"},
            timeout=settings.JIRA_TIMEOUT_SECONDS,
        )
        if resp.status_code != 200:
            # Most likely the service account lacks "Browse users and groups".
            logger.warning(
                "Jira user lookup returned HTTP %s: %s",
                resp.status_code, resp.text[:200],
            )
            return None
        try:
            candidates = _json_or_error(resp, url)
        except JiraError:
            # Already logged with the body snippet. Swallowed like every other
            # failure here — create_issue hits the same URL and raises the same
            # message a moment later, where the operator can act on it.
            return None
        for candidate in candidates:
            # Exact match only. `query` also matches displayName, so taking the
            # first hit could file the ticket under a colleague's name. A user
            # whose privacy settings hide their email simply will not match,
            # which lands in the warning path rather than mis-attributing.
            if (candidate.get("emailAddress") or "").lower() == email.lower():
                return candidate.get("accountId")
    except Exception:
        logger.exception("Jira user lookup failed for %s", email)
    return None


def create_issue(
    report: "BugReport",
    reporter: "User | None",
    settings: "Settings",
    admin: "User | None" = None,
) -> JiraResult:
    """Create the Jira issue and return its key (e.g. "NTRIPI-6").

    `admin` is the operator who clicked the button; the issue's Reporter is set
    to them when their email resolves to a Jira account on the project. When it
    does not, the issue is filed anyway under the service account and the
    returned warning says why — attribution must never cost us the ticket.
    """
    if not is_enabled(settings):
        raise JiraError("Jira is not configured.")

    # browse_base normalises what the operator pasted — trailing slash, a board
    # path, a missing scheme — all of which would otherwise fail silently.
    url = f"{browse_base(settings)}{_ISSUE_PATH}"
    payload = {
        "fields": {
            "project": {"key": settings.JIRA_PROJECT_KEY},
            "issuetype": {"name": settings.JIRA_ISSUE_TYPE},
            "summary": _summary(report),
            "description": _adf(_description_lines(report, reporter, settings)),
        }
    }

    warning: str | None = None
    account_id = find_account_id(admin.email, settings) if admin else None
    if account_id:
        payload["fields"]["reporter"] = {"id": account_id}
    elif admin is not None:
        # "Could not match", not "is not a user": a 403 on the search endpoint
        # (service account missing "Browse users and groups") lands here too,
        # and sending the operator off to add an account would not fix that.
        warning = (
            f"Filed under the service account — could not match {admin.email} to a "
            f"Jira user on {settings.JIRA_PROJECT_KEY}. Check they have access to "
            f'the project, and that the service account has "Browse users and groups".'
        )

    def _post() -> Any:
        try:
            import requests  # local import: only this path needs it

            return requests.post(
                url,
                json=payload,
                auth=(settings.JIRA_EMAIL, settings.JIRA_API_TOKEN),
                headers={"Accept": "application/json"},
                timeout=settings.JIRA_TIMEOUT_SECONDS,
            )
        except Exception as exc:
            logger.exception("Jira request failed for bug report %s", report.id)
            raise JiraError(f"Could not reach Jira: {exc!r}") from exc

    resp = _post()

    if resp.status_code == 400 and account_id and "reporter" in resp.text.lower():
        # Reporter is missing from the project's create screen, or the service
        # account lacks "Modify Reporter". Same remedy as an unknown user: drop
        # the attribution, keep the ticket, and say what happened.
        logger.warning("Jira rejected the reporter field: %s", resp.text[:200])
        payload["fields"].pop("reporter")
        warning = (
            "Filed under the service account — Jira rejected the Reporter field "
            "(check that Reporter is on the create screen and that the service "
            "account has Modify Reporter)."
        )
        resp = _post()

    if resp.status_code not in (200, 201):
        # Jira's error body names the offending field — a wrong JIRA_ISSUE_TYPE
        # is the most common first failure, and this is what diagnoses it.
        detail = resp.text[:500]
        logger.error("Jira returned HTTP %s: %s", resp.status_code, detail)
        raise JiraError(f"Jira returned HTTP {resp.status_code}: {detail}")

    data = _json_or_error(resp, url)
    key = data.get("key") if isinstance(data, dict) else None
    if not key:
        logger.error("Jira accepted the issue but returned no key: %s", str(data)[:200])
        raise JiraError("Jira accepted the request but returned no issue key.")

    logger.info("Filed bug report %s as Jira issue %s", report.id, key)
    return JiraResult(key, warning)


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
