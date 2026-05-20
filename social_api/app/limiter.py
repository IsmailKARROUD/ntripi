"""
limiter.py — slowapi rate-limiter singleton.

Importing this module in routers avoids a circular import: main.py imports
routers, so routers cannot import from main.py. The limiter lives here
instead, and main.py registers it on app.state after importing it.
"""

from slowapi import Limiter
from slowapi.util import get_remote_address

# In-memory store — sufficient for the current single-instance Railway deployment.
# If replicated horizontally, replace with a Redis-backed store to prevent
# limits from resetting per-instance on each deploy or restart.
limiter = Limiter(key_func=get_remote_address)
