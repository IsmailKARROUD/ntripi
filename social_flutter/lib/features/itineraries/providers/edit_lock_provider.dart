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
// The token a save or a heartbeat uses is the one in memory, handed to this run
// by its own claim; nothing else is ever adopted for writing. It is also written
// to the EditClaimJournal until its release lands, so that it can be handed
// back: memory dies with the app, and a claim the app was closed holding used to
// stay on the server, read by the next launch as "you're editing this on another
// device" — from the very device that left it.
//
// Nothing here decides anything. Whether the claim is still good is answered by
// the server on every heartbeat and every save; this class only records the
// answer and stops pinging when the answer is no.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/features/itineraries/data/edit_claim_journal.dart';
import 'package:social_flutter/features/itineraries/data/itinerary_repository.dart';
import 'package:social_flutter/features/itineraries/domain/edit_lock.dart';

/// How often the detail screen re-asks who is editing, while somebody else is.
///
/// Coarser than the heartbeat on purpose: this is a courtesy banner, not the
/// authority. The authority is the save, which fails cleanly regardless of how
/// stale this happens to be.
const kEditLockPollInterval = Duration(seconds: 30);

/// How long a claim outlives the last screen editing under it. Long enough for
/// a router.go() that rebuilds the detail screen to re-attach; short enough
/// that a claim nobody is looking at stops blocking other editors at once.
const kEditLockDetachGrace = Duration(seconds: 3);

/// Itineraries this device holds a claim on, so sign-out can hand every one
/// back while it still has an access token to do it with.
final Set<String> _heldClaims = {};

/// Release every claim this device holds, and every one an earlier run left in
/// the journal. Called by sign-out before the tokens go; never throws.
Future<void> releaseAllEditClaims(Ref ref) async {
  for (final id in _heldClaims.toList()) {
    await ref.read(editLockProvider(id).notifier).release();
  }
  final journal = ref.read(editClaimJournalProvider);
  final repo = ref.read(itineraryRepositoryProvider);
  for (final (id, token) in await journal.leftovers()) {
    await _sendRelease(repo, id, token);
  }
  // Whatever answered: the next account on this device could not release what
  // is left, and must not inherit it.
  await journal.clear();
}

/// DELETE one claim. True when nothing is left to retry — released, or no
/// longer there (404) or this account's to release (403); false when it may
/// still stand, so the journal keeps it for the next look at the trip.
Future<bool> _sendRelease(
  ItineraryRepository repo,
  String itineraryId,
  String token,
) async {
  try {
    await repo.releaseLock(itineraryId, token);
    return true;
  } on DioException catch (e) {
    final status = e.response?.statusCode;
    return status == 403 || status == 404;
  } catch (_) {
    return false;
  }
}

