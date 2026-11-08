// shared/widgets/text_rules.dart — what a field's text must obey to be saved.
//
// The server refuses user text that breaks one of its rules: a link where no
// link is allowed (validators/links.py, 422 `text_contains_link`). This says
// so under the field as the user types, in the words the server's refusal
// would use, and holds Save off while it lasts. Nothing typed is ever changed
// or cut: the user fixes the text, the app never does.
//
// One mechanism for every field that stores user text — never a field-by-field
// check. A form names its fields once ([RuledField]), shows [TextRulesNote]
// under each, and wraps its Save in [TextRulesGate].

import 'package:flutter/widgets.dart';
import 'package:ntripi/core/text/link_rule.dart';
import 'package:ntripi/l10n/app_localizations.dart';
import 'package:ntripi/shared/widgets/editorial_widgets.dart';
import 'package:ntripi/shared/widgets/keyboard_avoidance.dart';

/// The rules a field's text is held to.
class TextRules {
  const TextRules({this.refuseLinks = true});

  /// No link (link_rule.dart) — every user text but a stop's map link.
  final bool refuseLinks;

  /// The rules of any text a user writes for others to read.
  static const userText = TextRules();
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

/// Why [text] cannot be saved under [rules], or null.
///
/// [initial] is the value stored now: the server refuses a link only in a text
/// that changed, so a link saved before the rule never holds Save back until
/// its text is edited.
TextRuleBreak? textRuleBreak(String text, TextRules rules, {String? initial}) {
  if (rules.refuseLinks && text.trim() != (initial ?? '').trim()) {
    final match = findLink(text);
    if (match != null) return LinkInText(match);
  }
  return null;
}

/// A field held to [rules]: its controller and the value stored now.
class RuledField {
  const RuledField(this.controller,
      {this.rules = TextRules.userText, this.initial});

  final TextEditingController controller;
  final TextRules rules;
  final String? initial;

  TextRuleBreak? get breach =>
      textRuleBreak(controller.text, rules, initial: initial);
}

/// Whether every field obeys its rules right now.
bool textRulesHold(Iterable<RuledField> fields) =>
    fields.every((field) => field.breach == null);

/// The rule [field] breaks, shown under it — nothing when it breaks none.
/// Rebuilds as the user types.
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
        if (breach == null) return const SizedBox.shrink();
        return Padding(
          padding: padding,
          child: SheetErrorRow(breach.message(AppLocalizations.of(context)!)),
        );
      },
    );
  }
}

/// [child] — a field — with the rule it breaks under it, the two revealed
/// above the keyboard as one unit. For a field no ModerationHint groups
/// already; inside a ModerationHint, put a [TextRulesNote] under the field.
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
