// core/text/link_rule.dart — no user text carries a link, except a stop's map
// link: the app's twin of the server's validators/links.py.
//
// The server is the authority (422 `text_contains_link`); this tells the user
// before Save, quoting the very text the server would quote. Both detectors
// are held to one sample list, test/support/link_rule_samples.json — add a
// case there, never to one side. The patterns mirror the Python ones: explicit
// look-behinds instead of \b, ASCII-only where only ASCII is meant, and
// [\p{L}\p{N}] where Python writes [^\W_] (a Unicode letter or digit).
//
// A link is: any address scheme (`x://…`, `http:`, `https:`, `javascript:`,
// `vbscript:`, `mailto:`, and `data:` before a type/subtype), anything
// starting `www.`, markdown link or image syntax and a reference definition,
// an e-mail address, and a bare site name — dot-separated labels ending in a
// real top-level domain (tlds.dart) with a letter before it: `booking.com`,
// `anna.paris`. `3.5km`, `e.g.` and `St.Louis` are not; `lunch.Tours` (a
// missing space) is — a false alarm the owner accepted, since the message
// quotes the exact text and a space fixes it.

import 'package:ntripi/core/text/tlds.dart';

final _schemeSlashes =
    RegExp(r'[a-z][a-z0-9+.-]*://\S*', caseSensitive: false);
final _bareScheme = RegExp(
  r'(?<![a-z0-9_])(?:(?:https?|javascript|vbscript|mailto):\S+'
  r'|data:[a-z]+/[a-z0-9.+-]+\S*)',
  caseSensitive: false,
);
final _www = RegExp(
  r'(?<![\p{L}\p{N}_.-])www\.\S+',
  caseSensitive: false,
  unicode: true,
);
final _markdownLink = RegExp(r'!?\[[^\]\n]*\]\([^)\n]*\)');
final _markdownReference =
    RegExp(r'^[ ]{0,3}\[[^\]\n]+\]:[ \t]*\S+', multiLine: true);
final _email = RegExp(
  r'[A-Za-z0-9._%+-]+@(?<domain>(?:[\p{L}\p{N}_-]+\.)+[\p{L}\p{N}_-]+)',
  unicode: true,
);
final _siteName = RegExp(
  r'(?<![\p{L}\p{N}_.-])(?<domain>(?:[\p{L}\p{N}_-]+\.)+[\p{L}\p{N}_-]+)'
  r'(?![\p{L}\p{N}_-])(?:/\S*)?',
  unicode: true,
);
final _letter = RegExp(r'\p{L}', unicode: true);

/// Labels ending in a real top-level domain, with a letter before it.
bool _isSiteName(String domain) {
  final labels = domain.split('.');
  final tld = labels.removeLast().toLowerCase();
  return ianaTlds.contains(tld) && _letter.hasMatch(labels.join());
}

/// The first link in [text] — its exact characters, as the message quotes
/// them — or null. When two kinds start at the same place, the longer wins.
String? findLink(String? text) {
  if (text == null || text.isEmpty) return null;
  final spans = <(int, int)>[];
  for (final pattern in [
    _schemeSlashes,
    _bareScheme,
    _www,
    _markdownLink,
    _markdownReference,
  ]) {
    final match = pattern.firstMatch(text);
    if (match != null) spans.add((match.start, match.end));
  }
  for (final pattern in [_email, _siteName]) {
    for (final match in pattern.allMatches(text)) {
      if (_isSiteName(match.namedGroup('domain')!)) {
        spans.add((match.start, match.end));
        break;
      }
    }
  }
  if (spans.isEmpty) return null;
  spans.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : b.$2.compareTo(a.$2));
  return text.substring(spans.first.$1, spans.first.$2);
}
