"""
services/ordering.py — Fractional indexing for stable lexicographic ordering.

Implements the algorithm described at:
  https://observablehq.com/@dgreensp/implementing-fractional-indexing

Both tracks and stops use TEXT COLLATE "C" rank columns so PostgreSQL sorts
them by byte value — identical to Python's default string comparison.

Public API:
  key_between(a, b)       → a single key strictly between a and b
  n_keys_between(a, b, n) → n evenly-spaced keys between a and b
"""

from __future__ import annotations

# Sorted ASCII alphabet so COLLATE "C" byte comparison == lex order here.
_DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
_N = len(_DIGITS)  # 62
_INITIAL = "a0"  # first key returned for empty list


def _idx(c: str) -> int:
    return _DIGITS.index(c)


def key_between(a: str | None, b: str | None) -> str:
    """
    Return a rank key strictly between a and b (lexicographically).

    None is the open lower or upper bound:
      key_between(None, None) → first key for an empty list
      key_between(None, b)    → a key before b
      key_between(a, None)    → a key after a
    """
    if a is None and b is None:
        return _INITIAL

    if a is not None and b is not None and a >= b:
        raise ValueError(f"key_between: a ({a!r}) must be < b ({b!r})")

    a_d = [_idx(c) for c in a] if a else []
    b_d = [_idx(c) for c in b] if b else []

    result: list[str] = []
    i = 0
    b_open = b is None  # True once we've committed to being less than b

    while True:
        av = a_d[i] if i < len(a_d) else 0

        if b_open:
            # No upper constraint at this position — step one above a.
            if av < _N - 1:
                result.append(_DIGITS[av + 1])
            else:
                # a's digit is max: extend with a small extra digit.
                result.append(_DIGITS[av])
                result.append(_DIGITS[1])
            return "".join(result)

        bv = b_d[i] if i < len(b_d) else 0

        if av == bv:
            result.append(_DIGITS[av])
            i += 1
            continue

        # av < bv guaranteed (a < b)
        gap = bv - av
        if gap > 1:
            result.append(_DIGITS[av + gap // 2])
            return "".join(result)

        # gap == 1: digits are adjacent — record av, then b is unconstrained.
        result.append(_DIGITS[av])
        i += 1
        b_open = True


def n_keys_between(a: str | None, b: str | None, n: int) -> list[str]:
    """
    Return n keys evenly distributed between a and b.
    Uses recursive bisection to keep keys well-spread.
    """
    if n == 0:
        return []
    if n == 1:
        return [key_between(a, b)]
    mid_i = n // 2
    mid = key_between(a, b)
    return (
        n_keys_between(a, mid, mid_i)
        + [mid]
        + n_keys_between(mid, b, n - mid_i - 1)
    )
