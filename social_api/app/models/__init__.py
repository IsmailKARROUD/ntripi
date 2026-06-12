# Re-export all models so Alembic can discover them via `from app.models import *`.
# Alembic's env.py imports Base from database.py and needs all model classes
# to be registered on Base.metadata before it can detect schema changes.
from app.models.user import User
from app.models.refresh_token import RefreshToken
from app.models.follow import Follow, FollowStatus
from app.models.itinerary import Itinerary
from app.models.itinerary_allowed_user import ItineraryAllowedUser
from app.models.track import Track
from app.models.stop import Stop
from app.models.annotation import Annotation
from app.models.itinerary_rating import ItineraryRating
from app.models.itinerary_annotation import ItineraryAnnotation
from app.models.transit_segment import TransitSegment
from app.models.transport_leg import TransportLeg
from app.models.waitlist import WaitlistEntry

__all__ = [
    "User", "RefreshToken", "Follow", "FollowStatus",
    "Itinerary", "ItineraryAllowedUser", "Track",
    "Stop", "Annotation", "ItineraryRating", "ItineraryAnnotation",
    "TransitSegment", "TransportLeg", "WaitlistEntry",
]
