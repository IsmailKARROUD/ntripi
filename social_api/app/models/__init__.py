# Re-export all models so Alembic can discover them via `from app.models import *`.
# Alembic's env.py imports Base from database.py and needs all model classes
# to be registered on Base.metadata before it can detect schema changes.
from app.models.user import User
from app.models.refresh_token import RefreshToken
from app.models.email_token import EmailToken
from app.models.password_history import PasswordHistory
from app.models.security_audit_log import SecurityAuditLog
from app.models.follow import Follow, FollowStatus
from app.models.itinerary import Itinerary
from app.models.itinerary_allowed_user import ItineraryAllowedUser
from app.models.saved_itinerary import SavedItinerary
from app.models.track import Track
from app.models.stop import Stop
from app.models.annotation import Annotation
from app.models.itinerary_rating import ItineraryRating
from app.models.itinerary_annotation import ItineraryAnnotation
from app.models.transit_segment import TransitSegment
from app.models.transport_leg import TransportLeg
from app.models.waitlist import WaitlistEntry
from app.models.content_report import ContentReport
from app.models.image_moderation_log import ImageModerationLog
from app.models.moderation_log import ModerationLog
from app.models.appeal import Appeal
from app.models.text_moderation_cache import TextModerationCache
from app.models.text_moderation_decision import TextModerationDecision
from app.models.legal_escalation import LegalEscalation
from app.models.user_block import UserBlock
from app.models.bug_report import BugReport
from app.models.notification import Notification

__all__ = [
    "User", "RefreshToken", "EmailToken", "PasswordHistory", "SecurityAuditLog",
    "Follow", "FollowStatus",
    "Itinerary", "ItineraryAllowedUser", "SavedItinerary", "Track",
    "Stop", "Annotation", "ItineraryRating", "ItineraryAnnotation",
    "TransitSegment", "TransportLeg", "WaitlistEntry", "ContentReport",
    "ImageModerationLog", "ModerationLog", "Appeal",
    "TextModerationCache", "TextModerationDecision", "LegalEscalation",
    "UserBlock", "BugReport", "Notification",
]
