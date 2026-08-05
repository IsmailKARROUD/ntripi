"""
models/bug_report.py — SQLAlchemy ORM model for bug_reports.

A bug report is a user telling us the *app* is broken, not that content is
inappropriate — the two are deliberately separate tables. content_reports is
moderation evidence with hide thresholds and legal escalation paths; a bug
report is a support ticket with a screenshot and device diagnostics, reviewed
from /admin/bugs and purged once it is closed and stale.

The screenshot is stored as a storage KEY, not a URL: the admin lane derives
the URL with storage().public_url(), and the retention purge needs the key to
delete the object. It also keeps bug screenshots outside
admin_service.parse_storage_key, which only knows the three published-content
prefixes and whose job is refusing to guess.

Category, platform and status are constrained strings (String + CheckConstraint)
rather than native enums, matching the project convention (see ck_leg_mode and
ck_report_reason). The tuples below are the single source of truth, mirrored by
the check constraints and by the Flutter client's kBugCategories.
"""

import uuid
from datetime import datetime

from sqlalchemy import (
    CheckConstraint, DateTime, ForeignKey, Index, String, Text, func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# What kind of problem the reporter picked. Optional — a report with only a
# message is still worth having, so the column is nullable.
BUG_CATEGORIES = ("crash", "visual", "data", "slow", "other")

# Values the client may send for `platform`. Anything else is rejected by the
# check constraint rather than silently stored, so the admin lane can group on it.
BUG_PLATFORMS = ("ios", "android", "web", "macos", "windows", "linux")

# open → the operator has not looked at it yet; closed → triaged, and eligible
# for the retention purge. There is deliberately no "wontfix"/"fixed" split:
# the resolution note carries that, and a wider vocabulary would need an
# admin UI nobody asked for.
BUG_REPORT_STATUSES = ("open", "closed")

_CATEGORIES_SQL = ",".join(f"'{value}'" for value in BUG_CATEGORIES)
_PLATFORMS_SQL = ",".join(f"'{value}'" for value in BUG_PLATFORMS)
_STATUSES_SQL = ",".join(f"'{value}'" for value in BUG_REPORT_STATUSES)


class BugReport(Base):
    __tablename__ = "bug_reports"
    __table_args__ = (
        CheckConstraint(
            f"category IS NULL OR category IN ({_CATEGORIES_SQL})",
            name="ck_bug_report_category",
        ),
        CheckConstraint(
            f"platform IS NULL OR platform IN ({_PLATFORMS_SQL})",
            name="ck_bug_report_platform",
        ),
        CheckConstraint(
            f"status IN ({_STATUSES_SQL})",
            name="ck_bug_report_status",
        ),
        # The only query the admin lane runs: open reports, oldest first.
        Index("ix_bug_reports_status_created", "status", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    # SET NULL, not CASCADE: the diagnostic value of a bug report outlives the
    # account that filed it. Nullable also because the endpoint is auth-optional
    # — someone stuck on the login screen is exactly who needs to report.
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )

    message: Mapped[str] = mapped_column(Text, nullable=False)
    category: Mapped[str | None] = mapped_column(String(16), nullable=True)

    # Storage key (e.g. "bug_reports/<uuid>.jpg"), never a URL — see the module
    # docstring. Null when the capture failed or the reporter removed it.
    screenshot_key: Mapped[str | None] = mapped_column(String(255), nullable=True)

    # ── Diagnostics, all best-effort: a throwing platform channel on the client
    # yields null rather than a failed report. ────────────────────────────────
    app_version: Mapped[str | None] = mapped_column(String(32), nullable=True)
    platform: Mapped[str | None] = mapped_column(String(16), nullable=True)
    os_version: Mapped[str | None] = mapped_column(String(64), nullable=True)
    device_model: Mapped[str | None] = mapped_column(String(96), nullable=True)
    route: Mapped[str | None] = mapped_column(String(255), nullable=True)
    locale: Mapped[str | None] = mapped_column(String(8), nullable=True)
    theme_mode: Mapped[str | None] = mapped_column(String(8), nullable=True)

    status: Mapped[str] = mapped_column(
        String(16), nullable=False, default="open", server_default="open",
    )
    resolution_note: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(),
    )
    closed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True,
    )
    closed_by_admin_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
