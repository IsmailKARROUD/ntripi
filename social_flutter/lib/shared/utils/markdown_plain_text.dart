// shared/utils/markdown_plain_text.dart — a markdown text's words, without the
// markup.
//
// A folded preview (a description's first lines, a stop note's two) and a
// one-line summary show the text plain: `**`, `#` and `- ` are what a reader
// would otherwise see, and the formatted text opens in full. Parsed the way
// InertMarkdownBody parses it (no extensions), so the preview and the text it
// opens to agree on what is markup: an image is its description (it is never
// loaded), a link its label, a list item keeps its bullet or number.

import 'package:markdown/markdown.dart' as md;

/// [source]'s text without the markup, one line per paragraph, heading or
/// list item. [singleLine] joins them with spaces instead — a summary row.
String markdownPlainText(String source, {bool singleLine = false}) {
  final nodes = md.Document(
    extensionSet: md.ExtensionSet.none,
    encodeHtml: false,
  ).parseLines(source.replaceAll('\r\n', '\n').split('\n'));
  final out = StringBuffer();
  _write(nodes, out);
  final lines = out
      .toString()
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty);
  return lines.join(singleLine ? ' ' : '\n');
}

const _blockTags = {
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'pre', 'hr', //
  'li', 'ul', 'ol', 'table', 'tr',
};

void _write(List<md.Node> nodes, StringBuffer out) {
  for (final node in nodes) {
    if (node is md.Text) {
      out.write(node.text);
    } else if (node is md.Element) {
      _element(node, out);
    }
  }
}

void _element(md.Element element, StringBuffer out) {
  switch (element.tag) {
    case 'img':
      out.write(element.attributes['alt'] ?? '');
    case 'br':
      out.write('\n');
    case 'ul' || 'ol':
      final ordered = element.tag == 'ol';
      var number = int.tryParse(element.attributes['start'] ?? '') ?? 1;
      for (final item in element.children ?? const <md.Node>[]) {
        out.write('\n');
        out.write(ordered ? '${number++}. ' : '• ');
        if (item is md.Element) _item(item.children ?? const [], out);
        out.write('\n');
      }
    default:
      final block = _blockTags.contains(element.tag);
      if (block) out.write('\n');
      _write(element.children ?? const [], out);
      if (block) out.write('\n');
  }
}

/// A list item's content on its bullet's line: a loose list wraps it in
/// paragraphs, which would otherwise leave the bullet alone on a line.
void _item(List<md.Node> children, StringBuffer out) {
  for (final child in children) {
    if (child is md.Element && child.tag == 'p') {
      _write(child.children ?? const [], out);
      out.write(' ');
    } else if (child is md.Text) {
      out.write(child.text);
    } else if (child is md.Element) {
      _element(child, out);
    }
  }
}
