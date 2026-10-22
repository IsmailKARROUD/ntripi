// features/itineraries/providers/itinerary_providers.dart — Riverpod state management.
//
// Providers:
//   myItinerariesProvider      — list of current user's itineraries
//   tripSeedsProvider          — trips created here, until their screen reads them
//   itineraryDetailProvider    — full detail for one itinerary (family by ID)
//   allowedUsersProvider       — restricted allowlist for one itinerary (family by ID)
//   placeSearchProvider        — Nominatim suggestions for the stop form
//   mapPlaceSearchProvider     — Nominatim suggestions for the map picker

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';
import 'package:ntripi/core/providers/locale_provider.dart';
import 'package:ntripi/core/services/geocoding_service.dart';
import 'package:ntripi/features/feed/domain/feed_item.dart';
import 'package:ntripi/features/itineraries/data/itinerary_repository.dart';
import 'package:ntripi/features/itineraries/data/maps_launcher_service.dart';
import 'package:ntripi/features/itineraries/data/share_service.dart';
import 'package:ntripi/features/itineraries/domain/allowed_user.dart';
import 'package:ntripi/features/itineraries/domain/annotation.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/domain/my_rating.dart';
import 'package:ntripi/features/itineraries/domain/ratings_page.dart';
import 'package:ntripi/features/itineraries/domain/itinerary_editor.dart';
import 'package:ntripi/features/itineraries/domain/stop.dart';
import 'package:ntripi/features/itineraries/domain/trip_edit_answer.dart';
import 'package:ntripi/features/itineraries/providers/edit_lock_provider.dart';

// ---------------------------------------------------------------------------
// MyItinerariesNotifier
// ---------------------------------------------------------------------------

class MyItinerariesNotifier extends AsyncNotifier<List<Itinerary>> {
  @override
  Future<List<Itinerary>> build() async {
    return ref.read(itineraryRepositoryProvider).getMyItineraries();
  }

  Future<void> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return;
    state = const AsyncLoading();
    final next = await AsyncValue.guard(
      () => ref
          .read(itineraryRepositoryProvider)
          .getMyItineraries(forceRefresh: true),
    );
    if (!ref.mounted) return; // disposed mid-request (logout)
    state = next;
  }

  /// Create an itinerary — with its cover in the same request when
  /// [coverBytes] is given, so a refused cover creates nothing. Returns the new
  /// trip's id. The create answers with the trip itself, which waits in
  /// [tripSeedsProvider] for its screen: that screen opens with no GET.
  Future<String> addItinerary(
    Map<String, dynamic> data, {
    Uint8List? coverBytes,
    String? coverFilename,
  }) async {
    final repo = ref.read(itineraryRepositoryProvider);
    final answer = coverBytes == null
        ? await repo.createItinerary(data)
        : await repo.createItineraryWithCover(
            data,
            coverBytes: coverBytes,
            coverFilename: coverFilename,
          );
    final trip = answer.itinerary;
    // Disposed mid-request (logout): the next account must inherit nothing.
    if (ref.mounted && trip != null) {
      ref.read(tripSeedsProvider).put(trip);
      state.whenData((list) {
        state = AsyncData([trip.summary, ...list]);
      });
    }
    return answer.createdId!;
  }

  /// A save answered with this trip: its row takes the answer's place, so the
  /// list shows the save without downloading the list again.
  void replaceRow(Itinerary row) {
    if (state case AsyncData(:final value) when value.any((i) => i.id == row.id)) {
      state = AsyncData([for (final i in value) i.id == row.id ? row : i]);
    }
  }

  Future<void> removeItinerary(String id) async {
    await ref.read(itineraryRepositoryProvider).deleteItinerary(id);
    if (!ref.mounted) return; // disposed mid-request (logout)
    state.whenData((list) {
      state = AsyncData(list.where((i) => i.id != id).toList());
    });
  }
}

final myItinerariesProvider =
    AsyncNotifierProvider<MyItinerariesNotifier, List<Itinerary>>(
      () => MyItinerariesNotifier(),
    );

// ---------------------------------------------------------------------------
// SharedWithMeNotifier — itineraries someone else owns and granted me edit
// rights on. No create or delete: an editor may do neither. A row only follows
// a save's answer, or goes when my edit rights do.
// ---------------------------------------------------------------------------

