"""
services/openai_http.py — the one place that speaks HTTP to OpenAI.

Text moderation and translation both call OpenAI with OPENAI_API_KEY and a
blocking `requests.post`. Blocking is the right shape here: every caller runs
inside a sync `def` endpoint, which FastAPI runs in a threadpool — see
text_moderation_providers for why making these async would be the real hazard.

PRIVACY: callers put only the text and what the model needs to process it in
`body` — never a user id, an email or a content id.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from app.config import Settings

_BASE_URL = "https://api.openai.com/v1"


def post_json(settings: "Settings", path: str, body: dict, timeout: float):
    """POST `body` to /v1/<path>. Network errors propagate; status codes are the
    caller's to interpret."""
    import requests  # local import: only these paths need it

    return requests.post(
        f"{_BASE_URL}/{path}",
        headers={
            "Authorization": f"Bearer {settings.OPENAI_API_KEY}",
            "Content-Type": "application/json",
        },
        json=body,
        timeout=timeout,
    )
