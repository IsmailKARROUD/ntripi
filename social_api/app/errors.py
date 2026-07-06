"""errors.py — API error type carrying a stable machine-readable code.

The Flutter client localizes errors by `code`, falling back to the human
`detail` string and then a generic message. `detail` is kept byte-identical to
the pre-existing HTTPException messages so web templates and existing tests are
unaffected — `code` is purely additive.

Register `api_error_handler` in main.py so the JSON body includes both fields.
Plain `HTTPException` (no code) keeps emitting `{"detail": ...}` unchanged.
"""

from __future__ import annotations

from starlette.exceptions import HTTPException


class ApiError(HTTPException):
    """HTTPException with an extra stable `code` for client-side localization."""

    def __init__(
        self,
        status_code: int,
        code: str,
        detail: str,
        headers: dict | None = None,
    ) -> None:
        super().__init__(status_code=status_code, detail=detail, headers=headers)
        self.code = code