class SharedWithMeNotifier extends AsyncNotifier<List<FeedItem>> {
  @override
  Future<List<FeedItem>> build() async {
    return ref.read(itineraryRepositoryProvider).getSharedWithMe();
  }

  Future<void> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return;
    state = const AsyncLoading();
    final next = await AsyncValue.guard(
      () => ref
          .read(itineraryRepositoryProvider)
          .getSharedWithMe(forceRefresh: true),
    );
    if (!ref.mounted) return; // disposed mid-request (logout)
    state = next;
  }

  /// [MyItinerariesNotifier.replaceRow] for a trip shared with me. The owner
  /// attribution stays: a save never changes whose trip it is.
  void replaceRow(Itinerary row) {
    if (state case AsyncData(:final value)
        when value.any((item) => item.itinerary.id == row.id)) {
      state = AsyncData([
        for (final item in value)
          item.itinerary.id == row.id
              ? FeedItem(itinerary: row, owner: item.owner)
              : item,
      ]);
    }
  }

  /// The trip is no longer mine to edit — I left it, or a save of mine took
  /// my access — so the server would no longer list it.
  void removeRow(String itineraryId) {
    if (state case AsyncData(:final value)) {
      state = AsyncData(
          value.where((item) => item.itinerary.id != itineraryId).toList());
    }
  }
}

final sharedWithMeProvider =
    AsyncNotifierProvider<SharedWithMeNotifier, List<FeedItem>>(
      () => SharedWithMeNotifier(),
    );

// ---------------------------------------------------------------------------
// ItineraryScope — which slice of the Itineraries tab is on screen.
// ---------------------------------------------------------------------------

enum ItineraryScope { all, mine, shared }

class ItineraryScopeNotifier extends Notifier<ItineraryScope> {
  // Default to `all` so a user who never touches the control is never shown a
  // partial list.
  @override
  ItineraryScope build() => ItineraryScope.all;

  void set(ItineraryScope scope) => state = scope;
}

// Purely presentational: both lists are already loaded, so unlike feedSortProvider
// nothing watches this inside a build() and flipping it never refetches.
final itineraryScopeProvider =
    NotifierProvider<ItineraryScopeNotifier, ItineraryScope>(
      ItineraryScopeNotifier.new,
    );

// ---------------------------------------------------------------------------
// TripSeeds — trips created here, waiting for their screen's first read
// ---------------------------------------------------------------------------

/// A create answers with the trip it made, and the trip waits here until its
/// screen first reads it, so that screen opens with no GET. Taken once: any
/// later build downloads, as a pull-to-refresh must.
///
/// A plain holder, not provider state: [ItineraryDetailNotifier.build] takes
/// from it, and a provider may not change another provider while it builds.
class TripSeeds {
  final _trips = <String, Itinerary>{};

  void put(Itinerary trip) => _trips[trip.id] = trip;

  Itinerary? take(String id) => _trips.remove(id);
}

/// Keep-alive and user-scoped: reset with the account's other state.
final tripSeedsProvider = Provider<TripSeeds>((ref) => TripSeeds());

// ---------------------------------------------------------------------------
// ItineraryDetailNotifier
// ---------------------------------------------------------------------------

/// A trip save's request, made with the repository and this device's claim.
typedef _TripSend = Future<TripEditAnswer> Function(
    ItineraryRepository repo, String? lockToken);

class ItineraryDetailNotifier extends AsyncNotifier<Itinerary> {
  // Riverpod 3 removed FamilyAsyncNotifier; the family argument (itinerary id)
  // now arrives via the constructor and is kept in `arg` so method bodies below
  // read identically to the pre-migration code.
  ItineraryDetailNotifier(this.arg);
  final String arg;

  @override
  FutureOr<Itinerary> build() {
    // A trip created on this device opens on its create's answer, at once and
    // with no GET; every later build downloads it.
    final seed = ref.read(tripSeedsProvider).take(arg);
    if (seed != null) return seed;
    return ref.read(itineraryRepositoryProvider).getItinerary(arg);
  }

