// features/itineraries/data/itinerary_repository.dart — Itinerary API calls.
//
// EVERY CONTENT MUTATION CARRIES TWO PRECONDITIONS:
//
//   If-Match: the quoted updated_at timestamp from the last server response,
//   e.g. '"2026-05-07T14:23:11Z"'. Answers "is my copy current?".
//     - Match  → proceeds; the new ETag comes back in the response header.
//     - Stale  → 412 → ItineraryStaleException.
//
//   X-Edit-Lock: the opaque claim token from POST /itineraries/{id}/lock.
//   Answers "am I still the one editing?". Server-minted and rotated on every
//   takeover, so a device that was displaced fails here even though nothing
//   told it and it still believes it holds the claim.
//     - Missing → 428 → EditLockRequiredException.
//     - Rotated → 409 → EditLockLostException.
//     - Someone else holds it (claim path only) → 423 → ItineraryLockedException.
//
// WHO PROVIDES THEM?
//   ItineraryDetailNotifier._etag reads the ETag from the loaded state
//   (state.value?.eTag); EditLockNotifier holds the claim token. Every mutation
//   passes both down without the presentation layer thinking about it.
//
//   The header is attached explicitly, per call — never by a Dio interceptor.
//   A blanket interceptor would keep sending a token the client no longer
//   holds, onto requests that must not carry one.
//
// EVERY CONTENT MUTATION ASKS FOR THE TRIP BACK (`?return=itinerary`), AND
// SO DOES A CREATE: the answer is the whole trip as a GET would show it, so
// the save is the only request — nothing downloads the trip again after it. The
// server needs that parameter to answer this way; a backend without it answers
// the old shapes, so it deploys first.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ntripi/core/api/api_client.dart';
import 'package:ntripi/core/api/api_endpoints.dart';
// shared-with-me returns the same rows as the discovery feed (summary +
// owner), so it reuses FeedItem instead of duplicating the owner model.
import 'package:ntripi/features/feed/domain/feed_item.dart';
import 'package:ntripi/features/itineraries/domain/allowed_user.dart';
import 'package:ntripi/features/itineraries/domain/annotation.dart';
import 'package:ntripi/features/itineraries/domain/edit_lock.dart';
import 'package:ntripi/features/itineraries/domain/itinerary.dart';
import 'package:ntripi/features/itineraries/domain/itinerary_editor.dart';
import 'package:ntripi/features/itineraries/domain/my_rating.dart';
import 'package:ntripi/features/itineraries/domain/ratings_page.dart';
import 'package:ntripi/features/itineraries/domain/trip_edit_answer.dart';

/// Thrown when the server returns 412 Precondition Failed.
///
/// This means the itinerary was modified from another device (or another tab)
/// after the client's last fetch. The presentation layer should catch this,
/// show a "reload" dialog, and re-fetch the itinerary before retrying.
class ItineraryStaleException implements Exception {
  const ItineraryStaleException();
  @override
  String toString() =>
      'ItineraryStaleException: itinerary modified remotely, please reload';
}

/// Thrown on 409 — the edit claim this device was holding has been rotated
/// away, so the write did not happen.
///
/// The presentation layer must NOT pop the screen or clear any field here: the
/// user is mid-edit and their unsaved input is now the only copy. Show it,
/// disable Save, and offer to reclaim.
class EditLockLostException implements Exception {
  const EditLockLostException(this.holder);

  /// Who holds the claim now, when the server said. Null when it is simply gone.
  final EditLock? holder;

  @override
  String toString() => 'EditLockLostException: the editing session was taken over';
}

/// Thrown on 423 — somebody else's claim is in the way. Answerable by waiting
/// or (once takeable, or always for the owner) taking over, which is why it is
/// a different type from [EditLockLostException].
class ItineraryLockedException implements Exception {
  const ItineraryLockedException(this.holder);

  final EditLock? holder;

  @override
  String toString() => 'ItineraryLockedException: someone else is editing';
}

/// Thrown on 428 `edit_lock_required` — a mutation went out with no claim.
/// Always a client bug: acquire the lock before entering edit mode.
class EditLockRequiredException implements Exception {
  const EditLockRequiredException();
  @override
  String toString() => 'EditLockRequiredException: no editing session was started';
}

/// Build Dio options carrying both preconditions.
/// [etag] must already be quoted: '"2026-05-07T14:23:11Z"'.
Options _editOptions(String etag, String? lockToken) => Options(
      headers: {
        'If-Match': etag,
        if (lockToken != null) kEditLockHeader: lockToken,
      },
    );

