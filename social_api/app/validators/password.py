import unicodedata

# bcrypt refuses input longer than 72 bytes (bcrypt 5.x raises ValueError).
BCRYPT_MAX_BYTES = 72


def validate_password_strength(value: str) -> str:
    """Shared policy for register / reset / change password. Returns the value
    unchanged or raises ValueError (Pydantic field validators surface it as 422)."""
    # ASCII digits only — matches the client's [0-9] rule; Python's isdigit()
    # would also accept Arabic-Indic digits the client rejects.
    if not any("0" <= c <= "9" for c in value):
        raise ValueError("Password must contain at least one digit.")

    # Check the NFKC form: hash_password normalizes before hashing, and some
    # characters expand under NFKC, so the raw byte length can undercount.
    normalized = unicodedata.normalize("NFKC", value)
    if len(normalized.encode("utf-8")) > BCRYPT_MAX_BYTES:
        raise ValueError(
            "Password is too long — up to 72 characters, fewer when using "
            "non-Latin letters."
        )

    return value
