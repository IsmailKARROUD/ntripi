import re
from typing import Callable

# Conservative policy:
# - Must start with a letter
# - Middle chars: letters, digits, period, underscore
# - Must end with a letter or digit
# - Total length: 4-30 chars
USERNAME_PATTERN = re.compile(
    r"^[a-zA-Z][a-zA-Z0-9_.]{2,28}[a-zA-Z0-9]$"
)

# Reject any consecutive special chars (.., __, ._, _.)
CONSECUTIVE_SPECIAL = re.compile(r"[._]{2,}|[._][._]")

RESERVED_USERNAMES = frozenset({
    "admin", "administrator", "root", "system", "sysadmin",
    "ntripi", "official", "support", "help", "info",
    "contact", "feedback", "abuse", "moderator", "mod",
    "api", "app", "www", "mail", "email", "smtp",
    "auth", "login", "register", "signup", "signin",
    "logout", "signout", "user", "users", "me", "self",
    "anonymous", "anon", "guest", "everyone", "public",
    "null", "undefined", "true", "false", "none",
    "static", "assets", "share", "downloads",
    "settings", "profile", "account", "billing",
    "privacy", "terms", "tos", "guidelines", "about", "home",
    "search", "explore", "discover", "feed",
})


def validate_username(value: str) -> str:
    """Validates a username. Returns trimmed value or raises ValueError."""
    if not value:
        raise ValueError("Username is required.")

    value = value.strip()

    if len(value) < 4:
        raise ValueError("Username must be at least 4 characters long.")
    if len(value) > 30:
        raise ValueError("Username cannot exceed 30 characters.")

    if not USERNAME_PATTERN.match(value):
        raise ValueError(
            "Username must start with a letter, end with a letter or "
            "number, and contain only letters, numbers, periods, or "
            "underscores. Hyphens and spaces are not allowed."
        )

    if CONSECUTIVE_SPECIAL.search(value):
        raise ValueError(
            "Username cannot contain consecutive periods or underscores."
        )

    if value.lower() in RESERVED_USERNAMES:
        raise ValueError("This username is reserved. Please choose another.")

    return value


def normalize_username(value: str) -> str:
    """Returns the canonical (lowercase) form of a username."""
    return value.strip().lower()


# Used by generate_username_from to sanitize an arbitrary seed into the
# restricted username alphabet.
_USERNAME_DISALLOWED = re.compile(r"[^a-z0-9._]")
_USERNAME_SPECIAL_RUN = re.compile(r"[._]{2,}")


def generate_username_from(seed: str, is_taken: Callable[[str], bool]) -> str:
    """
    Derive a valid, available username from an email or display name.

    Google sign-ups don't supply a username, so we synthesize one. The seed is
    sanitized to satisfy validate_username (4-30 chars, starts with a letter,
    ends alnum, no consecutive '.'/'_', not reserved), then a numeric suffix is
    appended until the result is free.

    `is_taken` receives a normalized (lowercase) candidate and returns True when
    a user already owns it — supplied by the caller so this module stays DB-free.
    """
    base = (seed or "").strip().lower()
    if "@" in base:
        base = base.split("@", 1)[0]                  # email local-part only
    base = _USERNAME_DISALLOWED.sub("", base)         # drop chars outside [a-z0-9._]
    base = _USERNAME_SPECIAL_RUN.sub("_", base)       # collapse consecutive ./_ runs
    base = base.lstrip("._0123456789")                # must start with a letter
    base = base.rstrip("._")                          # must end with a letter/digit

    # Seed produced nothing usable (e.g. all-numeric or all-symbol handle).
    if len(base) < 3 or base in RESERVED_USERNAMES:
        base = "traveler"

    base = base[:26].rstrip("._")                     # leave room for a suffix; trim trailing special

    candidate = base
    suffix = 0
    while True:
        try:
            validate_username(candidate)
            taken = is_taken(normalize_username(candidate))
        except ValueError:
            taken = True                              # too short / reserved → force a suffix
        if not taken:
            return candidate
        suffix += 1
        # Keep within the 30-char ceiling once the numeric suffix is appended.
        candidate = f"{base[:30 - len(str(suffix))].rstrip('._')}{suffix}"


def validate_display_name(value: str | None) -> str | None:
    """Validates an optional display name. Returns cleaned value or None."""
    if value is None:
        return None
    value = value.strip()
    if not value:
        return None
    if len(value) > 50:
        raise ValueError("Display name cannot exceed 50 characters.")
    for c in value:
        code = ord(c)
        if code < 32 or code == 0x200B or code == 0x200C or code == 0x200D:
            raise ValueError("Display name contains invalid characters.")
    return value
