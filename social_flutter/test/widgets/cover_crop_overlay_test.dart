// The crop editor must go into the app's own navigator overlay.
//
// Regression: it used to insert an `opaque: true` entry into
// Overlay.of(context, rootOverlay: true) — which, since BetterFeedback wraps
// MaterialApp, is the feedback package's Overlay. Its single entry (the whole
// app) has maintainState:false, so an opaque entry above it unmounted the
// entire app; "Done" then threw on a disposed route before it could remove the
// overlay, leaving the crop screen stuck on screen.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/cover_image_field.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

Future<Uint8List> _pngBytes(WidgetTester tester) async {
  late Uint8List bytes;
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 40, 40), Paint()..color = Colors.red);
    final image = await recorder.endRecording().toImage(40, 40);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    bytes = data!.buffer.asUint8List();
  });
  return bytes;
}

void main() {
  testWidgets('crop overlay leaves the app mounted and Done closes it',
      (tester) async {
    final bytes = await _pngBytes(tester);

    late BuildContext ctx;
    await tester.pumpWidget(
      // Mirrors main.dart: BetterFeedback above MaterialApp.
      BetterFeedback(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(builder: (c) {
              ctx = c;
              return const Text('form');
            }),
          ),
        ),
      ),
    );

    Uint8List? result;
    var settled = false;
    openImageCropOverlay(ctx,
            sourceBytes: bytes, targetWidth: 1200, targetHeight: 630)
        .then((value) {
      result = value;
      settled = true;
    });
    await tester.pump();

    expect(find.text('Adjust cover photo'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget,
        reason: 'the app must stay mounted under the crop overlay');
    expect(find.text('form'), findsOneWidget,
        reason: 'the route below must stay mounted under the crop overlay');

    // Let the source image decode so Done is enabled.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    await tester.tap(find.text('Done'));
    // _done() awaits real async work (decode → rasterise → toByteData): each
    // step only advances when the real event loop runs, and its continuation
    // only lands when the fake-async zone is pumped. Alternate the two.
    for (var i = 0; i < 20 && !settled; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(find.text('Adjust cover photo'), findsNothing,
        reason: 'Done must close the crop screen');
    expect(result, isNotNull, reason: 'Done must return the cropped bytes');
    expect(find.text('form'), findsOneWidget);
  });
}
