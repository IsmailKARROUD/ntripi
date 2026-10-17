// features/itineraries/data/edit_claim_store_io.dart — the edit-claim journal
// on a device: secure storage, beside the session tokens. An entry is a claim
// token, and until that claim is released it is a capability on the trip.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ntripi/features/itineraries/data/edit_claim_store.dart';

// No AndroidOptions: encryptedSharedPreferences is deprecated/ignored in v10+.
const _storage = FlutterSecureStorage();

class _SecureEditClaimStore implements EditClaimStore {
  const _SecureEditClaimStore();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<Map<String, String>> readAll() async => {
        for (final MapEntry(:key, :value) in (await _storage.readAll()).entries)
          if (key.startsWith(kEditClaimKeyPrefix)) key: value,
      };

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

EditClaimStore platformEditClaimStore() => const _SecureEditClaimStore();
