// core/moderation/text_precheck.dart — client-side profanity hint.
//
// A courtesy, not a gate. The backend classifier is the authority; this only
// gives the writer a heads-up before they hit save. Three rules, all
// load-bearing:
//
//   1. It NEVER blocks. [looksOffensive] returning true produces an inline
//      hint and nothing else — the submit button stays enabled. A passing check
//      is not approval, and a failing one is not grounds to refuse a write.
//   2. It NEVER mutates. The user's words are their own; masking or
//      auto-correcting text somebody is still typing is a hostile act.
//   3. Any failure degrades to "clean". An unexpected input, an internal
//      error — all return false, so a broken filter is invisible rather than
//      obstructive.
//
// Scope: free prose only — descriptions, notes, review text, bios, display
// names. Deliberately NOT titles or place names: European place names
// false-positive on wordlist filters (Bitche in Moselle, Condom in the Gers,
// Sexbierum in Friesland, Wank in Bavaria), and flagging a real destination is
// worse than not filtering, because it teaches people to ignore the warning.
// The backend still moderates titles — its classifier reads context, which a
// wordlist cannot. That asymmetry is the whole reason for the split.
//
// ## Why the list is small and hand-written
//
// This used to run `safe_text`, whose bundled lists total ~21,700 entries for
// the app's six languages. Two measured reasons it is gone:
//
//   * Cost. Its Aho-Corasick preprocessing dequeues with `List.removeAt(0)`,
//     which is O(n) per node and therefore O(n²) over the ~150k-node trie:
//     2.9 s on a desktop JIT, tens of seconds on a mid-range phone — all
//     synchronous on the UI isolate, which is an Android ANR ("Ntripi isn't
//     responding") the first time any compose screen opened.
//   * Precision. Those lists are scraped, not curated: `beach`, `queue`,
//     `fish`, `after`, `el`, `ce`, `eg` and the bare pronoun `i` are all in
//     them, so roughly a third of ordinary travel prose flagged. No
//     minimum-length cutoff fixes that — `beach` is five letters.
//
// Precision beats recall for an advisory hint: the backend catches what this
// misses, while a hint that fires on "Beautiful beach" trains people to ignore
// every hint. So the list below is deliberately short, unambiguous, and ours.
// Adding an entry is cheap; adding one that appears in innocent prose is not.
//
// Pure Dart, no assets, no plugins, no isolate: the whole check is a few
// hash-set lookups, so it behaves identically on web and costs nothing.

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Whole-token entries. Matched against the text's tokens only, never as
/// substrings, so `Scunthorpe` and `Cockermouth` cannot trip `cunt` / `cock`.
///
/// Written lowercase and already leet-normalized (see [_normalize]) so a
/// pattern and the text it is compared against are in the same alphabet.
/// Inflections are enumerated rather than stemmed — prefix matching would put
/// `assume` and `analysis` back in scope.
const _kTokenPatterns = <String>{
  // ── English ──────────────────────────────────────────────────────────────
  'fuck', 'fucks', 'fucked', 'fucking', 'fuckin', 'fucker', 'fuckers',
  'fuckwit', 'clusterfuck', 'motherfucker', 'motherfuckers', 'motherfucking',
  'shit', 'shits', 'shitty', 'shitting', 'shithole', 'shithead', 'bullshit',
  'bitch', 'bitches', 'bitching', 'bitchy',
  'cunt', 'cunts',
  'asshole', 'assholes', 'arsehole', 'arseholes',
  'dickhead', 'dickheads', 'dick', 'dicks', 'prick', 'pricks',
  'wanker', 'wankers', 'twat', 'twats',
  'bastard', 'bastards',
  'slut', 'sluts', 'whore', 'whores', 'skank',
  'cock', 'cocks', 'pussy', 'pussies',
  'piss', 'pissing', 'pissed',
  'rape', 'raping', 'rapist', 'rapists',
  'pedophile', 'paedophile',
  'retard', 'retards', 'retarded',
  // Slurs — no innocent reading, so no inflection guesswork needed. `spic` and
  // `chink` are omitted despite being slurs: "spic and span" turns up in
  // accommodation reviews and "a chink of light" in travel prose, and a hint
  // that fires on those is worse than one that misses the slur the backend
  // will catch anyway. Same reason `pedo` is absent — it is everyday Spanish.
  'nigger', 'niggers', 'nigga', 'niggas', 'faggot', 'faggots',
  'kike', 'wetback', 'towelhead', 'raghead', 'tranny',

  // ── French ───────────────────────────────────────────────────────────────
  // "con" and "chatte" are omitted on purpose: too common in innocent French
  // and English prose respectively.
  'merde', 'putain', 'connard', 'connards', 'connasse', 'connasses',
  'salope', 'salopes', 'salaud', 'salauds', 'enfoire', 'enfoires',
  'encule', 'encules', 'pute', 'putes', 'bordel', 'foutre', 'nique', 'niquer',
  'batard', 'batards', 'pede', 'pedes',

  // ── Spanish ──────────────────────────────────────────────────────────────
  // "cono" is omitted — it collides with cone; the tilde form is the insult.
  'mierda', 'puta', 'putas', 'puto', 'putos', 'joder', 'jodido', 'jodida',
  'cabron', 'cabrones', 'gilipollas', 'coño', 'pendejo', 'pendejos',
  'chingar', 'chingada', 'verga', 'culero', 'maricon', 'maricones', 'zorra',
  'pinche', 'hijueputa',

  // ── German ───────────────────────────────────────────────────────────────
  'scheisse', 'scheiße', 'scheiss', 'scheiß', 'arschloch', 'arschlöcher',
  'fotze', 'wichser', 'hurensohn', 'hurensöhne', 'schlampe', 'nutte', 'nutten',
  'verpiss', 'fick', 'ficken', 'fickt', 'mistkerl', 'neger', 'kanake',

  // ── Arabic ───────────────────────────────────────────────────────────────
  // Arabic is space-delimited, so token matching works as it does for Latin.
  'شرموطة', 'قحبة', 'عاهرة', 'متناك', 'خرا', 'طيز', 'كس', 'زبي', 'منيوك',
};

