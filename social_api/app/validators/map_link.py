"""validators/map_link.py — is this a Google Maps link, and nothing else?

A stop's `map_url` is the one link a reader can tap ("Open in Google Maps"), so
it is the one user-supplied link that must lead where it says. A host check is
not enough: Google's own redirect pages (`maps.google.com/url?q=…`, `/amp/s/…`)
live on the same hosts and are a long-documented phishing route, a path such as
`/maps/../url` passes a "starts with /maps" test and a browser resolves it to
`/url`, and `https://evil.example\\@maps.google.com/` reads as Google to
`urlparse` but as evil.example to a browser. So only the link shapes Google
Maps itself produces pass:

  maps.app.goo.gl/<code>      the share sheet's short link
  goo.gl/maps/<code>          the old short link
  (www.)google.com/maps…      place, search, directions, viewport, My Maps
  maps.google.com[/maps…]     the legacy host

with no userinfo or port, no dot segment (raw or escaped), no backslash, no
whitespace or invisible character, and no web address hidden in the query or
the fragment.

The app mirrors this exactly — `isGoogleMapsUrl` in social_flutter's
lib/features/itineraries/data/google_maps_links.dart — and both are held to one
sample list, social_flutter/test/support/map_link_samples.json.
"""

from __future__ import annotations

import re

_HOSTS = frozenset({
    "maps.app.goo.gl", "goo.gl", "google.com", "www.google.com", "maps.google.com",
})

# Characters a link never needs and a spoof always does: ASCII and C1 controls,
# spaces of every kind, zero-width and bidi controls, the BOM, and the
# backslash browsers read as a slash. One explicit class (not `\s`) so Python
# and Dart refuse exactly the same characters.
_UNSAFE = re.compile(
    r"[\u0000- \u007f-\u009f   -‏ - "
    r" -⁯　﻿\\]"
)
# Only ASCII blanks are trimmed — the same set the app trims.
_EDGE_BLANKS = " \t\n\r\f\v"
_BAD_ESCAPE = re.compile(r"%(?![0-9A-Fa-f]{2})")
_ASCII_ESCAPE = re.compile(r"%([0-7][0-9A-Fa-f])")
_PARTS = re.compile(
    r"^(?P<scheme>[A-Za-z][A-Za-z0-9+.-]*)://(?P<authority>[^/?#]*)"
    r"(?P<path>[^?#]*)(?:\?(?P<query>[^#]*))?(?:#(?P<fragment>.*))?$",
    re.S,
)
_SHORT_PATH = re.compile(r"/[A-Za-z0-9_-]+/?")
_GOO_GL_PATH = re.compile(r"/maps/[A-Za-z0-9_-]+/?")
# A web address inside the query or fragment: any scheme://, a protocol-relative
# //, a backslash, a script/data/file scheme, or a www. name. ASCII-only
# matching (re.A, explicit look-behinds instead of \b) so Python and Dart agree
# on every character.
_EMBEDDED_ADDRESS = re.compile(
    r"[a-z][a-z0-9+.-]*://|//|\\"
    r"|(?<![a-z0-9_])(?:https?|javascript|vbscript|data|file|ftp):"
    r"|(?<![a-z0-9])www\.",
    re.I | re.A,
)


def strip_link(url: str) -> str:
    """The link without surrounding ASCII blanks — what is stored."""
    return url.strip(_EDGE_BLANKS)


def _decode_ascii_escapes(text: str) -> str:
    """%XX escapes of ASCII characters decoded, until stable (three rounds at
    most) — what a browser or a redirecting server may turn them into. Escaped
    bytes from 0x80 up stay as they are: no dot, slash or backslash hides there,
    and the app decodes exactly the same way."""
    for _ in range(3):
        decoded = _ASCII_ESCAPE.sub(lambda m: chr(int(m.group(1), 16)), text)
        if decoded == text:
            break
        text = decoded
    return text


def is_google_maps_link(url: str | None) -> bool:
    """True only for a link Google Maps itself would produce."""
    if url is None:
        return False
    link = strip_link(url)
    if not link or _UNSAFE.search(link) or _BAD_ESCAPE.search(link):
        return False
    parts = _PARTS.match(link)
    if parts is None or parts["scheme"].lower() not in ("http", "https"):
        return False
    # The whole authority must be a bare host: userinfo or a port never matches.
    host = parts["authority"].lower()
    if host not in _HOSTS:
        return False

    path = parts["path"]
    if host == "maps.app.goo.gl":
        shape_ok = _SHORT_PATH.fullmatch(path) is not None
    elif host == "goo.gl":
        shape_ok = _GOO_GL_PATH.fullmatch(path) is not None
    else:
        # The first segment is exactly "maps" — not /url, /amp, /mapsXYZ.
        shape_ok = path == "/maps" or path.startswith("/maps/") or (
            host == "maps.google.com" and path in ("", "/")
        )
    if not shape_ok:
        return False

    # Escaped slashes are legal inside a place link's data= (…!16s%2Fg%2F…);
    # what is refused is a dot segment or a backslash once decoded.
    decoded_path = _decode_ascii_escapes(path)
    if "\\" in decoded_path or any(seg in (".", "..") for seg in decoded_path.split("/")):
        return False

    for part in (parts["query"], parts["fragment"]):
        if part and _EMBEDDED_ADDRESS.search(_decode_ascii_escapes(part)):
            return False
    return True
