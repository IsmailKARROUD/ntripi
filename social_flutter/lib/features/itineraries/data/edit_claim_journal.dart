// features/itineraries/data/edit_claim_journal.dart — every edit claim this app
// holds, written down until its release is known to have reached the server.
//
// The claim token lives in EditLockNotifier's memory, and memory does not
// survive the app closing. A claim the app was closed holding stayed on the
// server, the next launch held no token for it, and the server's `is_you` read
// as "you're editing this on another device" — from the device that left it —
// until the claim was purged hours later. The journal is what lets the next
// look at that trip hand the claim back first.
//
// A journalled token is only ever sent to DELETE /lock. It is never adopted for
// a save or a heartbeat, and a token-bearing release ends only the claim that
// token names (edit_lock_service.release), so a stale entry is a no-op on the
// server: nothing here can resurrect a session.
//
// Best-effort throughout. A store that cannot be read or written leaves the app
// exactly where it was before the journal existed, never with an error.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ntripi/core/storage/secure_storage.dart';
import 'package:ntripi/features/itineraries/data/edit_claim_store.dart';
import 'package:ntripi/features/itineraries/data/edit_claim_store_io.dart'
    if (dart.library.js_interop) 'package:ntripi/features/itineraries/data/edit_claim_store_web.dart';

/// The account the session on this device belongs to — its JWT `sub`.
Future<String?> _signedInAccount() async => jwtSubject(await readToken());

class EditClaimJournal {
  EditClaimJournal(this._store, {Future<String?> Function()? account})
      : _account = account ?? _signedInAccount;

  final EditClaimStore _store;
  final Future<String?> Function() _account;

  // One queue for every operation: a forget never overtakes the record it
  // follows, and a read never lands between the steps of a write.
  Future<void> _tail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() op, {required T orElse}) {
    final result = _tail
        .then((_) => op())
        .then<T>((value) => value, onError: (Object _) => orElse);
    _tail = result.then<void>((_) {});
    return result;
  }

  static String _key(String itineraryId) => '$kEditClaimKeyPrefix$itineraryId';

  /// Write down a claim this app now holds, under the signed-in account.
  Future<void> record(String itineraryId, String token) => _serial(
        () async {
          final account = await _account();
          if (account == null) return; // nobody to hand it back as, later
          await _store.write(
            _key(itineraryId),
            jsonEncode({'account': account, 'token': token}),
          );
        },
        orElse: null,
      );

  /// The token journalled for [itineraryId] by the signed-in account — unless
  /// it is [live], the claim this run holds, which is nobody's leftover.
  Future<String?> leftover(String itineraryId, {String? live}) => _serial(
        () async {
          final key = _key(itineraryId);
          final raw = await _store.read(key);
          if (raw == null) return null;
          final entry = _Entry.parse(raw);
          final account = await _account();
          if (account == null) return null;
          if (entry == null || entry.account != account) {
            // Another account's claim is not this session's to release: the
            // entry goes, and the claim decays on its own.
            await _store.delete(key);
            return null;
          }
          return entry.token == live ? null : entry.token;
        },
        orElse: null,
      );

  /// Strike [itineraryId] off — only while its entry still holds [token]. A
  /// release that lands after the trip was claimed again must not erase the
  /// entry of the claim that followed it.
  Future<void> forget(String itineraryId, String token) => _serial(
        () async {
          final key = _key(itineraryId);
          final entry = _Entry.parse(await _store.read(key));
          if (entry != null && entry.token != token) return;
          await _store.delete(key);
        },
        orElse: null,
      );

  /// Every claim journalled by the signed-in account, as (itinerary id, token):
  /// what sign-out hands back before the session's tokens go.
  Future<List<(String, String)>> leftovers() => _serial(
        () async {
          final account = await _account();
          if (account == null) return const <(String, String)>[];
          return [
            for (final MapEntry(:key, :value) in (await _store.readAll()).entries)
              if (_Entry.parse(value) case final entry?
                  when entry.account == account)
                (key.substring(kEditClaimKeyPrefix.length), entry.token),
          ];
        },
        orElse: const <(String, String)>[],
      );

  /// Empty the journal, every account's entries — sign-out, once it has handed
  /// back what it could.
  Future<void> clear() => _serial(
        () async {
          for (final key in (await _store.readAll()).keys) {
            await _store.delete(key);
          }
        },
        orElse: null,
      );
}

class _Entry {
  const _Entry(this.account, this.token);

  final String account;
  final String token;

  static _Entry? parse(String? raw) {
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final account = json['account'];
      final token = json['token'];
      if (account is! String || token is! String) return null;
      return _Entry(account, token);
    } catch (_) {
      return null;
    }
  }
}

/// A plain Provider, and not in auth_provider's _userScopedProviders: the
/// journal holds nothing in memory but its queue, and every entry carries the
/// account it belongs to.
final editClaimJournalProvider = Provider<EditClaimJournal>(
  (ref) => EditClaimJournal(platformEditClaimStore()),
);
