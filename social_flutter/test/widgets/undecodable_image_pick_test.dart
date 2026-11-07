// A picked picture the crop editor cannot decode is reported where it was
// picked — never left loading, never silently dropped.
//
// Regression (2026-11-07): on the web the picker hands over the file as it is,
// so a HEIC photo reached the crop editor, whose decode threw with nobody
// listening — its loader spun forever with Done disabled. The profile photo's
// picker swallowed every failure, so there the tap just looked ignored.
//
// The gallery is mocked on the image_picker method channel; garbage bytes stand
// in for a format the platform cannot decode.
import 'dart:io';

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/features/itineraries/presentation/widgets/cover_image_field.dart';
import 'package:ntripi/features/profile/presentation/widgets/profile_edit_form.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/models/user.dart';
import 'package:ntripi/shared/widgets/loaders.dart';

const _picker = MethodChannel('plugins.flutter.io/image_picker');
final _l10n = lookupAppLocalizations(const Locale('en'));

/// Makes the gallery answer every pick with a file the platform cannot decode.
void _galleryAnswersUndecodable(WidgetTester tester) {
  final dir = Directory.systemTemp.createTempSync('undecodable_pick');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/photo.heic')
    ..writeAsBytesSync(Uint8List.fromList(List.filled(64, 7)));
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      _picker, (call) async => call.method == 'pickImage' ? file.path : null);
  addTearDown(() => messenger.setMockMethodCallHandler(_picker, null));
}

/// A pick reads a real file and decodes for real: each step only advances on
/// the real event loop, and its continuation only lands when the fake clock is
/// pumped. The fake clock also runs out the pre-check's time budget, whatever
/// the model does in a test.
Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 60 && !done(); i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 200));
  }
}

bool _shown(String text) => find.text(text).evaluate().isNotEmpty;

// The default theme, as the form tests use: the app's own fetches DM Sans
// through google_fonts, and _settle's real time would let that fetch fail.
Widget _app(Widget body) => ProviderScope(
      child: BetterFeedback(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: body),
        ),
      ),
    );

void main() {
  testWidgets('the cover field says the picture cannot be loaded',
      (tester) async {
    _galleryAnswersUndecodable(tester);
    Uint8List? selected;
    await tester.pumpWidget(_app(CoverImageField(
      onImageSelected: (bytes, _) => selected = bytes,
      onImageRemoved: () {},
    )));

    await tester.tap(find.text(_l10n.addCoverImage));
    await _settle(tester, () => _shown(_l10n.couldNotLoadImage));

    expect(find.text(_l10n.couldNotLoadImage), findsOneWidget);
    expect(find.text(_l10n.coverAdjustTitle), findsNothing,
        reason: 'the crop editor must not stay open on its loader');
    expect(find.byType(NTripiRingLoader), findsNothing,
        reason: 'nothing may keep loading');
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the profile photo says the picture cannot be loaded',
      (tester) async {
    _galleryAnswersUndecodable(tester);
    await tester.pumpWidget(_app(ProfileEditForm(
      user: User.fromJson(const {
        'id': 'user-1',
        'username': 'webcheck',
        'created_at': '2026-11-07T00:00:00.000Z',
      }),
      onCancel: () {},
      onSaved: () {},
      onDeleteAccount: () {},
    )));

    await tester.tap(find.text(_l10n.uploadPhoto));
    await _settle(tester, () => _shown(_l10n.couldNotLoadImage));

    expect(find.text(_l10n.couldNotLoadImage), findsOneWidget,
        reason: 'a failed pick used to look like an ignored tap');
    expect(find.text(_l10n.coverAdjustTitle), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
