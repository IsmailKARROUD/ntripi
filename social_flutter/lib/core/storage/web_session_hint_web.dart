// core/storage/web_session_hint_web.dart — the session hint on the web:
// localStorage, which the share pages share with this app (one origin), unlike
// a tab's sessionStorage. Best-effort: a browser that refuses storage just
// shows those pages' teaser, as before.

import 'package:ntripi/core/storage/web_session_hint.dart';
import 'package:web/web.dart' as web;

class _LocalStorageWebSessionHint implements WebSessionHint {
  const _LocalStorageWebSessionHint();

  @override
  void mark(DateTime? until) {
    try {
      web.window.localStorage
          .setItem(kWebSessionHintKey, until?.toUtc().toIso8601String() ?? '');
    } catch (_) {}
  }

  @override
  void clear() {
    try {
      web.window.localStorage.removeItem(kWebSessionHintKey);
    } catch (_) {}
  }
}

WebSessionHint platformWebSessionHint() => const _LocalStorageWebSessionHint();
