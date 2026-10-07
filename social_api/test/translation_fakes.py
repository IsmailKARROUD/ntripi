"""
translation_fakes.py — a scripted translation engine for tests. No network.

Lives in test/ so production code can never construct it.
"""

from app.services.translation_providers import FieldOutput, TranslationResult


class FakeTranslator:
    """Answers "[<lang>] <text>" for every field unless told otherwise.

    fail       — an exception to raise from every call.
    overrides  — source text → translation to return instead; None leaves the
                 field out of the answer entirely.
    source_lang — the language reported for every source.
    """

    def __init__(self, name: str = "fake", *, fail: Exception | None = None,
                 overrides: dict[str, str | None] | None = None,
                 source_lang: str | None = "en",
                 max_batch_fields: int = 50, max_batch_chars: int = 100_000,
                 daily_char_budget: int | None = None) -> None:
        self.name = name
        self.model = f"{name}-model"
        self.fail = fail
        self.overrides = overrides or {}
        self.source_lang = source_lang
        self.max_batch_fields = max_batch_fields
        self.max_batch_chars = max_batch_chars
        self.daily_char_budget = daily_char_budget
        self.calls: list[tuple[dict[str, str], str]] = []

    def translate(self, fields: dict[str, str], target_lang: str) -> TranslationResult:
        self.calls.append((dict(fields), target_lang))
        if self.fail is not None:
            raise self.fail
        outputs = {}
        for key, text in fields.items():
            translated = self.overrides.get(text, f"[{target_lang}] {text}")
            if translated is not None:
                outputs[key] = FieldOutput(text=translated, source_lang=self.source_lang)
        return TranslationResult(outputs=outputs, provider=self.name, model=self.model)

    @property
    def keys_seen(self) -> list[str]:
        return [key for fields, _ in self.calls for key in fields]
