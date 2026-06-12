// core/connectivity/connectivity_service.dart — Single source of truth for
// network reachability.
//
// Anything in the app that needs to know "are we online?" reads from
// [isOnlineProvider]. The provider listens to connectivity_plus's
// onConnectivityChanged stream and seeds the initial value from a one-shot
// check at construction. This keeps the connectivity_plus dependency
// contained to this file — every other consumer just watches a Riverpod
// stream.

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams `true` when the device has any connection, `false` when offline.
///
/// Emits the seed value (initial check) within ~1 frame of subscription so
/// consumers don't have to handle a null/loading state for the common case.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();

  // Seed from a one-shot check so the first emit isn't blocked on a change.
  final initial = await connectivity.checkConnectivity();
  yield !initial.contains(ConnectivityResult.none);

  await for (final results in connectivity.onConnectivityChanged) {
    yield !results.contains(ConnectivityResult.none);
  }
});

/// Synchronous accessor — `true` if we're online or if connectivity hasn't
/// emitted yet (optimistic default). Use this when you need a `bool` and
/// can't `await` (e.g. inside a Dio interceptor's onRequest).
bool isOnlineNow(WidgetRef ref) {
  return ref
      .read(isOnlineProvider)
      .maybeWhen(data: (online) => online, orElse: () => true);
}
