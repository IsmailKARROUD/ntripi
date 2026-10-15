// features/itineraries/data/edit_claim_store.dart — where the edit-claim
// journal keeps its entries: secure storage on a device
// (edit_claim_store_io.dart), the tab's sessionStorage on the web
// (edit_claim_store_web.dart), a map in tests.

/// Every journal key starts with this, so a store shared with other data —
/// secure storage also holds the session tokens — reads back only its own.
const kEditClaimKeyPrefix = 'ntripi_edit_claim_';

abstract class EditClaimStore {
  Future<String?> read(String key);

  /// Every entry whose key starts with [kEditClaimKeyPrefix], and nothing else.
  Future<Map<String, String>> readAll();

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}
