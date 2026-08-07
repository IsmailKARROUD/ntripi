"""
constants/tos.py — Terms of Service, served via GET /terms and GET /auth/tos.

Keeping the ToS here (backend) means updating it requires only a backend
deploy, not an app store submission. The Flutter app always fetches the
current version at registration time.

TOS_VERSION is written verbatim into users.tos_accepted_version at
registration, so bumping it is what makes "which document did this person
agree to" answerable after the text changes. Existing rows are never
backfilled — they agreed to the revision they were shown, and the client
gate (UserPrivateProfile.tos_current) is what re-prompts them.

The bodies live in app/constants/legal/<lang>.py; English is authoritative
and every other language is served with a prevailing-language notice.
"""

from app.constants import legal

TOS_VERSION = "3.0"
TOS_DATE = "2026-08-06"


def get_tos(lang: str = "en") -> str:
    return legal.document(lang, "TOS")
