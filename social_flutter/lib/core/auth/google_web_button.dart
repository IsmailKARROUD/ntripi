// core/auth/google_web_button.dart — platform facade for the Google web button.
//
// On web, authenticate() is unsupported; Google requires its own rendered
// button + an auth-event stream. This facade exports the web implementation
// when compiling for web and a no-op stub everywhere else, so the login screen
// can reference `GoogleWebButton` unconditionally.
export 'google_web_button_stub.dart'
    if (dart.library.js_interop) 'google_web_button_web.dart';
