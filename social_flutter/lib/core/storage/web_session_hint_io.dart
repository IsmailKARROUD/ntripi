// core/storage/web_session_hint_io.dart — the session hint on a device: there
// are no share pages to tell, so nothing is written.

import 'package:ntripi/core/storage/web_session_hint.dart';

class _NoWebSessionHint implements WebSessionHint {
  const _NoWebSessionHint();

  @override
  void mark(DateTime? until) {}

  @override
  void clear() {}
}

WebSessionHint platformWebSessionHint() => const _NoWebSessionHint();
