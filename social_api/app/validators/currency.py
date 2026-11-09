"""validators/currency.py — a trip's currency is a code from the ISO list.

The currency shows on every trip card, and until 2026-11-09 the API took any
three characters for it: text no moderation read, on every card. It is now a
code from constants/currencies.py — exactly what the app's picker offers.

Refused only when the value changes, as the link rule refuses only a changed
text (validators/links.py): the trip form sends the currency on every save, so
a trip saved before the rule — or priced in a currency later withdrawn from the
list — must stay editable without the owner having to change it first.
"""

from __future__ import annotations

from typing import Any

from fastapi import status

from app.constants.currencies import ISO_4217_CURRENCIES
from app.errors import ApiError


def refuse_unknown_currency(data: dict[str, Any], stored: Any | None = None) -> None:
    """Raises 422 `currency_not_supported` when `data` sets a currency outside
    the list. `stored` is the row being edited, or None on a create. Callers run
    this before moderation, so a refused write costs no provider call."""
    if "currency" not in data:
        return
    value = data["currency"]
    if value in ISO_4217_CURRENCIES:
        return
    if stored is not None and value == getattr(stored, "currency", None):
        return
    raise ApiError(
        status.HTTP_422_UNPROCESSABLE_ENTITY,
        "currency_not_supported",
        "This currency is not supported.",
    )
