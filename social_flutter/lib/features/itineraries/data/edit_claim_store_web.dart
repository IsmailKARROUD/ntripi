// features/itineraries/data/edit_claim_store_web.dart — the edit-claim journal
// on the web: the tab's sessionStorage. It survives a reload, the web's "closed
// the app while editing", and it belongs to that tab alone. localStorage would
// not do: every tab shares it, so opening the trip in a second tab would hand
// back the first tab's claim while it was still being edited under.

import 'package:ntripi/features/itineraries/data/edit_claim_store.dart';
import 'package:web/web.dart' as web;

class _SessionEditClaimStore implements EditClaimStore {
  const _SessionEditClaimStore();

  web.Storage get _storage => web.window.sessionStorage;

  @override
  Future<String?> read(String key) async => _storage.getItem(key);

  @override
  Future<Map<String, String>> readAll() async {
    final storage = _storage;
    final entries = <String, String>{};
    for (var i = 0; i < storage.length; i++) {
      final key = storage.key(i);
      if (key == null || !key.startsWith(kEditClaimKeyPrefix)) continue;
      final value = storage.getItem(key);
      if (value != null) entries[key] = value;
    }
    return entries;
  }

  @override
  Future<void> write(String key, String value) async {
    _storage.setItem(key, value);
  }

  @override
  Future<void> delete(String key) async {
    _storage.removeItem(key);
  }
}

EditClaimStore platformEditClaimStore() => const _SessionEditClaimStore();