/// What every trip edit asks to be answered with: the whole trip.
const _returnTrip = {'return': 'itinerary'};

/// Map the guard's rejections onto typed exceptions. Anything else rethrows and
/// is decoded downstream by extractErrorMessage.
Never _mapGuardError(DioException e) {
  final status = e.response?.statusCode;
  final body = e.response?.data;
  final code = body is Map ? body['code'] as String? : null;
  final holderJson = body is Map ? body['lock'] : null;
  final holder = holderJson is Map<String, dynamic>
      ? EditLock.fromJson(holderJson)
      : null;

  if (status == 412) throw const ItineraryStaleException();
  if (status == 409 && code == 'edit_lock_lost') throw EditLockLostException(holder);
  if (status == 423) throw ItineraryLockedException(holder);
  if (status == 428 && code == 'edit_lock_required') {
    throw const EditLockRequiredException();
  }
  throw e;
}

class ItineraryRepository {
  final Dio _dio;

  const ItineraryRepository(this._dio);

  /// A trip edit sent with [send], which asks for the trip back: its guard
  /// rejections are mapped as everywhere else, and the trip it answers with
  /// also becomes the cached answer to the trip's GET — the copy a trip shows
  /// offline, which the reload that used to follow every save kept current.
  /// Keyed by the answered trip's own id: a create has none until it answers.
  Future<TripEditAnswer> _tripEdit(
    Future<Response<Map<String, dynamic>>> Function() send,
  ) async {
    final Response<Map<String, dynamic>> response;
    try {
      response = await send();
    } on DioException catch (e) {
      _mapGuardError(e);
    }
    final data = response.data!;
    final trip = data['itinerary'];
    if (trip is Map<String, dynamic>) {
      await cacheAsGet(response.requestOptions,
          itineraryEndpoint(trip['id'] as String), trip);
    }
    return TripEditAnswer.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // Itinerary CRUD
  // ---------------------------------------------------------------------------

  Future<List<Itinerary>> getMyItineraries({bool forceRefresh = false}) async {
    final response = await _dio.get<List<dynamic>>(
      kMyItinerariesEndpoint,
      options: forceRefresh ? forceRefreshOptions() : null,
    );
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(Itinerary.fromJson)
        .toList();
  }

  /// Itineraries the caller was granted edit rights on (never their own).
  /// The payload is the feed row shape — summary fields plus owner attribution
  /// — so FeedItem parses it rather than a second owner model.
  Future<List<FeedItem>> getSharedWithMe({bool forceRefresh = false}) async {
    final response = await _dio.get<List<dynamic>>(
      kSharedWithMeEndpoint,
      options: forceRefresh ? forceRefreshOptions() : null,
    );
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(FeedItem.fromJson)
        .toList();
  }

  Future<List<Itinerary>> getUserItineraries(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      userItinerariesEndpoint(userId),
      options: forceRefresh ? forceRefreshOptions() : null,
    );
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(Itinerary.fromJson)
        .toList();
  }

