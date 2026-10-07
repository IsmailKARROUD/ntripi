"""
test_translation_validation.py — the checks a translation must pass before it
is cached. Each rule catches one way an engine goes wrong; none of them may
refuse an ordinary, faithful translation.
"""

import pytest

from app.services.translation_validation import failure


@pytest.mark.parametrize("source, translation", [
    ("Walk along the harbour at sunset.", "Marchez le long du port au coucher du soleil."),
    # Trailing punctuation is not part of the URL.
    ("Book ahead: https://example.com/tickets.", "Réservez : https://example.com/tickets"),
    ("Ask @marie_k at the front desk.", "Demandez à @marie_k à l'accueil."),
    ("Write to bob@example.com before you go.", "Écrivez à bob@example.com avant de partir."),
    ("Great view 🌅 from the top!", "Superbe vue 🌅 depuis le sommet !"),
    ("**Tip:** bring cash\n- for the bus\n- for the market",
     "**Conseil :** prenez du liquide\n- pour le bus\n- pour le marché"),
    # Too short for a ratio to mean anything.
    ("Paris", "París, la capitale"),
    # CJK packs a word into a character or two: far shorter is still right.
    ("A slow weekend walking around the old harbour.", "在老港口周围悠闲漫步的周末。"),
    ("在老港口周围悠闲漫步的周末。", "A slow weekend walking around the old harbour."),
    ("A slow weekend walking around the old harbour.", "عطلة نهاية أسبوع هادئة حول الميناء القديم."),
], ids=["plain", "url", "mention", "email", "emoji", "markdown", "short", "en-zh", "zh-en", "en-ar"])
def test_a_faithful_translation_passes(source, translation):
    assert failure(source, translation) is None


@pytest.mark.parametrize("source, translation, reason", [
    ("Walk along the harbour.", "   ", "empty"),
    ("Book ahead: https://example.com/tickets", "Réservez à l'avance.", "url"),
    ("Book ahead: https://example.com/tickets", "Réservez : https://example.fr/billets", "url"),
    ("Ask @marie_k at the desk.", "Demandez à Marie à l'accueil.", "mention"),
    ("Great view 🌅 from the top!", "Superbe vue depuis le sommet !", "symbols"),
    ("First paragraph here.\n\nSecond paragraph here.",
     "Premier paragraphe ici. Deuxième paragraphe ici.", "lines"),
    ("We spent two quiet days walking along the harbour, eating fresh fish and "
     "watching the boats come in at sunset every single evening.",
     "Belle balade.", "length"),
    ("A short note about the harbour.",
     "Une note sur le port. " * 20, "length"),
], ids=["empty", "url-dropped", "url-changed", "mention-dropped", "emoji-dropped",
        "lines-merged", "summarised", "padded"])
def test_an_unfaithful_translation_fails_for_its_reason(source, translation, reason):
    assert failure(source, translation) == reason


def test_a_dropped_variation_selector_is_not_a_missing_emoji():
    """❤️ is a heart plus U+FE0F; an engine that normalises the selector away
    still kept the emoji."""
    assert failure("Loved it ❤️ so much here.", "Adoré ❤ vraiment ici.") is None