  /// Current ETag for the If-Match header on every mutation.
  ///
  /// Reads the itinerary's updatedAt from the currently loaded state and
  /// formats it as a quoted RFC 7232 string, e.g. '"2026-05-07T14:23:11Z"'.
  ///
  /// Returns '' if state is not yet loaded (AsyncLoading / AsyncError). In
  /// practice this shouldn't happen because the user has to view the itinerary
  /// detail screen (which loads state) before any mutation is possible. If it
  /// does happen the server returns 412 / ItineraryStaleException which prompts
  /// a reload — a safe fallback.
  String get _etag => state.value?.eTag ?? '';

  // Writes carrying this device's claim that are still running, and whether
  // one of them failed since the count was last zero.
  int _writesInFlight = 0;
  bool _writeFailed = false;
  Completer<bool>? _writesSettled;

  /// Whether a write carrying this device's edit claim is still running.
  bool get hasWritesInFlight => _writesInFlight > 0;

  /// Completes once no write is running: true when every write that ran in
  /// the meantime landed, false when one failed (its caller shows the error).
  ///
  /// Leaving edit mode waits on this. Handing the claim back under a running
  /// write made the server refuse it — after the screen that would have shown
  /// the error had gone, so the change was lost without a word.
  Future<bool> writesSettled() => _writesInFlight == 0
      ? Future.value(true)
      : (_writesSettled ??= Completer<bool>()).future;

  /// Runs a write that carries this device's edit claim, counted until its
  /// answer has been adopted.
  ///
  /// The claim reaches [body] as `lockToken` and is readable nowhere else, so
  /// no write can skip the count. Null when no session was started — the server
  /// answers 428 and the presentation layer surfaces it, which is the right
  /// outcome: a mutation fired outside edit mode is a client bug, not something
  /// to paper over by claiming a lock nobody asked for.
  Future<T> _write<T>(Future<T> Function(String? lockToken) body) async {
    if (_writesInFlight++ == 0) _writeFailed = false;
    try {
      return await body(ref.read(editLockProvider(arg)).token);
    } catch (_) {
      _writeFailed = true;
      rethrow;
    } finally {
      if (--_writesInFlight == 0) {
        final settled = _writesSettled;
        _writesSettled = null;
        settled?.complete(!_writeFailed);
      }
    }
  }

