"""
services/text_moderation_providers.py — swappable text-classification backends.

Each provider turns text into a {category: score} dict using the OpenAI
omni-moderation category names; the Ntripi thresholds in moderation_policy
interpret those scores. Adding a provider means implementing `score()` and
listing it in `get_provider_chain` — no changes anywhere else, so switching is
a configuration change.

PRIVACY (hard requirement): the OpenAI request body carries the text and the
model name, nothing else. No user id, email, itinerary id, or session data ever
reaches the provider.

These calls BLOCK. That is deliberate: every text write path is a sync `def`
endpoint, which FastAPI runs in a threadpool, so a blocking call with a timeout
never touches the event loop. Making them async would force the endpoints to
`async def`, which would put the sync SQLAlchemy session on the loop instead —
the actual hazard. Same reasoning as pwned_service.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import TYPE_CHECKING, Protocol

from app.services.moderation_policy import CATEGORY_THRESHOLDS

if TYPE_CHECKING:
    from app.config import Settings

logger = logging.getLogger(__name__)

_OPENAI_ENDPOINT = "https://api.openai.com/v1/moderations"

# alt-profanity-check returns one probability, not per-category scores. Map it
# onto the two categories a wordlist-grade signal can honestly support; leaving
# the rest at 0.0 means the fallback can never trigger the minors special case.
_LOCAL_MAPPED_CATEGORIES = ("harassment", "hate")


class ProviderUnavailableError(Exception):
    """Raised when a provider cannot produce a verdict (network, auth, parse).
    Signals the orchestrator to try the next provider in the chain."""


@dataclass(frozen=True)
class ProviderResult:
    scores: dict[str, float]  # keys are omni-moderation category names
    provider: str
    model: str


class TextModerationProvider(Protocol):
    name: str
    model: str

    def score(self, text: str) -> ProviderResult:
        """Classify `text`. Raises ProviderUnavailableError on any failure."""
        ...


class OpenAIProvider:
    """OpenAI Moderation API (omni-moderation-latest by default)."""

    name = "openai"

    def __init__(self, settings: "Settings") -> None:
        self._api_key = settings.OPENAI_API_KEY
        self._timeout = settings.TEXT_MODERATION_TIMEOUT_SECONDS
        self.model = settings.TEXT_MODERATION_MODEL

    def score(self, text: str) -> ProviderResult:
        try:
            import requests  # local import: only this path needs it

            resp = requests.post(
                _OPENAI_ENDPOINT,
                headers={
                    "Authorization": f"Bearer {self._api_key}",
                    "Content-Type": "application/json",
                },
                # The text and the model — nothing that identifies the author.
                json={"model": self.model, "input": text},
                timeout=self._timeout,
            )
        except Exception as exc:
            raise ProviderUnavailableError(f"openai request failed: {exc!r}") from exc

        if resp.status_code != 200:
            raise ProviderUnavailableError(
                f"openai returned HTTP {resp.status_code}"
            )

        try:
            payload = resp.json()
            result = payload["results"][0]
            raw_scores = result["category_scores"]
            # The response echoes the resolved model (e.g. a dated snapshot);
            # record that rather than the alias, so the cache key tracks the
            # model actually used.
            model = payload.get("model") or self.model
        except Exception as exc:
            raise ProviderUnavailableError(f"openai response unparseable: {exc!r}") from exc

        scores = {
            category: float(raw_scores.get(category, 0.0) or 0.0)
            for category in CATEGORY_THRESHOLDS
        }
        return ProviderResult(scores=scores, provider=self.name, model=model)


class LocalProvider:
    """alt-profanity-check — a self-contained classifier, no network.

    Used as the fallback when the primary provider is unavailable, and as the
    sole provider when TEXT_MODERATION_PROVIDER='local'. Its single profanity
    probability is a much coarser signal than per-category scores, so it only
    populates the harassment/hate categories.
    """

    name = "local"
    model = "alt-profanity-check"

    def score(self, text: str) -> ProviderResult:
        try:
            from profanity_check import predict_prob  # local import: optional dep

            probability = float(predict_prob([text])[0])
        except Exception as exc:
            raise ProviderUnavailableError(f"local classifier failed: {exc!r}") from exc

        scores = {category: 0.0 for category in CATEGORY_THRESHOLDS}
        for category in _LOCAL_MAPPED_CATEGORIES:
            scores[category] = probability
        return ProviderResult(scores=scores, provider=self.name, model=self.model)


def get_provider_chain(settings: "Settings") -> list[TextModerationProvider]:
    """Providers to try in order. The first success wins; exhausting the chain
    leaves content 'pending' for the sweep to re-check."""
    provider = settings.TEXT_MODERATION_PROVIDER
    if provider == "openai":
        return [OpenAIProvider(settings), LocalProvider()]
    if provider == "local":
        return [LocalProvider()]
    return []
