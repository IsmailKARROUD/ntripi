// test/core/ui/orientation_policy_test.dart — phones stay portrait, a tablet
// turns: the line is a shortest side of 600, Android's sw600dp.
//
// The policy re-reads the size on every metrics change (a foldable opened up
// is a tablet), but asks the OS only when its answer changes: metrics change
// on every frame of a keyboard animation.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/ui/orientation_policy.dart';

const _portrait = ['DeviceOrientation.portraitUp', 'DeviceOrientation.portraitDown'];

void main() {
  test('Given a shortest side under 600, Then only portrait; from 600, Then any',
      () {
    expect(allowedOrientations(390),
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    expect(allowedOrientations(599.9),
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    expect(allowedOrientations(600), isEmpty);
    expect(allowedOrientations(1024), isEmpty);
  });

  testWidgets(
      'Given a phone, Then it is locked to portrait; When it opens up into a '
      'tablet, Then it may turn — and a keyboard asks the OS nothing',
      (tester) async {
    final asked = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          asked.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final policy = (await OrientationPolicy.start())!;
    addTearDown(policy.stop);
    expect(asked, [_portrait]);

    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pump();
    expect(asked, [_portrait]);

    // A foldable's inner screen: 1840 × 2208 at 2.625 is 701 × 841. The ratio
    // goes first: each setter is a metrics change of its own here, where a
    // device reports both at once.
    tester.view.devicePixelRatio = 2.625;
    tester.view.physicalSize = const Size(1840, 2208);
    await tester.pump();
    expect(asked, [_portrait, <String>[]]);
  });

  testWidgets(
      'Given no size yet, Then nothing is asked — a guess would flip a tablet '
      'held sideways to portrait and back', (tester) async {
    final asked = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          asked.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = Size.zero;
    addTearDown(tester.view.reset);

    final policy = (await OrientationPolicy.start())!;
    addTearDown(policy.stop);
    expect(asked, isEmpty);

    // An iPad held sideways: 1024 × 768.
    tester.view.physicalSize = const Size(2048, 1536);
    await tester.pump();
    expect(asked, [<String>[]]);
  });
}