  /// Full re-fetch from the server: pull-to-refresh and Retry on the detail
  /// screen. Never after a save — every save adopts the trip from its own
  /// answer ([_adopt]) — and never after leaving as an editor, which is
  /// [editRightsEnded]. Forces a fresh server fetch (bypasses the cache
  /// validator) so a 304 with a stale local body can't silently no-op a
  /// pull-to-refresh.
  Future<void> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return;
    state = const AsyncLoading();
    final next = await AsyncValue.guard(
      () => ref
          .read(itineraryRepositoryProvider)
          .getItinerary(arg, forceRefresh: true),
    );
    if (!ref.mounted) return; // disposed mid-request (logout)
    state = next;
  }

  /// Adopt a trip edit's answer — the whole trip as the server now has it,
  /// totals and track structure included — so a save is its one request and
  /// the screen is never rebuilt behind a reload. Ends on what was adopted.
  Future<AsyncValue<Itinerary>> _adopt(TripEditAnswer answer) async {
    final trip = answer.itinerary;
    // No trip: this very save took the viewer's access away (moderation hid an
    // editor's text on the spot), and the GET's refusal is what the screen
    // shows for that — the one request a save can be followed by.
    final next = trip != null
        ? AsyncData(trip)
        : await AsyncValue.guard(
            () => ref
                .read(itineraryRepositoryProvider)
                .getItinerary(arg, forceRefresh: true),
          );
    if (!ref.mounted) return next; // disposed mid-request (logout)
    state = next;
    return next;
  }

  /// One trip save — the only way any of them is made. [send] makes the
  /// request with this device's claim; its answer is adopted, and the trip's
  /// row in the Itineraries tab follows it, so nothing is downloaded after.
  /// Ends on the answer and what was adopted from it.
  Future<(TripEditAnswer, AsyncValue<Itinerary>)> _save(_TripSend send) =>
      _write((lockToken) async {
        final answer =
            await send(ref.read(itineraryRepositoryProvider), lockToken);
        _syncListRows(answer);
        return (answer, await _adopt(answer));
      });

  /// [_save] for a caller that needs the trip back, and what a create made.
  /// With no trip, the GET's own refusal is the answer — not requireValue,
  /// which wraps it.
  Future<({Itinerary trip, String? createdId})> _saveTrip(
    _TripSend send,
  ) async {
    final (answer, adopted) = await _save(send);
    if (adopted case AsyncData(:final value)) {
      return (trip: value, createdId: answer.createdId);
    }
    Error.throwWithStackTrace(adopted.error!, adopted.stackTrace!);
  }

  /// The Itineraries tab shows this trip's title, cover, stop count and
  /// totals, and both of its lists are keep-alive: the answered trip replaces
  /// the trip's row in whichever list is loaded, so a save downloads no list.
  /// No trip means the save took this viewer's access, and Shared with me
  /// would no longer list it.
  void _syncListRows(TripEditAnswer answer) {
    if (!ref.mounted) return;
    final row = answer.itinerary?.summary;
    if (row != null && ref.exists(myItinerariesProvider)) {
      ref.read(myItinerariesProvider.notifier).replaceRow(row);
    }
    if (ref.exists(sharedWithMeProvider)) {
      final shared = ref.read(sharedWithMeProvider.notifier);
      if (row == null) {
        shared.removeRow(arg);
      } else {
        shared.replaceRow(row);
      }
    }
  }

  /// This viewer gave their edit rights back. The trip a GET would now show
  /// them differs only in can_edit, so it changes here and nothing downloads.
  void editRightsEnded() {
    if (!ref.mounted) return;
    if (state case AsyncData(:final value)) {
      state = AsyncData(value.copyWith(canEdit: false));
    }
  }

  /// Add a stop. The ETag is attached automatically via _etag — the
  /// presentation layer does not need to know about concurrency control.
  /// Returns the created [Stop] so callers can act on its real server-assigned
  /// id (e.g. attach annotations) — the new stop is not necessarily last in
  /// rank order.
  Future<Stop> addStop(Map<String, dynamic> data) async {
    final saved = await _saveTrip((repo, lockToken) =>
        repo.addStop(arg, data, etag: _etag, lockToken: lockToken));
    return saved.trip.stops.firstWhere((s) => s.id == saved.createdId);
  }

  /// Update a stop.
  Future<void> updateStop(String stopId, Map<String, dynamic> data) =>
      _save((repo, lockToken) => repo.updateStop(arg, stopId, data,
          etag: _etag, lockToken: lockToken));

  /// Commit a batch reorder in one server transaction.
  ///
  /// At least one of [stopOrders], [trackOrder], or [segmentIdsToDelete] must
  /// be provided. The server validates set-equality (for stop_orders and
  /// track_order), recomputes fractional-index ranks, deletes any requested
  /// segments, and answers with the full updated itinerary, which is adopted
  /// as the server-confirmed state.
  Future<void> applyReorder({
    Map<String, List<String>>? stopOrders,
    List<String>? trackOrder,
    List<String>? segmentIdsToDelete,
  }) =>
      _save((repo, lockToken) => repo.reorderItinerary(
            arg,
            stopOrders: stopOrders,
            trackOrder: trackOrder,
            segmentIdsToDelete: segmentIdsToDelete,
            etag: _etag, lockToken: lockToken,
          ));

  /// Move a stop to a new position.
  ///
  /// Three move modes, mutually exclusive:
  ///   1. Within-track reorder: pass [afterStopId] / [beforeStopId] only.
  ///   2. Cross-track move into an existing track: pass [targetTrackId].
  ///   3. New-track move: pass [afterTrackId] and/or [beforeTrackId]
  ///      (with [targetTrackId] null). Server creates a brand-new track at
  ///      that position and moves this stop into it as the sole member.
  ///
  /// Adopts the answered trip, ETag included. Returns the moved [Stop] so
  /// callers can read its (possibly newly created) `trackId`.
  Future<Stop> moveStop(
    String stopId, {
    String? afterStopId,
    String? beforeStopId,
    String? targetTrackId,
    String? afterTrackId,
    String? beforeTrackId,
  }) async {
    final body = <String, dynamic>{
      if (afterStopId != null) 'after_stop_id': afterStopId,
      if (beforeStopId != null) 'before_stop_id': beforeStopId,
      if (targetTrackId != null) 'track_id': targetTrackId,
      if (afterTrackId != null) 'after_track_id': afterTrackId,
      if (beforeTrackId != null) 'before_track_id': beforeTrackId,
    };
    final saved = await _saveTrip((repo, lockToken) =>
        repo.updateStop(arg, stopId, body, etag: _etag, lockToken: lockToken));
    return saved.trip.stops.firstWhere((s) => s.id == stopId);
  }

  /// Delete a stop.
  Future<void> deleteStop(String stopId) => _save((repo, lockToken) =>
      repo.deleteStop(arg, stopId, etag: _etag, lockToken: lockToken));

  /// Update itinerary header fields.
  Future<Itinerary> updateHeader(Map<String, dynamic> data) async =>
      (await _saveTrip((repo, lockToken) => repo.updateItinerary(arg, data,
              etag: _etag, lockToken: lockToken)))
          .trip;

  /// The Edit itinerary form's save: its fields and, from the owner, a cover
  /// change, in one request. A cover sent ahead on its own moved updated_at, so
  /// the field save behind it carried a stale If-Match and was refused.
  Future<Itinerary> saveForm(
    Map<String, dynamic> data, {
    Uint8List? coverBytes,
    String? coverFilename,
    bool removeCover = false,
  }) async =>
      (await _saveTrip((repo, lockToken) => repo.saveItineraryForm(
                arg,
                data,
                coverBytes: coverBytes,
                coverFilename: coverFilename,
                removeCover: removeCover,
                etag: _etag,
                lockToken: lockToken,
              )))
          .trip;

  /// Create a transit segment.
  Future<void> createSegment(Map<String, dynamic> data) =>
      _save((repo, lockToken) => repo.createSegment(arg, data,
          etag: _etag, lockToken: lockToken));

  /// Update (replace) a transit segment.
  Future<void> updateSegment(
    String segmentId,
    Map<String, dynamic> data,
  ) =>
      _save((repo, lockToken) => repo.updateSegment(arg, segmentId, data,
          etag: _etag, lockToken: lockToken));

  /// Delete a transit segment.
  Future<void> deleteSegment(String segmentId) => _save((repo, lockToken) =>
      repo.deleteSegment(arg, segmentId, etag: _etag, lockToken: lockToken));

  /// Add a stop-level annotation.
  Future<void> addAnnotation(String stopId, Map<String, dynamic> data) =>
      _save((repo, lockToken) => repo.addAnnotation(arg, stopId, data,
          etag: _etag, lockToken: lockToken));

  /// Update a stop-level annotation.
  Future<void> updateAnnotation(
    String stopId,
    String annotationId, {
    String? content,
    AnnotationType? type,
  }) =>
      _save((repo, lockToken) => repo.updateAnnotation(
            arg,
            stopId,
            annotationId,
            content: content,
            type: type,
            etag: _etag, lockToken: lockToken,
          ));

  /// Delete a stop-level annotation.
  Future<void> deleteAnnotation(String stopId, String annotationId) =>
      _save((repo, lockToken) => repo.deleteAnnotation(arg, stopId, annotationId,
          etag: _etag, lockToken: lockToken));

  /// Add an itinerary-level annotation.
  Future<void> addItineraryAnnotation(Map<String, dynamic> data) =>
      _save((repo, lockToken) => repo.addItineraryAnnotation(arg, data,
          etag: _etag, lockToken: lockToken));

  /// Update an itinerary-level annotation.
  Future<void> updateItineraryAnnotation(
    String annotationId, {
    String? content,
    AnnotationType? type,
  }) =>
      _save((repo, lockToken) => repo.updateItineraryAnnotation(
            arg,
            annotationId,
            content: content,
            type: type,
            etag: _etag, lockToken: lockToken,
          ));

  /// Delete an itinerary-level annotation.
  Future<void> deleteItineraryAnnotation(String annotationId) =>
      _save((repo, lockToken) => repo.deleteItineraryAnnotation(
          arg, annotationId,
          etag: _etag, lockToken: lockToken));

  /// A rating moved the trip's aggregate, and its answer carries the new one.
  /// updatedAt stays where it was — the server's aggregate write preserves it
  /// — so the ETag the next save sends does too.
  void adoptRatingAggregate(RatingAggregate aggregate) {
    if (!ref.mounted) return;
    // Only onto a loaded trip: a failed load is not a trip to put numbers on.
    if (state case AsyncData(:final value)) {
      state = AsyncData(value.copyWith(
        ratingAvg: aggregate.avg,
        clearRatingAvg: aggregate.avg == null,
        ratingCount: aggregate.count,
      ));
    }
  }
}

