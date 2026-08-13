// features/itineraries/providers/edit_lock_provider.dart — owns one editing
// session: the claim token, the heartbeat, and what happened to it.
//
// This lives in a provider rather than in the detail screen's State because the
// claim has to outlive any one route. The user enters edit mode on the detail
// screen and then pushes the stop form on top of it; if the heartbeat lived in
// the screen it would keep running (the route is only covered, not disposed) —
// but a form pushed from a *different* entry point would have no claim at all,
// and nothing would survive a screen rebuild. One owner per itinerary, addressed
// by id, is the shape that matches what the server models.
//
// The token is held in memory only. It is not a credential worth persisting:
// any takeover rotates it, and a token that has been rotated away is worth
// exactly nothing. Writing it to secure storage would only create a way to
// resurrect a dead session.
//
// Nothing here decides anything. Whether the claim is still good is answered by
// the server on every heartbeat and every save; this class only records the
// answer and stops pinging when the answer is no.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/edit_lock.dart';

/// How often the detail screen re-asks who is editing, while somebody else is.
///
/// Coarser than the heartbeat on purpose: this is a courtesy banner, not the
/// authority. The authority is the save, which fails cleanly regardless of how
/// stale this happens to be.
const kEditLockPollInterval = Duration(seconds: 30);

/// Why the client is not currently able to save.
enum EditSessionProblem {
  /// Someone else's claim is in the way. Answerable: wait, or take over once
  /// the server says it is takeable (immediately, if you are the owner).
  locked,

  /// This device's claim was rotated away. NOT answerable by retrying the save —
  /// the user's unsaved work is now the only copy of it.
  lost,
}

/// One editing session, as the UI needs to see it.
class EditSession {
  const EditSession({
    this.token,
    this.lock,
    this.problem,
    this.busy = false,
  });

  /// The claim token, when this device holds one. Null means not editing.
  final String? token;

  /// The server's last word on who holds the claim — this device or someone
  /// else. Kept even after a loss, so the UI can name who took over.
  final EditLock? lock;

  final EditSessionProblem? problem;

  /// A claim/heartbeat/release request is in flight.
  final bool busy;

  bool get holdsClaim => token != null;

  /// Whether the blocking claim can be displaced right now. The server decides;
  /// this only reads back what it said, and `isYou` covers the "you're editing
  /// on another device" case, where takeover is always allowed.
  bool get canTakeOverNow {
    final current = lock;
    if (current == null) return true;
    return current.isYou || current.state == EditLockState.takeable;
  }

  EditSession copyWith({
    String? token,
    bool clearToken = false,
    EditLock? lock,
    bool clearLock = false,
    EditSessionProblem? problem,
    bool clearProblem = false,
    bool? busy,
  }) =>
      EditSession(
        token: clearToken ? null : (token ?? this.token),
        lock: clearLock ? null : (lock ?? this.lock),
        problem: clearProblem ? null : (problem ?? this.problem),
        busy: busy ?? this.busy,
      );
}

class EditLockNotifier extends Notifier<EditSession> {
  EditLockNotifier(this.arg); // family argument: itinerary id
  final String arg;

  Timer? _heartbeat;

  @override
  EditSession build() {
    // The notifier outlives every screen that uses it, so the timer has to be
    // torn down here rather than in any one widget's dispose.
    ref.onDispose(_stopHeartbeat);
    return const EditSession();
  }

  ItineraryRepository get _repo => ref.read(itineraryRepositoryProvider);

  /// Start (or move) an editing session onto this device.
  ///
  /// Returns true when the claim is held. On [ItineraryLockedException] it
  /// records who is in the way and returns false — the caller shows that and,
  /// if the user agrees, calls again with [takeover].
  Future<bool> acquire({bool takeover = false}) async {
    state = state.copyWith(busy: true, clearProblem: true);
    try {
      final claim = await _repo.acquireLock(arg, takeover: takeover);
      if (!ref.mounted) return false;
      state = EditSession(token: claim.token, lock: claim.lock);
      _startHeartbeat(claim.heartbeatInterval);
      return true;
    } on ItineraryLockedException catch (e) {
      if (!ref.mounted) return false;
      state = EditSession(lock: e.holder, problem: EditSessionProblem.locked);
      return false;
    } catch (_) {
      if (!ref.mounted) return false;
      // Network and everything else: no claim, no problem banner. The caller
      // surfaces the error; a lock problem would be the wrong diagnosis.
      state = const EditSession();
      rethrow;
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }

  /// End the session. Best-effort and never throws — it runs from teardown,
  /// where the user has already moved on and an error helps nobody. The server
  /// side is idempotent for the same reason.
  Future<void> release() async {
    final token = state.token;
    _stopHeartbeat();
    if (ref.mounted) state = const EditSession();
    if (token == null) return;
    try {
      await _repo.releaseLock(arg, token);
    } catch (_) {
      // The claim decays on its own; a failed release costs the next editor a
      // wait, not correctness.
    }
  }

  /// Fetch who holds the claim without touching this device's own session.
  /// What the banner polls while somebody else is editing.
  Future<EditLockStatus?> peek() async {
    try {
      final status = await _repo.getLockStatus(arg);
      if (!ref.mounted) return null;
      // Only mirror it into state when this device is not the holder — the
      // heartbeat is the authority on our own claim and is fresher.
      if (!state.holdsClaim) {
        state = state.copyWith(
          lock: status.lock,
          clearLock: status.lock == null,
        );
      }
      return status;
    } catch (_) {
      return null;
    }
  }

  /// Record that a save came back 409. Called by the presentation layer from its
  /// catch block, so the banner and the heartbeat agree without the repository
  /// having to know a provider exists.
  void markLost(EditLock? holder) {
    _stopHeartbeat();
    if (!ref.mounted) return;
    state = EditSession(lock: holder ?? state.lock, problem: EditSessionProblem.lost);
  }

  void _startHeartbeat(Duration interval) {
    _stopHeartbeat();
    _heartbeat = Timer.periodic(interval, (_) => unawaited(_ping()));
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  Future<void> _ping() async {
    final token = state.token;
    if (token == null) {
      _stopHeartbeat();
      return;
    }
    // Offline: skip rather than burn the claim on a request that cannot land.
    // The TTL is minutes and a tunnel is usually seconds; if it is not, the
    // claim decays and the user finds out from the save, which is the same
    // answer this ping would have given.
    if (!isOnlineNowRef(ref)) return;

    try {
      final lock = await _repo.heartbeatLock(arg, token);
      if (!ref.mounted) return;
      state = state.copyWith(lock: lock, clearProblem: true);
    } on EditLockLostException catch (e) {
      // The point of pinging: hear about a takeover before the user tries to
      // save, so the "your session was taken over" banner is already up.
      markLost(e.holder);
    } catch (_) {
      // A dropped ping is normal. EDIT_LOCK_IDLE_SECONDS is two intervals wide
      // precisely so one miss is not treated as anything.
    }
  }
}

/// One session per itinerary. Not autoDispose: the claim must survive the
/// detail screen being covered by the stop form, and releasing it is an
/// explicit act, never a side effect of a route popping.
final editLockProvider =
    NotifierProvider.family<EditLockNotifier, EditSession, String>(
  EditLockNotifier.new,
);
