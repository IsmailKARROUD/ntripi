// providers/order_by_distance_provider.dart — Order by distance's solver, read
// through a provider so a test can count its calls: nothing may be worked out
// before the button is tapped.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ntripi/features/itineraries/domain/order_by_distance.dart';
import 'package:ntripi/features/itineraries/domain/transit_segment.dart';
import 'package:ntripi/features/itineraries/domain/trip_arrangement.dart';

typedef OrderByDistanceSolver = Future<DistanceOrderChoices?> Function(
  TripArrangement arrangement,
  List<TransitSegment> segments, {
  bool Function()? isCancelled,
});

final orderByDistanceSolverProvider =
    Provider<OrderByDistanceSolver>((ref) => orderByDistanceChoices);
