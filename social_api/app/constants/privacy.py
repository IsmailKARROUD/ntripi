"""
constants/privacy.py — Privacy Policy served via GET /privacy and included in
the GET /auth/tos payload.

Placeholder text — to be reviewed and finalized before public launch.
Keeping this in the backend means updating it requires only a backend
deploy, not an app-store submission.

Plain text since 2.0, not HTML: the policy has to be readable inside the app
at the point of acceptance and inside the re-acceptance gate, and the in-app
sheet renders a bare Text widget. Section 5 is the list of every third party
that receives user data — keep it in step with the code, since an undisclosed
processor is a GDPR breach and a store-privacy-label mismatch.

The bodies live in app/constants/legal/<lang>.py; English is authoritative.
"""

from app.constants import legal

PRIVACY_VERSION = "2.2"
PRIVACY_DATE = "2026-08-13"


def get_privacy(lang: str = "en") -> str:
    return legal.document(lang, "PRIVACY")
