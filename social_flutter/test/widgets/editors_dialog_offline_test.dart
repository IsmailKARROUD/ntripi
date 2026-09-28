// test/widgets/editors_dialog_offline_test.dart
//
// The add-editor dialog put its results list's Flexible INSIDE OfflineGate.
// Online that is harmless; offline the gate wraps its child in an
// AbsorbPointer, so the Flexible was no longer a direct Flex child and the
// dialog crashed the moment the signal dropped while it was open.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/features/itineraries/domain/itinerary_editor.dart';
import 'package:social_flutter/features/itineraries/presentation/editors_screen.dart';
import 'package:social_flutter/features/itineraries/providers/itinerary_providers.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class _NoEditors extends EditorsNotifier {
  _NoEditors(super.arg);

  @override
  Future<List<ItineraryEditor>> build() async => const [];
}

void main() {
  testWidgets(
      'Given the add-editor dialog is open, When the connection drops, '
      'Then it stays up instead of throwing', (tester) async {
    final online = StreamController<bool>();
    addTearDown(online.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        isOnlineProvider.overrideWith((ref) => online.stream),
        editorsProvider.overrideWith2((id) => _NoEditors(id)),
      ],
      child: MaterialApp(
        theme: buildNtripiTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const EditorsScreen(itineraryId: 'itin-1'),
      ),
    ));
    online.add(true);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add an editor'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    online.add(false);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
