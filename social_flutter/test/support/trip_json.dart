// test/support/trip_json.dart — a trip as the API sends it, for tests that
// play the server.
//
// One builder per shape, so a field the API adds is added here once rather
// than in every test that mocks a trip.

const kTripId = 'itin-1';

/// The trip's stamp when a test loads it, and after a save that moved it.
const kLoadedAt = '2026-10-21T10:00:00.000000Z';
const kSavedAt = '2026-10-21T10:00:05.123456Z';

/// A stop as the trip's detail nests it.
Map<String, dynamic> stopJson(
  String id, {
  String trackId = 't1',
  String placeName = 'Harbour',
  bool isFree = true,
  String? notes,
  String createdAt = '2026-10-21T09:00:00.000000Z',
}) =>
    {
      'id': id,
      'itinerary_id': kTripId,
      'track_id': trackId,
      'rank': 'a0',
      'place_name': placeName,
      'place_address': null,
      'lat': null,
      'lng': null,
      'map_url': null,
      'place_type': null,
      'duration_min': null,
      'cost': 0.0,
      'is_free': isFree,
      'notes': notes,
      'created_at': createdAt,
      'annotations': <Map<String, dynamic>>[],
    };

/// A transit segment from [fromStopId] to [toStopId], by one walking leg.
Map<String, dynamic> segmentJson(String id, String fromStopId, String toStopId) =>
    {
      'id': id,
      'itinerary_id': kTripId,
      'from_stop_id': fromStopId,
      'to_stop_id': toStopId,
      'total_duration_min': 10,
      'total_cost': 0.0,
      'created_at': '2026-10-21T09:00:00.000000Z',
      'legs': [
        {
          'id': '$id-leg',
          'segment_id': id,
          'position': 1,
          'mode': 'walk',
          'line': null,
          'direction': null,
          'duration_min': 10,
          'cost': 0.0,
          'is_free': true,
          'notes': null,
          'note_type': null,
          'created_at': '2026-10-21T09:00:00.000000Z',
          'source_lang': null,
        },
      ],
    };

/// A track holding [stops].
Map<String, dynamic> trackJson(
  String id,
  List<Map<String, dynamic>> stops, {
  String rank = 'a0',
}) =>
    {'id': id, 'itinerary_id': kTripId, 'rank': rank, 'stops': stops};

/// An ItinerarySummary: a row of the Mine list.
Map<String, dynamic> summaryJson({
  String id = kTripId,
  String title = 'Coast walk',
  String? coverUrl,
  String updatedAt = kLoadedAt,
  int totalDurationMin = 0,
  double totalCost = 0.0,
  double? ratingAvg,
  int ratingCount = 0,
  int stopsCount = 0,
}) =>
    {
      'id': id,
      'user_id': 'user-1',
      'title': title,
      'cover_image_url': coverUrl,
      'total_duration_min': totalDurationMin,
      'total_cost': totalCost,
      'currency': 'EUR',
      'visibility': 'public',
      'created_at': '2026-10-21T09:00:00.000000Z',
      'updated_at': updatedAt,
      'rating_avg': ratingAvg,
      'rating_count': ratingCount,
      'stops_count': stopsCount,
    };

/// A row of Shared with me: the summary and whose trip it is.
Map<String, dynamic> sharedRowJson(Map<String, dynamic> summary) => {
      ...summary,
      'owner': {
        'user_id': 'owner-1',
        'username': 'tripowner',
        'display_name': 'Trip Owner',
        'avatar_url': null,
      },
      'source_lang': null,
      'title_translation': null,
    };

/// The trip as GET /itineraries/{id} shows it. `stops_count` follows [tracks].
Map<String, dynamic> tripJson({
  String id = kTripId,
  String title = 'Coast walk',
  String? coverUrl,
  String updatedAt = kLoadedAt,
  String? description,
  int totalDurationMin = 0,
  double totalCost = 0.0,
  double? ratingAvg,
  int ratingCount = 0,
  List<Map<String, dynamic>> tracks = const [],
  List<Map<String, dynamic>> segments = const [],
  bool canEdit = true,
}) =>
    {
      ...summaryJson(
        id: id,
        title: title,
        coverUrl: coverUrl,
        updatedAt: updatedAt,
        totalDurationMin: totalDurationMin,
        totalCost: totalCost,
        ratingAvg: ratingAvg,
        ratingCount: ratingCount,
        stopsCount: tracks.fold<int>(0, (n, t) => n + (t['stops'] as List).length),
      ),
      'description': description,
      'tracks': tracks,
      'segments': segments,
      'annotations': <Map<String, dynamic>>[],
      'can_edit': canEdit,
    };

/// What a trip edit or a create answers when asked for the trip back.
Map<String, dynamic> tripAnswer(
  Map<String, dynamic>? trip, {
  String? createdId,
}) =>
    {'itinerary': trip, 'created_id': createdId};
