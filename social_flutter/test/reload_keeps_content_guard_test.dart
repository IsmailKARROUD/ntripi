// A reload never blanks content already on screen — and this keeps it true for
// code nobody has written yet.
//
// Riverpod 3 carries the previous value into every AsyncLoading and AsyncError
// a notifier writes, and AsyncValue.when() still draws them as the loader and
// the error view, so a reload written by hand unmounted the content — and the
// two hand-written guards that kept it during the load still let a failed
// reload replace it with the error view. ReloadKeepsContent
// (lib/core/providers/reload_keeps_content.dart) is the one place those rules
// live. So no class writes AsyncLoading or AsyncError into its state, or uses
// AsyncValue.guard, outside it, and every refresh() reloads through
// reloadKeepingContent. On the screen side, every reload a screen starts is
// either reported (reportReloads: a pull or a Retry, whose failure is the
// user's to hear about) or fired on purpose without (unawaited: a reload the
// app starts, which fails silently). An exception may still be right — with
// its reason, here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The mechanism itself: the only file that writes the two states freely.
const _mechanism = 'lib/core/providers/reload_keeps_content.dart';

/// Classes that may write a loading or error state themselves.
const _mayWriteLoadingOrError = {
  // A new query must not keep showing the previous query's results: its
  // loader answers a new question, it is not a reload of content on screen.
  'PlaceSearchNotifier',
  // The same for Google's suggestions, the stop form's fallback search.
  'GooglePlaceSearchNotifier',
};

final _writesLoadingOrError = RegExp(
    r'\bstate\s*=\s*(?:const\s+)?(?:Async(?:Loading|Error)\b|AsyncValue\s*\.\s*(?:loading|error)\b)');
final _usesGuard = RegExp(r'\bAsyncValue\s*\.\s*guard\b');
final _classStart = RegExp(r'\b(?:class|mixin)\s+(\w+)[^{;]*\{');
final _refreshDeclaration = RegExp(
    r'\b(?:Future<[^;{]*?>|void)\s+refresh\s*\(\s*\)\s*(?:async\s*)?(\{|=>)');

/// [source] with comments and string literals blanked to spaces (newlines
/// kept): a mention in prose or in a string is not code, and a brace inside
/// either would throw the class bodies out of step.
String _codeOnly(String source) {
  final out = StringBuffer();
  final n = source.length;
  void blank(int from, int to) {
    for (var k = from; k < to; k++) {
      out.write(source[k] == '\n' ? '\n' : ' ');
    }
  }

  var i = 0;
  while (i < n) {
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      final stop = end < 0 ? n : end;
      blank(i, stop);
      i = stop;
    } else if (source.startsWith('/*', i)) {
      // Dart block comments nest.
      var depth = 1;
      var k = i + 2;
      while (k < n && depth > 0) {
        if (source.startsWith('/*', k)) {
          depth++;
          k += 2;
        } else if (source.startsWith('*/', k)) {
          depth--;
          k += 2;
        } else {
          k++;
        }
      }
      blank(i, k);
      i = k;
    } else if (source[i] == "'" || source[i] == '"') {
      final raw = i > 0 && source[i - 1] == 'r';
      final quote = source.startsWith(source[i] * 3, i)
          ? source[i] * 3
          : source[i];
      var k = i + quote.length;
      while (k < n && !source.startsWith(quote, k)) {
        if (!raw && source[k] == r'\') k++;
        k++;
      }
      k = k + quote.length > n ? n : k + quote.length;
      blank(i, k);
      i = k;
    } else {
      out.write(source[i]);
      i++;
    }
  }
  return out.toString();
}

/// The index of the bracket closing the one at [open] — a brace, or with
/// [pair] `'()'` a parenthesis.
int _closing(String code, int open, [String pair = '{}']) {
  var depth = 0;
  for (var k = open; k < code.length; k++) {
    if (code[k] == pair[0]) {
      depth++;
    } else if (code[k] == pair[1] && --depth == 0) {
      return k;
    }
  }
  return code.length - 1;
}

final _reloadCall = RegExp(r'\.refresh\(\s*\)');
final _reportingCall = RegExp(r'\b(?:reportReloads|unawaited)\s*\(');

/// The lines of [source] with a `.refresh()` outside every reportReloads(...)
/// and unawaited(...) call — a reload nobody reports and nobody chose to drop.
List<int> _unreportedReloads(String source) {
  final code = _codeOnly(source);
  final spans = [
    for (final call in _reportingCall.allMatches(code))
      (start: call.end - 1, end: _closing(code, call.end - 1, '()')),
  ];
  return [
    for (final reload in _reloadCall.allMatches(code))
      if (!spans.any((s) => s.start < reload.start && reload.end <= s.end))
        '\n'.allMatches(code.substring(0, reload.start)).length + 1,
  ];
}

