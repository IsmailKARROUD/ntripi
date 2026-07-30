// core/api/api_endpoints.dart — All API URL constants in one place.
//
// Why centralise URLs?
//   If an endpoint path changes on the backend, you update it here and
//   every file that imports this gets the fix automatically.
//   It also makes it easy to audit all the API calls your app makes.

/// Base URL of the Ntripi API.
///
/// 10.0.2.2 is the Android emulator's alias for the host machine's localhost.
/// Change this to your server URL for production builds or real devices.
/// For iOS simulator, use 127.0.0.1 or localhost.
///
/// To make this configurable at build time:
///   flutter run --dart-define=API_BASE_URL=https://api.myserver.com
/// Then use: const kApiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '...');
const kApiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');

// ---------------------------------------------------------------------------
// Auth endpoints
// ---------------------------------------------------------------------------
const kRegisterEndpoint = '/auth/register';
const kLoginEndpoint = '/auth/login';
const kRefreshEndpoint = '/auth/refresh';
const kLogoutEndpoint = '/auth/logout';
const kTosEndpoint = '/auth/tos';

/// Exchange a Google ID token for a Ntripi token pair (sign in / up / verify).
const kGoogleAuthEndpoint = '/auth/google';

/// Request a password-reset email (enumeration-safe; always 200).
const kForgotPasswordEndpoint = '/auth/forgot-password';

/// Resend the email-verification link to the signed-in user.
const kResendVerificationEndpoint = '/auth/resend-verification';

/// Change the signed-in user's password (returns a fresh token pair).
const kChangePasswordEndpoint = '/auth/change-password';

/// Google **web/server** OAuth client id, passed to the Google SDK as
/// `serverClientId` so the issued ID token's `aud` equals the backend audience.
/// Supply at build time: --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>
const kGoogleServerClientId =
    String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID', defaultValue: '');

// ---------------------------------------------------------------------------
// User endpoints
// ---------------------------------------------------------------------------
const kMyProfileEndpoint = '/users/me';
const kSearchUsersEndpoint = '/users/search';
const kMyAvatarEndpoint = '/users/me/avatar';
const kMyCoverImageEndpoint = '/users/me/cover-image';

// ---------------------------------------------------------------------------
// Moderation appeals
// ---------------------------------------------------------------------------
const kAppealsEndpoint = '/appeals';
const kViolationsEndpoint = '/appeals/violations';

/// Returns the aggregate visited-locations endpoint for a given user.
String userLocationsEndpoint(String userId) => '/users/$userId/locations';

/// Returns the profile endpoint for a given user ID.
String userProfileEndpoint(String userId) => '/users/$userId';

/// Returns the follow endpoint for a given user ID.
String followEndpoint(String userId) => '/users/$userId/follow';

/// Returns the followers list endpoint.
String followersEndpoint(String userId) => '/users/$userId/followers';

/// Returns the following list endpoint.
String followingEndpoint(String userId) => '/users/$userId/following';

// ---------------------------------------------------------------------------
// Follow request endpoints
// ---------------------------------------------------------------------------
const kFollowRequestsEndpoint = '/users/me/follow-requests';

// ---------------------------------------------------------------------------
// Itinerary endpoints
// ---------------------------------------------------------------------------

/// List the authenticated user's itineraries.
const kMyItinerariesEndpoint = '/itineraries/me';

/// Create a new itinerary.
const kItinerariesEndpoint = '/itineraries/';

/// Public discovery feed. [sort] is 'recent' or 'top'.
String feedEndpoint({required String sort, int limit = 20, int offset = 0}) =>
    '/itineraries/feed?sort=$sort&limit=$limit&offset=$offset';

/// List the authenticated user's saved (bookmarked) itineraries, newest first.
const kSavedItinerariesEndpoint = '/itineraries/saved';

/// Save (POST) or unsave (DELETE) an itinerary for the current user.
String itinerarySaveEndpoint(String id) => '/itineraries/$id/save';

/// CRUD for a single itinerary.
String itineraryEndpoint(String id) => '/itineraries/$id';

/// Add a stop to an itinerary / list stops.
String itineraryStopsEndpoint(String id) => '/itineraries/$id/stops';

/// Batch reorder of stops within tracks (POST). Server computes new
/// fractional-index ranks from the order the client sends.
String itineraryReorderEndpoint(String id) => '/itineraries/$id/reorder';

/// Update or delete a single stop.
String itineraryStopEndpoint(String id, String stopId) =>
    '/itineraries/$id/stops/$stopId';

/// Add an annotation to a stop.
String stopAnnotationsEndpoint(String id, String stopId) =>
    '/itineraries/$id/stops/$stopId/annotations';

/// Update or delete a single stop annotation.
String stopAnnotationEndpoint(String id, String stopId, String annotationId) =>
    '/itineraries/$id/stops/$stopId/annotations/$annotationId';

