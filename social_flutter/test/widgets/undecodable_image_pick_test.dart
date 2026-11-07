// A picked picture that cannot be used is reported where it was picked —
// never left loading, never silently dropped.
//
// Regressions (2026-11-07):
// - On the web the picker hands over the file as it is, so a HEIC photo
//   reached the crop editor, whose decode threw with nobody listening — its
//   loader spun forever with Done disabled. The profile photo's picker
//   swallowed every failure, so there the tap just looked ignored.
// - Once reported, it still loaded first — the NSFW model, then the editor's
//   own loader — before a generic "Could not load image". A format the app
//   cannot open is now named at the pick, and the editor never opens.
//
// The gallery is mocked on the image_picker method channel. A HEIC header
// stands in for a format the app refuses; a JPEG header on a broken body for a
// damaged file, which only the editor's decode can find out.
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

// heif-enc's HEIC header (major heic, compatible mif1 heic miaf), then junk.
final _heic = Uint8List.fromList([
  0, 0, 0, 0x1C, ...'ftyp'.codeUnits, ...'heic'.codeUnits, 0, 0, 0, 0,
  ...'mif1'.codeUnits, ...'heic'.codeUnits, ...'miaf'.codeUnits,
  ...List.filled(64, 7),
]);
final _unrecognised = Uint8List.fromList(List.filled(64, 7));
// A JPEG's first bytes on a body no decoder can read.
final _brokenJpeg =
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(64, 7)]);

/// Makes the gallery answer every pick with [bytes], in a file named [name].
void _galleryAnswers(WidgetTester tester, String name, Uint8List bytes) {
  final dir = Directory.systemTemp.createTempSync('image_pick');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/$name')..writeAsBytesSync(bytes);
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      _picker, (call) async => call.method == 'pickImage' ? file.path : null);
  addTearDown(() => messenger.setMockMethodCallHandler(_picker, null));
}

bool _shown(String text) => find.text(text).evaluate().isNotEmpty;

/// A pick reads a real file and decodes for real: each step only advances on
/// the real event loop, and its continuation only lands when the fake clock is
/// pumped. The fake clock also runs out the pre-check's time budget, whatever
/// the model does in a test. Answers whether the crop editor was on screen at
/// any point on the way.
Future<bool> _settle(WidgetTester tester, bool Function() done) async {
  var editorShown = false;
  for (var i = 0; i < 60 && !done(); i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 200));
    editorShown |= _shown(_l10n.coverAdjustTitle);
  }
  return editorShown;
}

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

Widget _profileForm() => ProfileEditForm(
      user: User.fromJson(const {
        'id': 'user-1',
        'username': 'webcheck',
        'created_at': '2026-11-07T00:00:00.000Z',
      }),
      onCancel: () {},
      onSaved: () {},
      onDeleteAccount: () {},
    );

void main() {
  group('the cover field', () {
    Future<Uint8List?> pickInCoverField(
        WidgetTester tester, String expected) async {
      Uint8List? selected;
      await tester.pumpWidget(_app(CoverImageField(
        onImageSelected: (bytes, _) => selected = bytes,
        onImageRemoved: () {},
      )));
      await tester.tap(find.text(_l10n.addCoverImage));
      final editorShown = await _settle(tester, () => _shown(expected));
      if (expected != _l10n.couldNotLoadImage) {
        expect(editorShown, isFalse,
            reason: 'refused at the pick: the crop editor must not open');
      }
      return selected;
    }

    testWidgets('names a format the app cannot open, at the pick',
        (tester) async {
      _galleryAnswers(tester, 'IMG_0001.HEIC', _heic);
      final message = _l10n.imageFormatUnsupported('HEIC');
      final selected = await pickInCoverField(tester, message);

      expect(find.text(message), findsOneWidget);
      expect(find.byType(NTripiRingLoader), findsNothing,
          reason: 'nothing may keep loading');
      expect(selected, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('says so when the bytes are no picture it knows',
        (tester) async {
      // Named .jpg on purpose: the bytes decide, never the name.
      _galleryAnswers(tester, 'photo.jpg', _unrecognised);
      final selected =
          await pickInCoverField(tester, _l10n.imageFormatUnknown);

      expect(find.text(_l10n.imageFormatUnknown), findsOneWidget);
      expect(find.byType(NTripiRingLoader), findsNothing);
      expect(selected, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a damaged file reaches the editor, which says it cannot',
        (tester) async {
      _galleryAnswers(tester, 'photo.jpg', _brokenJpeg);
      final selected =
          await pickInCoverField(tester, _l10n.couldNotLoadImage);

      expect(find.text(_l10n.couldNotLoadImage), findsOneWidget);
      expect(find.text(_l10n.coverAdjustTitle), findsNothing,
          reason: 'the crop editor must not stay open on its loader');
      expect(find.byType(NTripiRingLoader), findsNothing,
          reason: 'nothing may keep loading');
      expect(selected, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('the profile photo', () {
    testWidgets('names a format the app cannot open, at the pick',
        (tester) async {
      _galleryAnswers(tester, 'IMG_0001.HEIC', _heic);
      await tester.pumpWidget(_app(_profileForm()));

      await tester.tap(find.text(_l10n.uploadPhoto));
      final message = _l10n.imageFormatUnsupported('HEIC');
      final editorShown = await _settle(tester, () => _shown(message));

      expect(find.text(message), findsOneWidget,
          reason: 'a refused pick used to look like an ignored tap');
      expect(editorShown, isFalse,
          reason: 'refused at the pick: the crop editor must not open');
      expect(tester.takeException(), isNull);
    });

    testWidgets('says a damaged file cannot be loaded', (tester) async {
      _galleryAnswers(tester, 'photo.jpg', _brokenJpeg);
      await tester.pumpWidget(_app(_profileForm()));

      await tester.tap(find.text(_l10n.uploadPhoto));
      await _settle(tester, () => _shown(_l10n.couldNotLoadImage));

      expect(find.text(_l10n.couldNotLoadImage), findsOneWidget);
      expect(find.text(_l10n.coverAdjustTitle), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
