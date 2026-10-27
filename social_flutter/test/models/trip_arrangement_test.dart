// test/models/trip_arrangement_test.dart — every move arrange mode can make,
// as plain function calls on the immutable arrangement.

import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/features/itineraries/domain/stop.dart';
import 'package:ntripi/features/itineraries/domain/track.dart';
import 'package:ntripi/features/itineraries/domain/trip_arrangement.dart';

Stop _stop(String id, String trackId) => Stop(
      id: id,
      itineraryId: 'itin-1',
      trackId: trackId,
      rank: 'a0',
      placeName: id,
      type: StopType.waypoint,
      createdAt: DateTime.utc(2026, 1, 1),
    );

Track _track(String id, List<String> stopIds) => Track(
      id: id,
      itineraryId: 'itin-1',
      rank: id,
      stops: [for (final s in stopIds) _stop(s, id)],
    );

/// tracks A(a1, a2), B(b), C(c).
TripArrangement _trip() => TripArrangement.of([
      _track('A', ['a1', 'a2']),
      _track('B', ['b']),
      _track('C', ['c']),
    ]);

/// `[[trackId or '+', stopIds…], …]` — the arrangement in one comparable value.
List<List<String>> _shape(TripArrangement t) => [
      for (final r in t.rows) [r.trackId ?? '+', ...r.stops.map((s) => s.id)],
    ];

void main() {
  test('starts as the trip is, with nothing to save', () {
    final t = _trip();
    expect(_shape(t), [
      ['A', 'a1', 'a2'],
      ['B', 'b'],
      ['C', 'c'],
    ]);
    expect(t.isDirty, isFalse);
  });

  group('moveTrack', () {
    test('to the front and to the end', () {
      expect(_shape(_trip().moveTrack('C', 0)).map((r) => r.first), ['C', 'A', 'B']);
      expect(_shape(_trip().moveTrack('A', 3)).map((r) => r.first), ['B', 'C', 'A']);
    });

    test('the gaps on either side of a track change nothing', () {
      final t = _trip();
      expect(t.isTrackNoOpGap('B', 1), isTrue);
      expect(t.isTrackNoOpGap('B', 2), isTrue);
      expect(t.isTrackNoOpGap('B', 0), isFalse);
      expect(t.moveTrack('B', 2).isDirty, isFalse);
    });
  });

  group('moveStopToGap', () {
    test('an alternative gets a new track where it was put', () {
      final t = _trip().moveStopToGap('a2', 2);
      expect(_shape(t), [
        ['A', 'a1'],
        ['B', 'b'],
        ['+', 'a2'],
        ['C', 'c'],
      ]);
      expect(t.isDirty, isTrue);
      expect(t.toLayoutJson()[2], {
        'track_id': null,
        'stop_ids': ['a2'],
      });
    });

    test('a stop alone in its track moves the track, creating none', () {
      final t = _trip().moveStopToGap('c', 0);
      expect(_shape(t), [
        ['C', 'c'],
        ['A', 'a1', 'a2'],
        ['B', 'b'],
      ]);
      expect(_trip().isStopNoOpGap('c', 2), isTrue);
      expect(_trip().isStopNoOpGap('a2', 1), isFalse);
    });

    test('new tracks keep distinct keys after one takes in other stops', () {
      // a2 out on its own, b joins it, then a2 leaves it for a new track again.
      var t = _trip().moveStopToGap('a2', 1);
      final first = t.rows[1].key;
      t = t.moveStopToRow('b', first);
      t = t.moveStopToGap('a2', 0);
      final keys = t.rows.map((r) => r.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
      expect(_shape(t), [
        ['+', 'a2'],
        ['A', 'a1'],
        ['+', 'b'],
        ['C', 'c'],
      ]);
    });
  });

  group('moveStopToRow', () {
    test('joins another track at its end, and the emptied track goes', () {
      final t = _trip().moveStopToRow('c', 'B');
      expect(_shape(t), [
        ['A', 'a1', 'a2'],
        ['B', 'b', 'c'],
      ]);
      expect(t.toLayoutJson(), [
        {'track_id': 'A', 'stop_ids': ['a1', 'a2']},
        {'track_id': 'B', 'stop_ids': ['b', 'c']},
      ]);
    });

    test('lands before the stop it was dropped on', () {
      final t = _trip().moveStopToRow('c', 'A', beforeStopId: 'a1');
      expect(_shape(t).first, ['A', 'c', 'a1', 'a2']);
    });

    test('in its own track it reorders the alternatives', () {
      final t = _trip().moveStopToRow('a2', 'A', beforeStopId: 'a1');
      expect(_shape(t).first, ['A', 'a2', 'a1']);
      expect(t.isDirty, isTrue);
      // Back where it was: nothing to save again.
      expect(t.moveStopToRow('a1', 'A', beforeStopId: 'a2').isDirty, isFalse);
    });

    test('a full track refuses another stop but still reorders its own', () {
      final full = TripArrangement.of([
        _track('A', ['a1', 'a2', 'a3', 'a4']),
        _track('B', ['b']),
      ]);
      expect(Track.maxParallelStops, 4);
      expect(full.accepts('A', 'b'), isFalse);
      expect(_shape(full.moveStopToRow('b', 'A')), _shape(full));
      expect(full.accepts('A', 'a4'), isTrue);
      expect(
        _shape(full.moveStopToRow('a4', 'A', beforeStopId: 'a1')).first,
        ['A', 'a4', 'a1', 'a2', 'a3'],
      );
    });

    test('dropped on itself it changes nothing', () {
      expect(_trip().moveStopToRow('a1', 'A', beforeStopId: 'a1').isDirty, isFalse);
    });
  });

  test('tracks stand in for the layout, new rows under their local key', () {
    final t = _trip().moveStopToGap('a2', 3);
    expect(t.tracks.map((tr) => tr.id), ['A', 'B', 'C', t.rows.last.key]);
    expect(t.tracks.last.stops.single.id, 'a2');
  });

  test('there is something to arrange with two tracks or two alternatives', () {
    expect(TripArrangement.hasAnythingToArrange([_track('A', ['a'])]), isFalse);
    expect(TripArrangement.hasAnythingToArrange([_track('A', ['a', 'b'])]), isTrue);
    expect(
      TripArrangement.hasAnythingToArrange([_track('A', ['a']), _track('B', ['b'])]),
      isTrue,
    );
  });
}
