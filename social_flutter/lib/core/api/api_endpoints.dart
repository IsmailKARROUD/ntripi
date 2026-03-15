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
const kApiBaseUrl = 'http://localhost:8000'; // Use http://10.0.2.2:8000 for Android emulator

// ---------------------------------------------------------------------------
// Auth endpoints
// ---------------------------------------------------------------------------
const kRegisterEndpoint = '/auth/register';
const kLoginEndpoint = '/auth/login';

// ---------------------------------------------------------------------------
// User endpoints
// ---------------------------------------------------------------------------
const kMyProfileEndpoint = '/users/me';
const kSearchUsersEndpoint = '/users/search';

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
const kItinerariesEndpoint = '/itineraries';

/// CRUD for a single itinerary.
String itineraryEndpoint(String id) => '/itineraries/$id';

/// Add a stop to an itinerary / list stops.
String itineraryStopsEndpoint(String id) => '/itineraries/$id/stops';

/// Reorder all stops in an itinerary.
String itineraryStopsReorderEndpoint(String id) => '/itineraries/$id/stops/reorder';

/// Update or delete a single stop.
String itineraryStopEndpoint(String id, String stopId) =>
    '/itineraries/$id/stops/$stopId';

/// Add an annotation to a stop.
String stopAnnotationsEndpoint(String id, String stopId) =>
    '/itineraries/$id/stops/$stopId/annotations';

/// Delete a single annotation.
String stopAnnotationEndpoint(String id, String stopId, String annotationId) =>
    '/itineraries/$id/stops/$stopId/annotations/$annotationId';

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
