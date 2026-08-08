"""
services/age_service.py — the minimum-age rule, in one place.

Single source of truth for how old an account holder must be, mirroring the
role can_view_itinerary() plays for access control: three write paths enforce
this (register, Google signup, the re-acceptance gate) and none of them may
re-implement the arithmetic.

16 rather than 13: it clears GDPR Art. 8's digital-consent age in every member
state, so no parental-consent path is ever required. It does NOT imply contract
capacity — the ToS keeps its separate age-of-majority / guardian clause.
"""

from datetime import date

MINIMUM_AGE = 16

# Nobody alive is older than this; a date implying more is a typo or a probe,
# not a birthday. Guards the schema, not the age gate.
MAX_PLAUSIBLE_AGE = 120


def calculate_age(dob: date, today: date | None = None) -> int:
    """Completed years between `dob` and `today` (defaults to the current date).

    The tuple comparison is what makes leap-year births behave: someone born
    2008-02-29 has not yet had a birthday on 2024-02-28, because
    (2, 28) < (2, 29), so they turn 16 on 2024-03-01.
    """
    today = today or date.today()
    return today.year - dob.year - ((today.month, today.day) < (dob.month, dob.day))


def is_old_enough(dob: date, today: date | None = None) -> bool:
    """True when this date of birth clears MINIMUM_AGE."""
    return calculate_age(dob, today) >= MINIMUM_AGE


def is_plausible(dob: date, today: date | None = None) -> bool:
    """Shape check: not in the future, not absurdly long ago.

    Deliberately separate from is_old_enough — a malformed date is a 422 about
    the request, while a real date under 16 is a 400 about the person.
    """
    today = today or date.today()
    return dob <= today and calculate_age(dob, today) <= MAX_PLAUSIBLE_AGE