final itineraryDetailProvider =
    AsyncNotifierProvider.family<ItineraryDetailNotifier, Itinerary, String>(
      ItineraryDetailNotifier.new,
    );

// ---------------------------------------------------------------------------
// AllowedUsersNotifier
// ---------------------------------------------------------------------------

class AllowedUsersNotifier extends AsyncNotifier<List<AllowedUser>> {
  AllowedUsersNotifier(this.arg); // family argument: itinerary id
  final String arg;

  @override
  Future<List<AllowedUser>> build() {
    return ref.read(itineraryRepositoryProvider).getAllowedUsers(arg);
  }

  Future<void> addUser(String userId) async {
    final added = await ref
        .read(itineraryRepositoryProvider)
        .addAllowedUser(arg, userId);
    if (!ref.mounted) return; // disposed mid-request (logout)
    state.whenData((list) {
      state = AsyncData([...list, added]);
    });
  }

  Future<void> removeUser(String userId) async {
    await ref.read(itineraryRepositoryProvider).removeAllowedUser(arg, userId);
    if (!ref.mounted) return; // disposed mid-request (logout)
    state.whenData((list) {
      state = AsyncData(list.where((u) => u.userId != userId).toList());
    });
  }
}

final allowedUsersProvider = AsyncNotifierProvider.family<
  AllowedUsersNotifier,
  List<AllowedUser>,
  String
