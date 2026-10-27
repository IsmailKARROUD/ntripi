// features/itineraries/domain/trip_arrangement.dart — The trip as arrange mode
// is reshaping it, before anything is saved.
//
// Arrange mode is the one place a trip's structure changes: the order of its
// tracks, the order of the alternatives inside a track, and which track a stop
// belongs to (another track's alternative, or a track of its own). Every move
// is local; Save sends the result as one POST /reorder `layout`, so the server
// applies it all or nothing.
//
// Immutable: every move returns a new arrangement, and the original snapshot
// travels with it, which is what `isDirty` compares against.

import 'package:ntripi/features/itineraries/domain/stop.dart';
import 'package:ntripi/features/itineraries/domain/track.dart';

/// One row of an arrangement: an existing track, or one the save will create.
class ArrangedTrack {
  const ArrangedTrack({required this.key, this.trackId, required this.stops});

  /// Stable within the arrangement: the track's id, or `new:<n>` for a track
  /// the save will create.
  final String key;

  /// Null for a track the save will create.
  final String? trackId;

  /// Never empty: a track exists only while it holds a stop.
  final List<Stop> stops;

  ArrangedTrack withStops(List<Stop> stops) =>
      ArrangedTrack(key: key, trackId: trackId, stops: stops);
}

class TripArrangement {
  const TripArrangement._(this.rows, this._original, this._created);

  factory TripArrangement.of(List<Track> tracks) {
    final rows = [
      for (final t in tracks)
        if (t.stops.isNotEmpty)
          ArrangedTrack(key: t.id, trackId: t.id, stops: t.stops),
    ];
    return TripArrangement._(rows, _signature(rows), 0);
  }

  /// Whether arrange mode has anything to offer: tracks to put in another
  /// order, or alternatives to order or split out.
  static bool hasAnythingToArrange(List<Track> tracks) =>
      tracks.length >= 2 || tracks.any((t) => t.stops.length >= 2);

  final List<ArrangedTrack> rows;
  final String _original;

  /// How many tracks this arrangement has created — what keeps a new row's key
  /// unique even after an earlier new row took in other stops.
  final int _created;

  bool get isDirty => _signature(rows) != _original;

  static String _signature(List<ArrangedTrack> rows) => [
        for (final r in rows)
          '${r.trackId ?? '+'}:${r.stops.map((s) => s.id).join(',')}',
      ].join('|');

  /// Index of the row holding [stopId], or -1.
  int rowOf(String stopId) =>
      rows.indexWhere((r) => r.stops.any((s) => s.id == stopId));

  int _rowIndex(String key) => rows.indexWhere((r) => r.key == key);

  Stop? stop(String stopId) {
    for (final r in rows) {
      for (final s in r.stops) {
        if (s.id == stopId) return s;
      }
    }
    return null;
  }

  /// Whether the row [rowKey] can take [stopId]: its own row always can (that
  /// is a reorder); any other only below the parallel-stop cap.
  bool accepts(String rowKey, String stopId) {
    final target = _rowIndex(rowKey);
    if (target < 0) return false;
    if (target == rowOf(stopId)) return true;
    return rows[target].stops.length < Track.maxParallelStops;
  }

  /// Whether dropping the track [rowKey] into gap [gap] would change nothing:
  /// the gaps on either side of a track are where it already is.
  bool isTrackNoOpGap(String rowKey, int gap) {
    final from = _rowIndex(rowKey);
    return gap == from || gap == from + 1;
  }

  /// Whether dropping [stopId] into gap [gap] would change nothing — true only
  /// for a stop alone in its track, which moves the track instead.
  bool isStopNoOpGap(String stopId, int gap) {
    final from = rowOf(stopId);
    if (from < 0 || rows[from].stops.length > 1) return false;
    return gap == from || gap == from + 1;
  }

  /// Move the track [rowKey] into gap [gap] — gap `i` sits before row `i`,
  /// gap `rows.length` after the last row.
  TripArrangement moveTrack(String rowKey, int gap) {
    final from = _rowIndex(rowKey);
    if (from < 0 || gap < 0 || gap > rows.length) return this;
    final next = [...rows];
    final moved = next.removeAt(from);
    next.insert(gap > from ? gap - 1 : gap, moved);
    return TripArrangement._(next, _original, _created);
  }

  /// Put [stopId] in a track of its own at gap [gap]. A stop alone in its
  /// track takes the track with it, so no track is created for nothing.
  TripArrangement moveStopToGap(String stopId, int gap) {
    final from = rowOf(stopId);
    if (from < 0 || gap < 0 || gap > rows.length) return this;
    final source = rows[from];
    if (source.stops.length == 1) return moveTrack(source.key, gap);
    final stop = source.stops.firstWhere((s) => s.id == stopId);
    final next = [...rows];
    next[from] = source.withStops([
      for (final s in source.stops)
        if (s.id != stopId) s,
    ]);
    // The source row stays (it keeps its other stops), so the gaps keep their
    // indexes.
    next.insert(gap, ArrangedTrack(key: 'new:$_created', stops: [stop]));
    return TripArrangement._(next, _original, _created + 1);
  }

  /// Put [stopId] in the track [rowKey], before [beforeStopId] or at its end.
  /// In its own track this reorders the alternatives; in another it joins
  /// them, and a track it leaves empty goes. Refused (unchanged) past the cap.
  TripArrangement moveStopToRow(
    String stopId,
    String rowKey, {
    String? beforeStopId,
  }) {
    final from = rowOf(stopId);
    final to = _rowIndex(rowKey);
    if (from < 0 || to < 0 || stopId == beforeStopId) return this;
    if (!accepts(rowKey, stopId)) return this;
    final stop = rows[from].stops.firstWhere((s) => s.id == stopId);

    final next = [...rows];
    next[from] = rows[from].withStops([
      for (final s in rows[from].stops)
        if (s.id != stopId) s,
    ]);
    final target = next[to].stops;
    final at = beforeStopId == null
        ? target.length
        : target.indexWhere((s) => s.id == beforeStopId);
    next[to] = next[to].withStops([...target]
      ..insert(at < 0 ? target.length : at, stop));
    if (next[from].stops.isEmpty) next.removeAt(from);
    return TripArrangement._(next, _original, _created);
  }

  /// The arrangement as tracks, for the transit-segment adjacency check. A row
  /// the save will create stands in under its local key.
  List<Track> get tracks => [
        for (final r in rows)
          Track(
            id: r.key,
            itineraryId: r.stops.first.itineraryId,
            rank: '',
            stops: r.stops,
          ),
      ];

  /// The `layout` of `POST /itineraries/{id}/reorder`.
  List<Map<String, dynamic>> toLayoutJson() => [
        for (final r in rows)
          {
            'track_id': r.trackId,
            'stop_ids': [for (final s in r.stops) s.id],
          },
      ];
}
