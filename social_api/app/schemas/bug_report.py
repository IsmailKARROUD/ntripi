"""
schemas/bug_report.py — Response schema for in-app bug reports.

There is no Create schema: POST /bug-reports is multipart (the screenshot rides
in the same request as the fields), so FastAPI takes the fields as Form(...)
parameters and there is no JSON body for Pydantic to validate.

The ack carries the new id so a future client can reference the report — the
in-app flow only shows a thank-you, but a support reply needs something to quote.
"""

from __future__ import annotations

import uuid

from pydantic import BaseModel


class BugReportAck(BaseModel):
    ok: bool = True
    id: uuid.UUID
