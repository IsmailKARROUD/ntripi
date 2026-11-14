// widgets/order_by_distance_sheet.dart — Order by distance in arrange mode:
// the button that starts it, the sheet that asks only what changes the
// answer, and the bar over the suggested order, whose Save saves at once.
//
// No distance is ever shown, anywhere: the order is worked out in straight
// lines, which cannot say what the traveller gains on the road.

import 'package:flutter/material.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/features/itineraries/domain/order_by_distance.dart';
import 'package:ntripi/features/itineraries/domain/trip_arrangement.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/editorial_widgets.dart';
import 'package:ntripi/shared/widgets/keyboard_avoidance.dart';

/// Above the arrangement: starts Order by distance. Nothing is worked out
/// until it is tapped; [working] while the answer is on its way.
class OrderByDistanceButton extends StatelessWidget {
  const OrderByDistanceButton({
    super.key,
    required this.working,
    required this.onPressed,
  });

  final bool working;

  /// Null while [working] or while nothing may start.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        onPressed: working ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: nt.forest,
          side: BorderSide(color: nt.border),
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        icon: working
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: nt.forest),
              )
            : const Icon(Icons.route_rounded, size: 18),
        label: Text(
          working ? l10n.orderByDistanceWorking : l10n.orderByDistance,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Asks where the trip ends and whether linked tracks stay together — only
/// what changes the answer — and returns the choice, or null for Cancel.
Future<OrderChoice?> showOrderByDistanceSheet(
  BuildContext context, {
  required DistanceOrderChoices choices,
  required TripArrangement arrangement,
}) =>
    showModalBottomSheet<OrderChoice>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          _OrderByDistanceSheet(choices: choices, arrangement: arrangement),
    );

class _OrderByDistanceSheet extends StatefulWidget {
  const _OrderByDistanceSheet({
    required this.choices,
    required this.arrangement,
  });

  final DistanceOrderChoices choices;
  final TripArrangement arrangement;

  @override
  State<_OrderByDistanceSheet> createState() => _OrderByDistanceSheetState();
}

class _OrderByDistanceSheetState extends State<_OrderByDistanceSheet> {
  // The careful answers first: the end stays, and no segment is deleted.
  bool _keepEnd = true;
  bool _keepLegs = true;

  OrderChoice get _choice => OrderChoice(keepEnd: _keepEnd, keepLegs: _keepLegs);

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final choices = widget.choices;
    final rows = widget.arrangement.rows;
    final result = choices.resultFor(_choice);
    final freeEnd =
        choices.resultFor(OrderChoice(keepEnd: false, keepLegs: _keepLegs));
    final breaking =
        choices.resultFor(OrderChoice(keepEnd: _keepEnd, keepLegs: false));

    Widget check(bool selected) => Icon(
          selected ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 22,
          color: selected ? nt.forest : nt.text3,
        );

    Widget option({
      required IconData icon,
      required String label,
      String? subtitle,
      required bool selected,
      required VoidCallback onTap,
      bool isLast = false,
    }) =>
        Semantics(
          inMutuallyExclusiveGroup: true,
          checked: selected,
          child: EditorialRow(
            icon: icon,
            iconBg: nt.mist,
            iconColor: nt.forest,
            label: label,
            subtitle: subtitle,
            trailing: check(selected),
            isLast: isLast,
            onTap: onTap,
          ),
        );

    return KeyboardSafeSheetBody(
      actions: SheetActionBar(
        child: Row(
          children: [
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: nt.forest),
              child: Text(l10n.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed:
                  result == null ? null : () => Navigator.of(context).pop(_choice),
              child: Text(l10n.orderByDistanceSuggest),
            ),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 4),
            child: Text(
              l10n.orderByDistance,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: nt.bark,
                letterSpacing: -0.3,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
            child: Text(
              l10n.orderByDistanceStartsAt(_rowName(rows.first, l10n)),
              style: TextStyle(fontSize: 13, height: 1.35, color: nt.text2),
            ),
          ),
          if (choices.endMatters) ...[
            SectionLabel(label: l10n.orderByDistanceEndTitle),
            SectionCard(
              clipBehavior: Clip.antiAlias,
              children: [
                option(
                  icon: Icons.flag_rounded,
                  label: l10n.orderByDistanceEndAtLast(_rowName(rows.last, l10n)),
                  subtitle: l10n.orderByDistanceEndAtLastHint,
                  selected: _keepEnd,
                  onTap: () => setState(() => _keepEnd = true),
                ),
                option(
                  icon: Icons.alt_route_rounded,
                  label: l10n.orderByDistanceEndAnywhere,
                  subtitle: freeEnd == null
                      ? null
                      : l10n.orderByDistanceWouldEndAt(
                          _rowName(freeEnd.arrangement.rows.last, l10n)),
                  selected: !_keepEnd,
                  isLast: true,
                  onTap: () => setState(() => _keepEnd = false),
                ),
              ],
            ),
          ],
          if (choices.legsMatter) ...[
            SectionLabel(label: l10n.orderByDistanceLegsTitle),
            SectionCard(
              clipBehavior: Clip.antiAlias,
              children: [
                option(
                  icon: Icons.link_rounded,
                  label: l10n.orderByDistanceKeepLegs,
                  subtitle: l10n.orderByDistanceKeepLegsHint,
                  selected: _keepLegs,
                  onTap: () => setState(() => _keepLegs = true),
                ),
                option(
                  icon: Icons.link_off_rounded,
                  label: l10n.orderByDistanceBreakLegs,
                  subtitle: breaking == null || breaking.brokenLegs.isEmpty
                      ? null
                      : l10n.transitSegmentsWillBeDeleted(
                          breaking.brokenLegs.length),
                  selected: !_keepLegs,
                  isLast: true,
                  onTap: () => setState(() => _keepLegs = false),
                ),
              ],
            ),
          ],
          if (result == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: nt.text2),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.orderByDistanceNoChange,
                      style:
                          TextStyle(fontSize: 13, height: 1.35, color: nt.text2),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A track as the sheet names it: by its first stop (a track is never empty).
String _rowName(ArrangedTrack row, AppLocalizations l10n) =>
    row.stops.first.placeName ?? l10n.unnamedStop;

/// Over the suggested order: what it changes, and Cancel / Save. Save saves
/// the trip at once — the order is never applied to the arrangement first.
class SuggestedOrderBar extends StatelessWidget {
  const SuggestedOrderBar({
    super.key,
    required this.order,
    required this.onCancel,
    required this.onSave,
  });

  final DistanceOrder order;
  final VoidCallback onCancel;

  /// Null while saving is not possible: offline, or without the claim.
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final notes = [
      if (order.unmeasured > 0)
        (Icons.location_off_outlined, l10n.suggestedOrderUnmeasured(order.unmeasured)),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
      decoration: BoxDecoration(
        color: nt.surface,
        borderRadius: BorderRadius.circular(NtripiRadius.tile),
        border: Border.all(color: nt.forest),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, size: 18, color: nt.forest),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.suggestedOrderTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: nt.bark,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 26, top: 2),
            child: Text(
              l10n.suggestedOrderMoved(order.moved, order.arrangement.rows.length),
              style: TextStyle(fontSize: 13, color: nt.text2),
            ),
          ),
          for (final (icon, text) in notes)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 26, top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 14, color: nt.text2),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      text,
                      style:
                          TextStyle(fontSize: 12.5, height: 1.35, color: nt.text2),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(foregroundColor: nt.forest),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: onSave,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
