// shared/widgets/duration_picker_sheet.dart — the days/hours/minutes wheel.
//
// One sheet for the two places that ask for a duration: the stop form's "Time
// to spend" and the transport leg's "Duration", which until now carried two
// copies of the same block.
//
// Deliberately NOT a CupertinoPicker. That widget hard-codes
// overAndUnderCenterOpacity = 0.447 (cupertino/picker.dart) and does not expose
// it, so every row but the centred one lands near 2.9:1 against nt.sand — under
// WCAG's 4.5:1, and unreachable by any colour choice, since black is already as
// dark as ink gets. ListWheelScrollView exposes that opacity; that single
// parameter is the whole reason for the rewrite. Dropping Cupertino also drops
// CupertinoColors, which resolve against the *OS* appearance whenever no
// ancestor supplies a brightness — wrong in an app whose theme is chosen
// independently of the system (themeModeProvider).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_flutter/core/services/haptics_service.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

/// A duration as the forms store it. Kept as three fields rather than a
/// [Duration] because the wheels are three fields — "2 d" and "48 h" are the
/// same length of time but not the same answer to put back on the wheel.
typedef DurationParts = ({int days, int hours, int minutes});

// CupertinoPicker's own eyeballed geometry (cupertino/picker.dart:20-22),
// copied verbatim so the wheel keeps exactly the feel it had.
const double _diameterRatio = 1.07;
const double _perspective = 0.003;
const double _squeeze = 1.45;
const double _itemExtent = 44;

// The point of the exercise: legible off-centre rows. Cupertino's 0.447 is what
// made the numbers look near-white on the sand sheet.
const double _overAndUnderCenterOpacity = 0.9;

// Tap-a-row-to-centre-it, the other behaviour CupertinoPicker gave us for free
// (picker.dart:32-33).
const Duration _tapToScrollDuration = Duration(milliseconds: 300);
const Curve _tapToScrollCurve = Curves.easeInOut;

/// Opens the duration sheet and resolves to what the user picked, or `null` if
/// they cancelled or dismissed it.
///
/// Callers apply the result only when it is non-null, so a dismissed sheet
/// cannot half-apply — unlike the two `temp*`-locals-plus-outer-`setState`
/// blocks this replaces.
Future<DurationParts?> showDurationPickerSheet({
  required BuildContext context,
  required String title,
  required int days,
  required int hours,
  required int minutes,
}) {
  return showModalBottomSheet<DurationParts>(
    context: context,
    backgroundColor: context.nt.sand,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder:
        (_) => _DurationPickerSheet(
          title: title,
          days: days,
          hours: hours,
          minutes: minutes,
        ),
  );
}

class _DurationPickerSheet extends StatefulWidget {
  const _DurationPickerSheet({
    required this.title,
    required this.days,
    required this.hours,
    required this.minutes,
  });

  final String title;
  final int days;
  final int hours;
  final int minutes;

  @override
  State<_DurationPickerSheet> createState() => _DurationPickerSheetState();
}

class _DurationPickerSheetState extends State<_DurationPickerSheet> {
  late int _days = widget.days;
  late int _hours = widget.hours;
  late int _minutes = widget.minutes;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Hand-drawn rather than showDragHandle: true, so it matches the
          // place-type sheet pixel for pixel.
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: nt.text3.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel, style: TextStyle(color: nt.text2)),
                ),
                Flexible(
                  child: Text(
                    widget.title.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: nt.text2,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                TextButton(
                  onPressed:
                      () => Navigator.of(context).pop((
                        days: _days,
                        hours: _hours,
                        minutes: _minutes,
                      )),
                  child: Text(
                    l10n.doneTooltip,
                    style: TextStyle(
                      color: nt.forest,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: Stack(
              children: [
                // One band across all three wheels, the way a native
                // multi-component picker reads. IgnorePointer because
                // tap-to-scroll lives on the rows themselves.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        height: _itemExtent,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: nt.mist,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _DurationWheel(
                        count: 366,
                        initialItem: _days,
                        labelBuilder: (i) => '$i ${l10n.daysLabel}',
                        onChanged: (i) => _days = i,
                      ),
                    ),
                    Expanded(
                      child: _DurationWheel(
                        count: 24,
                        initialItem: _hours,
                        labelBuilder: (i) => '$i ${l10n.hoursLabel}',
                        onChanged: (i) => _hours = i,
                      ),
                    ),
                    Expanded(
                      child: _DurationWheel(
                        count: 60,
                        initialItem: _minutes,
                        labelBuilder:
                            (i) =>
                                '${i.toString().padLeft(2, '0')} '
                                '${l10n.minutesLabel}',
                        onChanged: (i) => _minutes = i,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationWheel extends ConsumerStatefulWidget {
  const _DurationWheel({
    required this.count,
    required this.initialItem,
    required this.labelBuilder,
    required this.onChanged,
  });

  final int count;
  final int initialItem;
  final String Function(int index) labelBuilder;
  final ValueChanged<int> onChanged;

  @override
  ConsumerState<_DurationWheel> createState() => _DurationWheelState();
}

class _DurationWheelState extends ConsumerState<_DurationWheel> {
  late final _controller = FixedExtentScrollController(
    initialItem: widget.initialItem,
  );
  late int _selected = widget.initialItem;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleChanged(int index) {
    setState(() => _selected = index); // repaints the bold/ink centre row
    widget.onChanged(index);
    // The gate CupertinoPicker itself applies (iOS only — picker.dart:271),
    // but routed through HapticsService, which is where the user's haptics
    // switch is read; a raw HapticFeedback call would be the one cue in the
    // app that ignores it.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      ref.read(hapticsServiceProvider).fire(Haptic.selection);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    return ListWheelScrollView.useDelegate(
      controller: _controller,
      physics: const FixedExtentScrollPhysics(),
      itemExtent: _itemExtent,
      diameterRatio: _diameterRatio,
      perspective: _perspective,
      squeeze: _squeeze,
      overAndUnderCenterOpacity: _overAndUnderCenterOpacity,
      onSelectedItemChanged: _handleChanged,
      // Builder, not a List.generate: the days wheel is 366 rows and only a
      // handful are ever on screen.
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: widget.count,
        builder: (context, index) {
          final selected = index == _selected;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:
                () => _controller.animateToItem(
                  index,
                  duration: _tapToScrollDuration,
                  curve: _tapToScrollCurve,
                ),
            child: Center(
              child: Text(
                widget.labelBuilder(index),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? nt.bark : nt.text2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
