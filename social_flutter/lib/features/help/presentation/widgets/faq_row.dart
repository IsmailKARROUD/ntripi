// features/help/presentation/widgets/faq_row.dart
//
// One expandable question inside the Help Center's SectionCard.
//
// Deliberately not an ExpansionTile: that widget brings its own dividers,
// padding and text theme, all of which fight the editorial SectionCard it would
// sit inside. AnimatedSize + AnimatedRotation gets the same behaviour with the
// app's own proportions.

import 'package:flutter/material.dart';
import 'package:social_flutter/core/ui/app_theme.dart';

class FaqRow extends StatefulWidget {
  final String question;
  final String answer;
  final bool isLast;

  const FaqRow({
    super.key,
    required this.question,
    required this.answer,
    this.isLast = false,
  });

  @override
  State<FaqRow> createState() => _FaqRowState();
}

class _FaqRowState extends State<FaqRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    const duration = Duration(milliseconds: 180);

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.question,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: nt.bark,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: duration,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: nt.text3,
                      ),
                    ),
                  ],
                ),
                // AnimatedSize over a zero-height box rather than a Visibility
                // toggle, so the card grows and shrinks instead of jumping.
                AnimatedSize(
                  duration: duration,
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: _open
                      ? Padding(
                          padding:
                              const EdgeInsetsDirectional.only(top: 8, end: 8),
                          child: Text(
                            widget.answer,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: nt.text2,
                              height: 1.45,
                            ),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
        if (!widget.isLast)
          Container(
            height: 1,
            margin: const EdgeInsetsDirectional.only(start: 16),
            color: nt.border,
          ),
      ],
    );
  }
}