/// Add an itinerary-level annotation.
String itineraryAnnotationsEndpoint(String id) =>
    '/itineraries/$id/annotations';

/// Update or delete a single itinerary-level annotation.
String itineraryAnnotationEndpoint(String id, String annotationId) =>
    '/itineraries/$id/annotations/$annotationId';

/// Accept a specific follow request.
String acceptFollowRequestEndpoint(String followId) =>
    '/users/me/follow-requests/$followId/accept';

/// Reject a specific follow request.
String rejectFollowRequestEndpoint(String followId) =>
    '/users/me/follow-requests/$followId';

// ---------------------------------------------------------------------------
// Allowlist endpoints (restricted visibility)
// ---------------------------------------------------------------------------

/// List or add users to the restricted allowlist.
String itineraryAllowedUsersEndpoint(String id) =>
    '/itineraries/$id/allowed-users';

/// Remove a specific user from the restricted allowlist.
String itineraryAllowedUserEndpoint(String id, String userId) =>
    '/itineraries/$id/allowed-users/$userId';

// ---------------------------------------------------------------------------
// User itinerary endpoints
// ---------------------------------------------------------------------------

/// List itineraries visible to the authenticated user on another user's profile.
String userItinerariesEndpoint(String userId) => '/users/$userId/itineraries';

// ---------------------------------------------------------------------------
// Transit segment endpoints
// ---------------------------------------------------------------------------

/// Create a segment or list segments for an itinerary.
/// Note: listing is not used by Flutter — segments are embedded in the
/// full itinerary detail returned by [itineraryEndpoint].
String itinerarySegmentsEndpoint(String id) => '/itineraries/$id/segments';

/// Update or delete a single segment (full leg replacement on PATCH).
String itinerarySegmentEndpoint(String id, String segmentId) =>
    '/itineraries/$id/segments/$segmentId';
// Individual leg CRUD endpoints (POST/PATCH/DELETE .../legs/{legId}) are
// not used by Flutter — the segment PATCH does a full leg replacement instead.
// Those endpoints are defined in the backend for future API consumers.

// ---------------------------------------------------------------------------
// Share endpoints
// ---------------------------------------------------------------------------

/// Base URL for the HTML share landing pages.
const kShareBaseUrl = String.fromEnvironment(
  'SHARE_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

/// Android APK / Play Store download URL. Empty string means no link.
const kAndroidDownloadUrl = String.fromEnvironment('ANDROID_DOWNLOAD_URL', defaultValue: '');

/// Google Maps Embed API key for the stop link-preview map (never hardcoded —
/// provisioned in Google Cloud, restricted to the Maps Embed API). Empty by
/// default: the preview card falls back to a plain "Opens in Google Maps" row
/// until the key is supplied via --dart-define, so the feature ships inert.
const kGoogleMapsEmbedApiKey =
    String.fromEnvironment('GOOGLE_MAPS_EMBED_API_KEY', defaultValue: '');

/// Public-facing Terms of Service page URL.
const kTermsUrl = '$kShareBaseUrl/terms';

/// Public-facing Privacy Policy page URL.
const kPrivacyPolicyUrl = '$kShareBaseUrl/privacy';

/// Returns the public share URL for a given itinerary ID.
String shareUrlFor(String itineraryId) => '$kShareBaseUrl/share/i/$itineraryId';

// ---------------------------------------------------------------------------
// Cover image endpoints
// ---------------------------------------------------------------------------

/// Upload or replace the cover image for an itinerary.
String itineraryImageEndpoint(String id) => '/itineraries/$id/image';

// ---------------------------------------------------------------------------
// Rating endpoints
// ---------------------------------------------------------------------------

/// Submit or update the current user's rating for an itinerary.
String itineraryRatingsEndpoint(String id) => '/itineraries/$id/ratings';

/// Get or delete the current user's own rating.
String itineraryMyRatingEndpoint(String id) => '/itineraries/$id/ratings/me';

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------

/// Report content for moderation (auth optional server-side). Targets are
/// polymorphic — see ReportTarget.
const kReportsEndpoint = '/reports';

// ---------------------------------------------------------------------------
// Blocking
// ---------------------------------------------------------------------------

/// Block / unblock a user (POST / DELETE on the same path).
String kBlockEndpoint(String userId) => '/users/$userId/block';

/// The accounts the current user has blocked.
const kMyBlocksEndpoint = '/users/me/blocks';

// ---------------------------------------------------------------------------
// Safety / compliance surfaces
// ---------------------------------------------------------------------------

/// Community guidelines, served by the backend so updating them is a deploy
/// rather than an app-store submission.
const kGuidelinesUrl = '$kShareBaseUrl/guidelines';

/// Published abuse contact. Must match the backend's ABUSE_CONTACT_EMAIL and
/// the store listing — reviewers compare them.
const kAbuseContactEmail = 'abuse@ntripi.app';
