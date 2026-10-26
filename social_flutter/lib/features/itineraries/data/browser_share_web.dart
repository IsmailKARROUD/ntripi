// data/browser_share_web.dart — whether this browser has a share popup. Phone
// browsers and some desktop ones do; most desktop browsers do not, and there
// share_plus falls back to opening an email draft.

import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

bool browserHasSharePopup() {
  try {
    return web.window.navigator.has('share');
  } catch (_) {
    return false;
  }
}
