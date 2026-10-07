// shared/widgets/keyboard_avoidance.dart — keeping what the user types above
// the on-screen keyboard.
//
// The contract, app-wide:
//  1. Whoever lifts content above the keyboard removes the inset from what it
//     passes down. Scaffold does; the bottom-nav shell (app_router.dart) and
//     [AboveKeyboard] do too. Nothing below compensates, so nothing counts the
//     keyboard twice.
//  2. Screens keep the default `resizeToAvoidBottomInset`. `false` is only for a
//     page that must not reflow for its own reason (a live map, a crop frame);
//     test/keyboard_avoidance_guard_test.dart allowlists each one.
//  3. A sheet lifts its body with the inset OUTSIDE its scroll view
//     ([KeyboardSafeSheetBody]). Padding inside the scroll view only works while
//     the sheet can still grow; once a height cap stops it, the viewport runs on
//     behind the keyboard and a covered field counts as visible.
//  4. A field and the text that belongs to it are revealed as one unit
//     ([RevealTogether]) — never with `scrollPadding` numbers.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Reveals [child] as one unit whenever something inside it asks to be shown:
/// a focused field, its caret, or the keyboard rising over it.
///
/// A text field reveals only its caret line plus `scrollPadding`, so the empty
/// lines under the caret, its counter, and any hint or advisory beneath it stay
/// under the keyboard. This widens each such request in transit to the whole
/// child — the move the framework's own pinned headers make — provided the
/// child fits every enclosing viewport. A taller child (a long note) passes the
/// request on untouched, so the caret is never pushed out of view.
class RevealTogether extends SingleChildRenderObjectWidget {
  const RevealTogether({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRevealTogether();
}

class _RenderRevealTogether extends RenderProxyBox {
  @override
  void showOnScreen({
    RenderObject? descendant,
    Rect? rect,
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
  }) {
    if (descendant != null && hasSize) {
      final requested = MatrixUtils.transformRect(
        descendant.getTransformTo(this),
        rect ?? descendant.paintBounds,
      );
      final whole = (Offset.zero & size).expandToInclude(requested);
      if (_fitsEveryViewport(whole)) {
        super.showOnScreen(
          descendant: this,
          rect: whole,
          duration: duration,
          curve: curve,
        );
        return;
      }
    }
    super.showOnScreen(
      descendant: descendant,
      rect: rect,
      duration: duration,
      curve: curve,
    );
  }

  // A rect taller than a viewport is revealed by its leading edge, which could
  // scroll a long field's caret out of view — so widen only when it all fits.
  bool _fitsEveryViewport(Rect whole) {
    for (var viewport = RenderAbstractViewport.maybeOf(this);
        viewport != null;
        viewport = RenderAbstractViewport.maybeOf(viewport.parent)) {
      final leading = viewport.getOffsetToReveal(this, 0.0, rect: whole).offset;
      final trailing = viewport.getOffsetToReveal(this, 1.0, rect: whole).offset;
      if (leading < trailing) return false;
    }
    return true;
  }
}

/// Lifts [child] above the keyboard and hands it no keyboard inset: the inset
/// is consumed here, exactly as a resizing Scaffold consumes it for its body.
///
/// Reads the inset from its own context — 0 inside a bottom-nav tab (the shell
/// has already lifted it), the keyboard's height on the root navigator — so the
/// same sheet is right whichever navigator it was opened on.
class AboveKeyboard extends StatelessWidget {
  const AboveKeyboard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: child,
      ),
    );
  }
}

/// The body of a bottom sheet that holds a text field.
///
/// Lifts the content above the keyboard outside the scroll view, so the
/// viewport ends at the keyboard and a focused field can reveal itself. Caps
/// the content — not the sheet — at [maxHeightFactor] of the window, so the cap
/// never eats into the space above the keyboard, and always scrolls.
///
/// Show the sheet with `isScrollControlled: true` (so it can grow by the
/// keyboard) and `useSafeArea: true` (so growing stops below the status bar).
class KeyboardSafeSheetBody extends StatelessWidget {
  const KeyboardSafeSheetBody({
    super.key,
    required this.child,
    this.maxHeightFactor = 0.7,
    this.padding = const EdgeInsets.only(bottom: 16),
  });

  final Widget child;

  /// Fraction of the window height the content may take before it scrolls.
  final double maxHeightFactor;

  /// Padding inside the scroll view, around [child].
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AboveKeyboard(
      // MediaQuery padding.bottom is 0 while the keyboard is up, so this only
      // clears the home indicator once the keyboard is down.
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
          ),
          child: SingleChildScrollView(padding: padding, child: child),
        ),
      ),
    );
  }
}
