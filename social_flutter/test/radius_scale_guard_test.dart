// Every corner in the app comes from the radius scale — and this keeps it
// true for code nobody has written yet.
//
// NtripiRadius (lib/core/ui/app_radii.dart) names one radius per job: a card,
// a field, a button, a pill. Before it, 247 corners were typed as numbers — 18
// different ones — and boxes doing the same job drifted apart: the trip page's
// edit-mode info boxes copied a 4 from a field that had since moved to 14. Two
// habits bring that back without a number in sight, so they are refused too:
// a `shape:` on a sheet or a dialog (the theme says NtripiRadius.modal, once),
// and an OutlineInputBorder that names no radius (Material falls back to 4).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files that may type a radius as a number.
const _mayTypeRadius = {
  // The loader animations draw the content they stand in for, to scale —
  // artwork, not chrome.
  'lib/shared/widgets/loaders.dart',
};

/// Every Dart file under lib/, comments removed and string contents blanked —
/// a radius in prose, or a paren inside a string, is not code.
Map<String, String> _sources() => {
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        file.path: _codeOnly(file.readAsStringSync()),
    };

/// [src] with comments removed and every string's contents blanked. Newlines
/// survive, so a reported line number is the file's own.
String _codeOnly(String src) {
  final out = StringBuffer();
  final ident = RegExp(r'[A-Za-z0-9_$]');
  var i = 0;

  void blockComment() {
    var depth = 0;
    do {
      if (src.startsWith('/*', i)) {
        depth++;
        i += 2;
      } else if (src.startsWith('*/', i)) {
        depth--;
        i += 2;
      } else {
        if (src[i] == '\n') out.write('\n');
        i++;
      }
    } while (depth > 0 && i < src.length);
  }

  late void Function({required bool interpolation}) code;

  void string() {
    final raw = src[i] == 'r';
    if (raw) {
      out.write('r');
      i++;
    }
    final quote = src[i];
    final delimiter = src.startsWith(quote * 3, i) ? quote * 3 : quote;
    out.write(delimiter);
    i += delimiter.length;
    while (i < src.length) {
      if (src.startsWith(delimiter, i)) {
        out.write(delimiter);
        i += delimiter.length;
        return;
      }
      if (!raw && src[i] == r'\') {
        out.write('  ');
        i += 2;
        continue;
      }
      // An interpolation is code again, and may hold strings of its own.
      if (!raw && src.startsWith(r'${', i)) {
        out.write(r'${');
        i += 2;
        code(interpolation: true);
        out.write('}');
        i++;
        continue;
      }
      out.write(src[i] == '\n' ? '\n' : ' ');
      i++;
    }
  }

  code = ({required bool interpolation}) {
    var braces = 0;
    while (i < src.length) {
      if (src.startsWith('//', i)) {
        while (i < src.length && src[i] != '\n') {
          i++;
        }
        continue;
      }
      if (src.startsWith('/*', i)) {
        blockComment();
        continue;
      }
      final c = src[i];
      final rawString = c == 'r' &&
          i + 1 < src.length &&
          (src[i + 1] == "'" || src[i + 1] == '"') &&
          (i == 0 || !ident.hasMatch(src[i - 1]));
      if (rawString || c == "'" || c == '"') {
        string();
        continue;
      }
      if (interpolation) {
        if (c == '{') braces++;
        if (c == '}') {
          if (braces == 0) return;
          braces--;
        }
      }
      out.write(c);
      i++;
    }
  };

  code(interpolation: false);
  return out.toString();
}

int _lineOf(String code, int offset) =>
    '\n'.allMatches(code.substring(0, offset)).length + 1;

/// Each call [callee] matches, with the text of its own arguments only —
/// whatever sits inside a nested call, list or map is blanked, so a
/// `BoxDecoration(shape: …)` in a dialog's content is not the dialog's shape.
List<({int line, String args})> _calls(String code, RegExp callee) => [
      for (final match in callee.allMatches(code))
        (line: _lineOf(code, match.start), args: _ownArgs(code, match.end - 1)),
    ];

String _ownArgs(String code, int open) {
  final args = StringBuffer();
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    final c = code[i];
    if ('([{'.contains(c)) {
      depth++;
      if (depth == 1) continue;
    } else if (')]}'.contains(c)) {
      depth--;
      if (depth == 0) break;
    }
    args.write(depth == 1 ? c : ' ');
  }
  return args.toString();
}

void main() {
  final sources = _sources();

  test('a radius is a token of the scale, never a number', () {
    final literal = RegExp(r'\b(?:BorderRadius(?:Directional)?|Radius)'
        r'\.(?:circular|elliptical)\(\s*-?\d[\d.]*\s*[,)]');
    final offenders = [
      for (final MapEntry(key: path, value: code) in sources.entries)
        if (!_mayTypeRadius.contains(path))
          for (final m in literal.allMatches(code))
            '$path:${_lineOf(code, m.start)}',
    ];
    expect(offenders, isEmpty,
        reason: 'Take the token of the job — NtripiRadius.card, .field, '
            '.button, .tile, .pill… (lib/core/ui/app_radii.dart). A number is '
            'how two boxes doing the same job drifted apart. Artwork drawn to '
            'scale may compute its radius from its size, or join '
            '_mayTypeRadius with the reason.');
    final typing = {
      for (final MapEntry(key: path, value: code) in sources.entries)
        if (literal.hasMatch(code)) path,
    };
    expect(_mayTypeRadius.difference(typing), isEmpty,
        reason: 'A stale entry would let the next real one through unseen.');
  });

  test('sheets and dialogs take their corners from the theme', () {
    final modal = RegExp(r'\b(?:showModalBottomSheet|showBottomSheet'
        r'|AlertDialog|SimpleDialog|Dialog)\s*(?:<[^()]*?>)?\s*\(');
    final shape = RegExp(r'\bshape\s*:');
    final offenders = [
      for (final MapEntry(key: path, value: code) in sources.entries)
        for (final call in _calls(code, modal))
          if (shape.hasMatch(call.args)) '$path:${call.line}',
    ];
    expect(offenders, isEmpty,
        reason: 'bottomSheetTheme and dialogTheme give every sheet top and '
            'every dialog NtripiRadius.modal; a shape: per call is how sheet '
            'tops ended up at 20, 24 and 28. Drop it — a sheet that draws its '
            'own top on a transparent background rounds it with '
            'NtripiRadius.modal.');
  });

  test('every OutlineInputBorder names its radius', () {
    final border = RegExp(r'\bOutlineInputBorder\s*\(');
    final radius = RegExp(r'\bborderRadius\s*:');
    final offenders = [
      for (final MapEntry(key: path, value: code) in sources.entries)
        for (final call in _calls(code, border))
          if (!radius.hasMatch(call.args)) '$path:${call.line}',
    ];
    expect(offenders, isEmpty,
        reason: 'Without one Material falls back to 4 — a square field among '
            'the 14s. Name NtripiRadius.field.');
  });
}