>(AllowedUsersNotifier.new);

// ---------------------------------------------------------------------------
// EditorsNotifier — who, besides the owner, may modify one itinerary.
// Same shape as AllowedUsersNotifier; only the owner ever mutates either.
// ---------------------------------------------------------------------------

class EditorsNotifier extends AsyncNotifier<List<ItineraryEditor>> {
  EditorsNotifier(this.arg); // family argument: itinerary id
  final String arg;

  @override
  Future<List<ItineraryEditor>> build() {
    return ref.read(itineraryRepositoryProvider).getEditors(arg);
  }

  /// Grant edit rights. Rethrows [EditorCannotViewException] untouched — that
  /// is a question for the owner, not a failure, and the screen is the only
  /// layer that can ask it.
  ///
  /// The owner's trip is not downloaded again: a grant leaves updated_at, and
  /// everything the owner sees, as it was.
  Future<void> addEditor(String userId, {bool grantView = false}) async {
    final added = await ref
        .read(itineraryRepositoryProvider)
        .addEditor(arg, userId, grantView: grantView);
    if (!ref.mounted) return; // disposed mid-request (logout)
    state.whenData((list) {
      state = AsyncData([...list, added]);
    });
    // The allowlist gained a row the answer does not carry; no open screen
    // shows it, so it loads when the visibility screen next opens.
    if (grantView) ref.invalidate(allowedUsersProvider(arg));
  }

  /// The owner revokes someone else's edit rights. Nothing in the trip the
  /// owner sees changes, so only this list does.
  Future<void> removeEditor(String userId) async {
    await ref.read(itineraryRepositoryProvider).removeEditor(arg, userId);
    if (!ref.mounted) return; // disposed mid-request (logout)
    _dropRow(userId);
  }

  /// An editor hands their own edit rights back. Their trip view and their
  /// Shared list follow from that alone, so nothing is downloaded.
  Future<void> leave(String myId) async {
    await ref.read(itineraryRepositoryProvider).removeEditor(arg, myId);
    if (!ref.mounted) return; // disposed mid-request (logout)
    _dropRow(myId);
    final trip = itineraryDetailProvider(arg);
    if (ref.exists(trip)) ref.read(trip.notifier).editRightsEnded();
    if (ref.exists(sharedWithMeProvider)) {
      ref.read(sharedWithMeProvider.notifier).removeRow(arg);
    }
  }

  void _dropRow(String userId) {
    state.whenData((list) {
      state = AsyncData(list.where((e) => e.userId != userId).toList());
    });
  }
}

final editorsProvider = AsyncNotifierProvider.family<
  EditorsNotifier,
  List<ItineraryEditor>,
  String
>(EditorsNotifier.new);

// ---------------------------------------------------------------------------
// UserItinerariesNotifier
// ---------------------------------------------------------------------------

