// test/core/connectivity/network_changes_test.dart — a move to another
// network is reported; the state the device was already in is not.
//
// isOnlineProvider cannot see Wi-Fi giving way to mobile data, since both are
// online, and main.dart retires the API's pooled connections on exactly that
// move. The plugin replays the current state to every new listener, which must
// not count as one: it would retire a warm connection at every launch.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/connectivity/connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const check = MethodChannel('dev.fluttercommunity.plus/connectivity');
  const status = EventChannel('dev.fluttercommunity.plus/connectivity_status');

  test('Wi-Fi to mobile data and back is two moves; the replay is none',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(check, (_) async => ['wifi']);
    messenger.setMockStreamHandler(
      status,
      MockStreamHandler.inline(onListen: (_, events) {
        events.success(['wifi']); // the replay every new listener gets
        events.success(['mobile']);
        events.success(['mobile']);
        events.success(['wifi']);
      }),
    );
    addTearDown(() => messenger.setMockMethodCallHandler(check, null));

    var moves = 0;
    final subscription = networkChanges().listen((_) => moves++);
    addTearDown(subscription.cancel);
    await pumpEventQueue(times: 50);

    expect(moves, 2);
  });
}
