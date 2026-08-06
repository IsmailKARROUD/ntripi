"""bug report jira issue key

Records the Jira issue an operator filed from /admin/bugs. Nullable and
unconstrained — project keys are opaque, and the overwhelming majority of
reports are triaged without ever reaching Jira.

The column doubles as state: its presence is what hides the "Create Jira issue"
button and makes the route refuse a second API call, so two operators working
the queue cannot file duplicates for the same report.

Revision ID: 87495daa26f9
Revises: 8cd9a4fe3396
Create Date: 2026-08-06 00:17:09.516609+00:00

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '87495daa26f9'
down_revision: Union[str, None] = '8cd9a4fe3396'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'bug_reports',
        sa.Column('jira_issue_key', sa.String(length=32), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('bug_reports', 'jira_issue_key')
