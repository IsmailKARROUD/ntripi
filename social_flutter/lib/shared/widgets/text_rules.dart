// shared/widgets/text_rules.dart — what a field's text must obey to be saved.
//
// The server refuses user text that breaks one of its rules: a link where no
// link is allowed (validators/links.py, 422 `text_contains_link`), and a text
// over its field's cap (a 422 `string_too_long`). This says so under the field
// as the user types — the link in the words the server's refusal would use,
// the length as a count shown from 90% of the cap — and holds Save off while a
// rule is broken. Nothing typed or pasted is ever changed or cut: the user
// fixes the text, the app never does (a field gets no `maxLength`, which cuts).
//
// One mechanism for every field that stores user text — never a field-by-field
// check. A form names its fields once ([RuledField]), shows [TextRulesNote]
// under each, and wraps its Save in [TextRulesGate].

import 'package:flutter/material.dart';
import 'package:ntripi/core/text/link_rule.dart';
import 'package:ntripi/core/text/text_limits.dart';
import 'package:ntripi/core/ui/app_theme.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/editorial_widgets.dart';
import 'package:ntripi/shared/widgets/keyboard_avoidance.dart';

/// The rules a field's text is held to.
class TextRules {
  const TextRules(this.limit, {this.refuseLinks = true});

  /// The server's cap on the field, from [TextLimits], counted by [textLength].
  final int limit;

  /// No link (link_rule.dart) — every user text but a stop's map link and the
  /// texts only the operator reads (a report, an appeal, a bug report), where
  /// quoting what is reported is the point.
  final bool refuseLinks;
}

/// A rule a text breaks, worded for the user.
sealed class TextRuleBreak {
  const TextRuleBreak();

  String message(AppLocalizations l10n);
}

/// The text holds a link; [match] is the exact text found.
final class LinkInText extends TextRuleBreak {
  const LinkInText(this.match);

  final String match;

  @override
  String message(AppLocalizations l10n) => l10n.textRuleNoLinks(match);
}

/// The text is longer than its field's cap.
final class TextTooLong extends TextRuleBreak {
  const TextTooLong(this.limit);

  final int limit;

  @override
  String message(AppLocalizations l10n) => l10n.textRuleTooLong(limit);
}

/// Why [text] cannot be saved under [rules], or null.
///
/// [initial] is the value stored now: the server refuses a link only in a text
/// that changed, so a link saved before the rule never holds Save back until
/// its text is edited. The cap holds whatever changed — a field is sent whole.
TextRuleBreak? textRuleBreak(String text, TextRules rules, {String? initial}) {
  if (rules.refuseLinks && text.trim() != (initial ?? '').trim()) {
    final match = findLink(text);
    if (match != null) return LinkInText(match);
  }
  if (textLength(text) > rules.limit) return TextTooLong(rules.limit);
  return null;
}

/// A field held to [rules]: its controller and the value stored now.
class RuledField {
  const RuledField(this.controller, {required this.rules, this.initial});

  final TextEditingController controller;
  final TextRules rules;
  final String? initial;

  TextRuleBreak? get breach =>
      textRuleBreak(controller.text, rules, initial: initial);
}

/// Whether every field obeys its rules right now.
bool textRulesHold(Iterable<RuledField> fields) =>
    fields.every((field) => field.breach == null);

/// Under [field]: the rule it breaks, and its count once it reaches 90% of its
/// cap — red past it. Nothing at all while neither applies. Rebuilds as the
/// user types.
class TextRulesNote extends StatelessWidget {
  const TextRulesNote(this.field,
      {super.key, this.padding = const EdgeInsets.only(top: 6)});

  final RuledField field;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: field.controller,
      builder: (context, _) {
        final breach = field.breach;
        final length = textLength(field.controller.text);
        final limit = field.rules.limit;
        final counted = length * 10 >= limit * 9;
        if (breach == null && !counted) return const SizedBox.shrink();
        return Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: breach == null
                    ? const SizedBox.shrink()
                    : SheetErrorRow(
                        breach.message(AppLocalizations.of(context)!)),
              ),
              if (counted)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8, top: 1),
                  child: _Count(length: length, limit: limit),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// "3612/4000", as Flutter's own counter writes it; red past the cap.
class _Count extends StatelessWidget {
  const _Count({required this.length, required this.limit});

  final int length;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final nt = context.nt;
    final over = length > limit;
    return Semantics(
      // Past the cap the message beside it says why; under it, how much room
      // is left, in the words Flutter's own counter uses.
      label: over
          ? null
          : MaterialLocalizations.of(context)
              .remainingTextFieldCharacterCount(limit - length),
      child: ExcludeSemantics(
        excluding: !over,
        child: Text(
          '$length/$limit',
          style: TextStyle(
            fontSize: 12,
            fontWeight: over ? FontWeight.w700 : FontWeight.w500,
            color: over ? nt.danger : nt.text3,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// [child] — a field — with what [TextRulesNote] says under it, the two
/// revealed above the keyboard as one unit. For a field no ModerationHint
/// groups already; inside a ModerationHint, put a [TextRulesNote] under the
/// field.
class TextRulesField extends StatelessWidget {
  const TextRulesField({super.key, required this.field, required this.child});

  final RuledField field;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RevealTogether(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [child, TextRulesNote(field)],
      ),
    );
  }
}

/// Rebuilds [builder] with whether every one of [fields] obeys its rules —
/// wrap a Save button in it: `onPressed: ok ? save : null`.
class TextRulesGate extends StatelessWidget {
  const TextRulesGate({super.key, required this.fields, required this.builder});

  final List<RuledField> fields;
  final Widget Function(BuildContext context, bool ok) builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([for (final f in fields) f.controller]),
      builder: (context, _) => builder(context, textRulesHold(fields)),
    );
  }
}