class UserItinerariesNotifier extends AsyncNotifier<List<Itinerary>> {
  UserItinerariesNotifier(this.arg); // family argument: user id
  final String arg;

  @override
  Future<List<Itinerary>> build() {
    return ref.read(itineraryRepositoryProvider).getUserItineraries(arg);
  }

  Future<void> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return;
    state = const AsyncLoading();
    final next = await AsyncValue.guard(
      () => ref
          .read(itineraryRepositoryProvider)
          .getUserItineraries(arg, forceRefresh: true),
    );
    if (!ref.mounted) return; // disposed mid-request (logout)
    state = next;
  }
}

final userItinerariesProvider = AsyncNotifierProvider.family<
  UserItinerariesNotifier,
  List<Itinerary>,
  String
>(UserItinerariesNotifier.new);

// ---------------------------------------------------------------------------
// MyRatingNotifier
// ---------------------------------------------------------------------------

class MyRatingNotifier extends AsyncNotifier<MyRating?> {
  MyRatingNotifier(this.arg); // family argument: itinerary id
  final String arg;

  @override
  Future<MyRating?> build() {
    return ref.read(itineraryRepositoryProvider).getMyRating(arg);
  }

  Future<void> submitRating(MyRating rating) async {
    final saved = await ref
        .read(itineraryRepositoryProvider)
        .submitRating(arg, rating, withRatingsPage: _ratingsPageLoaded);
    if (!ref.mounted) return; // disposed mid-request (logout)
    state = AsyncData(saved.rating);
    _adoptPage(saved.page);
    _adoptAggregate(saved.aggregate);
  }

  Future<void> deleteRating() async {
    final left = await ref
        .read(itineraryRepositoryProvider)
        .deleteMyRating(arg, withRatingsPage: _ratingsPageLoaded);
    if (!ref.mounted) return; // disposed mid-request (logout)
    state = const AsyncData(null);
    _adoptPage(left.page);
    _adoptAggregate(left.aggregate);
  }

  /// The ratings page is keep-alive: once opened it holds this trip's reviews,
  /// averages and histogram, so a rating asks for the page as it now stands
  /// and adopts it. A page never opened is not asked for — reading it would
  /// build it, which is a GET.
  bool get _ratingsPageLoaded => ref.exists(ratingsPageProvider(arg));

  void _adoptPage(RatingsPage? page) {
    if (page != null && _ratingsPageLoaded) {
      ref.read(ratingsPageProvider(arg).notifier).adopt(page);
    }
  }

  /// The answer carries the trip's new aggregate, so the trip page takes it
  /// from there instead of downloading the trip again. Only a trip already
  /// loaded: reading the provider would otherwise build it, which is a GET.
  void _adoptAggregate(RatingAggregate aggregate) {
    final trip = itineraryDetailProvider(arg);
    if (ref.exists(trip)) ref.read(trip.notifier).adoptRatingAggregate(aggregate);
  }
}

final myRatingProvider =
    AsyncNotifierProvider.family<MyRatingNotifier, MyRating?, String>(
      MyRatingNotifier.new,
    );

// ---------------------------------------------------------------------------
// RatingsPageNotifier
// ---------------------------------------------------------------------------

class RatingsPageNotifier extends AsyncNotifier<RatingsPage> {
  RatingsPageNotifier(this.arg); // family argument: itinerary id
  final String arg;

  @override
  Future<RatingsPage> build() {
    return ref.read(itineraryRepositoryProvider).getRatingsPage(arg);
  }

  Future<void> refresh() async {
    // Offline: keep cached AsyncData — a forced refresh could only degrade it.
    if (!isOnlineNowRef(ref)) return;
    state = const AsyncLoading();
    final next = await AsyncValue.guard(
      () => ref
          .read(itineraryRepositoryProvider)
          .getRatingsPage(arg, forceRefresh: true),
    );
    if (!ref.mounted) return; // disposed mid-request (logout)
    state = next;
  }

  /// A rating write answered with the page as it now stands.
  void adopt(RatingsPage page) {
    if (!ref.mounted) return;
    state = AsyncData(page);
  }
}

final ratingsPageProvider =
    AsyncNotifierProvider.family<RatingsPageNotifier, RatingsPage, String>(
      RatingsPageNotifier.new,
    );

