// The connections every request to the API travels on. Phones keep them open
// between requests and start over after leaving the screen or changing network
// (api_connection_pool_io.dart); browsers manage their own
// (api_connection_pool_web.dart).
export 'api_connection_pool_io.dart'
    if (dart.library.js_interop) 'api_connection_pool_web.dart';
