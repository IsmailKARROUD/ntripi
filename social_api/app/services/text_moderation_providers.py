"""
services/text_moderation_providers.py — swappable text-classification backends.

Each provider turns text into a {category: score} dict using the OpenAI
omni-moderation category names; the Ntripi thresholds in moderation_policy
interpret those scores. Adding a provider means implementing `score()` and
`score_many()` (the batch form, used to vet translations) and listing it in
`get_provider_chain` — no changes anywhere else, so switching is a
configuration change.

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

from app.services import openai_http
from app.services.moderation_policy import CATEGORY_THRESHOLDS

if TYPE_CHECKING:
    from app.config import Settings

logger = logging.getLogger(__name__)

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

    def score_many(self, texts: list[str]) -> list[ProviderResult]:
        """Classify each text in one call, results in input order. Raises
        ProviderUnavailableError on any failure."""
        ...


class OpenAIProvider:
    """OpenAI Moderation API (omni-moderation-latest by default)."""

    name = "openai"

    def __init__(self, settings: "Settings") -> None:
        self._settings = settings
        self._timeout = settings.TEXT_MODERATION_TIMEOUT_SECONDS
        self.model = settings.TEXT_MODERATION_MODEL

    def score(self, text: str) -> ProviderResult:
        return self._classify(text)[0]

    def score_many(self, texts: list[str]) -> list[ProviderResult]:
        # The endpoint takes an array and answers one result per input, so a
        # batch costs one request rather than one per text.
        return self._classify(texts)

    def _classify(self, payload_input: str | list[str]) -> list[ProviderResult]:
        expected = len(payload_input) if isinstance(payload_input, list) else 1
        try:
            resp = openai_http.post_json(
                self._settings, "moderations",
                # The text and the model — nothing that identifies the author.
                {"model": self.model, "input": payload_input},
                self._timeout,
            )
        except Exception as exc:
            raise ProviderUnavailableError(f"openai request failed: {exc!r}") from exc

        if resp.status_code != 200:
            raise ProviderUnavailableError(
                f"openai returned HTTP {resp.status_code}"
            )

        try:
            payload = resp.json()
            results = payload["results"]
            raw = [result["category_scores"] for result in results]
            # The response echoes the resolved model (e.g. a dated snapshot);
            # record that rather than the alias, so the cache key tracks the
            # model actually used.
            model = payload.get("model") or self.model
        except Exception as exc:
            raise ProviderUnavailableError(f"openai response unparseable: {exc!r}") from exc
        if len(raw) != expected:
            raise ProviderUnavailableError(
                f"openai answered {len(raw)} results for {expected} inputs"
            )

        return [
            ProviderResult(
                scores={
                    category: float(raw_scores.get(category, 0.0) or 0.0)
                    for category in CATEGORY_THRESHOLDS
                },
                provider=self.name,
                model=model,
            )
            for raw_scores in raw
        ]


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
        return self.score_many([text])[0]

    def score_many(self, texts: list[str]) -> list[ProviderResult]:
        try:
            from profanity_check import predict_prob  # local import: optional dep

            probabilities = [float(p) for p in predict_prob(texts)]
        except Exception as exc:
            raise ProviderUnavailableError(f"local classifier failed: {exc!r}") from exc

        results = []
        for probability in probabilities:
            scores = {category: 0.0 for category in CATEGORY_THRESHOLDS}
            for category in _LOCAL_MAPPED_CATEGORIES:
                scores[category] = probability
            results.append(
                ProviderResult(scores=scores, provider=self.name, model=self.model)
            )
        return results


def get_provider_chain(settings: "Settings") -> list[TextModerationProvider]:
    """Providers to try in order. The first success wins; exhausting the chain
    leaves content 'pending' for the sweep to re-check."""
    provider = settings.TEXT_MODERATION_PROVIDER
    if provider == "openai":
        return [OpenAIProvider(settings), LocalProvider()]
    if provider == "local":
        return [LocalProvider()]
    return []