/// Whether the app is in front of the user. A heartbeat from the background
/// kept a claim "active" for hours after the user walked away; the server still
/// honours a matching token past its TTL when they come back. Unknown (no
/// binding, as in a plain unit test) reads as foreground.
bool _appInForeground() {
  try {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  } catch (_) {
    return true;
  }
}

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
  Timer? _releaseTimer;
  int _attached = 0;

  @override
  EditSession build() {
    // The notifier outlives every screen that uses it, so the timer has to be
    // torn down here rather than in any one widget's dispose.
    ref.onDispose(() {
      _stopHeartbeat();
      _releaseTimer?.cancel();
      _heldClaims.remove(arg);
    });
    return const EditSession();
  }

  /// A screen editing under this claim is on screen. Paired with [detach].
  void attach() {
    _attached++;
    _releaseTimer?.cancel();
    _releaseTimer = null;
  }

  /// The screen is gone. When the last one leaves, the claim is handed back
  /// after [kEditLockDetachGrace] — nothing used to stop the heartbeat, so a
  /// claim left behind by a router.go() or a push tap stayed "active" for as
  /// long as the app lived and no other editor could take it.
  void detach() {
    if (_attached > 0) _attached--;
    _releaseIfUnattended();
  }

  /// Hand the claim back after [kEditLockDetachGrace] unless a screen is
  /// editing under it by then.
  void _releaseIfUnattended() {
    if (_attached > 0 || !state.holdsClaim) return;
    _releaseTimer?.cancel();
    _releaseTimer = Timer(kEditLockDetachGrace, () {
      if (_attached == 0 && ref.mounted) unawaited(release());
    });
  }

  ItineraryRepository get _repo => ref.read(itineraryRepositoryProvider);

  EditClaimJournal get _journal => ref.read(editClaimJournalProvider);

  /// The hand-back in flight, so the first look and the first claim send one
  /// release between them.
  Future<void>? _settling;

  /// Hand back a claim this device took on this trip and never released — the
  /// app was closed in edit mode, or the release could not reach the server.
  /// Until it goes the server reports it as ours, and with no token for it that
  /// read as "you're editing this on another device", from this one.
  Future<void> _settleLeftover() =>
      _settling ??= _handBackLeftover().whenComplete(() => _settling = null);

  Future<void> _handBackLeftover() async {
    final journal = _journal;
    final repo = _repo;
    final token = await journal.leftover(arg, live: state.token);
    if (token == null) return;
    if (await _sendRelease(repo, arg, token)) await journal.forget(arg, token);
  }

  /// Start (or move) an editing session onto this device.
  ///
  /// Returns true when the claim is held. On [ItineraryLockedException] it
  /// records who is in the way and returns false — the caller shows that and,
  /// if the user agrees, calls again with [takeover].
  Future<bool> acquire({bool takeover = false}) async {
    state = state.copyWith(busy: true, clearProblem: true);
    try {
      // A claim this device left behind would be refused back to it as "you,
      // on another device".
      await _settleLeftover();
      if (!ref.mounted) return false;
      final claim = await _repo.acquireLock(arg, takeover: takeover);
      if (!ref.mounted) return false;
      state = EditSession(token: claim.token, lock: claim.lock);
      _heldClaims.add(arg);
      // Written down before anything can close the app on it: a claim this run
      // never gets to release is handed back by the next look at the trip.
      unawaited(_journal.record(arg, claim.token));
      _startHeartbeat(claim.heartbeatInterval);
      // The screen that asked may be gone by now (the user backed out while
      // the claim was in flight), and nothing would ever detach it.
      _releaseIfUnattended();
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
  ///
  /// A release that does not land stays in the journal, so the next look at
  /// this trip — this run or the next — hands the claim back, instead of the
  /// server reporting it as this user on another device until its TTL.
  Future<void> release() async {
    final token = state.token;
    _stopHeartbeat();
    _releaseTimer?.cancel();
    _heldClaims.remove(arg);
    // Unmounted, there is no repository left to send it with.
    if (!ref.mounted) return;
    state = const EditSession();
    if (token == null) return;
    final journal = _journal;
    if (await _sendRelease(_repo, arg, token)) await journal.forget(arg, token);
  }

  /// Fetch who holds the claim without touching this device's own session.
  /// What the banner polls while somebody else is editing.
  Future<EditLockStatus?> peek() async {
    try {
      // First any claim this device left on the trip — otherwise the answer is
      // that leftover, read back as "you're editing this on another device".
      await _settleLeftover();
      if (!ref.mounted) return null;
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
    _heldClaims.remove(arg);
    if (!ref.mounted) return;
    // Rotated away or revoked: there is no claim left to hand back.
    final token = state.token;
    if (token != null) unawaited(_journal.forget(arg, token));
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
    if (!_appInForeground()) return;

    try {
      final lock = await _repo.heartbeatLock(arg, token);
      if (!ref.mounted) return;
      state = state.copyWith(lock: lock, clearProblem: true);
    } on EditLockLostException catch (e) {
      // The point of pinging: hear about a takeover before the user tries to
      // save, so the "your session was taken over" banner is already up.
      markLost(e.holder);
    } on DioException catch (e) {
      // Both are final, not dropped pings: 403 means edit rights were revoked
      // (the server checks them before the claim), 404 that the itinerary is
      // gone. Swallowing them pinged a dead claim for the rest of the session.
      final status = e.response?.statusCode;
      if (status == 403) {
        markLost(null);
      } else if (status == 404) {
        // The itinerary is gone, and its claim with it.
        _stopHeartbeat();
        _heldClaims.remove(arg);
        if (!ref.mounted) return;
        unawaited(_journal.forget(arg, token));
        state = const EditSession();
      }
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
