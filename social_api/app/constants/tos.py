"""
constants/tos.py — Terms of Service text served via GET /tos.

Keeping the ToS here (backend) means updating it requires only a backend
deploy, not an app store submission. The Flutter app always fetches the
current version at registration time.
"""

TOS_VERSION = "1.0"
TOS_DATE = "2026-01-01"

TOS_SUMMARY = """By creating an account on Ntripi, you agree to the following:

1. Your personal data (name, email, profile) will be deleted when you close your account.

2. Ratings you submit on itineraries will be retained in anonymized form (score only, no identifying information) after account deletion. This preserves the integrity of community scores for other users.

3. Your itineraries and their content will be permanently deleted when you close your account."""