  Future<Itinerary> getItinerary(String id, {bool forceRefresh = false}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      itineraryEndpoint(id),
      options: forceRefresh ? forceRefreshOptions() : null,
    );
    final data = response.data!;
    final itinerary = Itinerary.fromJson(data);
    // Diagnostic: which path served the body and did parsing keep the tracks?
    // `assert(() { … return true; }())` is the same trick api_client.dart uses
    // for its LogInterceptor — the whole block is tree-shaken in release.
    assert(() {
      final tracksRaw = data['tracks'];
      debugPrint(
        '[itinerary.detail] id=$id '
        'forceRefresh=$forceRefresh '
        'statusCode=${response.statusCode} '
        'fromCache=${response.extra['@fromNetwork@'] == false} '
        'tracks_runtime=${tracksRaw.runtimeType} '
        'tracks_len=${tracksRaw is List ? tracksRaw.length : "n/a"} '
        'stops_count=${data['stops_count']} '
        '→ parsed tracks=${itinerary.tracks.length} '
        'stops=${itinerary.stops.length}',
      );
      return true;
    }());
    return itinerary;
  }

  // ---------------------------------------------------------------------------
  // Saved (bookmarked) itineraries — user-scoped state, no If-Match.
  // ---------------------------------------------------------------------------

  Future<List<Itinerary>> getSavedItineraries({bool forceRefresh = false}) async {
    final response = await _dio.get<List<dynamic>>(
      kSavedItinerariesEndpoint,
      options: forceRefresh ? forceRefreshOptions() : null,
    );
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(Itinerary.fromJson)
        .toList();
  }

  Future<void> saveItinerary(String id) async {
    await _dio.post(itinerarySaveEndpoint(id));
  }

  Future<void> unsaveItinerary(String id) async {
    await _dio.delete(itinerarySaveEndpoint(id));
  }

  /// A create answers like a trip edit — with the trip it made, whose id is
  /// [TripEditAnswer.createdId] — so its screen opens with no GET.
  Future<TripEditAnswer> createItinerary(Map<String, dynamic> data) =>
      _tripEdit(
        () => _dio.post<Map<String, dynamic>>(
          kItinerariesEndpoint,
          data: data,
          queryParameters: _returnTrip,
        ),
      );

  /// The New itinerary form's save when a cover was picked: the fields and the
  /// cover in one multipart request, so a refused cover creates nothing.
  Future<TripEditAnswer> createItineraryWithCover(
    Map<String, dynamic> data, {
    required Uint8List coverBytes,
    String? coverFilename,
  }) =>
      _tripEdit(
        () => _dio.post<Map<String, dynamic>>(
          kItineraryFormEndpoint,
          data: FormData.fromMap({
            'fields': jsonEncode(data),
            'image': _coverPart(coverBytes, coverFilename),
          }),
          queryParameters: _returnTrip,
        ),
      );

  /// Header fields: title, description, currency, recommended period — and
  /// `visibility`, which the server accepts only from the owner.
  Future<TripEditAnswer> updateItinerary(
    String id,
    Map<String, dynamic> data, {
    required String etag,
    required String? lockToken,
  }) =>
      _tripEdit(
        () => _dio.patch<Map<String, dynamic>>(
          itineraryEndpoint(id),
          data: data,
          queryParameters: _returnTrip,
          options: _editOptions(etag, lockToken),
        ),
      );

  /// The Edit itinerary form's save: [data] as for [updateItinerary], plus a
  /// cover change from the owner — [coverBytes] replaces it, [removeCover]
  /// takes it off — in one multipart request under one If-Match and one claim.
  /// Sent as two, the cover write moved updated_at and the PATCH behind it 412'd.
  Future<TripEditAnswer> saveItineraryForm(
    String id,
    Map<String, dynamic> data, {
    Uint8List? coverBytes,
    String? coverFilename,
    bool removeCover = false,
    required String etag,
    required String? lockToken,
  }) =>
      _tripEdit(
        () => _dio.patch<Map<String, dynamic>>(
          itineraryFormEndpoint(id),
          data: FormData.fromMap({
            'fields': jsonEncode(data),
            if (coverBytes != null)
              'image': _coverPart(coverBytes, coverFilename),
            if (removeCover) 'remove_cover': 'true',
          }),
          queryParameters: _returnTrip,
          options: _editOptions(etag, lockToken),
        ),
      );

  static MultipartFile _coverPart(Uint8List bytes, String? filename) =>
      MultipartFile.fromBytes(bytes, filename: filename ?? 'cover.jpg');

  Future<void> deleteItinerary(String id) async {
    await _dio.delete(itineraryEndpoint(id));
  }

  // ---------------------------------------------------------------------------
  // Stop CRUD — all require ETag
  // ---------------------------------------------------------------------------

  /// The answer's [TripEditAnswer.createdId] is the new stop.
  Future<TripEditAnswer> addStop(
    String itineraryId,
    Map<String, dynamic> data, {
    required String etag,
    required String? lockToken,
  }) =>
      _tripEdit(
        () => _dio.post<Map<String, dynamic>>(
          itineraryStopsEndpoint(itineraryId),
          data: data,
          queryParameters: _returnTrip,
          options: _editOptions(etag, lockToken),
        ),
      );

  Future<TripEditAnswer> updateStop(
    String itineraryId,
    String stopId,
    Map<String, dynamic> data, {
    required String etag,
    required String? lockToken,
  }) =>
      _tripEdit(
        () => _dio.patch<Map<String, dynamic>>(
          itineraryStopEndpoint(itineraryId, stopId),
          data: data,
          queryParameters: _returnTrip,
          options: _editOptions(etag, lockToken),
        ),
      );

  Future<TripEditAnswer> deleteStop(
    String itineraryId,
    String stopId, {
    required String etag,
    required String? lockToken,
  }) =>
      _tripEdit(
        () => _dio.delete<Map<String, dynamic>>(
          itineraryStopEndpoint(itineraryId, stopId),
          queryParameters: _returnTrip,
          options: _editOptions(etag, lockToken),
        ),
      );

  /// Apply a batch reorder in one atomic transaction.
  ///
  /// At least one of [stopOrders], [trackOrder], or [segmentIdsToDelete] must
  /// be non-empty / non-null.
  ///
  /// - [stopOrders] maps `trackId → [stopId, ...]` in the desired display
  ///   order. The provided stop-id set per track must exactly match the
  ///   track's current stop-id set, or the server returns 422.
  /// - [trackOrder] is the full track order. If provided, must contain
  ///   exactly the current track set.
  /// - [segmentIdsToDelete] is the list of segment IDs to remove in the
  ///   same transaction (typically those orphaned by a track reorder).
  Future<TripEditAnswer> reorderItinerary(
    String itineraryId, {
    Map<String, List<String>>? stopOrders,
    List<String>? trackOrder,
    List<String>? segmentIdsToDelete,
    required String etag,
    required String? lockToken,
  }) {
    final body = <String, dynamic>{
      if (stopOrders != null && stopOrders.isNotEmpty) 'stop_orders': stopOrders,
      if (trackOrder != null) 'track_order': trackOrder,
      if (segmentIdsToDelete != null && segmentIdsToDelete.isNotEmpty)
        'segments_to_delete': segmentIdsToDelete,
    };
    return _tripEdit(
      () => _dio.post<Map<String, dynamic>>(
        itineraryReorderEndpoint(itineraryId),
        data: body,
        queryParameters: _returnTrip,
        options: _editOptions(etag, lockToken),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Annotation CRUD — all require ETag
  // ---------------------------------------------------------------------------

  Future<TripEditAnswer> addAnnotation(
    String itineraryId,
    String stopId,
    Map<String, dynamic> data, {
    required String etag,
    required String? lockToken,
  }) =>
      _tripEdit(
        () => _dio.post<Map<String, dynamic>>(
          stopAnnotationsEndpoint(itineraryId, stopId),
          data: data,
          queryParameters: _returnTrip,
          options: _editOptions(etag, lockToken),
        ),
      );

  Future<TripEditAnswer> deleteAnnotation(
    String itineraryId,
    String stopId,
    String annotationId, {
    required String etag,
    required String? lockToken,
  }) =>
      _tripEdit(
        () => _dio.delete<Map<String, dynamic>>(
          stopAnnotationEndpoint(itineraryId, stopId, annotationId),
          queryParameters: _returnTrip,
          options: _editOptions(etag, lockToken),
        ),
      );

  Future<TripEditAnswer> updateAnnotation(
    String itineraryId,
    String stopId,
    String annotationId, {
    String? content,
    AnnotationType? type,
    required String etag,
    required String? lockToken,
  }) {
    final body = <String, dynamic>{
      if (content != null) 'content': content,
      if (type != null) 'type': type.name,
    };
    return _tripEdit(
      () => _dio.patch<Map<String, dynamic>>(
        stopAnnotationEndpoint(itineraryId, stopId, annotationId),
        data: body,
        queryParameters: _returnTrip,
        options: _editOptions(etag, lockToken),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Itinerary-level annotation CRUD — all require ETag
  // ---------------------------------------------------------------------------

  Future<TripEditAnswer> addItineraryAnnotation(
    String itineraryId,
    Map<String, dynamic> data, {
    required String etag,
    required String? lockToken,
  }) =>
      _tripEdit(
        () => _dio.post<Map<String, dynamic>>(
          itineraryAnnotationsEndpoint(itineraryId),
          data: data,
          queryParameters: _returnTrip,
          options: _editOptions(etag, lockToken),
        ),
      );

  Future<TripEditAnswer> updateItineraryAnnotation(
    String itineraryId,
    String annotationId, {
    String? content,
    AnnotationType? type,
    required String etag,
    required String? lockToken,
  }) {
    final body = <String, dynamic>{
      if (content != null) 'content': content,
      if (type != null) 'type': type.name,
    };
    return _tripEdit(
      () => _dio.patch<Map<String, dynamic>>(
        itineraryAnnotationEndpoint(itineraryId, annotationId),
        data: body,
        queryParameters: _returnTrip,
        options: _editOptions(etag, lockToken),
      ),
    );
  }

  Future<TripEditAnswer> deleteItineraryAnnotation(
    String itineraryId,
    String annotationId, {
    required String etag,
    required String? lockToken,
  }) =>
      _tripEdit(
        () => _dio.delete<Map<String, dynamic>>(
          itineraryAnnotationEndpoint(itineraryId, annotationId),
          queryParameters: _returnTrip,
          options: _editOptions(etag, lockToken),
        ),
      );

  // ---------------------------------------------------------------------------
  // Allowlist CRUD
  // ---------------------------------------------------------------------------

  Future<List<AllowedUser>> getAllowedUsers(String itineraryId) async {
    final response = await _dio.get<List<dynamic>>(
      itineraryAllowedUsersEndpoint(itineraryId),
    );
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(AllowedUser.fromJson)
        .toList();
  }

  Future<AllowedUser> addAllowedUser(String itineraryId, String userId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      itineraryAllowedUsersEndpoint(itineraryId),
      data: {'user_id': userId},
    );
    return AllowedUser.fromJson(response.data!);
  }

  Future<void> removeAllowedUser(String itineraryId, String userId) async {
    await _dio.delete(itineraryAllowedUserEndpoint(itineraryId, userId));
  }

  // ---------------------------------------------------------------------------
  // Editors — who, besides the owner, may modify this itinerary
  // ---------------------------------------------------------------------------

  Future<List<ItineraryEditor>> getEditors(String itineraryId) async {
    final response = await _dio.get<List<dynamic>>(
      itineraryEditorsEndpoint(itineraryId),
    );
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(ItineraryEditor.fromJson)
        .toList();
  }

  /// Grant edit rights.
  ///
  /// Throws [EditorCannotViewException] when the target cannot see the
  /// itinerary. The caller asks the owner whether to widen view access too and,
  /// if they agree, calls again with [grantView] — the server never widens
  /// visibility on its own.
  Future<ItineraryEditor> addEditor(
    String itineraryId,
    String userId, {
    bool grantView = false,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        itineraryEditorsEndpoint(itineraryId),
        data: {'user_id': userId, 'grant_view': grantView},
      );
      return ItineraryEditor.fromJson(response.data!);
    } on DioException catch (e) {
      final body = e.response?.data;
      final code = body is Map ? body['code'] as String? : null;
      if (e.response?.statusCode == 409 && code == 'editor_cannot_view') {
        throw EditorCannotViewException(
          visibility: body is Map ? body['visibility'] as String? : null,
          canFixWithAllowlist:
              body is Map && body['can_fix_with_allowlist'] == true,
        );
      }
      rethrow;
    }
  }

  Future<void> removeEditor(String itineraryId, String userId) async {
    await _dio.delete(itineraryEditorEndpoint(itineraryId, userId));
  }

  // ---------------------------------------------------------------------------
  // Edit lock
  //
  // The claim token exists only in memory, for the life of one editing session.
  // It is not a credential worth persisting: it is rotated away by any takeover
  // and is useless afterwards.
  // ---------------------------------------------------------------------------

  /// Claim the lock. Throws [ItineraryLockedException] (423) when somebody
  /// else's claim is in the way — pass [takeover] to displace it, which the
  /// server allows only for a takeable claim, your own other device, or the
  /// owner.
  Future<EditLockClaim> acquireLock(
    String itineraryId, {
    bool takeover = false,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        itineraryLockEndpoint(itineraryId),
        data: {'takeover': takeover},
      );
      return EditLockClaim.fromJson(response.data!);
    } on DioException catch (e) {
      _mapGuardError(e);
    }
  }

  Future<EditLock> heartbeatLock(String itineraryId, String lockToken) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        itineraryLockHeartbeatEndpoint(itineraryId),
        options: Options(headers: {kEditLockHeader: lockToken}),
      );
      return EditLock.fromJson(response.data!);
    } on DioException catch (e) {
      _mapGuardError(e);
    }
  }

  /// Give up the claim. Idempotent server-side and never 404s — it is called
  /// from teardown, where an error for something already finished is noise.
  Future<void> releaseLock(String itineraryId, String? lockToken) async {
    await _dio.delete(
      itineraryLockEndpoint(itineraryId),
      options: lockToken == null
          ? null
          : Options(headers: {kEditLockHeader: lockToken}),
    );
  }

  Future<EditLockStatus> getLockStatus(String itineraryId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      itineraryLockEndpoint(itineraryId),
      // Always the live answer: a cached claim is a claim that has already
      // decayed, and the whole point of this call is the countdown.
      options: forceRefreshOptions(),
    );
    return EditLockStatus.fromJson(response.data!);
  }

  // ---------------------------------------------------------------------------
  // Transit segments
  // ---------------------------------------------------------------------------

  Future<TripEditAnswer> createSegment(
    String itineraryId,
    Map<String, dynamic> data, {
    required String etag,
    required String? lockToken,
  }) =>
      _tripEdit(
        () => _dio.post<Map<String, dynamic>>(
          itinerarySegmentsEndpoint(itineraryId),
          data: data,
          queryParameters: _returnTrip,
          options: _editOptions(etag, lockToken),
        ),
      );

  Future<TripEditAnswer> updateSegment(
    String itineraryId,
    String segmentId,
    Map<String, dynamic> data, {
    required String etag,
    required String? lockToken,
  }) =>
      _tripEdit(
        () => _dio.patch<Map<String, dynamic>>(
          itinerarySegmentEndpoint(itineraryId, segmentId),
          data: data,
          queryParameters: _returnTrip,
          options: _editOptions(etag, lockToken),
        ),
      );

  Future<TripEditAnswer> deleteSegment(
    String itineraryId,
    String segmentId, {
    required String etag,
    required String? lockToken,
  }) =>
      _tripEdit(
        () => _dio.delete<Map<String, dynamic>>(
          itinerarySegmentEndpoint(itineraryId, segmentId),
          queryParameters: _returnTrip,
          options: _editOptions(etag, lockToken),
        ),
      );

  // ---------------------------------------------------------------------------
  // Ratings
  // ---------------------------------------------------------------------------

  /// The answer carries the trip's new aggregate beside the rating, so the trip
  /// page takes it from there instead of reloading the trip — and, with
  /// [withRatingsPage], the ratings page as it now stands, for a caller that
  /// has it open.
  Future<({MyRating rating, RatingAggregate aggregate, RatingsPage? page})>
      submitRating(
    String itineraryId,
    MyRating rating, {
    bool withRatingsPage = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      itineraryRatingsEndpoint(itineraryId),
      data: rating.toJson(),
      queryParameters: withRatingsPage ? _returnRatingsPage : null,
    );
    final data = response.data!;
    final page = data['ratings_page'];
    return (
      rating: MyRating.fromJson(data),
      aggregate: RatingAggregate.fromJson(data),
      page: page is Map<String, dynamic>
          ? await _ratingsPageAnswer(response, itineraryId, page)
          : null,
    );
  }

  /// The delete answers with the trip's aggregate once the rating is gone —
  /// or, with [withRatingsPage], with the whole ratings page left, which
  /// carries the aggregate too.
  Future<({RatingAggregate aggregate, RatingsPage? page})> deleteMyRating(
    String itineraryId, {
    bool withRatingsPage = false,
  }) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      itineraryMyRatingEndpoint(itineraryId),
      queryParameters:
          withRatingsPage ? _returnRatingsPage : const {'return': 'aggregate'},
    );
    final data = response.data!;
    return (
      aggregate: RatingAggregate.fromJson(data),
      page: withRatingsPage
          ? await _ratingsPageAnswer(response, itineraryId, data)
          : null,
    );
  }

  static const _returnRatingsPage = {'return': 'ratings_page'};

  /// A rating write's answered page, which also becomes the cached answer to
  /// the page's GET — the copy it shows offline, which a reload used to renew.
  Future<RatingsPage> _ratingsPageAnswer(
    Response<Map<String, dynamic>> response,
    String itineraryId,
    Map<String, dynamic> page,
  ) async {
    await cacheAsGet(
        response.requestOptions, itineraryRatingsEndpoint(itineraryId), page);
    return RatingsPage.fromJson(page);
  }

  Future<RatingsPage> getRatingsPage(
    String itineraryId, {
    bool forceRefresh = false,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      itineraryRatingsEndpoint(itineraryId),
      options: forceRefresh ? forceRefreshOptions() : null,
    );
    return RatingsPage.fromJson(response.data!);
  }

  Future<MyRating?> getMyRating(String itineraryId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        itineraryMyRatingEndpoint(itineraryId),
      );
      return MyRating.fromJson(response.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}

final itineraryRepositoryProvider = Provider<ItineraryRepository>((ref) {
  return ItineraryRepository(dio);
});
