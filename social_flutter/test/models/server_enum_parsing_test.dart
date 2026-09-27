// test/models/server_enum_parsing_test.dart
//
// A value this build has never heard of must degrade, not throw: fromJson runs
// inside the itinerary-detail parse, so one unknown string would blank the whole
// screen for every deployed client the day a newer backend ships it.

import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/itineraries/domain/annotation.dart';
import 'package:social_flutter/features/itineraries/domain/transport_leg.dart';

void main() {
  group('AnnotationType.fromString', () {
    test('parses every known value', () {
      for (final type in AnnotationType.values) {
        expect(AnnotationType.fromString(type.name), type);
      }
    });

    test('an unknown or missing value degrades to info', () {
      expect(AnnotationType.fromString('warning'), AnnotationType.info);
      expect(AnnotationType.fromString(null), AnnotationType.info);
    });
  });

  group('TransportMode.fromString', () {
    test('parses every known value', () {
      for (final mode in TransportMode.values) {
        expect(TransportMode.fromString(mode.name), mode);
      }
    });

    test('an unknown value degrades to the generic vehicle', () {
      expect(TransportMode.fromString('hoverboard'), TransportMode.car);
    });
  });

  test('a leg with an unknown mode and note type still parses', () {
    final leg = TransportLeg.fromJson({
      'id': 'l1',
      'segment_id': 's1',
      'position': 0,
      'mode': 'hoverboard',
      'note_type': 'warning',
      'created_at': '2026-01-01T00:00:00Z',
    });
    expect(leg.mode, TransportMode.car);
    expect(leg.noteType, AnnotationType.info);
  });

  test('an annotation with an unknown type still parses', () {
    final annotation = Annotation.fromJson({
      'id': 'a1',
      'stop_id': 's1',
      'type': 'warning',
      'content': 'Mind the gap',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    });
    expect(annotation.type, AnnotationType.info);
  });
}
