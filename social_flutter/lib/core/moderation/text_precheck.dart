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
//   3. Any failure degrades to "clean". A missing wordlist, an init error, an
//      unsupported platform — all return false, so a broken filter is invisible
//      rather than obstructive.
//
// Scope: free prose only — descriptions, notes, review text, bios, display
// names. Deliberately NOT titles or place names: European place names
// false-positive on wordlist filters (Bitche in Moselle, Condom in the Gers,
// Sexbierum in Friesland, Wank in Bavaria), and flagging a real destination is
// worse than not filtering, because it teaches people to ignore the warning.
// The backend still moderates titles — its classifier reads context, which a
// wordlist cannot. That asymmetry is the whole reason for the split.
//
// Pure Dart with no platform imports, so it behaves identically on web.

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:safe_text/safe_text.dart';

// The app's own languages. Deliberately not "every language the package
// ships": coverage varies wildly, and a filter that fires unpredictably in one
// language trains users to dismiss it everywhere.
const _kLanguages = <Language>[
  Language.english,
  Language.french,
  Language.spanish,
  Language.german,
  Language.arabic,
  Language.chinese,
];

Future<void>? _initFuture;
bool _available = false;

/// Loads the wordlists. Safe to call repeatedly — the work happens once.
///
/// Call it when a compose screen opens so the first check is instant. Failure
/// is remembered, not retried: a wordlist that failed to load once will fail
/// again, and retrying on every keystroke would be worse than being silent.
Future<void> warmUpTextPrecheck() {
  return _initFuture ??= _initialize();
}

Future<void> _initialize() async {
  try {
    await SafeTextFilter.init(languages: _kLanguages);
    _available = true;
  } catch (e) {
    if (kDebugMode) debugPrint('text precheck unavailable: $e');
    _available = false;
  }
}

/// True if [text] probably reads as offensive.
///
/// Returns false for anything it cannot judge — see the never-block contract
/// above. Callers render a hint; they must not gate submission on it.
Future<bool> looksOffensive(String text) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  try {
    await warmUpTextPrecheck();
    if (!_available) return false;
    return await SafeTextFilter.containsBadWord(text: trimmed);
  } catch (e) {
    if (kDebugMode) debugPrint('text precheck failed: $e');
    return false;
  }
}
