// core/storage/web_session_hint.dart — tells the share pages somebody is signed
// in on this site.
//
// A shared link (ntripi.app/share/…) is a page the server renders on the same
// origin as the web app, so its script can read the web app's localStorage —
// but not the tokens, which flutter_secure_storage keeps encrypted. So while a
// session lasts, the web app keeps one plain entry beside them: when the
// session ends. A share page that finds it live sends the reader straight into
// the web app instead of showing the teaser (social_api
// templates/_app_links.html, reader_head).
//
// Only an end time, never a token or an account: every script on the origin
// can read it. Written by saveTokens and cleared by clearAllTokens
// (secure_storage.dart), the only two places the tokens change; localStorage on
// the web (web_session_hint_web.dart), nothing anywhere else
// (web_session_hint_io.dart).

/// The localStorage key — a contract with social_api's
/// `app_links.WEB_SESSION_HINT_KEY`. Change both in the same commit.
const kWebSessionHintKey = 'ntripi_web_session_until';

abstract class WebSessionHint {
  /// Somebody is signed in until [until]; null when the end is unknown, which
  /// the share page counts as live, as `hasLiveRefreshToken` does.
  void mark(DateTime? until);

  /// Nobody is signed in any more.
  void clear();
}