// ---------------------------------------------------------------------------
// PlaceSearchNotifier
// ---------------------------------------------------------------------------

class PlaceSearchNotifier extends AsyncNotifier<List<PlaceSuggestion>> {
  // Bumped by every search/searchArea/clear — a stale searchArea widening loop
  // compares its captured value and abandons instead of overwriting new state.
  int _epoch = 0;

  @override
  Future<List<PlaceSuggestion>> build() async => [];

  /// [near] biases results toward that point and sorts them nearest-first
  /// (see GeocodingService.search).
  Future<void> search(String query, {LatLng? near}) async {
    _epoch++;
    if (query.trim().isEmpty) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();
    final next = await AsyncValue.guard(
      () => ref
          .read(geocodingServiceProvider)
          .search(
            query,
            languageCode: ref.read(localeProvider).languageCode,
            near: near,
          ),
    );
    if (!ref.mounted) return; // disposed mid-request (logout)
    state = next;
  }

  /// Searches inside the box [sw]–[ne] (the map's visible bounds). If the box
  /// has no matches, widens it ×4 around [center] up to twice (viewport → ×4 →
  /// ×16 span), then falls back to an unbounded search — so the nearest
  /// matches are always found even when far outside the displayed area.
  /// Results are sorted nearest-to-[center] first.
  Future<void> searchArea(
    String query, {
    required LatLng sw,
    required LatLng ne,
    required LatLng center,
  }) async {
    final epoch = ++_epoch;
    if (query.trim().isEmpty) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();

    final service = ref.read(geocodingServiceProvider);
    final languageCode = ref.read(localeProvider).languageCode;
    final halfLat = (ne.latitude - sw.latitude) / 2;
    final halfLng = (ne.longitude - sw.longitude) / 2;

    try {
      List<PlaceSuggestion> results = [];
      // factor 1 = the visible box; 4/16 = zero-result widenings around center.
      for (final factor in const [1, 4, 16]) {
        if (factor > 1) {
          // Space attempts ≥1s apart — Nominatim ToS caps at 1 request/second.
          await Future.delayed(const Duration(seconds: 1));
          if (epoch != _epoch) return; // superseded by a newer query
        }
        results = await service.search(
          query,
          languageCode: languageCode,
          near: center,
          boxSw: LatLng(
            center.latitude - halfLat * factor,
            center.longitude - halfLng * factor,
          ),
          boxNe: LatLng(
            center.latitude + halfLat * factor,
            center.longitude + halfLng * factor,
          ),
          bounded: true,
        );
        if (epoch != _epoch) return;
        if (results.isNotEmpty) break;
      }

      if (results.isEmpty) {
        await Future.delayed(const Duration(seconds: 1));
        if (epoch != _epoch) return;
        // Unbounded fallback: soft bias + distance sort = nearest 5 anywhere.
        results = await service.search(
          query,
          languageCode: languageCode,
          near: center,
        );
        if (epoch != _epoch) return;
      }

      if (!ref.mounted) return; // disposed mid-request (logout)
      state = AsyncData(results);
    } catch (error, stackTrace) {
      if (epoch != _epoch || !ref.mounted) return;
      state = AsyncError(error, stackTrace);
    }
  }

  void clear() {
    _epoch++;
    state = const AsyncData([]);
  }
}

final placeSearchProvider =
    AsyncNotifierProvider<PlaceSearchNotifier, List<PlaceSuggestion>>(
      () => PlaceSearchNotifier(),
    );

/// Separate instance for the map picker — the stop form (beneath it in the
/// navigator stack) watches [placeSearchProvider]; sharing one would leak the
/// picker's results into the form's inline suggestion list on return.
final mapPlaceSearchProvider =
    AsyncNotifierProvider<PlaceSearchNotifier, List<PlaceSuggestion>>(
      () => PlaceSearchNotifier(),
    );

// ---------------------------------------------------------------------------
// ShareService provider
// ---------------------------------------------------------------------------

final shareServiceProvider = Provider<ShareService>((ref) => ShareService());

// ---------------------------------------------------------------------------
// MapsLauncherService provider
// ---------------------------------------------------------------------------

final mapsLauncherServiceProvider = Provider<MapsLauncherService>(
  (ref) => MapsLauncherService(),
);
