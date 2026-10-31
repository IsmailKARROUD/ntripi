// test/widgets/profile_tab_icon_test.dart — the Profile tab draws the user's
// photo, and the person icon it always had whenever there is no photo to draw.
//
// The bar sizes a tab by its icon, so the photo keeps to the icon's 24 px box
// in both states — a bigger box put the Profile label lower than the others.
// A photo cannot turn green like the other icons, so the open tab rings it in
// the bar's selected color. Every image comes from a provider the test holds:
// the real cache cannot run under test.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/shared/widgets/profile_tab_icon.dart';

const _barColor = Color(0xFF1F6E3A);

/// A photo ready at once — what the memory cache hands back.
class _ReadyImage extends ImageProvider<_ReadyImage> {
  _ReadyImage(this.image);

  final ui.Image image;

  @override
  Future<_ReadyImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_ReadyImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: image.clone())));
}

/// A photo still on its way.
class _PendingImage extends ImageProvider<_PendingImage> {
  @override
  Future<_PendingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          _PendingImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
}

/// A photo that will not come — offline, or gone from storage.
class _FailingImage extends ImageProvider<_FailingImage> {
  @override
  Future<_FailingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          _FailingImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          Future<ImageInfo>.error(StateError('offline')));
}

/// The icon as the bar holds it: inside the IconTheme the bar gives each tab.
Future<void> _pump(WidgetTester tester, ProfileTabIcon icon) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildNtripiTheme(),
    home: Scaffold(
      body: Center(
        child: IconTheme(
          data: const IconThemeData(size: 24, color: _barColor),
          child: icon,
        ),
      ),
    ),
  ));
  await tester.pump();
}

Future<ui.Image> _photo(WidgetTester tester) async =>
    (await tester.runAsync(() => createTestImage(width: 8, height: 8)))!;

BoxDecoration _ring(WidgetTester tester) => tester
    .widget<DecoratedBox>(find.descendant(
      of: find.byType(ProfileTabIcon),
      matching: find.byType(DecoratedBox),
    ))
    .decoration as BoxDecoration;

void main() {
  testWidgets(
      'Given no photo, Then the tab shows the person icon — outlined, '
      'and filled when it is the open tab', (tester) async {
    await _pump(tester, const ProfileTabIcon());
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);

    await _pump(tester, const ProfileTabIcon(selected: true));
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });

  testWidgets(
      'Given a photo, Then it replaces the icon, in the icon\'s own 24 px box '
      'and at the same size whether or not the tab is open', (tester) async {
    final image = await _photo(tester);
    for (final selected in [false, true]) {
      await _pump(
          tester, ProfileTabIcon(photo: _ReadyImage(image), selected: selected));

      expect(find.byType(Icon), findsNothing);
      expect(tester.getSize(find.byType(ProfileTabIcon)), const Size(24, 24));
      expect(tester.getSize(find.byType(RawImage)), const Size(20, 20));
    }
  });

  testWidgets(
      'Given a photo, When its tab is open, Then a 2 px ring in the bar\'s '
      'selected color goes around it — and only then', (tester) async {
    final image = await _photo(tester);

    await _pump(tester, ProfileTabIcon(photo: _ReadyImage(image)));
    expect(_ring(tester).border, isNull);

    await _pump(
        tester, ProfileTabIcon(photo: _ReadyImage(image), selected: true));
    final border = _ring(tester).border as Border;
    expect(border.top.color, _barColor);
    expect(border.top.width, 2);
  });

  testWidgets(
      'Given a photo still loading, Then the person icon holds its place',
      (tester) async {
    await _pump(tester, ProfileTabIcon(photo: _PendingImage()));

    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    expect(tester.getSize(find.byType(ProfileTabIcon)), const Size(24, 24));
  });

  testWidgets(
      'Given a photo that fails to load, Then the person icon stays, '
      'filled when it is the open tab', (tester) async {
    await _pump(tester, ProfileTabIcon(photo: _FailingImage()));
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);

    await _pump(tester, ProfileTabIcon(photo: _FailingImage(), selected: true));
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Given the photo in a real bottom bar, Then the Profile label lines up '
      'with the other labels, and the open tab rings it in the bar\'s color',
      (tester) async {
    final image = await _photo(tester);
    await tester.pumpWidget(MaterialApp(
      theme: buildNtripiTheme(),
      home: Scaffold(
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: 1,
          selectedItemColor: _barColor,
          items: [
            const BottomNavigationBarItem(
                icon: Icon(Icons.dynamic_feed_outlined), label: 'Feed'),
            BottomNavigationBarItem(
              icon: ProfileTabIcon(photo: _ReadyImage(image)),
              activeIcon:
                  ProfileTabIcon(photo: _ReadyImage(image), selected: true),
              label: 'Profile',
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Profile')).dy,
        tester.getTopLeft(find.text('Feed')).dy);
    expect((_ring(tester).border as Border).top.color, _barColor);
  });
}
