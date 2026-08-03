// Guards the fragment-rollup contract: stops and annotations are wire-reported
// as their PARENT itinerary, and the only trace of which fragment was reported
// is the prefix on the notes a moderator reads in /admin/reports.

import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/reports/domain/report_target.dart';

void main() {
  const itineraryId = 'itin-1';
  const stopId = 'stop-2';
  const annotationId = 'anno-3';

  group('wireKind', () {
    test('every fragment variant reports as the parent itinerary', () {
      const targets = [
        ReportTarget.itinerary(itineraryId),
        ReportTarget.stop(itineraryId, stopId),
        ReportTarget.stopAnnotation(itineraryId, stopId, annotationId),
        ReportTarget.itineraryAnnotation(itineraryId, annotationId),
      ];
      for (final target in targets) {
        expect(target.wireKind, 'itinerary');
        expect(target.id, itineraryId);
      }
    });

    test('rating and user keep their own target type', () {
      expect(const ReportTarget.rating('r-1').wireKind, 'rating');
      expect(const ReportTarget.user('u-1').wireKind, 'user');
    });
  });

  group('isStop / isAnnotation', () {
    test('a stop annotation is an annotation, not a stop', () {
      const target =
          ReportTarget.stopAnnotation(itineraryId, stopId, annotationId);
      expect(target.isAnnotation, isTrue);
      expect(target.isStop, isFalse);
    });

    test('a bare stop is a stop', () {
      const target = ReportTarget.stop(itineraryId, stopId);
      expect(target.isStop, isTrue);
      expect(target.isAnnotation, isFalse);
    });

    test('a whole itinerary is neither', () {
      const target = ReportTarget.itinerary(itineraryId);
      expect(target.isStop, isFalse);
      expect(target.isAnnotation, isFalse);
    });
  });

  group('notesWithContext', () {
    test('no fragment passes the notes through, trimmed', () {
      const target = ReportTarget.itinerary(itineraryId);
      expect(target.notesWithContext('  spammy  '), 'spammy');
    });

    test('no fragment and no notes sends nothing', () {
      const target = ReportTarget.itinerary(itineraryId);
      expect(target.notesWithContext(null), isNull);
      expect(target.notesWithContext('   '), isNull);
    });

    test('a stop prefixes its id', () {
      const target = ReportTarget.stop(itineraryId, stopId);
      expect(target.notesWithContext('bad place'), '[stop:$stopId] bad place');
    });

    test('a stop with no notes still sends the prefix', () {
      const target = ReportTarget.stop(itineraryId, stopId);
      expect(target.notesWithContext(null), '[stop:$stopId]');
      expect(target.notesWithContext('  '), '[stop:$stopId]');
    });

    test('a stop annotation names both ids', () {
      const target =
          ReportTarget.stopAnnotation(itineraryId, stopId, annotationId);
      expect(
        target.notesWithContext('slur in the note'),
        '[stop:$stopId annotation:$annotationId] slur in the note',
      );
    });

    test('an itinerary annotation names only the annotation', () {
      const target = ReportTarget.itineraryAnnotation(itineraryId, annotationId);
      expect(
        target.notesWithContext(null),
        '[annotation:$annotationId]',
      );
      expect(
        target.notesWithContext('hate speech'),
        '[annotation:$annotationId] hate speech',
      );
    });
  });
}