/// Multi-token phrases, matched over consecutive tokens.
const _kPhrasePatterns = <String>{
  'hijo de puta',
  'ta gueule',
  'va te faire foutre',
  'fils de pute',
  'kill yourself',
};

/// Patterns matched as substrings rather than tokens, for the two cases where
/// tokenizing cannot work:
///
///   * Chinese has no word delimiters, so a whole sentence is one token. Only
///     multi-character entries are listed — single characters like 靠 (common
///     in 依靠, "to rely on") and 屎 would false-positive constantly.
///   * Symbol-censored spellings whose vowel is gone (`f*ck`), which no amount
///     of character normalization can reconstruct.
const _kSubstringPatterns = <String>{
  // ── Chinese ──────────────────────────────────────────────────────────────
  '他妈的', '操你妈', '傻逼', '婊子', '草泥马', '尼玛', '王八蛋', '贱人',
  '妓女', '干你娘', '去死',
  // ── Censored spellings ───────────────────────────────────────────────────
  'f*ck', 'f**k', 'f***', 'sh*t', 'b*tch', 'c*nt', 'a**hole', 'p*ss',
};

/// Leet-speak folding, applied identically to the text and (at build time) to
/// the patterns, so `sh!t` and `f@ggot` reach the same alphabet as the list.
///
/// Deliberately excludes the `v`→`u` mapping the previous implementation used:
/// it rewrote innocent words wholesale (`love` → `loue`) to catch a spelling
/// nobody actually uses.
const _kLeetMap = <String, String>{
  '@': 'a', '4': 'a', '8': 'b', '(': 'c', '3': 'e', '1': 'i', '!': 'i',
  '|': 'i', '0': 'o', r'$': 's', '5': 's', '7': 't', '+': 't', '#': 'h',
};

/// Any run of characters that is neither a letter nor a digit is a token
/// boundary. Unicode-aware so Arabic, Cyrillic and Greek tokenize correctly.
final _kTokenSeparator = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Collapses every run of one repeated character to a single one, so stretched
/// spellings (`fuuck`, `shiiit`, `fuckkk`) reach the same form as the list.
/// Applied to both sides, so `fuucking` → `fucing` meets `fucking` → `fucing`.
String _squeeze(String token) {
  final buffer = StringBuffer();
  int? previous;
  for (final rune in token.runes) {
    if (rune != previous) buffer.writeCharCode(rune);
    previous = rune;
  }
  return buffer.toString();
}

/// Squeezed forms of [_kTokenPatterns], consulted only for tokens that actually
/// stutter — see the guard in [looksOffensive].
final Set<String> _kSqueezedTokenPatterns =
    _kTokenPatterns.map(_squeeze).toSet();

String _normalize(String text) {
  final lower = text.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_kLeetMap[char] ?? char);
  }
  return buffer.toString();
}

/// Phrases pre-split into tokens and indexed by first token, so a text token
/// that starts no phrase costs one failed map lookup.
final Map<String, List<List<String>>> _phrasesByFirstToken = () {
  final index = <String, List<List<String>>>{};
  for (final phrase in _kPhrasePatterns) {
    final tokens = _tokenize(phrase);
    if (tokens.isEmpty) continue;
    index.putIfAbsent(tokens.first, () => []).add(tokens);
  }
  return index;
}();

List<String> _tokenize(String normalized) =>
    normalized.split(_kTokenSeparator).where((t) => t.isNotEmpty).toList();

/// True if [text] probably reads as offensive.
///
/// Returns false for anything it cannot judge — see the never-block contract
/// above. Callers render a hint; they must not gate submission on it.
///
/// Async only to keep the call site's contract stable: the work is a handful of
/// set lookups and stays on the caller's isolate.
Future<bool> looksOffensive(String text) async {
  try {
    final normalized = _normalize(text.trim());
    if (normalized.isEmpty) return false;

    for (final pattern in _kSubstringPatterns) {
      if (normalized.contains(pattern)) return true;
    }

    final tokens = _tokenize(normalized);
    for (var i = 0; i < tokens.length; i++) {
      if (_kTokenPatterns.contains(tokens[i])) return true;

      // Only tokens that actually stutter are squeeze-matched: squeezing every
      // token would collapse the country `Niger` onto `nigger`, `putto` onto
      // `puto`, and put the whole place-name problem back.
      final squeezed = _squeeze(tokens[i]);
      if (squeezed.length != tokens[i].length &&
          _kSqueezedTokenPatterns.contains(squeezed)) {
        return true;
      }

      final phrases = _phrasesByFirstToken[tokens[i]];
      if (phrases == null) continue;
      for (final phrase in phrases) {
        if (i + phrase.length > tokens.length) continue;
        var matched = true;
        for (var j = 0; j < phrase.length; j++) {
          if (tokens[i + j] != phrase[j]) {
            matched = false;
            break;
          }
        }
        if (matched) return true;
      }
    }
    return false;
  } catch (e) {
    if (kDebugMode) debugPrint('text precheck failed: $e');
    return false;
  }
}
