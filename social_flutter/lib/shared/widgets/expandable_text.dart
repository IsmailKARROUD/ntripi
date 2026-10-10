// shared/widgets/expandable_text.dart — a text folded to a few lines, with
// "… view more" / "view less" when it does not fit.
//
// The one widget for it: stop-card notes, review notes and a transport leg's
// thoughts. Two private copies had grown apart, and both measured the overflow
// with a bare TextPainter — no theme font, no text scaler, no bold-text — so
// under large accessibility text a note rendered ellipsised with no link to the
// rest of it.
//
// Never place it under IntrinsicHeight: the overflow check is a LayoutBuilder,
// which throws on an intrinsic query (the 2026-09-29 parallel-stops freeze,
// test/widgets/parallel_stop_group_layout_test.dart).

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';
import 'package:social_flutter/l10n/app_localizations.dart';

class ExpandableText extends StatefulWidget {
  const ExpandableText(
    this.text, {
    super.key,
    this.maxLines = 2,
    this.style,
    this.linkStyle,
    this.expandedBuilder,
    this.expandOnTextTap = false,
  });

  final String text;

  /// Lines shown while folded.
  final int maxLines;

  /// Defaults to 13/1.4 in `nt.text2`.
  final TextStyle? style;

  /// The "view more" / "view less" link. Defaults to 12/w600 in `nt.forest`.
  final TextStyle? linkStyle;

  /// Renders the unfolded text — markdown notes pass `InertMarkdownBody`.
  /// Defaults to the same plain text, unclamped.
  final Widget Function(BuildContext context, String text)? expandedBuilder;

  /// Tapping the folded text unfolds it too. Off where the text sits inside
  /// something with a tap of its own (a stop card opens its stop).
  final bool expandOnTextTap;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;

  /// Whether the text needs more than [ExpandableText.maxLines] at [maxWidth],
  /// measured with everything `Text` renders it with — measuring with less is
  /// how a folded note ended up with no link.
  bool _overflows(BuildContext context, TextStyle style, double maxWidth) {
    var effective = DefaultTextStyle.of(context).style.merge(style);
    if (MediaQuery.boldTextOf(context)) {
      effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: effective),
      maxLines: widget.maxLines,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: maxWidth);
    final overflows = painter.didExceedMaxLines;
    painter.dispose();
    return overflows;
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final l10n = AppLocalizations.of(context)!;
    final style = widget.style ??
        TextStyle(fontSize: 13, height: 1.4, color: nt.text2);
    final linkStyle = widget.linkStyle ??
        TextStyle(fontSize: 12, color: nt.forest, fontWeight: FontWeight.w600);

    return LayoutBuilder(
      builder: (context, constraints) {
        final overflows = _overflows(context, style, constraints.maxWidth);
        final Widget body;
        if (_expanded) {
          body = widget.expandedBuilder?.call(context, widget.text) ??
              Text(widget.text, style: style);
        } else {
          final folded = Text(
            widget.text,
            style: style,
            maxLines: widget.maxLines,
            overflow: TextOverflow.ellipsis,
          );
          body = widget.expandOnTextTap
              ? GestureDetector(
                  // No-op when it already fits.
                  onTap: overflows ? _toggle : null,
                  behavior: HitTestBehavior.opaque,
                  child: folded,
                )
              : folded;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            body,
            if (overflows || _expanded)
              Semantics(
                // Its own node, so the link is not merged into a surrounding row.
                container: true,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggle,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _expanded ? l10n.viewLess : l10n.viewMore,
                      style: linkStyle,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
