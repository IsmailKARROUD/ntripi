"""
services/ordering.py — Fractional indexing for stable lexicographic ordering.

WHY FRACTIONAL INDEXING?
  Classic integer positions (1, 2, 3…) require updating every row above an
  insertion point. With 50 stops and a mid-list insert, that's 25 UPDATE
  statements — and they race with concurrent edits.

  Fractional indexing gives every item a short string "rank". Inserting
  between ranks "a0" and "b" just picks the midpoint (e.g. "aV") and writes
  ONE row. No other rows are touched. Re-ranking is never needed unless the
  app runs out of space between two adjacent keys — which takes thousands of
  inserts at the exact same gap.

HOW THE ALGORITHM WORKS:
  Keys are base-62 strings over the alphabet below (sorted ASCII). The
  algorithm walks digit-by-digit: when two ranks share the same digit at a
  position it moves to the next position; when there is a gap of ≥2 it picks
  the midpoint digit. When digits are adjacent (gap==1) it records the lower
  digit and opens the upper bound, then extends one more position.

  Examples:
    key_between(None, None)  → "a0"       (initial key for an empty list)
    key_between("a0", None)  → "b"        (one step after a0)
    key_between("a0", "b")   → "aV"       (midpoint — 'V' is index 31, halfway)
    key_between("a0", "a1")  → "a01"      (adjacent digits: extend one level)

WHY TEXT COLLATE "C" IN POSTGRES?
  The default PostgreSQL collation is locale-aware (e.g. en_US). That changes
  the sort order of uppercase vs lowercase letters and makes it different from
  Python's string comparison. COLLATE "C" enforces pure byte order — identical
  to how Python compares strings — so ORDER BY rank in SQL produces the same
  order as sorting the strings in Python.

Public API:
  key_between(a, b)       → a single key strictly between a and b
  n_keys_between(a, b, n) → n evenly-spaced keys between a and b
"""

from __future__ import annotations

# Base-62 alphabet. Order matters: '0' < '9' < 'A' < 'Z' < 'a' < 'z' in
# ASCII, so byte-wise sort (COLLATE "C") puts digits before uppercase before
# lowercase — exactly the order of this string.
_DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
_N = len(_DIGITS)  # 62
_INITIAL = "a0"  # first key returned for an empty list

# When a freshly computed rank exceeds this length the caller should rebalance
# the surrounding column before persisting. After ~6 halvings each subsequent
# insert at the same edge appends one character, so a track that drives the
# leading rank past this threshold is in pathological territory and a single
# pass of n_keys_between(None, None, count) brings every rank back to ≤2 chars.
MAX_RANK_LENGTH = 32


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

    # Convert each character to its index in _DIGITS.
    a_d = [_idx(c) for c in a] if a else []
    b_d = [_idx(c) for c in b] if b else []

    result: list[str] = []
    i = 0
    # b_open becomes True when we've already committed to being below b at an
    # earlier digit position. After that, b provides no more constraint and we
    # just need to produce something strictly greater than the remaining a digits.
    b_open = b is None

    while True:
        # Past the end of a → pad with 0 (the minimum digit).
        av = a_d[i] if i < len(a_d) else 0

        if b_open:
            # b provides no upper constraint. Step one digit above a.
            if av < _N - 1:
                result.append(_DIGITS[av + 1])
            else:
                # a's digit is already at the maximum — we can't go one higher
                # at this position, so write it and add a small extra digit.
                result.append(_DIGITS[av])
                result.append(_DIGITS[1])
            return "".join(result)

        # Past the end of b → pad with 0.
        bv = b_d[i] if i < len(b_d) else 0

        if av == bv:
            # Same digit: no room to split here, move to the next position.
            result.append(_DIGITS[av])
            i += 1
            continue

        # av < bv is guaranteed because a < b lexicographically.
        gap = bv - av
        if gap > 1:
            # There is at least one digit between av and bv — take the midpoint.
            result.append(_DIGITS[av + gap // 2])
            return "".join(result)

        # gap == 1: the two digits are adjacent (e.g. 'a' and 'b'). We can't
        # fit anything between them at this position alone, so we record av
        # (committing the result to start with …av) and set b_open=True because
        # the result is now already guaranteed to be < b at this digit position.
        result.append(_DIGITS[av])
        i += 1
        b_open = True


def n_keys_between(a: str | None, b: str | None, n: int) -> list[str]:
    """
    Return n keys evenly distributed between a and b.

    Uses recursive binary bisection so keys stay well-spread rather than
    crowding toward one end. For example, n=3 between "a0" and "z" gives
    roughly ["G", "a0", "m"] — evenly spaced across the space.
    """
    if n == 0:
        return []
    if n == 1:
        return [key_between(a, b)]
    # Split at the midpoint, then recurse on each half independently.
    # This ensures all n keys are roughly equidistant.
    mid_i = n // 2
    mid = key_between(a, b)
    return (
        n_keys_between(a, mid, mid_i)
        + [mid]
        + n_keys_between(mid, b, n - mid_i - 1)
    )
