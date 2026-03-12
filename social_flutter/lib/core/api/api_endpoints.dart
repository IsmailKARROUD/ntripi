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

/// Accept a specific follow request.
String acceptFollowRequestEndpoint(String followId) =>
    '/users/me/follow-requests/$followId/accept';

/// Reject a specific follow request.
String rejectFollowRequestEndpoint(String followId) =>
    '/users/me/follow-requests/$followId';
