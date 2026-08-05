// widgets/long_press_to_edit.dart — Owner shortcut from view mode into an editor.
//
// Read-mode sections render inert variants, so the owner otherwise has to enter
// edit mode before anything is tappable. Long-press jumps straight to the right
// editor for the section pressed.
//
// The gesture is free because every existing long-press in the itinerary
// surfaces is wired `onReport: isOwner ? null : …` — owner-edit and
// viewer-report are disjoint by role and never contend for the same press.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/connectivity/connectivity_service.dart';
import 'package:social_flutter/shared/widgets/offline_gate.dart';

class LongPressToEdit extends ConsumerWidget {
  /// Null makes the wrapper fully transparent — no detector is inserted at all,
  /// so viewers keep whatever long-press the child already defines (report).
  final VoidCallback? onEdit;
  final Widget child;

  const LongPressToEdit({
    super.key,
    required this.onEdit,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (onEdit == null) return child;
    // Optimistic while the stream seeds — never falsely lock the UI.
    final online = ref.watch(isOnlineProvider).value ?? true;
    // Deliberately not OfflineGate: its AbsorbPointer swallows a long-press
    // without ever reaching the onTap that shows the hint.
    return GestureDetector(
      // translucent, not deferToChild: sections are mostly text, and a press
      // landing in the padding between glyphs must still count. Taps are
      // untouched — this detector only ever claims the long-press, so the
      // child's own InkWell/GestureDetector still wins them.
      behavior: HitTestBehavior.translucent,
      onLongPress: () {
        if (!online) {
          showOfflineHint(context);
          return;
        }
        // Long-press has no visible affordance — the haptic is the only
        // confirmation the gesture registered before the editor opens.
        HapticFeedback.selectionClick();
        onEdit!();
      },
      child: child,
    );
  }
}