/// What one source says, class by class: who writes a loading or error state
/// (or uses AsyncValue.guard), who declares refresh(), and whose refresh()
/// does not go through reloadKeepingContent.
({Set<String> writers, Set<String> refreshers, Set<String> strays}) _scan(
    String source) {
  final code = _codeOnly(source);
  final writers = <String>{};
  final refreshers = <String>{};
  final strays = <String>{};
  for (final declaration in _classStart.allMatches(code)) {
    final name = declaration.group(1)!;
    final open = declaration.end - 1;
    final body = code.substring(open, _closing(code, open) + 1);
    if (_writesLoadingOrError.hasMatch(body) || _usesGuard.hasMatch(body)) {
      writers.add(name);
    }
    for (final refresh in _refreshDeclaration.allMatches(body)) {
      refreshers.add(name);
      final String method;
      if (refresh.group(1) == '{') {
        final start = refresh.end - 1;
        method = body.substring(start, _closing(body, start) + 1);
      } else {
        final end = body.indexOf(';', refresh.end);
        method = body.substring(refresh.end, end < 0 ? body.length : end);
      }
      if (!method.contains('reloadKeepingContent(')) strays.add(name);
    }
  }
  return (writers: writers, refreshers: refreshers, strays: strays);
}

/// Every Dart file under lib/ but the mechanism, by path.
Map<String, String> _sources() => {
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && f.path != _mechanism))
        file.path: file.readAsStringSync(),
    };

void main() {
  final scans = {
    for (final entry in _sources().entries) entry.key: _scan(entry.value),
  };
  Set<String> where(Set<String> Function(
              ({Set<String> writers, Set<String> refreshers, Set<String> strays})
                  scan)
          pick) =>
      {
        for (final entry in scans.entries)
          for (final name in pick(entry.value)) '$name (${entry.key})',
      };
  String nameOf(String entry) => entry.substring(0, entry.indexOf(' ('));

  test('only ReloadKeepsContent writes a loading or error state', () {
    final live = where((s) => s.writers);
    final unexplained =
        live.where((e) => !_mayWriteLoadingOrError.contains(nameOf(e)));
    expect(unexplained, isEmpty,
        reason: 'A loading or error state written by hand blanks what the '
            'screen shows — the loader on every reload, the error view on '
            'every failed one. Reload through reloadKeepingContent, or add '
            'the class to _mayWriteLoadingOrError with the reason its loader '
            'is not a reload of content on screen.');
    expect(_mayWriteLoadingOrError.difference(live.map(nameOf).toSet()),
        isEmpty,
        reason: 'A stale entry would let the next real one through unseen.');
  });

  test('every refresh() reloads through reloadKeepingContent', () {
    expect(where((s) => s.strays), isEmpty,
        reason: 'refresh() is pull-to-refresh and Retry: with content on '
            'screen it must keep it through the reload, and through a '
            'failure the server did not answer with a refusal. '
            'ReloadKeepsContent.reloadKeepingContent is how.');
    // The scan must still see the notifiers it exists for.
    expect(where((s) => s.refreshers), hasLength(greaterThanOrEqualTo(14)));
  });

  test('every reload a screen starts is reported, or dropped on purpose', () {
    final unreported = [
      for (final entry in _sources().entries)
        if (entry.key.contains('/presentation/'))
          for (final line in _unreportedReloads(entry.value))
            '${entry.key}:$line',
    ];
    expect(unreported, isEmpty,
        reason: 'refresh() hands back the failure it kept the content '
            'through. A pull or a Retry passes it to reportReloads(context, '
            '[...]), which shows it in a SnackBar; a reload the app starts '
            'itself wraps it in unawaited(...), which says its failure is '
            'meant to stay silent.');
  });

  test('the reload scan tells a reported reload from a dropped one', () {
    const sample = '''
Widget build(BuildContext context) => Column(children: [
      RefreshIndicator(onRefresh: () => reportReloads(context, [
            ref.read(a.notifier).refresh(),
            ref.read(b.notifier).refresh(),
          ])),
      FilledButton(onPressed: () => ref.read(c.notifier).refresh()),
    ]);
void initState() {
  // ref.read(d.notifier).refresh(); is prose here.
  unawaited(ref.read(e.notifier).refresh());
  ref.refresh(someProvider);
}
''';
    expect(_unreportedReloads(sample), [6]);
  });

  test('the scan sees past comments and strings, and finds what it looks for',
      () {
    const sample = '''
class Kept extends AsyncNotifier<int> with ReloadKeepsContent<int> {
  // state = const AsyncLoading(); is prose here, and so is { this brace.
  final note = 'state = AsyncError(e, s) { in a string';
  Future<ReloadFailure?> refresh() async {
    return reloadKeepingContent(() async => 1);
  }
}

class Blanked extends AsyncNotifier<int> {
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async => 1);
  }
}

class Arrow extends AsyncNotifier<int> {
  Future<void> refresh() => ref.read(repo).load();
}
''';
    final scan = _scan(sample);
    expect(scan.writers, {'Blanked'});
    expect(scan.refreshers, {'Kept', 'Blanked', 'Arrow'});
    expect(scan.strays, {'Blanked', 'Arrow'});
  });
}
